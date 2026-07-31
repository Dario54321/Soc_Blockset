# Prova_2 — trasporto ARM ↔ FPGA per l'acceleratore MPC (PYNQ-Z1)

Infrastruttura di interfacciamento fra l'ARM della PYNQ-Z1 e un blocco di calcolo
FPGA, costruita con metodo: **ogni modello è generato da script, ogni affermazione
ha un gate che la verifica, e ogni gate è stato provato anche in fallimento.**

---

## Il perimetro, in una frase

> Costruire un trasporto **deterministico, a bassa latenza e sostituibile** fra
> l'ARM e un **blocco di calcolo di terzi**, dimensionato per i vettori che
> attraversano oggi e scalabile, dentro un budget d'anello di **33 µs**.

Il calcolo dell'MPC (inversione 3×3 e altro) è dentro un blocco FPGA di un altro
ingegnere: **non è nel nostro perimetro**. Il nostro deliverable è
**[un contratto d'interfaccia](docs/20_CONTRATTO_INTERFACCIA.md) più il suo
wrapper**.

---

## Stato

### ✅ Test 1 — infrastruttura *(concluso)*

La catena ARM → impacchettamento → AXI4-Stream → PL → spacchettamento è **bit-esatta**:

```
matA : errore max = 0
matB : errore max = 0
sonda: errore max = 0        (LSB del formato = 0.125)
```

A fine Test 1: 11 gate verdi (oggi 16), ognuno validato con una mutazione che
riproduce un difetto reale.
Ha prodotto la struttura a tre modelli, le ricette di configurazione, la suite di
gate e le note API — materiale che vale indipendentemente dal payload.

### 🔄 Test 2 — wrapper AXI4-Lite *(in corso)*

Specifica: [`docs/21_SPEC_WRAPPER.md`](docs/21_SPEC_WRAPPER.md).

| | |
|---|---|
| P8 · contratto d'interfaccia | ✅ bozza — **8 domande in attesa di risposta** |
| P9 · wrapper: CSR, FSM start/done, watchdog, contatore | ✅ gate G9 (T12), 3 mutazioni catturate |
| P10 · studio di sensibilità alla latenza | ✅ gate G10 (T13) → [`docs/22_STUDIO_LATENZA.md`](docs/22_STUDIO_LATENZA.md) |
| P11 · board plugin PYNQ-Z1 | ✅ gate G11 (T14) → [`docs/23_BOARD_PYNQZ1.md`](docs/23_BOARD_PYNQZ1.md) — resta una conferma manuale |
| P12 · reference design | ✅ **costruito e validato su Vivado 2022.1 reale** *(31/07)*: `validate_refdesign()` dà `completa`, gate **G12b chiuso** → [`docs/24_REFERENCE_DESIGN.md`](docs/24_REFERENCE_DESIGN.md) §24.6bis e §24.7 |
| P13 · bitstream | ⬜ **Dario** (serve Vivado 2022.1) |
| P14–P16 · software PS, bring-up, misure | ⬜ serve la board |

---

## Le decisioni, in breve

| | Scelto | Perché |
|---|---|---|
| **Trasporto** | **AXI4-Lite** | payload ~28 B su un budget di 33 µs: il DMA su Linux lascia 100 cicli al calcolo, i registri ne lasciano 3150 |
| **Board** | SoC Blockset per simulare, **HDL Coder per deployare** | la PYNQ-Z1 non è fra le board supportate da SoC Blockset |
| **Integrazione** | **due IP separati** in Vivado | è il confine di proprietà: sostituire un lato non obbliga a rigenerare l'altro |
| **Protocollo** | `start`/`done` **insensibile alla latenza** | il blocco di terzi cambierà; l'adattamento sta nel nostro wrapper |
| **Stack PS** | ⚠️ **da decidere fra due** | bare-metal (3150 cicli) o Linux mappato (2300): il prezzo di Linux è **850 cicli**. Un driver kernel è fuori per aritmetica |

Motivazioni e alternative scartate: [`docs/01_PIANO.md`](docs/01_PIANO.md).

---

## Come si usa

```matlab
cd D:\Project_SoC\Soc_Blockset\HDL_Test\Prova_2
addpath('scripts')

p = soc_params();      % configurazione + controlli di coerenza
budget_report;         % quanti cicli restano al calcolo, per stack PS e trasporto

gen_vectors(p);        % rigenera test/vectors.mat (seed fisso, deterministico)
build_soc_fpga();      % ricostruisce models/soc_fpga.slx da zero
build_soc_proc();
build_soc_top();

run_regression;        % PASS/FAIL dell'intera suite (~4 minuti)
run_system_sim;        % solo la simulazione di sistema (~2 minuti)

export_r2023b();       % REGOLA R1 — prima di ogni commit che tocca .slx
```

Per il deploy serve anche la board registrata in HDL Coder — una riga:

```matlab
addpath('hdlplugins')      % rende visibile la Digilent PYNQ-Z1
check_board_plugin();      % i pin combaciano coi board file Vivado
check_refdesign();         % i 4 file del reference design concordano
validate_refdesign();      % costruisce il block design — serve Vivado 2022.1
```

I modelli in `models/` (esclusi i `*_ref.slx`) sono **artefatti rigenerabili**:
non si modificano a mano, si modifica lo script che li costruisce.

### L'equazione di progetto

`budget_report()` risponde alla domanda da fare all'altro ingegnere:

```
target 33 µs @ 100 MHz  ->  3300 cicli totali      (nx=6: due vettori 3×1)

trasporto    stack PS          trasp[µs]   cicli al calcolo
axi4lite     baremetal              1.50               3150
axi4lite     linux_mmap            10.00               2300
axi4stream   baremetal              2.00               3100
axi4stream   linux (qualunque)     32.00                100
axi4lite     linux_driver          50.00           esaurito
```

Togliendo **l'overhead del wrapper — 1 ciclo, misurato** e non stimato
([`docs/22_STUDIO_LATENZA.md`](docs/22_STUDIO_LATENZA.md)) — si arriva alla
risposta da dare all'altro ingegnere:

> **ordine dei 3000 cicli a 100 MHz** con PS bare-metal, **~2300** con Linux e
> registri mappati. Da confermare a misura: le costanti di trasporto sono ordini
> di grandezza da letteratura, non misure su questa board.

`linux_driver` non è "stretto", è **impossibile**: 50 µs di trasporto contro 33
di budget. Eliminato per aritmetica. Il corollario è che **trasporto e stack
software del PS non sono decisioni indipendenti**.

```matlab
S = latency_study();      % rifà lo studio: tabella overhead + tabella budget
```

---

## La suite di regressione

Un comando, 16 gate, **ognuno verificato anche in fallimento**. ~4 minuti.

| Gate | Cosa verifica |
|---|---|
| T1–T2 | `soc_params` è coerente **e rifiuta** configurazioni sbagliate |
| T3–T5 | vettori deterministici, reference == cross-check, copertura e range |
| T6–T7 | `soc_fpga` compila; il suo algoritmo == reference su 510 vettori |
| T8 | `soc_proc` compila |
| T9 | **contratto ARM→FPGA**: pack e unpack sono operazioni inverse |
| T10 | **G6**: struttura a 3 modelli riconosciuta e compilante |
| T11 | **G7**: catena end-to-end bit-esatta |
| T12 | **G9**: invarianti del wrapper, `CYCLES` esatto, **watchdog** |
| T13 | **G10**: l'overhead del wrapper è ancora 1 ciclo |
| T14 | **G11**: plugin PYNQ-Z1 registrato, e i pin combaciano coi board file |
| T15 | **G12a**: i quattro file del reference design dicono la stessa cosa |
| T16 | **R1**: i `.slx` su disco sono davvero R2023b, non solo esportabili |

Mutazioni usate per validarli:

| Mutazione | Gate che la prende |
|---|---|
| `matB` legge `U(1:16)` invece di `U(10:25)` — **il bug storico di `Prova_1`** | T4 / T2 |
| `matB` srotolata row-major invece che column-major | T7 |
| ordine di impacchettamento invertito lato ARM | T9 |
| `Register Write` rimosso (segnale grezzo verso il Register Channel) | T10 |
| watchdog disattivato (`elseif false`) — l'ARM resterebbe appeso | T12 |
| contatore dei cicli sfasato di uno | T12 |
| la FSM non torna a IDLE dopo `done` | T12 |
| uno stadio di registro in più sul percorso `done` | T13 |
| package `clg484` (quello della ZedBoard) al posto di `clg400` | T14 |
| due pin LED invertiti | T14 |
| `LVCMOS18` al posto di `LVCMOS33` | T14 |
| riferimento di registrazione della board sbagliato | T14 |
| clock a 50 MHz nel reference design invece di 100 | T15 |
| nome della board diverso fra board plugin e reference design | T15 |
| istanza rinominata nel `.tcl` ma non in `plugin_rd` | T15 |
| board part maiuscolo (`PYNQ-Z1` invece di `pynq-z1`) | T15 |
| `clock-div` del device tree incoerente col clock reale | T15 |
| un modello ricostruito e lasciato in formato R2026a | T16 |

---

## Documentazione

**Da leggere per primi:**

| | |
|---|---|
| [`13_APERTI.md`](docs/13_APERTI.md) | punti aperti e prossimi passi |
| [`20_CONTRATTO_INTERFACCIA.md`](docs/20_CONTRATTO_INTERFACCIA.md) | il confine con il blocco di terzi — **8 domande aperte** |
| [`22_STUDIO_LATENZA.md`](docs/22_STUDIO_LATENZA.md) | **quanti cicli ha il blocco di calcolo**, e da cosa dipendono |
| [`23_BOARD_PYNQZ1.md`](docs/23_BOARD_PYNQZ1.md) | come la PYNQ-Z1 è stata registrata in HDL Coder |
| [`24_REFERENCE_DESIGN.md`](docs/24_REFERENCE_DESIGN.md) | il sistema attorno all'IP core — **per chi ha Vivado 2022.1** |
| [`11_NOTE_API.md`](docs/11_NOTE_API.md) | diario delle scoperte: messaggi d'errore esatti, cause, soluzioni |

**Il resto:**

```
docs/
  00_DIAGNOSI.md           perché Prova_1 non arrivava in fondo (causa strutturale unica)
  01_PIANO.md              perimetro, decisioni con le alternative scartate, rischi
  03_AMBIENTE.md           audit macchina, add-on, versioni Vivado supportate
  04_CONVENZIONI.md        regole di progetto vincolanti (R1…R8)
  05_PROCEDURA.md          i passi con deliverable e gate
  10_SPEC_TEST.md          Test 1 — infrastruttura, concluso (storico)
  12_RICERCA_TOOLCHAIN.md  ricerca sistematica su doc MathWorks e artefatti installati
  21_SPEC_WRAPPER.md       Test 2 — specifica del wrapper, con invarianti e criteri
```

```
scripts/
  soc_params.m             UNICA fonte di verità + controlli di coerenza
  budget_report.m          equazione di progetto: cicli disponibili per il calcolo
  ref_model.m              il giudice, scritto nell'ordine di operazioni dell'hardware
  gen_vectors.m            510 vettori, seed 20260728
  build_soc_{fpga,proc,top}.m
  build_wrapper_fpga.m     costruisce il wrapper AXI4-Lite (Test 2)
  wrapper_sim_solve.m      simula un solve e dice cos'e' successo (usato da 2 chiamanti)
  run_wrapper_unit_sim.m   banco del wrapper: 4 sotto-prove + watchdog
  latency_study.m          P10: overhead misurato + cicli disponibili per stack PS
  run_system_sim.m         simulazione di sistema + confronto numerico
  run_regression.m         un comando → PASS/FAIL
  check_board_plugin.m     verifica il plugin board contro i board file Vivado
  check_refdesign.m        verifica che i 4 file del reference design concordino
  validate_refdesign.m     esegue il block design in Vivado (serve la 2022.1)
  export_r2023b.m          REGOLA R1
models/                    soc_top · soc_fpga · soc_proc · soc_wrapper_fpga
                           + *_ref.slx (storici, read-only)
test/                      vectors.mat (rigenerabile, non versionato)
hdlplugins/                +PYNQZ1: plugin board + reference design AXI4-Lite
                           (plugin_rd, system_top.tcl, axilite.dtsi)
ps/                        (vuota) lato ARM
vivado/                    (vuota) progetto e report, rigenerabili
```

---

## Chi può eseguire cosa

Il repository è condiviso fra due postazioni con versioni diverse. Questa
tabella evita il tentativo a vuoto.

| | serve | verificato? |
|---|---|---|
| **aprire i modelli** `.slx` | R2023b o successiva | ✅ gate **T16**, che rilegge i file — non solo `export_r2023b` |
| **rigenerare i modelli** (`build_*`) e la regressione | **R2026a** | ✅ ricostruzione da zero, 131 s + 15 gate |
| **usare la board e il reference design** in HDL Coder | R2023b+ *in linea di principio* | ⚠️ **non provato**: qui non c'è R2023b |
| **costruire il block design / il bitstream** | **Vivado 2022.1 o 2024.1** | ⚠️ qui c'è solo la 2026.1 → `validate_refdesign` dà `parziale` |

> **La regola R1 garantisce i modelli, non gli script.** Il gate T16 rilegge ogni
> `.slx` in `models/` e pretende che sia R2023b; nessuno ha mai eseguito gli
> script di questa cartella su R2023b, e non c'è un gate che lo affermi.
>
> T16 esiste perché per otto commit R1 è stata **violata**: `export_r2023b`
> dichiarava successo e i file su disco erano R2026a, perché il risultato
> dell'export veniva scartato a valle ([`11_NOTE_API` §15](docs/11_NOTE_API.md)).
> Verificare il comando non basta: va riletto il file.
> Un'ispezione ha escluso costrutti introdotti dopo il 2023 nei file che servono
> per il deploy (`hdlplugins/`, `check_refdesign`, `validate_refdesign`), ma
> **ispezionare non è provare**.
>
> Chi è su R2023b e vuole solo arrivare al bitstream **non ha bisogno dei nostri
> script**: gli bastano `addpath('hdlplugins')` e l'HDL Workflow Advisor. Il
> percorso minimo è in [`docs/24_REFERENCE_DESIGN.md`](docs/24_REFERENCE_DESIGN.md) §24.5.

---

## Ambiente

| | versione |
|---|---|
| MATLAB / Simulink / HDL Coder / SoC Blockset / Embedded Coder | **R2026a** |
| Vivado per i workflow integrati | **2022.1** o 2024.1 — la 2026.1 **non è supportata** |
| Compatibilità dei modelli versionati | **R2023b** (regola R1) |
| Board di simulazione / di deploy | ZedBoard (stesso die) / PYNQ-Z1 |

## ⚠ Prima di ogni commit che tocca un `.slx`

```matlab
export_r2023b()
```

I modelli versionati devono restare apribili con **R2023b**: il repo è condiviso e
l'aggiornamento di formato di un `.slx` è irreversibile. Lo script si ferma con
errore se un modello non è esportabile — non salta mai in silenzio.
