# SoC Blockset — accelerazione FPGA di un MPC su Pynq-Z1

Co-design hardware/software su **Xilinx Zynq-7020** (scheda **Pynq-Z1**,
`xc7z020-clg400-1`): portare sulla logica programmabile la parte più onerosa di
un controllore **MPC**, lasciando all'ARM supervisione e I/O.

Il repository raccoglie il percorso completo: prima un modello didattico con cui
imparare il toolchain e misurare costi reali in hardware, poi l'infrastruttura
di trasporto destinata all'MPC vero.

---

## Come funziona, in breve

Uno Zynq ha due mondi sullo stesso chip: il **PS** (Processing System — un vero
processore ARM che esegue software) e la **PL** (Programmable Logic — la parte
FPGA riconfigurabile). Accelerare significa spostare del calcolo dal primo alla
seconda; il problema che ne nasce è **come far viaggiare i dati fra i due**, e a
quale costo in tempo.

**SoC Blockset** è il toolbox MATLAB/Simulink che modella entrambi i lati in un
solo schema: si simula come comunicano, e dallo stesso modello si generano il
codice ARM e il bitstream FPGA.

Tre scelte attraversano tutto il progetto e conviene averle presenti leggendo:

- **Il canale.** Fra ARM e PL si può passare per un flusso continuo
  (**AXI4-Stream**, con DMA) oppure per **registri** (**AXI4-Lite**). Non è una
  preferenza: sotto una certa taglia di payload il costo fisso del DMA domina e
  i registri vincono; sopra, il contrario. Il punto di pareggio decide
  l'architettura.
- **La rappresentazione dei numeri.** Il lato software del canale non accetta
  virgola mobile: i `double` si trasmettono **reinterpretandone i bit** come
  interi e rileggendoli dall'altra parte — nessuna perdita, costo hardware
  nullo. Ma quando serve un **calcolo** vero, in FPGA si lavora in **virgola
  fissa**: il floating-point richiederebbe IP molto più costosi.
- **Chi possiede cosa.** Il calcolo dell'MPC è dentro un blocco FPGA di un altro
  ingegnere. Il perimetro di questo lavoro è il **trasporto** e il **wrapper**
  in cui quel blocco si innesta — non il calcolo.

---

## Due filoni

| | **A — apprendimento e misura** | **B — il trasporto per l'MPC** |
|---|---|---|
| dove | `Prova_1.slx`, `HDL_Test/`, `docs/` | `HDL_Test/Prova_2/`, bring-up in `HDL_Test/TEST2/` |
| cosa | modello didattico via AXI4-Stream, misure Vivado reali, toolchain ARM, esplorazione SoC Builder | contratto d'interfaccia e wrapper AXI4-Lite verso il blocco di terzi |
| flusso | SoC Builder / sintesi Vivado via Tcl | HDL Coder *IP Core Generation* |
| stato | **concluso** — vale come metodo e come numeri | **attivo** — bitstream reale programmato su hardware fisico *(31/07)*; resta il test funzionale via registri |

I due filoni non si contraddicono: dove si sono sovrapposti sono arrivati alla
stessa conclusione per strade indipendenti.

**Coda al filone A**: il filone A si era fermato prima di un bitstream reale
(bloccato su `IPCoreVersion`, canale AXI4-Stream). Un esempio didattico
ricostruito da zero in `prove_2/` (tre modelli separati, canale **Register
Channel/AXI4-Lite** invece di AXI4-Stream, matrici 3x3 con moltiplicazione
vera) è arrivato dove il filone A non era arrivato: **un bitstream reale
completo**, via `socModelBuilder`/SoC Builder — vedi
[`docs/socbuilder_notes.md`](docs/socbuilder_notes.md) (sezione "ripreso da
zero con Register Channel") e [`docs/hdl_findings.md`](docs/hdl_findings.md)
(Risultato 4) per numeri e metodo. Board usata: ZedBoard (`clg484`, non ancora
`clg400` Pynq-Z1 reale — SoC Builder supporta nativamente solo ZedBoard tra le
board disponibili per questo meccanismo). Nessun deployment su hardware reale
ancora fatto.

---

## Come navigare

| Se cerchi… | Vai a |
|---|---|
| **lo stato del lavoro attivo, e come far girare qualcosa** | [`HDL_Test/Prova_2/README.md`](HDL_Test/Prova_2/README.md) |
| **cosa manca e qual è il prossimo passo** | [`Prova_2/docs/13_APERTI.md`](HDL_Test/Prova_2/docs/13_APERTI.md) |
| **cosa serve chiedere all'altro ingegnere** | [`Prova_2/docs/20_CONTRATTO_INTERFACCIA.md`](HDL_Test/Prova_2/docs/20_CONTRATTO_INTERFACCIA.md) |
| **come arrivare al bitstream** (serve Vivado 2022.1) | [`Prova_2/docs/24_REFERENCE_DESIGN.md`](HDL_Test/Prova_2/docs/24_REFERENCE_DESIGN.md) |
| **errori già incontrati sul toolchain**, con il messaggio esatto | [`Prova_2/docs/11_NOTE_API.md`](HDL_Test/Prova_2/docs/11_NOTE_API.md) · [`docs/socbuilder_notes.md`](docs/socbuilder_notes.md) |
| **quanto costa in hardware un'operazione** | [`docs/hdl_findings.md`](docs/hdl_findings.md) |
| **come sintetizzare in Vivado da un modello SoC Blockset** | [`docs/vivado_synthesis_guide/`](docs/vivado_synthesis_guide/) |
| **perché sono state prese le decisioni architetturali** | [`Prova_2/docs/01_PIANO.md`](HDL_Test/Prova_2/docs/01_PIANO.md) |

### Struttura del repository

```
Prova_1.slx               modello didattico, funzionante in simulazione
Prova_1.slx.original      versione precedente, conservata
FPGA_TEST.slx             subsystem FPGA isolato per la codegen HDL
docs/                     filone A: misure hardware, note SoC Builder, guida Vivado

prove_2/                  esempio da zero (Register Channel): primo bitstream reale
                          NB: cartella distinta da HDL_Test/Prova_2/ (filone B)
  MatMul_Processor.slx    lato software (ARM), genera A/B
  MatMul_FPGA.slx         lato FPGA, moltiplicazione matriciale 3x3 vera
  MatMul_Top.slx          Top: Register Channel + Register Write/Read, collega i due

HDL_Test/
  FPGA_Prova1.slx                  varianti FPGA-only del modello didattico
  FPGA_Prova1_fixedpoint.slx
  vivado_synth*/                   script Tcl e report di sintesi reali
  socbuilder_test/                 ristrutturazione per SoC Builder

  Prova_2/                    <-- FILONE B, LAVORO ATTIVO
    README.md                 stato, comandi, architettura
    docs/                     diagnosi, piano, procedura, note, punti aperti
    scripts/                  ogni modello è generato da qui
    models/                   artefatti rigenerabili (+ *_ref.slx storici)
    hdlplugins/               board Pynq-Z1 e reference design per HDL Coder
```

`Prova_1` e `HDL_Test/vivado_synth*` sono **materiale storico**: si conservano
perché documentano i tentativi e i loro esiti, ma non si sviluppano più.

---

## Ambiente

| | |
|---|---|
| MATLAB | **R2026a** (filone B) · **R2023b** (filone A) |
| Toolbox | SoC Blockset, HDL Coder, Embedded Coder, support package AMD |
| Vivado | **2022.1** o 2024.1 per i workflow integrati — la 2026.1 **non è supportata** da R2026a |
| Board | Pynq-Z1 (deploy) · ZedBoard come proxy di simulazione, stesso die |

La Pynq-Z1 **non è fra le board supportate da SoC Blockset**: è registrata a mano
per HDL Coder in `Prova_2/hdlplugins/`. I suoi **board file Vivado non sono in
questo repository** — il pacchetto d'origine non dichiara una licenza. Origine e
impronte SHA-256 in
[`board_files_manifest.m`](HDL_Test/Prova_2/hdlplugins/board_files_manifest.m):
un comando dice se la revisione installata è quella giusta.

Chi lavora su versioni diverse trovi in
[`Prova_2/README.md`](HDL_Test/Prova_2/README.md) la tabella *"chi può eseguire
cosa"*, che distingue ciò che è verificato da ciò che non è mai stato provato.

---

## Contribuire

Il filone B segue otto regole vincolanti, per esteso in
[`04_CONVENZIONI.md`](HDL_Test/Prova_2/docs/04_CONVENZIONI.md). Due riguardano
chiunque tocchi il repository:

- **I `.slx` versionati devono restare apribili con R2023b.** L'aggiornamento di
  formato è irreversibile e il repo è condiviso. Prima di ogni commit che tocca
  un modello: `export_r2023b()` dalla cartella `Prova_2/scripts` — **e si
  committa il risultato**, non lo si scarta come rumore binario. Il gate T16
  rilegge i file e blocca la regressione se qualcuno lo dimentica.
- **README e documentazione si aggiornano nello stesso commit del codice.**

Per il filone B vale inoltre che ogni affermazione ha un gate che la verifica, e
ogni gate è stato provato anche in fallimento: `run_regression` dalla cartella
`Prova_2/scripts`.

---

## Riferimenti

**Interni** — tutti i collegamenti citati sopra sono stati verificati esistenti
al momento di questo commit. Non c'è un controllo automatico che li mantenga
tali: chi sposta o rinomina un documento li ricontrolli.

**Esterni**, consultati e verificati durante il lavoro:

| Cosa | Dove | Verificato |
|---|---|---|
| Board file Vivado Pynq-Z1 | [cathalmccabe/pynq-z1_board_files](https://github.com/cathalmccabe/pynq-z1_board_files) | **nessun file di licenza** (29/07/2026) — per questo non sono ridistribuiti qui |
| Esempio ufficiale di board di terze parti registrata a mano | `toolbox/shared/hdlmotorcontrol/socMotorControl/refdesigns/trenzboard/` nell'installazione MATLAB | usato come template per `hdlplugins/+PYNQZ1` |
| Reference design AXI4-Lite di riferimento | `toolbox/hdlcoder/boards/amd/+ZedBoard/+vivado_base_2022_1/` | topologia ricalcata, PS sostituito dal preset della board |
| Esempio SoC Blockset a tre modelli | `toolbox/soc/socexamples/soc_swhw_stream_*.slx` | da cui proviene la configurazione dei modelli del Test 1 |

Le fonti MathWorks usate per le singole scoperte sono citate punto per punto,
con marcatori di affidabilità, in
[`Prova_2/docs/12_RICERCA_TOOLCHAIN.md`](HDL_Test/Prova_2/docs/12_RICERCA_TOOLCHAIN.md).
