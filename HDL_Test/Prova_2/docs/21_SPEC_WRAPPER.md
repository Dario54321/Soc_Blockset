# Specifica del wrapper AXI4-Lite — Test 2

> **Congelata il 28/07/2026.** Da qui in poi ogni modifica richiede una
> giustificazione scritta (regola R5).
>
> Sostituisce come bersaglio [`10_SPEC_TEST.md`](10_SPEC_TEST.md), che resta valido
> come **registro del Test 1** (infrastruttura, completato e superato).

---

## 1. Cosa questo test deve dimostrare

> Che l'ARM possa consegnare l'insieme completo degli ingressi al blocco di calcolo,
> farlo partire, accorgersi di quando ha finito, leggere il risultato e **misurare
> quanto ci ha messo** — con latenza deterministica e senza poter mai restare
> appeso.

Cosa **non** dimostra, e non va presentato come se lo facesse:

- niente sull'MPC: il calcolo è di terzi e qui è un segnaposto;
- niente sullo speedup: senza il blocco vero non c'è nulla da confrontare;
- niente sul timing closure finché non esiste un bitstream.

---

## 2. Interfacce

**Verso l'ARM**: AXI4-Lite, mappa in [`20_CONTRATTO_INTERFACCIA.md` §6](20_CONTRATTO_INTERFACCIA.md).
**Verso il blocco di calcolo**: `start`/`done`, protocollo in [§1–2 del contratto](20_CONTRATTO_INTERFACCIA.md).

Nessuna delle due è ridefinita qui: **una decisione, un posto solo** (regola R2).

---

## 3. Comportamento del wrapper

### Macchina a stati

```
        ┌────────────────────────── SOFT_RESET ─────────────────────────┐
        │                                                               │
        ▼                                                               │
     ┌──────┐   CTRL.START    ┌──────────┐   done      ┌──────────┐    │
     │ IDLE │ ───────────────▶│  RUNNING │ ───────────▶│   DONE   │────┘
     └──────┘                 └────┬─────┘             └──────────┘
        ▲                          │ contatore == TIMEOUT
        │                          ▼
        │                     ┌──────────┐
        └──────────────────── │ TIMED_OUT│
             lettura STATUS   └──────────┘
```

| Transizione | Effetti |
|---|---|
| `IDLE → RUNNING` | `START` si **autoazzera**; impulso di `start` di un ciclo verso il blocco; contatore azzerato e avviato; `BUSY = 1` |
| `RUNNING → DONE` | `u` latchato; contatore fermato e copiato in `CYCLES`; `DONE = 1`, `BUSY = 0` |
| `RUNNING → TIMED_OUT` | `TIMEOUT = 1`, `BUSY = 0`; `u` **non** aggiornato; `CYCLES` = valore raggiunto |
| qualunque → `IDLE` | `SOFT_RESET`, oppure lettura di `STATUS` che azzera i flag sticky |

### Invarianti — le proprietà che i gate devono verificare

| | Invariante | Perché |
|---|---|---|
| **I1** | `x` è stabile da `start` a `done` | il blocco può leggerlo quando vuole |
| **I2** | `START` si autoazzera entro un ciclo | senza, il primo solve funziona e il secondo non parte mai |
| **I3** | `start` è un impulso di **esattamente un ciclo** | contratto §2 |
| **I4** | fra `start` e `done` non parte un secondo `start` | un solve alla volta |
| **I5** | `CYCLES` conta esattamente i cicli fra `start` e `done` | è la misura, dev'essere esatta o non serve |
| **I6** | il wrapper torna sempre a `IDLE` in tempo finito | **l'ARM non può restare appeso** |
| **I7** | in `TIMED_OUT`, `u` conserva il valore precedente e non un dato parziale | un risultato parziale è peggio di nessun risultato |

**I6 e I7 sono requisiti di sicurezza**, non comodità: un anello di controllo che
si pianta o che consuma un risultato parziale è peggio di uno lento.

---

## 4. Il blocco di calcolo, in simulazione

Segnaposto con **latenza configurabile** (`p.compute.latencyCycles`), che permette
di far girare il sistema completo prima di avere il blocco vero, e soprattutto di
rispondere a:

> *qual è la latenza massima del calcolo che sta ancora dentro i 33 µs?*

Tre modalità da coprire:

| Modalità | Cosa esercita |
|---|---|
| latenza **costante** | il caso nominale |
| latenza **variabile** entro un intervallo | la robustezza dell'handshake |
| **nessun `done`** (blocco muto) | il watchdog — il gate che va provato in entrambi i sensi |

---

## 5. Criterio di accettazione — scritto PRIMA dell'implementazione

| | Clausola |
|---|---|
| **B1** | Il valore letto da `U` coincide con quello prodotto dal segnaposto, per ogni latenza nell'intervallo dichiarato |
| **B2** | `CYCLES` == **latenza del segnaposto + 1**, esattamente (vedi nota sotto) |
| **B3** | Con blocco muto, `TIMEOUT` si alza entro `TIMEOUT+1` cicli e il wrapper torna a `IDLE` |
| **B4** | Due solve consecutivi funzionano entrambi (verifica di I2) |
| **B5** | `ID_VER` letto == `0x50325A31` |
| **B6** | Nessun invariante I1–I7 violato sulla suite di stimoli |
| **B7** | Tutto rigenerabile da script |

`B2` e `B3` sono i due che meritano più attenzione: il primo perché `CYCLES` è lo
strumento di misura e uno strumento non verificato produce numeri credibili e
sbagliati; il secondo perché è **l'unico gate che protegge dallo stallo**, e va
provato facendo tacere il blocco di proposito.

> ### Perché `+1` in B2
>
> Il segnaposto è configurato **nondirect feedthrough** — è così che si rompe
> l'anello `fsm → blocco → fsm` ([`11_NOTE_API` §11.1](11_NOTE_API.md)). Le sue
> uscite escono quindi dallo **stato**: `done` arriva un ciclo dopo che il
> contatore ha raggiunto la latenza.
>
> Non è un artificio di simulazione: è il registro che in hardware c'è comunque
> sull'uscita `done` di un IP.
>
> **Conseguenza pratica**: il numero letto da `CYCLES` sull'hardware sarà la
> latenza del blocco **più il costo del confine**. È la cosa giusta da misurare —
> è quello che l'anello di controllo paga davvero — ma va detto quando si comunica
> il numero all'altro ingegnere, altrimenti gli si attribuisce un ciclo che non è
> suo.

### Come si verifica

**Simulando il modello**, non emulandolo. Una versione precedente del banco
estraeva le MATLAB Function e le faceva girare in un anello MATLAB: va bene per la
logica, ma **non per le misure di tempo** — l'emulazione introduce un ciclo in più
che non è aggirabile ([`11_NOTE_API` §12](11_NOTE_API.md)). Misurava 502 dove il
modello fa 501.

Lo stimolo si costruisce con `createInputDataset`, che genera il dataset con i tipi
compilati di ogni porta.

### Verificato in fallimento

| Mutazione | Gate che scatta | Esito |
|---|---|---|
| watchdog rimosso (`elseif false`) | **B3** | ✅ *"con blocco muto il watchdog NON è scattato. L'ARM resterebbe appeso."* |
| contatore sfasato di uno | **B2** | ✅ *"CYCLES = 502 invece di 501"* |
| la FSM non torna a IDLE dopo `done` | **B4 / I2 / I6** | ✅ *"1 solve completati invece di 2"* |

---

## 6. Fuori perimetro, dichiarato

- **L'algoritmo di calcolo.** È di terzi. Qui è un segnaposto.
- **Il percorso AXI4-Stream.** Costruito e verificato nel Test 1, resta disponibile
  come seconda implementazione della stessa interfaccia. Torna in gioco oltre i
  ~10–12 elementi (vedi [`20_CONTRATTO_INTERFACCIA.md` §9](20_CONTRATTO_INTERFACCIA.md)).
- **Interrupt.** Il bit `IRQ_EN` è previsto nella mappa ma non implementato:
  il primo bring-up si fa in polling, che è anche il percorso più veloce a questo
  budget.

---

## 7. Decisioni di questo test, con l'alternativa scartata

| Decisione | Scelto | Scartato, e perché |
|---|---|---|
| Dove sta la FSM | nel modello Simulink, generata da HDL Coder | scriverla a mano in HDL — perderemmo la verifica per simulazione e la rigenerabilità |
| Notifica di fine calcolo | polling di `STATUS` | interrupt — a 33 µs il costo di un interrupt sotto Linux è dell'ordine del budget intero |
| Watchdog | contatore nel wrapper, soglia da registro | soglia fissa in hardware — costringerebbe a risintetizzare per adattarsi al blocco |
| Blocco di calcolo in simulazione | segnaposto a latenza configurabile | attendere il blocco vero — bloccherebbe tutto e non risponderebbe alla domanda sul budget |
