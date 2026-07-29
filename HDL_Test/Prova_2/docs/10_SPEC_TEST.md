# Test 1 — infrastruttura di interfacciamento · COMPLETATO E SUPERATO COME BERSAGLIO

> **Stato: concluso con esito positivo, ma non è più il bersaglio del progetto.**
>
> Questo test ha dimostrato che la catena ARM → impacchettamento → AXI4-Stream → PL
> → spacchettamento funziona ed è **bit-esatta** (errore 0). Ha prodotto la
> struttura a tre modelli, le ricette di configurazione, la suite di gate e le note
> API — tutto materiale che vale indipendentemente dal payload.
>
> Il bersaglio è cambiato dopo il riorientamento del perimetro
> ([`01_PIANO.md` §1](01_PIANO.md)): payload reale di **due vettori 3×1**, calcolo
> dentro un **blocco di terzi**, budget di **33 µs**, trasporto **AXI4-Lite**.
>
> **La specifica corrente è [`21_SPEC_WRAPPER.md`](21_SPEC_WRAPPER.md).**
> Questo documento resta come registro di ciò che è stato fatto e verificato: non
> va aggiornato, va letto come storia.

---

## Specifica del Test 1 — congelata 28/07/2026

> Passo P1 della procedura. Da qui in avanti ogni modifica a questo documento
> richiede una giustificazione scritta (regola R5). Il benchmark congelato è la
> precondizione di ogni confronto che il progetto farà in seguito.

## 1. Cosa questo test deve dimostrare

**Che un vettore prodotto sull'ARM arrivi alla PL, sia elaborato, e torni indietro
identico al riferimento — con una latenza misurata e un percorso riproducibile da
script.**

Cosa **non** dimostra, e non deve essere presentato come se lo facesse:
- niente sull'MPC;
- niente sullo speedup di un acceleratore (il carico computazionale è una sonda,
  non un algoritmo);
- niente sul timing closure reale finché il datapath non contiene registri.

## 2. Payload

| | |
|---|---|
| Elementi | **25** |
| Tipo | **`fixdt(1,32,16)`** (sfix32_En16) |
| Range rappresentabile | ±32768, LSB = 1.526·10⁻⁵ |
| **Range operativo dichiarato** | **±1024** |
| Larghezza stream | **32 bit** — vincolo C1 del reference design AXI4-Stream |

Il range operativo non è una stima ma un impegno: i vettori di test sono generati
dentro questo intervallo e i formati a valle sono dimensionati su di esso.
Riferimento: il caso storico del progetto (`A*B` con `A=[1 2 3;4 5 6;7 8 9]`,
`B=[9 8 7;6 5 4;3 2 1]`) arriva a **138**; ±1024 lascia margine.

**Il `typecast` a `uint64` è abolito.** Era la causa delle tre varianti divergenti
della funzione di reshape in Prova_1 ed è incompatibile con il vincolo a 32 bit.

## 3. Partizione del payload

| Uscita | Indici (1-based) | Forma | Ordine |
|---|---|---|---|
| `matA` | `1:9` | 3×3 | column-major |
| `matB` | `10:25` | 4×4 | column-major |

`mat(r,c) = u( base + (c-1)·nRighe + (r-1) )`

Gli indici devono **partizionare esattamente** `1:25` — nessuna sovrapposizione,
nessun buco. La condizione è verificata da `soc_params` a ogni chiamata: è
letteralmente il controllo che il Verilog di Prova_1 violava
(`matB` leggeva `U(1:16)`, sovrapponendosi a `matA` e lasciando 9 ingressi scollegati).

## 4. Sonda aritmetica

Esiste per **un motivo solo**: garantire che il flusso generi hardware vero e non
solo cablaggio. Un reshape puro sintetizza a zero risorse, e su zero risorse il gate
sul timing non significa niente (è quanto successo in `vivado_synth_fpga_real`:
0 LUT, 0 DSP, 0 FF).

```
matA  --[Data Type Conversion]--> fixdt(1,16,3) --[Gain 3.7]--> matA_probe
```

| | Valore | Come è stato scelto |
|---|---|---|
| Guadagno | 3.7 | ereditato dal prototipo `FPGA_Prova1_fixedpoint` |
| Uscita massima | 1024 × 3.7 = **3788.8** | derivata dal range dichiarato |
| Formato uscita | **`fixdt(1,16,3)`** — range [−4096, +4095.88], LSB 0.125 | **derivato**: `fl = 15 − ⌈log₂(3788.8)⌉ = 15 − 12 = 3` |
| Arrotondamento | `Floor` | coerente con l'HDL generato |
| Overflow | **Saturate** | non wrap |

> ⚠️ Differenza voluta rispetto al prototipo. `FPGA_Prova1_fixedpoint` usava
> `fixdt(1,16,10)` (range ±32) con **saturazione disattivata**, mentre i valori
> reali di `matA` arrivano a 138 e la loro uscita moltiplicata a 510: quel prototipo
> produceva wrap-around silenzioso. Qui il formato è calcolato dal range e
> l'overflow satura. È un esempio in miniatura di cosa vuol dire fare analisi di
> range invece di scegliere un formato a occhio.

## 5. Canale e tempi

| | Valore |
|---|---|
| Clock IP | 100 MHz → `Ts_FPGA` = 10 ns |
| Frame size / burst | 25 campioni |
| Buffer | 8 |
| FIFO depth / almost-full | 8 / 6 |
| Frame period | 250 ns |
| `(N_buffers+1)·FramePeriod` | **2.25 µs** ≤ budget 1 s ✔ |
| Periodo ComputeTask | 0.1 s, event-driven |

## 6. Criterio di accettazione — scritto PRIMA dell'implementazione

Il test è superato quando **tutte** le clausole sono vere.

| | Clausola |
|---|---|
| **A1** | L'uscita della PL è **bit-identica** al reference model su **tutte e tre** le famiglie di vettori — `matA`, `matB` e la sonda, nessuna eccezione |
| **A2** | Zero campioni persi nello scenario nominale; il comportamento in overload è caratterizzato e documentato, non ignorato |
| **A3** | Il bitstream chiude il timing con **slack positivo su un design contenente registri** |
| **A4** | `ID_VER` letto dalla board coincide con la costante `0x50325A31` |
| **A5** | Latenza hardware (contatore on-chip) ed end-to-end misurate entrambe, con distribuzione e jitter — **non un numero singolo** |
| **A6** | Ogni risultato rigenerabile da un altro operatore con i comandi documentati |

## 7. Suite di vettori

Generata da `scripts/gen_vectors.m`, **seed fisso `20260728`**, 510 vettori:

| Famiglia | N | Contenuto |
|---|---|---|
| `realistic` | 3 | il caso storico `A*B`/`C*D`, `A*A`/`C*C`, matrici identità |
| `random` | 500 | uniformi su ±1024, quantizzati sulla griglia del formato |
| `corner` | 7 | zeri, ±max, ±1 LSB, alternanza di estremi, rampa di indici |

Tutti i vettori sono **esattamente rappresentabili** in `fixdt(1,32,16)`: altrimenti il
confronto bit-true misurerebbe l'errore del generatore invece che quello del datapath.

## 8. Stato rispetto al criterio di accettazione

| | Clausola | Stato |
|---|---|---|
| **A1** | uscita PL bit-identica al reference | ✅ **verificato in simulazione** (gate T11, errore 0 su `matA`, `matB`, sonda) |
| **A2** | zero campioni persi, overload caratterizzato | ⬜ manca lo studio di dropout con durate di task variabili |
| **A3** | timing con slack positivo su design con registri | ⬜ dipende da P12 |
| **A4** | `ID_VER` letto dalla board == `0x50325A31` | ⬜ serve la board |
| **A5** | latenza HW ed end-to-end con distribuzione e jitter | ⬜ serve la board |
| **A6** | tutto rigenerabile da un altro operatore | ✅ un comando per i modelli, uno per la regressione |

**Segnaposto ancora presenti e punti aperti**: elencati in un solo posto,
[`13_APERTI.md`](13_APERTI.md) (regola R2 — una decisione, un posto solo).
Il più importante: `tdata` vettoriale a 25 elementi funziona in simulazione ma
**non è generabile in hardware**.

## 9. Decisioni registrate, con l'alternativa scartata

| Decisione | Scelto | Scartato, e perché |
|---|---|---|
| Board | PYNQ-Z1 via HDL Coder custom board (A3) | ZedBoard (la PYNQ-Z1 è vincolo di progetto); SoC Blockset custom board completo (sotto-progetto a sé) |
| Trasporto | AXI4-Stream (B2) | Register Channel — tecnicamente preferibile a 200 B, scartato per scelta esplicita dell'utente. Conseguenza dichiarata: la latenza end-to-end sarà dominata dal costo fisso |
| Formato payload | `sfix32_En16` a 32 bit | `double`/`uint64` — incompatibile con il vincolo a 32 bit del reference design |
| Formato sonda | derivato dal range | `fixdt(1,16,10)` del prototipo — va in overflow silenzioso sui valori reali |
| Reference model | scritto a mano nell'ordine dell'hardware | `reshape` di MATLAB — usato come cross-check, non come giudice |
