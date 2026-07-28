# SoC Blockset — Pynq-Z1 / accelerazione FPGA per MPC

## Obiettivo del progetto

Applicare **MATLAB SoC Blockset** (R2023b) per accelerare via FPGA il calcolo di un controllore **MPC (Model Predictive Control)**, spostando su hardware (logica programmabile) le operazioni più onerose che oggi girano solo su software (ARM). La scheda target finale è la **Pynq-Z1** (chip Xilinx Zynq-7020, PS+PL sullo stesso silicio).

Questo repository contiene il percorso di apprendimento e sperimentazione che porta a quell'obiettivo: prima un modello didattico minimale (due matrici moltiplicate, inviate dal processore alla FPGA via streaming), poi misure reali di risorse hardware e tempi, poi la costruzione dell'infrastruttura di build reale (SoC Builder).

## Stato attuale

- **Modello didattico completo e funzionante in simulazione**: `Prova_1.slx`. Calcola il prodotto di due matrici (3x3) sul lato software (rappresentando l'ARM), lo converte in un formato trasmissibile bit-esatto, lo invia via **AXI4-Stream** (protocollo standard ARM AMBA) al lato FPGA, dove viene ricomposto.
- **Risorse hardware e tempi reali misurati** con sintesi Vivado 2022.1 vera (non stime teoriche) — vedi [`docs/hdl_findings.md`](docs/hdl_findings.md) per il dettaglio completo.
- **Infrastruttura di build reale (`socBuilder`)** in costruzione: risolto un blocco architetturale importante che impediva di generare software+bitstream — vedi sezione sotto e [`docs/socbuilder_notes.md`](docs/socbuilder_notes.md).

## Perché SoC Blockset e come funziona (in breve)

Uno Zynq ha due mondi sullo stesso chip: il **PS** (Processing System, un vero processore ARM che esegue software) e il **PL** (Programmable Logic, la parte FPGA riconfigurabile). SoC Blockset è il toolbox MATLAB/Simulink che modella *entrambi* insieme in un solo schema, permettendo di simulare come comunicano, poi generare sia il codice software (ARM) sia il bitstream hardware (FPGA) dallo stesso modello.

Il "canale" scelto per far viaggiare i dati tra i due mondi è **AXI4-Stream** — un protocollo a flusso continuo (niente indirizzi di memoria, solo un flusso di byte con segnali di handshake `TVALID`/`TREADY`). Nel nostro modello, questo si materializza nel blocco `Software to AXI4-Stream`, affiancato da un `Task Manager` (che decide *quando* il codice software deve girare) e da un subsystem `FPGA` (la logica che gira davvero sul silicio riconfigurabile).

## Struttura del repository

```
Prova_1.slx              — il modello principale, funzionante in simulazione
Prova_1.slx.original      — copia di sicurezza di una versione precedente
FPGA_TEST.slx             — copia di lavoro usata per esplorare l'HDL Workflow Advisor in GUI
HDL_Test/                 — tutti gli esperimenti di verifica (vedi sotto)
docs/                     — spiegazioni tecniche di dettaglio
```

Dentro `HDL_Test/`:
- `FPGA_Prova1.slx` — il subsystem FPGA isolato, usato per misurare il costo hardware del solo "reshape" (riorganizzazione dati, senza calcolo) → **risultato: costo zero, è pura re-instradazione di fili**.
- `FPGA_Prova1_fixedpoint.slx` — stesso subsystem ma con una vera moltiplicazione in aritmetica fixed-point (a virgola fissa) → **risultato: 1 blocco DSP48 dedicato per moltiplicazione, ~3.8 ns di ritardo reale**.
- `vivado_synth*/` — le cartelle con gli script Tcl e i report reali di sintesi Vivado (risorse usate, timing) per ciascun test.
- `socbuilder_test/` — il tentativo (riuscito) di ristrutturare il modello per renderlo compatibile con `socBuilder`, il tool che genera davvero software+bitstream per la scheda.

## Le scelte tecniche principali, spiegate

### Perché fixed-point e non floating-point?

I dati che viaggiano tra ARM e FPGA nascono come numeri `double` (virgola mobile). Il lato software del canale AXI4-Stream però **non accetta virgola mobile direttamente** — solo interi (`uint16/32/64`). La soluzione usata è la **reinterpretazione bit-esatta** (`typecast` in MATLAB): si prendono gli stessi 64 bit di un `double` e li si legge come un intero, si trasmettono, e dall'altra parte si rileggono come `double` — nessuna perdita di precisione, nessun vero calcolo, solo un cambio di "etichetta" sul dato. Misurato con sintesi Vivado reale: questo costa **zero risorse hardware** (nessun LUT, nessun DSP).

Quando invece serve fare un **vero calcolo** (una moltiplicazione, ad esempio, come richiederà l'MPC), i numeri vanno rappresentati in **fixed-point** (virgola fissa, es. 16 bit con una parte frazionaria fissa) — usare la virgola mobile reale in hardware richiederebbe un supporto floating-point IP molto più costoso in risorse. Misurato: una moltiplicazione fixed-point costa **1 DSP48 dedicato** (su 220 disponibili nello Zynq-7020) e circa **3.8 ns** di ritardo — numeri concreti da usare per stimare quante operazioni concorrenti può reggere il chip per l'MPC finale.

### Perché un subsystem "Processor" avvolge il Task Manager?

Il blocco `Task Manager` decide quando l'algoritmo software deve eseguire (agganciato a un evento hardware, in questo caso "il canale ha nuovi dati"). Per generare davvero software+bitstream con `socBuilder`, l'algoritmo triggerato dal Task Manager **deve** vivere in un **Model Reference** (un file `.slx` separato, referenziato come blocco) — un subsystem normale funziona solo in simulazione, non per la build reale.

Inoltre — scoperta confrontando un esempio ufficiale MathWorks funzionante — `Task Manager` non deve stare allo stesso livello del blocco del canale (`Software to AXI4-Stream`): va **annidato dentro un subsystem dedicato** (chiamato per convenzione "Processor") insieme al Model Reference che contiene l'algoritmo. Senza questo annidamento, il meccanismo interno di SoC Blockset che collega automaticamente l'evento del canale al task non riesce a "vedere" la connessione, anche se elettricamente il filo è disegnato correttamente — e la generazione fallisce con un errore poco intuitivo ("Unable to find a corresponding event"). Dettagli completi in [`docs/socbuilder_notes.md`](docs/socbuilder_notes.md).

## Prossimi passi

- **Installare il toolchain di cross-compilazione ARM** (via MATLAB Add-Ons Manager → Hardware Setup) — è l'unico pezzo mancante per completare davvero la generazione software: il pipeline (`socModelBuilder`/`buildModel`) genera correttamente il sistema software e il codice C reale dell'algoritmo, fermandosi solo alla compilazione finale per mancanza del compilatore ARM installato.
  - **Verificato**: questo blocco vale sia per `BuildType='Processor only'` sia per `BuildType='FPGA only'` — anche scegliendo "solo FPGA" il pipeline genera comunque il lato software e tenta comunque la compilazione ARM di `ComputeAlgorithm`, fallendo con lo stesso errore. Non esiste una build parziale che aggiri il toolchain mancante. Dettagli in [`docs/socbuilder_notes.md`](docs/socbuilder_notes.md).
  - Il wizard di Hardware Setup richiede una vera SD card/chiavetta USB rimovibile nello step "Select a Drive"; un disco virtuale (VHD) creato con `diskpart` non basta, perché Windows lo classifica sempre come `Fixed`/`File Backed Virtual`, mai come `Removable` — approfondito anch'esso in `docs/socbuilder_notes.md`.
  - **Anche il download manuale del compilatore ARM reale (Linaro GCC 6.3.1) e il suo piazzamento nella cartella corretta non bastano**: MATLAB richiede una registrazione interna che solo il wizard ufficiale (con SD/USB vera) può scrivere — verificato provando anche il wizard di un pacchetto correlato ("SoC Blockset Support Package for Xilinx Devices"), che porta comunque allo stesso requisito hardware. Dettagli completi in `docs/socbuilder_notes.md`.
- Una volta installato il toolchain (con media rimovibile reale), ripetere il build con `BuildType='Processor and FPGA'` per ottenere anche il bitstream.
- Applicare gli stessi principi (canale dati, fixed-point, task/eventi) all'algoritmo MPC vero, non solo alla demo con due matrici — nel frattempo si può procedere in parallelo con sintesi Vivado diretta (via Tcl) su blocchi dell'algoritmo MPC, senza dipendere dal toolchain ARM.
- Valutare se e come usare la Pynq-Z1 come scheda reale (la sua registrazione come "board" in MATLAB risulta al momento incompleta/da sistemare — nel frattempo si usa `ZedBoard`, stesso chip Zynq-7020, come riferimento per i test).

## Note per chi riprende questo lavoro 

- Il file `.gitignore` esclude deliberatamente le cartelle generate/rigenerabili (cache MATLAB, progetti Vivado completi, codice HDL intermedio) — solo i modelli `.slx` sorgente, gli script `.tcl` di sintesi e i report finali sono tracciati.
- Ogni volta che si fa un push su questo repository, README e documentazione in `docs/` vanno tenuti aggiornati con lo stato più recente — è una regola esplicita del proprietario del progetto.
