# Piano e registro delle decisioni

> Documento vivo. Registra **le decisioni architetturali con l'alternativa scartata**
> e i **rischi con la loro via d'uscita**. Per lo stato operativo vedere il
> [README](../README.md); per i punti aperti [`13_APERTI.md`](13_APERTI.md).
>
> Ultimo aggiornamento: 28/07/2026, dopo il riorientamento del perimetro.

---

## 1. Il perimetro — riformulato il 28/07/2026

**Non stiamo accelerando un MPC.** L'informazione che ha cambiato il quadro:
l'inversione 3×3 e il resto dell'algoritmo stanno dentro un **blocco FPGA di un
altro ingegnere**, le cui scelte non sono negoziabili (almeno per ora).

Il perimetro è:

> costruire un trasporto **deterministico, a bassa latenza e sostituibile** fra
> l'ARM della PYNQ-Z1 e un blocco di calcolo di terzi, dimensionato per i vettori
> che attraversano oggi e scalabile, dentro un budget d'anello di **33 µs**.

Il deliverable non è un acceleratore: è **un contratto d'interfaccia più il suo
wrapper** ([`20_CONTRATTO_INTERFACCIA.md`](20_CONTRATTO_INTERFACCIA.md)).

Ne consegue una regola di lavoro: il valore ingegneristico sta nella partizione e
nelle interfacce, non nei blocchi. Se il blocco di calcolo cambia — e cambierà —
la nostra infrastruttura deve restare in piedi.

### Quello che sappiamo, e con quanta confidenza

| | Valore | Confidenza |
|---|---|---|
| Payload ARM→PL | **due vettori 3×1** | osservato in un esempio, contenuto ignoto |
| `n_x` totale | 6 elementi | da confermare |
| `n_u` | 1 | ipotesi |
| Budget d'anello | 33 µs | **letto in un paper, non misurato** |
| Latenza del blocco di calcolo | ignota | da misurare con `CYCLES` |
| La 3×3 è tempo-variante? | probabile (assemblata dai vettori) | da confermare |

**Finché `p.mpc.confirmed` è `false`, ogni sessione MATLAB emette un avviso.**
Progettare l'infrastruttura contro un contratto parametrico è legittimo; farlo
senza accorgersene no.

---

## 2. Decisioni

### D1 · Board — **SoC Blockset per simulare, HDL Coder per deployare** *(28/07)*

La PYNQ-Z1 non è fra le board supportate da SoC Blockset. Si usa SoC Blockset per
architettura e simulazione (funziona con board non registrate) e **HDL Coder IP
Core Generation con board registrata a mano** per il deployment.

*Scartate*: board supportata (ZedBoard) — la PYNQ-Z1 è vincolo di progetto;
custom board support completo per SoC Blockset — richiede device tree, immagine
Linux con i moduli MathWorks, `soc.sdk.BoardSupport`: è un sotto-progetto a sé.

*Costo accettato*: reference design in Vivado e software PS diventano deliverable
nostri, non generati.

### D2 · Trasporto — **AXI4-Lite** *(28/07, sostituisce la decisione precedente)*

**Superata la decisione di usare AXI4-Stream**, presa quando si ipotizzava un
payload di 25 elementi. Con il payload reale (6 elementi, ~28 byte) e un budget di
33 µs, `budget_report()` dà:

| trasporto + stack | trasporto | cicli al calcolo (su 3300) |
|---|---:|---:|
| **AXI4-Lite + bare-metal** | **1.5 µs** | **3150** |
| AXI4-Lite + Linux mmap | 10 µs | 2300 |
| AXI4-Stream + bare-metal | 2.0 µs | 3100 |
| AXI4-Stream + Linux | 32 µs | **100** |
| AXI4-Lite + Linux driver kernel | 50 µs | **esaurito** |

Il DMA su Linux è squalificato **dall'aritmetica**: il costo fisso di setup più
interrupt è ~32 µs indipendentemente dalla taglia del payload.

*Argomento aggiuntivo, indipendente dalla latenza*: con più vettori d'ingresso la
PL deve avere l'**insieme completo** prima di partire. Con i registri la
completezza è esplicita (si alza `START`); con uno stream va dedotta da `TLAST` o
da un contatore — logica in più e **un modo di fallire in più**, del tipo
silenzioso.

*Non è irreversibile*: `p.transport.kind` è un selettore, e il percorso stream
resta costruito e verificato. La soglia registri↔stream sta intorno a **10–12
elementi** su bare-metal: se i vettori diventano quattro, si riapre.

### D3 · Stack software del PS — **ristretta a due opzioni** *(29/07)*

La curva mostrava già che lo stack pesa **quanto o più del bus**. P10 l'ha
quantificato per il trasporto scelto ([`22_STUDIO_LATENZA`](22_STUDIO_LATENZA.md)),
e il verdetto con AXI4-Lite e 6 elementi è:

| stack | cicli al calcolo | quota del budget |
|---|---:|---|
| `baremetal` (poll o irq) | 3149 | ~95 % |
| `linux_mmap` | 2299 | ~70 % |
| `linux_driver` | **−1701** | **fuori** |

`linux_driver` non è "stretto", è impossibile: il trasporto da solo costa 50 µs
contro 33 di budget. Eliminato per aritmetica, non per preferenza.

**Trasporto e stack non sono decisioni indipendenti** — questa formulazione
sostituisce quella precedente. Il costo per-accesso si moltiplica per il numero
di accessi, che è il protocollo a fissare: cambiare D2 rimescola questa tabella.

La scelta fra i due superstiti resta aperta e non è tecnica in senso stretto:
dipende da cosa deve fare il PS oltre a questo anello. **Il prezzo di Linux ora
è noto: 850 cicli.** PYNQ/Python va benissimo per il **bring-up** in ogni caso.
**Decisione da prendere prima di P13.**

### D4 · Integrazione con il blocco di terzi — **due IP separati** *(28/07)*

Il blocco di calcolo resta un IP a sé, collegato al nostro nel block design Vivado,
non inglobato nel nostro DUT.

*Perché*: ciascuno resta padrone dei propri strumenti e sostituire un lato non
obbliga a rigenerare l'altro. È il confine di proprietà, e va reso visibile
nell'architettura.

### D5 · Il protocollo verso il blocco di terzi — **start/done insensibile alla latenza** *(28/07)*

Nessun numero di cicli cablato da nessuna parte. L'`enable` che il blocco già usa
**va bene com'è**: l'adattamento a `done` sta nel nostro wrapper.

*Scartato*: chiedere al collega di adeguare il suo blocco al nostro protocollo. È
il modo più veloce per non ottenerlo, e non serve.

### D6 · Formato numerico — **`sfix32_En16`, da concordare** *(proposta)*

Proposto, non concordato. Le quattro caselle del §3 del contratto (formato reale,
range, overflow, arrotondamento) sono le cose che nessuno dei due lati può
decidere da solo. Finché non sono spuntate, **ogni confronto numerico fra i due
lati misura la cosa sbagliata**.

---

## 3. Le fasi

### Concluse

| | Cosa | Esito |
|---|---|---|
| **F0** | ambiente: R2026a + SoC Blockset + Embedded Coder + support package AMD | ✅ verificato |
| **F1** | struttura a tre modelli, generata da script | ✅ **gate G6** |
| **F2** | catena end-to-end simulata e bit-esatta | ✅ **gate G7** |
| **F3** | contratto d'interfaccia e modello di budget | ✅ documento + `budget_report` |

> F1–F2 sono state fatte sul payload vecchio (25 elementi, AXI4-Stream). **Non sono
> sprecate**: hanno prodotto la struttura, le ricette di configurazione, la suite di
> gate e le note API, che valgono indipendentemente dal payload. E il percorso
> stream resta come seconda implementazione della stessa interfaccia.

### In corso e successive

| | Cosa | Dipendenze |
|---|---|---|
| **F4** | **wrapper AXI4-Lite**: CSR, FSM start/done, watchdog, contatore di cicli, blocco di calcolo come segnaposto a latenza configurabile | nessuna — è parametrico |
| **F5** | studio di sensibilità alla latenza: fin dove regge il budget | F4 |
| **F6** | board plugin PYNQ-Z1 | nessuna (validazione: Vivado) |
| **F7** | reference design da `+vivado_base_2022_1` | **Vivado 2022.1 → Dario** |
| **F8** | bitstream | **Dario** |
| **F9** | software PS + driver | D3 decisa |
| **F10** | bring-up: `ID_VER` → registro R/W → vettore noto → **prima lettura di `CYCLES`** | board |
| **F11** | campagna di misura | F10 |

Il passo che produce il primo dato reale è **F10**: la lettura di `CYCLES` dice se i
33 µs sono raggiungibili con il blocco attuale. Tutto ciò che viene prima serve a
poterlo misurare.

---

## 4. Registro dei rischi

| Rischio | Prob. | Mitigazione, con la sua uscita |
|---|---|---|
| **Il blocco di calcolo non sta nel budget** | **alta** | il contatore `CYCLES` lo dice presto e senza toccare il loro codice. Uscita: la conversazione con l'altro ingegnere si fa con un numero, non con un'impressione |
| I 33 µs non sono il vero requisito | media | sono dichiarati "da paper, non misurati" ovunque compaiano. Uscita: si sostituiscono al primo bring-up |
| `n_x` cresce oltre ~12 elementi | media | il trasporto è dietro un selettore e il percorso stream è già costruito e verificato. Uscita: si cambia `p.transport.kind` |
| Lo stack PS scelto non regge il budget | media | la curva è calcolata per tutti gli stack. Uscita: bare-metal, con PYNQ relegato al bring-up |
| Reference design PYNQ-Z1 non converge | alta | partire dal plugin shipped, cambiare solo board e PS7. **Uscita datata: 2 settimane** → ZedBoard, e la PYNQ-Z1 diventa una limitazione dichiarata |
| Il formato numerico diverge fra i due lati | **alta se non concordato** | §3 del contratto. È un guasto **silenzioso**: produce risultati plausibili e sbagliati |
| Si progetta su ipotesi senza accorgersene | alta | avviso automatico a ogni sessione finché `p.mpc.confirmed` è `false` |
| Versioni tool incompatibili | media | R2026a + Vivado 2022.1/2024.1 fissate. **La 2026.1 presente su questa macchina non è supportata** |
| Risultati non riproducibili | bassa | tutto da script, un comando per i modelli e uno per la regressione |

---

## 5. Fonti

- MathWorks — [SoC Blockset Model Structure](https://www.mathworks.com/help/soc/ug/soc-blockset-model-structure.html) · [Build Error When FPGA or Processor Model Not Detected](https://www.mathworks.com/help/soc/ug/build-error-for-fpga-or-processor-model-not-detected.html) · [Supported Third-Party Tools and Hardware](https://www.mathworks.com/help/soc/ug/supported-third-party-tools-and-hardware.html) · [Using a Custom Board with SoC Blockset](https://www.mathworks.com/help/soc/ug/Using-a-Custom-Board-with-SoC-Blockset.html)
- MathWorks — [Register a Custom Board](https://www.mathworks.com/help/hdlcoder/ug/register-a-custom-board.html) · [Register a Custom Reference Design](https://www.mathworks.com/help/hdlcoder/ug/register-a-custom-reference-design.html) · [Model Design for AXI4 Register Interface Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-axi4-slave-interface-generation.html)
- Ricerca sistematica su doc e artefatti installati: [`12_RICERCA_TOOLCHAIN.md`](12_RICERCA_TOOLCHAIN.md)
- Modello di costo del trasporto e soglia registri↔DMA: skill `soc-expert` ch06;
  formulazione MPC e split offline/online: ch17–ch18; metodo della catena di
  artefatti e bring-up: ch22. Regole AXI e handshake: skill `fpga-expert` ch08.
