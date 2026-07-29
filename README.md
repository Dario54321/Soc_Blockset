# SoC Blockset — Pynq-Z1 / accelerazione FPGA per un MPC

## Obiettivo del progetto

Applicare **MATLAB SoC Blockset** per accelerare via FPGA il calcolo di un
controllore **MPC (Model Predictive Control)**, spostando su hardware (logica
programmabile) le operazioni più onerose che oggi girano solo su software (ARM).
La scheda target è la **Pynq-Z1** (Xilinx Zynq-7020, `xc7z020-clg400-1`: PS+PL
sullo stesso silicio).

---

## Due filoni di lavoro

Il repository contiene due percorsi distinti. Serve saperlo prima di leggere:
alcune conclusioni valgono solo dentro il proprio filone.

| | Filone A — apprendimento e misura | Filone B — il trasporto per l'MPC vero |
|---|---|---|
| **dove** | `Prova_1.slx`, `HDL_Test/`, `docs/` | `HDL_Test/Prova_2/` |
| **cosa** | modello didattico (due matrici via AXI4-Stream), misure Vivado reali, toolchain ARM, esplorazione SoC Builder | contratto d'interfaccia + wrapper AXI4-Lite verso un blocco di calcolo di terzi |
| **stato** | **concluso**, riusabile come metodo e come numeri | **attivo** |
| **flusso** | SoC Builder / sintesi Vivado diretta via Tcl | HDL Coder *IP Core Generation* |

Il filone A ha prodotto i numeri di dimensionamento e ha sbloccato il toolchain
ARM; il filone B è dove si costruisce l'infrastruttura che andrà davvero in
produzione. **Non si contraddicono**: dove si sono sovrapposti — le regole
strutturali del modello FPGA — sono arrivati alla stessa conclusione per strade
indipendenti.

---

## Da dove si comincia

| Se vuoi… | Vai a |
|---|---|
| **capire lo stato del lavoro attivo e far girare qualcosa** | [`HDL_Test/Prova_2/README.md`](HDL_Test/Prova_2/README.md) |
| **sapere cosa manca e cosa fare dopo** | [`HDL_Test/Prova_2/docs/13_APERTI.md`](HDL_Test/Prova_2/docs/13_APERTI.md) |
| **arrivare al bitstream (serve Vivado 2022.1)** | [`HDL_Test/Prova_2/docs/24_REFERENCE_DESIGN.md`](HDL_Test/Prova_2/docs/24_REFERENCE_DESIGN.md) §24.5 |
| **non ripetere errori già fatti sul toolchain** | [`HDL_Test/Prova_2/docs/11_NOTE_API.md`](HDL_Test/Prova_2/docs/11_NOTE_API.md) e [`docs/socbuilder_notes.md`](docs/socbuilder_notes.md) |
| **imparare a sintetizzare in Vivado da un modello SoC Blockset** | [`docs/vivado_synthesis_guide/`](docs/vivado_synthesis_guide/) |
| **i numeri di risorse e timing misurati davvero** | [`docs/hdl_findings.md`](docs/hdl_findings.md) |

---

# Filone B — il trasporto ARM ↔ FPGA *(attivo)*

**Perimetro**: costruire il **trasporto** fra l'ARM e un blocco di calcolo FPGA,
dentro un budget d'anello di **33 µs**. Il calcolo dell'MPC (inversione 3×3 e
altro) è dentro un blocco di **un altro ingegnere** e non è nel nostro
perimetro: il deliverable è
**[un contratto d'interfaccia](HDL_Test/Prova_2/docs/20_CONTRATTO_INTERFACCIA.md)
più il suo wrapper**.

**Stato**: l'infrastruttura simula ed è verificata bit-esatta (Test 1, concluso).
Il wrapper AXI4-Lite — CSR, handshake `start`/`done`, watchdog, contatore di
cicli — è costruito e verificato in simulazione; la PYNQ-Z1 è registrata in HDL
Coder e il reference design che le sta attorno è scritto (Test 2).

**Niente di questo filone è ancora girato su hardware.** Da qui in poi serve
Vivado 2022.1: costruire il reference design e il bitstream. Quel che è scritto
qui è verificato per quanto si può senza quel tool — e dove non si è potuto, è
detto quale verifica manca.

> ### ▶ Il prossimo passo, per chi ha Vivado 2022.1
> Tre comandi in ordine, con un esito atteso ciascuno:
> [`24_REFERENCE_DESIGN` §24.5](HDL_Test/Prova_2/docs/24_REFERENCE_DESIGN.md).
> Il primo è `validate_refdesign()`, che deve rispondere `completa`.

> ### ⚠ Otto domande in attesa
> Il [contratto d'interfaccia](HDL_Test/Prova_2/docs/20_CONTRATTO_INTERFACCIA.md) §8
> elenca otto domande che servono per chiudere la bozza. Le più urgenti: **cosa
> sono i due vettori 3×1** che attraversano il confine, e **cos'altro lo
> attraverserà** (i dati grezzi di radar/lidar restano sull'ARM?). La seconda
> decide la taglia del progetto.

> ### ⚠ Una decisione da prendere: cosa gira sull'ARM
> Bare-metal o Linux con registri mappati. Non è una scelta tecnica in senso
> stretto — dipende da cosa deve fare il PS oltre a questo anello — ma **il
> prezzo ora è quantificato: 850 cicli, il 26 % del budget**
> ([D3 in `01_PIANO`](HDL_Test/Prova_2/docs/01_PIANO.md)). Un driver di kernel
> Linux è invece **fuori per aritmetica**: costerebbe 50 µs di solo trasporto
> contro 33 di budget.

## Cosa è stato dimostrato

**Test 1 — infrastruttura.** La catena completa simula ed è numericamente
corretta, con **errore 0** contro il modello di riferimento:

```
ARM: calcola due matrici  → impacchetta in 25 elementi sfix32_En16
   → reinterpreta a uint32 (Stored Integer: stessi bit)  → Stream Write
      → Software to AXI4-Stream (PS memory, 8 buffer, 100 MHz, 32 bit)
         → PL: reinterpreta  → spacchetta  → sonda aritmetica in virgola fissa
```

**Test 2 — il wrapper.** `soc_wrapper_fpga` implementa il confine verso il
blocco di terzi: registri AXI4-Lite, macchina a stati insensibile alla latenza,
**watchdog** (l'unica cosa che impedisce all'ARM di restare appeso se il blocco
tace) e un contatore che espone la latenza reale nel registro `CYCLES`. Da lì
esce il numero da mettere in mano all'altro ingegnere:

> **ordine dei 3000 cicli a 100 MHz** — ~3150 con PS bare-metal, ~2300 con Linux
> e registri mappati.
> → [`22_STUDIO_LATENZA`](HDL_Test/Prova_2/docs/22_STUDIO_LATENZA.md)

**Board e reference design.** La PYNQ-Z1 non è fra le sedici board che MathWorks
fornisce ad HDL Coder: registrata in `HDL_Test/Prova_2/hdlplugins/+PYNQZ1`,
insieme al sistema dentro cui l'IP core si innesta. I pin non vengono da un
manuale ma dai **board file Vivado già installati** (impronte SHA-256 in
`board_files_manifest.m`), e il Processing System non è trascritto a mano come
nei reference design MathWorks: si applica il preset di quei board file.
→ [`23_BOARD_PYNQZ1`](HDL_Test/Prova_2/docs/23_BOARD_PYNQZ1.md),
[`24_REFERENCE_DESIGN`](HDL_Test/Prova_2/docs/24_REFERENCE_DESIGN.md)

**15 gate di regressione, ognuno provato anche in fallimento** — compresi il
watchdog (fatto tacere di proposito), il contatore dei cicli, la mappatura dei
pin e la coerenza fra i file del reference design. L'intera cartella si
ricostruisce da zero in ~2 minuti, verificato cancellando i modelli e rifacendoli.

## Cosa NON è ancora dimostrato

- **Niente di questo filone è mai girato su hardware reale.**
- I 33 µs vengono da un paper, **non sono stati misurati da noi**.
- I costi di trasporto ARM↔FPGA sono **ordini di grandezza da letteratura**, non
  misure su questa board. Bastano a scartare un'alternativa che costa trenta
  volte più di un'altra, non a garantire la terza cifra.
- La latenza del blocco di calcolo di terzi è **ignota**: si misurerà con il
  registro `CYCLES` del wrapper, senza toccare il loro codice.
- Handshake e priming del canale del Test 1 sono segnaposto: **qualunque misura
  di throughput fatta adesso sarebbe falsa**.

---

# Filone A — modello didattico, misure reali, toolchain *(concluso)*

## Come funziona, in breve

Uno Zynq ha due mondi sullo stesso chip: il **PS** (Processing System, un vero
processore ARM che esegue software) e il **PL** (Programmable Logic, la parte
FPGA riconfigurabile). SoC Blockset è il toolbox MATLAB/Simulink che modella
*entrambi* insieme in un solo schema, permettendo di simulare come comunicano,
poi generare sia il codice software (ARM) sia il bitstream hardware (FPGA) dallo
stesso modello.

Nel modello didattico il canale è **AXI4-Stream** — un protocollo a flusso
continuo (niente indirizzi di memoria, solo un flusso con handshake
`TVALID`/`TREADY`), materializzato nel blocco `Software to AXI4-Stream`,
affiancato da un `Task Manager` (che decide *quando* il software deve girare) e
da un subsystem `FPGA`.

## Le scelte tecniche, spiegate

### Perché fixed-point e non floating-point

I dati che viaggiano tra ARM e FPGA nascono come `double`. Il lato software del
canale AXI4-Stream però **non accetta virgola mobile** — solo interi. La
soluzione è la **reinterpretazione bit-esatta** (`typecast`): stessi bit, letti
come intero, trasmessi, e riletti come `double` — nessuna perdita, solo un
cambio di etichetta. Misurato con sintesi Vivado reale: **zero risorse**.

Quando serve un **vero calcolo**, i numeri vanno in **fixed-point**: la virgola
mobile in hardware richiederebbe IP molto più costosi. Misurato: una
moltiplicazione fixed-point costa **1 DSP48** (su 220 dello Zynq-7020) e circa
**3.8 ns** — numeri concreti per stimare quante operazioni concorrenti regge il
chip. Dettaglio in [`docs/hdl_findings.md`](docs/hdl_findings.md).

### Perché un subsystem "Processor" avvolge il Task Manager

Per generare software+bitstream con `socBuilder`, l'algoritmo triggerato dal
Task Manager **deve** vivere in un Model Reference. Inoltre — scoperta
confrontando un esempio ufficiale MathWorks — il `Task Manager` non deve stare
allo stesso livello del blocco del canale: va **annidato dentro un subsystem
dedicato** ("Processor") insieme al Model Reference. Senza, il meccanismo che
collega l'evento del canale al task non "vede" la connessione e la generazione
fallisce con *"Unable to find a corresponding event"*.
→ [`docs/socbuilder_notes.md`](docs/socbuilder_notes.md)

## Risultati e blocchi risolti

- **Toolchain ARM sbloccato senza SD card né USB fisica.** La conclusione
  precedente ("serve una SD vera") era sbagliata: erano tre problemi software
  indipendenti — `codertarget.zynq.internal.addCompilerPath` da chiamare prima
  del build; un bug di MATLAB su Windows per cui `system()` non cerca eseguibili
  nella cartella corrente (serve `setenv('PATH', ['.;' getenv('PATH')])`), che
  rompeva silenziosamente anche il sysroot; e un header (`iio.h`) da copiare
  dove il build lo cerca. **Risultato verificato**: `buildModel` con
  `BuildType='Processor only'` produce un vero `.elf` ARM.
- **Sintesi Vivado reale** del DUT `ComputeCore`: **0 LUT, 0 registri, 0 DSP** —
  coerente con la misura nota per il reshape puro (in quel modello la
  moltiplicazione è lato software).
- **Bitstream via SoC Builder: fermato per scelta strategica.** Scoperte quattro
  regole strutturali non documentate del validatore, applicate tutte, e il build
  arriva a un errore di categoria diversa (`Invalid HDL Implementation Parameter
  'IPCoreVersion'`). Decisione: fermarsi con il modello didattico — le regole
  sono un *metodo* riusabile, non uno stato trasferibile all'MPC vero.
  ⚠ Avvertimento documentato in `docs/socbuilder_notes.md`: fra le modifiche c'è
  **un pass-through vuoto di `streamEnable`** che soddisfa la topologia ma non
  la semantica — da verificare numericamente prima di fidarsene, e da **non**
  copiare acriticamente sull'MPC vero.
- **`soc.sdk.BoardSupport`** (SoC Blockset R2019b+) registra board SoC
  personalizzate via script, senza wizard: provata funzionante. È la via giusta
  **per SoC Builder** — da non confondere con `hdlcoder.Board`, usata nel filone
  B per il flusso IP Core Generation
  ([`23_BOARD_PYNQZ1` §23.2bis](HDL_Test/Prova_2/docs/23_BOARD_PYNQZ1.md)).

---

## Struttura del repository

```
Prova_1.slx               modello didattico, funzionante in simulazione
Prova_1.slx.original      copia di una versione precedente
FPGA_TEST.slx             subsystem FPGA isolato per la codegen HDL
docs/                     filone A: findings HDL, note socBuilder, guida sintesi Vivado

HDL_Test/
  FPGA_Prova1.slx                  reshape puro → costo zero
  FPGA_Prova1_fixedpoint.slx       con moltiplicazione → 1 DSP48, ~3.8 ns
  vivado_synth*/                   script Tcl e report di sintesi reali
  socbuilder_test/                 ristrutturazione per socBuilder

  Prova_2/                    ← FILONE B, LAVORO ATTIVO
    README.md                 stato, comandi, architettura
    docs/                     diagnosi, piano, procedura, note API, punti aperti
    scripts/                  tutto è generato da script
    models/                   soc_top · soc_fpga · soc_proc · soc_wrapper_fpga
    hdlplugins/               board PYNQ-Z1 + reference design per HDL Coder
```

`Prova_1` e `HDL_Test/vivado_synth*` sono **materiale storico**: si conservano
perché documentano i tentativi e i loro risultati, ma non si sviluppano più.

---

## Ambiente

| | versione |
|---|---|
| MATLAB del filone B | **R2026a** (SoC Blockset, HDL Coder, Embedded Coder, support package AMD) |
| MATLAB del filone A | **R2023b** |
| Vivado per i workflow integrati | **2022.1** (o 2024.1) — la **2026.1 non è supportata** da R2026a |
| Board di simulazione | ZedBoard (stesso die `xc7z020` della PYNQ-Z1) |
| Board di deploy | PYNQ-Z1, con board plugin registrato a mano |

> La PYNQ-Z1 **non è fra le board supportate da SoC Blockset**: si usa SoC
> Blockset per architettura e simulazione, e HDL Coder per il deployment.
> Decisione e alternative scartate in
> [`01_PIANO.md`](HDL_Test/Prova_2/docs/01_PIANO.md).
>
> Chi lavora su una versione diversa trovi in
> [`Prova_2/README.md`](HDL_Test/Prova_2/README.md) la tabella *"chi può
> eseguire cosa"*: dice cosa è garantito e cosa non è mai stato provato.

---

## Regole di progetto

Vincolanti per il filone B, per esteso in
[`04_CONVENZIONI.md`](HDL_Test/Prova_2/docs/04_CONVENZIONI.md).

1. **I `.slx` versionati restano apribili con R2023b.** Il repo è condiviso e
   l'aggiornamento di formato è irreversibile. Prima di ogni commit che tocca un
   modello: `export_r2023b()`.
2. **Una decisione, un posto solo.** Se due componenti possono fissare la stessa
   cosa, uno dei due è di troppo.
3. **Niente hardware prima della simulazione.**
4. **Tutto rigenerabile**: i modelli sono artefatti di script, non sorgenti.
5. **Le decisioni si documentano quando si prendono**, con l'alternativa
   scartata.
6. **Versioni dichiarate**, mai "l'ultima".
7. **Un gate mai visto fallire non è un gate**: ogni verifica si prova anche
   rompendo di proposito ciò che verifica.
8. **Le scoperte sul toolchain si scrivono con il messaggio d'errore esatto**,
   così sono ricercabili.

---

## Note per chi riprende questo lavoro

- Il `.gitignore` esclude deliberatamente le cartelle generate/rigenerabili
  (cache MATLAB, progetti Vivado, HDL intermedio, profiling del Task Manager):
  solo i `.slx` sorgente, gli script e i report finali sono tracciati.
- **README e documentazione vanno tenuti aggiornati ad ogni push** — è una regola
  esplicita del proprietario del progetto.
- I **board file Vivado della PYNQ-Z1 non sono nel repository**: il pacchetto
  d'origine non dichiara una licenza. Origine e impronte SHA-256 in
  [`hdlplugins/board_files_manifest.m`](HDL_Test/Prova_2/hdlplugins/board_files_manifest.m),
  così chiunque verifica in un comando di avere la stessa revisione.
