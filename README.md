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

- **RISOLTO — il toolchain ARM funziona, senza nessuna SD card/USB fisica.** La conclusione precedente di questa sezione ("serve una SD/USB vera per completare il wizard") era **sbagliata**: il blocco non era hardware, erano tre problemi software indipendenti, tutti risolti via script, senza toccare il wizard "Hardware Setup":
  1. Il compilatore ARM Linaro (scaricato manualmente in una sessione precedente) va reso visibile a MATLAB chiamando `codertarget.zynq.internal.addCompilerPath('6.3.1','AARCH32')` prima del build — imposta l'env var che il Makefile generato si aspetta.
  2. **Bug generico di MATLAB su Windows**: `system()` non cerca eseguibili/`.bat` nella cartella corrente (a differenza di una shell interattiva) — serviva `setenv('PATH', ['.;' getenv('PATH')])` prima del build. Questo bug rompeva silenziosamente anche il collegamento automatico del sysroot, che è la vera causa dietro il warning "sysroot not registered" visto in tutti i tentativi precedenti.
  3. Un header pubblico (`iio.h`, libreria di supporto incidentale, non richiede licenza) mancava dalla cartella dove il build lo cerca — copiato una volta per tutte da dove MATLAB lo scarica già (`3P.instrset/libiio.instrset/...`) alla cartella attesa (`toolbox/shared/libiio/base/include/`).
  - **Risultato verificato sul disco**: con questi tre fix e senza nessuna modifica manuale al Makefile generato, `socModelBuilder`/`buildModel` con `BuildType='Processor only'` produce un vero eseguibile `Prova_1_socbuilder_sw.elf` — confermato con `file`: `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked ... for GNU/Linux`. Pipeline completa, compilazione e link riusciti, zero errori. Dettagli tecnici completi (comandi esatti, path, causa di ogni errore) in [`docs/socbuilder_notes.md`](docs/socbuilder_notes.md).
  - **Verificato anche**: `BuildType='FPGA only'` non aggira comunque il bisogno del toolchain (il modello ha software e hardware co-progettati), ma non è più un problema dato che il toolchain ora funziona.
- **Bitstream FPGA via SoC Builder — parzialmente sbloccato via script, poi FERMATO per scelta strategica (non per blocco tecnico).** Con `Simulink.SubSystem.convertToModelReference` (funzione ufficiale) e un confronto diretto con l'esempio ufficiale MathWorks (`soc_swhw_stream_top/fpga/proc`), sono state scoperte 4 regole strutturali del validatore SoC Builder Gen mai documentate: (1) il modello FPGA deve avere device type `ASIC/FPGA` e `HardwareBoard=None`, non ereditare le impostazioni ARM; (2) blocchi `Display`/Scope non sono ammessi a livello root ("Only subsystems can be IP"); (3) ogni segnale mappato su registro AXI4-Lite (es. `StreamEnable`) deve collegarsi in modo **esclusivo** al DUT, senza diramazioni parallele; (4) le uscite del DUT non possono avere connessioni multiple, serve una porta dedicata per destinazione. Applicando tutte e 4 le regole il build supera ogni errore di topologia e arriva a un errore di categoria diversa (`Invalid HDL Implementation Parameter 'IPCoreVersion'`, un parametro HDL Coder, non più un problema di wiring). **Decisione presa dopo una revisione strategica approfondita**: fermarsi qui con questo modello didattico — le regole scoperte sono un *metodo* riusabile ma non uno stato di avanzamento trasferibile all'MPC vero (ogni DUT ha porte/segnali propri, il lavoro andrebbe rifatto comunque), mentre la sintesi Vivado diretta via Tcl (bypassando interamente questo validatore) fornisce già tutti i numeri necessari per dimensionare l'MPC. Dettagli completi, incluso un avvertimento sul rischio delle modifiche fatte (un pass-through vuoto di `streamEnable` che soddisfa la topologia ma non la semantica — da verificare numericamente prima di fidarsene, e da NON copiare acriticamente sull'MPC vero) in `docs/socbuilder_notes.md`.
- Rendere i tre fix del toolchain ARM permanenti in modo più pulito (es. uno script di setup del progetto o uno `startup.m`) invece di richiamarli a mano a ogni sessione MATLAB.
- **Prossimo passo prioritario**: applicare gli stessi principi (canale dati, fixed-point, task/eventi, e le 4 regole di IP Core Generation sopra) all'algoritmo MPC vero, usando la sintesi Vivado diretta via Tcl come via principale — non più la demo con due matrici.
- Valutare se e come usare la Pynq-Z1 come scheda reale — è stata trovata e testata con successo un'API pubblica (`soc.sdk.BoardSupport`, SoC Blockset R2019b+) che registra board SoC personalizzate via script, senza wizard: il meccanismo giusto per completare la registrazione di Pynq-Z1 (finora incompleta), riusando la configurazione del target Zynq-7000. Rimandato a quando sarà rilevante (il lavoro fatto su ZedBoard-proxy andrebbe comunque rifatto sulla board vera) — vedi `docs/socbuilder_notes.md`.

## Note per chi riprende questo lavoro 

- Il file `.gitignore` esclude deliberatamente le cartelle generate/rigenerabili (cache MATLAB, progetti Vivado completi, codice HDL intermedio) — solo i modelli `.slx` sorgente, gli script `.tcl` di sintesi e i report finali sono tracciati.
- Ogni volta che si fa un push su questo repository, README e documentazione in `docs/` vanno tenuti aggiornati con lo stato più recente — è una regola esplicita del proprietario del progetto.
