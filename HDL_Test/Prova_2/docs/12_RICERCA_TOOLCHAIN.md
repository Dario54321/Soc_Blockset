<!--
  ATTENZIONE, LEGGERE PRIMA.

  Questo documento e' il risultato di una RICERCA SISTEMATICA condotta il
  28/07/2026 su:
    - la documentazione online MathWorks,
    - gli artefatti installati (maschere .slx, cataloghi messaggi
      matlabroot/resources/<prodotto>/en/*.xml, esempi in toolbox/soc/socexamples),
    - esperimenti in MATLAB.

  E' la fonte da consultare PER PRIMA davanti a una domanda nuova sul toolchain.

  Il documento gemello 11_NOTE_API.md contiene invece le scoperte fatte
  COSTRUENDO i modelli di Prova_2, con i messaggi d'errore esatti. Alcune di
  quelle voci sono POSTERIORI a questa ricerca e la integrano — in particolare:

    * soc:scheduler:SimInProgress e la necessita' di marcare il modello
      processore con ESB.ProcessingUnit='APU'   -> 11_NOTE_API §2
    * il lato software del Register Channel richiede un blocco accessore
      prociolib/Register Write (porta messaggio)  -> 11_NOTE_API §3
    * RegisterTable a 5 colonne in R2026a         -> 11_NOTE_API §3
    * ChTypeWriterChIf accetta solo unsigned      -> 11_NOTE_API §4
    * il rate del modello FPGA non e' il clock della PL -> 11_NOTE_API §6
    * stallo dell'handshake se ready dipende da valid   -> 11_NOTE_API §7

  In caso di conflitto fra i due documenti prevale 11_NOTE_API.md, perche'
  registra comportamenti osservati sul nostro modello.
-->

# Note API — SoC Blockset (MATLAB R2026a)

> **Scopo.** Documento operativo per chi deve costruire, configurare e generare codice da modelli SoC Blockset **via API** (`set_param`, `add_block`, funzioni di libreria), senza avere assistito alla sessione di ricerca da cui deriva.
>
> **Ambiente di riferimento di tutte le verifiche.** MATLAB **26.1.0.3234472 (R2026a) Update 1**, Windows, installazione in `C:\Program Files\MATLAB\R2026a`. Licenza SoC Blockset presente. Doc HTML locale del SoC Blockset **assente** in questa installazione (verificato con ricerca su `help\**` e su `C:\ProgramData\MATLAB\SupportPackages\R2026a\**`): la documentazione è **solo online**.
>
> **Metodo delle verifiche.** Tre sorgenti, in ordine di forza probatoria:
> 1. **Esperimento** in MATLAB (modelli sintetici, `get_param`/`set_param`, log).
> 2. **Artefatto installato**: gli `.slx` sono archivi ZIP con XML — maschere, callback e istanze sono state lette direttamente; i cataloghi messaggi `resources\<prodotto>\en\*.xml` contengono i vincoli realmente applicati.
> 3. **Documentazione online MathWorks**.

## Legenda dei marcatori di affidabilità

Ogni affermazione non banale porta uno di questi marcatori. **Non trattare `[INFERENZA]` come fatto.**

| Marcatore | Significato |
|---|---|
| `[DOC]` | Affermato dalla documentazione MathWorks (link in fondo alla sezione). |
| `[ART]` | Verificato leggendo l'artefatto installato (maschera `.slx`, catalogo messaggi, script shipped). |
| `[EXP]` | Verificato sperimentalmente in MATLAB in questa sessione di ricerca. |
| `[INFERENZA]` | Ricostruzione plausibile a partire dai fatti, **non** fonte MathWorks. |
| `[INCERTO]` | Il rapporto d'origine dichiara di non avere potuto verificare. |

---

# Indice

1. [Struttura del modello e configurazione (top / FPGA / processore)](#1-struttura-del-modello-e-configurazione)
2. [Register Channel](#2-register-channel)
3. [Software to AXI4-Stream](#3-software-to-axi4-stream)
4. [Task Manager e Asynchronous Task Specification](#4-task-manager-e-asynchronous-task-specification)
5. [Generazione HDL da un modello SoC](#5-generazione-hdl-da-un-modello-soc)
6. [Dove la documentazione e gli artefatti divergono](#6-dove-la-documentazione-e-gli-artefatti-divergono)
7. [Trappole (messaggi d'errore esatti, ricercabili)](#7-trappole)
8. [Cosa NON è documentato e va scoperto sperimentalmente](#8-cosa-non-e-documentato)
9. [File locali di riferimento](#9-file-locali-di-riferimento)
10. [Fonti](#10-fonti)

---

<a name="1-struttura-del-modello-e-configurazione"></a>
# 1. Struttura del modello e configurazione (top / FPGA / processore)

## 1.1 Il modello mentale

Un progetto SoC Blockset è **una terna di modelli**:

| Ruolo | `SolverType` | `ProdHWDeviceType` | `HardwareBoard` | `ESB.ProcessingUnit` |
|---|---|---|---|---|
| **top** | **Variable-step** | ARM Cortex-A (32-bit) | board reale | **`None`** |
| **fpga** (referenziato) | Fixed-step | **`ASIC/FPGA->ASIC/FPGA`** | ereditata dal top | `FPGA` |
| **proc** (referenziato) | Fixed-step | ARM Compatible->ARM Cortex-A (32-bit) | **board reale, persistita** | `APU` |

`[EXP]` Tabella misurata a runtime sui tre modelli generati dal template shipped `soc_swhw.sltx`, non dedotta. Corrisponde al 100% a [SoC Blockset Model Structure](https://www.mathworks.com/help/soc/ug/soc-blockset-model-structure.html) e a [Build Error When FPGA or Processor Model Not Detected](https://www.mathworks.com/help/soc/ug/build-error-for-fpga-or-processor-model-not-detected.html).

## 1.2 FATTO CRITICO: la configurazione del modello FPGA non è persistita nel file

`[EXP]` `ProdHWDeviceType`, `HardwareBoard`, `ProcessingUnit` letti dal `.slx` del modello FPGA **non sono lo stato effettivo**. Al caricamento del **top model** gira `soc.internal.postModelLoadCallback` → `codertarget.<board>.internal.forwardingHook`, che propaga la board del top ai modelli referenziati.

Prova decisiva (stesso processo MATLAB, stesso file, log `probe_a.log`):

```text
--- soc_swhw_stream_fpga caricato DA SOLO (top NON caricato) ---
  HardwareBoard            = None
  HardwareBoardFeatureSet  = SoCBlockset
  ProdHWDeviceType         = ASIC/FPGA->ASIC/FPGA
  ESB.ProcessingUnit       = <ERR> The model is not set for Coder Target.

--- dopo load_system('soc_swhw_stream_top'), STESSO modello già in memoria ---
  HardwareBoard            = Xilinx Zynq ZC706 evaluation kit
  HardwareBoardFeatureSet  = SoCBlockset
  ProdHWDeviceType         = ASIC/FPGA->ASIC/FPGA
  SolverType               = Fixed-step
  ESB.ProcessingUnit       = FPGA
```

`Dirty` resta `off` su tutti e tre i modelli: è una **derivazione al load**, non una modifica. Il file su disco è board-agnostico *by design* — il template deve funzionare con qualunque board scelta nel top.

**Regola operativa: qualunque script che ispezioni il modello FPGA deve prima caricare il top model. Mai standalone.**

## 1.3 Uso via API — lettura e scrittura di `ESB.ProcessingUnit`

`[EXP]` `get_param(mdl,'ESB.ProcessingUnit')` **non esiste in nessun caso**, nemmeno sul top model correttamente configurato:

```text
get_param('soc_swhw_stream_top','ESB.ProcessingUnit')
  -> block_diagram does not have a parameter named 'ESB.ProcessingUnit'
```

Accessori corretti:

```matlab
codertarget.data.getParameterValue(getActiveConfigSet(mdl), 'ESB.ProcessingUnit')
codertarget.data.setParameterValue(getActiveConfigSet(mdl), 'ESB.ProcessingUnit', 'FPGA')
```

Fonte concetto: [Processing Unit](https://www.mathworks.com/help/soc/ref/processingunit.html).

## 1.4 Requisiti esatti per il riconoscimento dei modelli referenziati

`[EXP]` Gate provato in **entrambe le direzioni** con modelli sintetici identici tranne un parametro (`probe_e.log`, `probe_f.log`):

| modello referenziato | `ProdHWDeviceType` | `HardwareBoard` su disco | esito al load sotto il top |
|---|---|---|---|
| `pe_a` / `pf_fpga` | `ASIC/FPGA->ASIC/FPGA` | `None` | riconosciuto: board ereditata + **PU=FPGA** |
| `pf_proc` | `ARM Compatible->ARM Cortex-A (32-bit)` | ZC706 + `FeatureSet=SoCBlockset` | riconosciuto: **PU=APU** |
| `pe_b` / `pf_procNoBoard` | `ARM Compatible->ARM Cortex-A (32-bit)` | `None` | **NON riconosciuto** (controllo negativo) |

Regole derivate:

1. **Modello FPGA** — il discriminante persistito è **`ProdHWDeviceType = 'ASIC/FPGA->ASIC/FPGA'`** (combacia con `<processingunit type="fpga"><productionhwdevicetype>` nel registry board). È *sufficiente*: board, Feature set e `PU=FPGA` arrivano dal top. **Non serve** impostare la board nel modello FPGA.
2. **Modello processore** — deve avere **`HardwareBoard` uguale a quella del top E `HardwareBoardFeatureSet='SoCBlockset'` persistiti**. Non è ereditata: senza board il modello viene **ignorato del tutto, in silenzio**.
3. Il riconoscimento è **indipendente dall'ordine** dei Model block (nel test `pf_fpga` era il terzo).
4. Al massimo **un** modello FPGA; uno o più modelli processore.
5. Il modello processore deve essere pilotato da un blocco **Task Manager**.

> **Nota onesta.** I punti 1 e 2 (quale proprietà persistita fa la classificazione, e l'asimmetria FPGA/processore) **non sono documentati da MathWorks**: sono ricavati sperimentalmente qui.

## 1.5 Ricetta minima per costruire i modelli a mano

`[EXP]` `ProdHWDeviceType` **non si aggiorna** impostando `ESB.ProcessingUnit` via `codertarget.data.setParameterValue` (resta ARM anche dopo save/reload — `probe_c`/`probe_d`). Va impostato esplicitamente.

```matlab
% --- modello FPGA ---
set_param(fpgaMdl,'SolverType','Fixed-step');
set_param(fpgaMdl,'ProdHWDeviceType','ASIC/FPGA->ASIC/FPGA');   % <-- il discriminante
% board / FeatureSet / ProcessingUnit: NON impostarli, arrivano dal top

% --- modello processore ---
set_param(procMdl,'SolverType','Fixed-step');
set_param(procMdl,'HardwareBoard','Xilinx Zynq ZC706 evaluation kit');
set_param(procMdl,'HardwareBoardFeatureSet','SoCBlockset');
set_param(procMdl,'ProdHWDeviceType','ARM Compatible->ARM Cortex-A (32-bit)');

% --- top model ---
set_param(topMdl,'SolverType','Variable-step');       % hard requirement, vedi 1.6
set_param(topMdl,'HardwareBoardFeatureSet','SoCBlockset');
set_param(topMdl,'SystemTargetFile','ert.tlc');
set_param(topMdl,'HardwareBoard','Xilinx Zynq ZC706 evaluation kit');
codertarget.data.setParameterValue(getActiveConfigSet(topMdl),'ESB.ProcessingUnit','None');
```

**Verifica sempre con il top caricato, mai standalone.**

## 1.6 Top model: Variable-step è un requisito, non una raccomandazione

`[ART]` Da `C:\Program Files\MATLAB\R2026a\resources\soc\en\scheduler.xml`, chiave `UnsupportedSolver`:

> `Solver type ''{1}'' in ''{0}'' model is not supported for SoC Blockset simulation.`

con link d'azione `set_param('{0}','SolverType','Variable-step')`.

Altri vincoli sul top `[ART]`/`[EXP]`: `ProcessingUnit=None`, `HardwareBoardFeatureSet='SoCBlockset'`, `SystemTargetFile='ert.tlc'`, `HardwareBoard` = board reale, Task Manager nel top o in un **subsystem virtuale** del top (`scheduler.xml`, `TaskMgrMisplaced`).

`[ART]` Il top **non deve** chiamarsi `*_top`: l'esempio `soc_image_rotation.slx` (*Random Access of External Memory*) è un top FPGA-only senza suffisso — conferma anche che **il modello processore è opzionale**.

## 1.7 API di creazione — cosa esiste davvero

`[ART]` **I template SoC sono template di PROGETTO** (`cp:category = Project`), non template di modello. Contengono `fsroot/soc_*_top.slx`, `fsroot/referencedmodels/{fpga,proc}.slx`, `fsroot/utilities/*_init.m`.

Path: `C:\Program Files\MATLAB\R2026a\toolbox\soc\templates\` — `soc_swhw`, `soc_hwsw`, `soc_hdmi`, `soc_hdmi_framebuffer`, `soc_multiproc`, `soc_rfsoc`, `soc_sdr`, `soc_syscomposer`.

**Unica via CLI supportata e verificata** `[EXP]`:

```matlab
tpl = fullfile(matlabroot,'toolbox','soc','templates','soc_swhw.sltx');
p = Simulink.createFromTemplate(tpl, 'Folder', 'D:\Project_SoC\MioProgetto');
% -> slproject.ProjectManager
% i 3 modelli escono già con top=None / fpga=FPGA / proc=APU
```

`Folder` e `Name` sono le **uniche** name-value ammesse. **Senza `Folder` crea in `~\MATLAB\Projects\<nome>` ignorando la cwd.**

`[EXP]` `matlab.project.createProject` **NON** accetta `Template`:
`Invalid argument name 'Template'. Name must be 'Name' or 'Folder'.`

Le altre funzioni (tutte esistenti, verificate con `which`/`help`) `[EXP]`:

| Funzione | Cosa fa davvero |
|---|---|
| `socModelCreator` | **UI, zero argomenti.** "Create SoC model based on selected reference design". R2021b, arriva col support package AMD. `...\toolbox\shared\soc\socmodelcreator\socModelCreator.p` |
| `socModelConverter('mymodel.slx')` | Genera un modello SoC Blockset da un modello IP-core esistente |
| `socTemplateBuilder` | **Deprecato**, "will be removed in a future release" → usare `socModelCreator` |
| `socCreateModel(modelName)` / `(allocationSet,allocationScenario)` | **Documentato**, R2022b. Da architettura software System Composer produce lo scheletro SoC lato **processore** (Task Manager + partizioni Schedule Editor). Default **Custom Board**. **Non** crea la terna top/fpga/proc. [ref](https://www.mathworks.com/help/soc/ref/soccreatemodel.html) |
| `socBuilder('modelname')` | Lancia SoC Builder (UI). R2019a |
| `socModelBuilder(modelName, Name=Value)` | **Build programmatica**, R2023a. Proprietà: `ProjectFolder` (default `'soc_prj'`), `BuildType` in {`'Processor and FPGA'`, `'Processor only'`, `'FPGA only'`}, `ExternalMode`, `RunExternalFPGABuild`. Metodi: `buildModel`, `loadBinaries` |

`soc.internal.generateTopModel` / `generateFPGAModel` / `generateProcessorModel` esistono ma sono `.p` interne: **non sono API**.

**Non esiste** un'API pubblica che crei i tre modelli già configurati: l'unica via CLI è `Simulink.createFromTemplate` sul template di progetto.

## 1.8 Board non supportata / Custom Hardware Board

`[DOC]` [Custom Hardware Board Configuration](https://www.mathworks.com/help/soc/ug/custom-hardware-board-configuration.html):

> "The Custom hardware board selection only supports simulation. For code generation, use one of the provided SoC Blockset hardware board selections."

`[EXP]` (`probe_d.log`) Con `HardwareBoard='Custom Hardware Board'` il Feature set diventa `SoCBlockset` e `ESB.ProcessingUnit` è settabile sia a `FPGA` sia a `APU`. **La struttura del modello resta valida e simulabile**; si perde solo la catena di deploy.

Cosa si perde: generazione HDL/C verso hardware, reference design e bitstream, load & run, external mode, profiling on-target, connessione Ethernet/JTAG, generazione DTB.
Da configurare a mano nel dialog: **Number of cores**, **FPGA design (PS mem controllers)**, **FPGA design (PL mem controllers)** — dal datasheet.

**Alternativa con funzionalità piena**: Board Support API — `soc.sdk.BoardSupport`, `soc.sdk.packageBoardSupport`, `addNewDeployer` / `addNewPIL` / `addNewProfiler` / `addNewExternalMode` / `addNewOperatingSystem`, `addNewFPGACore`, `addNewMemorySystem`. Scheletro commentato pronto all'uso:
`C:\Program Files\MATLAB\R2026a\toolbox\shared\soc\socmodelcreator\+soc\+internal\RD_Templates\createCustomBoardForSoCModelCreator.txt`
Vedi [Using a Custom Board with SoC Blockset](https://www.mathworks.com/help/soc/ug/Using-a-Custom-Board-with-SoC-Blockset.html) e [Define Custom Pynq-Z2 Board](https://www.mathworks.com/help/soc/ug/define-custom-pynq-z2-board-with-socb.html).

`[ART]` `workflow.xml` → `InvalidHardwareType`: *"Only 'Zynq' and 'IntelSoC' hardware boards are supported"* per il flusso custom-target/DTB.

**Fonti area 1**: [SoC Blockset Model Structure](https://www.mathworks.com/help/soc/ug/soc-blockset-model-structure.html) · [Build Error When FPGA or Processor Model Not Detected](https://www.mathworks.com/help/soc/ug/build-error-for-fpga-or-processor-model-not-detected.html) · [Use SoC Builder to Generate SoC Design](https://www.mathworks.com/help/soc/ug/generate-soc-design.html) · [Project and Top-Level Model](https://www.mathworks.com/help/soc/ug/project-and-top-level-model.html) · [Use Template to Create SoC Model](https://www.mathworks.com/help/soc/ug/use-templates-to-create-soc-model.html) · [Create SoC Model](https://www.mathworks.com/help/soc/ug/create-new-soc-model.html) · [socCreateModel](https://www.mathworks.com/help/soc/ref/soccreatemodel.html) · [Processing Unit](https://www.mathworks.com/help/soc/ref/processingunit.html) · [Custom Hardware Board Configuration](https://www.mathworks.com/help/soc/ug/custom-hardware-board-configuration.html) · [SoC Blockset Supported Hardware](https://www.mathworks.com/help/soc/supported-hardware.html) · [Random Access of External Memory](https://www.mathworks.com/help/soc/ug/image-rotation.html)

---

<a name="2-register-channel"></a>
# 2. Register Channel

## 2.1 Quale blocco ottieni davvero in R2026a

`[ART]` In `soclib.slx` la categoria "Memory" ha `<P Name="OpenFcn">socmemlib</P>` (e "Processor I/O" → `prociolib`). Il blocco trascinato dal Library Browser è quindi **`socmemlib/Register Channel`**.

Il `forwardingTable.xml` di `socmemlib` lo conferma **vivo, non deprecato**:

```xml
<Block OldVersion="0.0" NewVersion="10.8">socmemlib/Register Channel</Block>
<TransformationFunction>soc.blkcb.socmemlibForwarding</TransformationFunction>
```

Nello stesso file `socmemlib/Memory Channel` e `socmemlib/Memory Controller` puntano invece a `socmemlib_deprecated/...`. **Memory Channel è deprecato, Register Channel no.**

`[ART]` `socmemlib2.slx` non ha forwardingTable e non è raggiunta da `soclib`: usa etichette FPGA/CPU invece di HW/SW e **non ha il parametro `SampleTime`**. Se qualcosa non torna, verificare **con quale libreria** si sta lavorando.

Librerie e file coinvolti:

| File | Ruolo |
|---|---|
| `...\toolbox\soc\blocks\soclib.slx` | Library Browser (root) |
| `...\toolbox\soc\fpga\simulation\socmemlib.slx` | **Blocco vivo** in R2026a |
| `...\toolbox\soc\fpga\simulation\socmemlib2.slx` | Variante più recente, NON esposta |
| `...\toolbox\soc\fpga\simulation\socmemlib_internal.slx` | Implementazione interna dei registri |
| `...\toolbox\shared\soc\processor\blocks\prociolib.slx` | Register Read / Register Write (lato SW) |

## 2.2 Semantica delle porte

`[ART]` **Regola fondamentale: ogni riga della tabella genera esattamente una porta di ingresso e una di uscita.** N registri ⇒ N in + N out. L'indice di porta segue **l'ordine delle righe**. La direzione non cambia il *numero* di porte: cambia **su quale lato** ciascuna si trova.

Descrizione della maschera (verbatim):

> "Each pair of input and output ports with the same name represent a register. On the FPGA side (HW) each port interfaces directly with the FPGA logic. On the processor side (SW) each port interfaces directly with a Register Read block if the register direction is configured to read, or with a Register Write block if the register direction is configured to write."

| Direzione | Ingresso | Uscita |
|---|---|---|
| **Read** (SW legge, HW scrive) | lato **FPGA** (sinistra) | lato **CPU** (destra) |
| **Write** (SW scrive, HW legge) | lato **CPU** (destra) | lato **FPGA** (sinistra) |

`[ART]` L'icona ha `IconRotate="port"`; le porte lato CPU sono realizzate con `<P Name="Rotation">3.1415926535897931</P>` (pi greco) nelle `PortProperties`. Nomi interni: Inport `wr_regN`, Outport `rd_regN` (prospettiva del canale: `wr_` = chi scrive nel registro, `rd_` = chi legge).

**Prova diretta** `[ART]` — `soc_swhw_stream_top.slx`, tabella `{streamEnable Write; lowFreqReg Read; highFreqReg Read; validDropReg Read}`, `NumRegisters=4`, `PortCounts in="4" out="4"`, Processor=SID 216, FPGA=SID 270, canale=SID 272:

```text
216#out:2 -> 272#in:1      streamEnable (Write): ingresso dal PROCESSORE   [Rotation=pi]
272#out:1 -> 270#in:3      streamEnable: uscita verso FPGA
270#out:5 -> 272#in:2      lowFreqReg   (Read): ingresso da FPGA           [Rotation=0]
270#out:6 -> 272#in:3      highFreqReg
270#out:7 -> 272#in:4      validDropReg
272#out:2 -> 216#in:4      lowFreqReg: uscita verso PROCESSORE
272#out:3 -> 216#in:3
272#out:4 -> 216#in:2
```

`in:i` e `out:i` appartengono **allo stesso registro i**. L'ordine invertito sugli inport del Processor è solo routing dell'esempio, non semantica.

## 2.3 Porte messaggio vs porte segnale

`[ART]` **Lato FPGA = porte di SEGNALE.** L'Inport interno `wr_reg1` porta la mappatura HDL — prova che è un segnale hardware:

```xml
<Cell Class="char">IOInterface</Cell>        <Cell Class="char">AXI4-Lite</Cell>
<Cell Class="char">IOInterfaceMapping</Cell> <Cell Class="char">x"100"</Cell>
```

`[DOC]` **Lato processore = porte MESSAGGIO.** Register Read, porta `msg` (tipo `SoCData`), verbatim:

> "This message port receives data messages from a connected Register Channel or IO Data Source block."

Register Write, porta `msg` in uscita:

> "This message port sends the output register data, as a message, to the connected Register Channel or IO Data Sink block."

`[ART]` Confermato nel modello processore `soc_hwsw_stream_proc.slx`: gli Outport root che alimentano il Register Channel sono in **message mode**:

```xml
<Block BlockType="Outport" Name="LowFreqIndicator" SID="271">
  <P Name="InputPortMessageModes">m</P>
```

L'Outport `DataOut`, che va invece al canale AXI4-Stream, **non** ha questo attributo: la differenza è reale e significativa.

## 2.4 Il blocco "HWSW Message Receive": dov'è davvero

`[ART]` `HWSW Message Receive` esiste, ma sta **dentro il blocco Register Read**, non dentro il Register Channel. Nella maschera di `prociolib/Register Read` il Sample time è promosso da:

```xml
<MaskParameter Name="SampleTime" Type="promote" Tunable="off">
  <Prompt>Sample time:</Prompt>
  <Value>-1</Value>
  <TypeOptions>
    <Option>Variant/SIM/HWSW Message Receive/SampleTime</Option>
  </TypeOptions>
</MaskParameter>
```

Il percorso che compare negli errori è quindi del tipo
`<modello>/.../Register Read/Variant/SIM/HWSW Message Receive`.

`[ART]` **Fatto controintuitivo e importante: il Register Channel non contiene alcun blocco messaggio.** Verificato l'intero sottoalbero `system_4331*` di `socmemlib`: solo `Inport`, `Reference` (Register1…Register32), `Terminator`, `Outport`. L'implementazione del singolo registro (`socmemlib_internal`, varianti `HW To SW` / `SW To HW` / `None`) è basata su **DataStoreMemory / DataStoreRead / DataStoreWrite**. Ricerca di `Message Receive|Message Send|BlockType="Receive"|BlockType="Send"` nel sottoalbero: **zero risultati**.

**Conseguenza pratica:** se colleghi un segnale ordinario dove è atteso un messaggio, **Simulink segnala l'errore sul Register Read, non sul Register Channel.** Cercare la causa nel Register Channel è una pista falsa.

## 2.5 Come alimentare correttamente l'ingresso lato software

`[ART]`/`[DOC]`

- **Registro Write (SW→HW)**: dentro il *modello referenziato processore*, un blocco **Register Write** con `OutputSink = 'To output port'`; la sua uscita `msg` va a un Outport root (che diventa message port) → ingresso lato CPU del Register Channel.
- **Registro Read (HW→SW)**: uscita lato CPU del Register Channel → Inport root del modello processore → ingresso del blocco **Register Read**.
- **Senza processore**: la maschera autorizza esplicitamente la sostituzione — *"Alternatively IO Data Source or IO Data Sink blocks can be used instead of Register Read or Register Write blocks when there is no processor in the system."*

Parametri reali dell'istanza in `soc_hwsw_stream_proc.slx` `[ART]`:

```matlab
OutputSink    = 'To output port'
RegisterName  = 'RegA'
DeviceName    = '/dev/mwfpga_algorithm_ip0'
OffsetAddress = hex2dec('010C')
```

`[ART]` **Attenzione a `prociolib2`** (non esposta dal Library Browser, ma se ci finisci il comportamento cambia): lì Register Read ha `PortCounts out="1"` — **nessun ingresso** — con parametro `SimulationInput` (`Zeros` | `From input port`, default `Zeros`); Register Write ha `SimulationOutput` (`Terminator` | `To output port`, default `Terminator`). **Con i default il blocco non ha la porta verso il canale.**

## 2.6 Contesto richiesto per il segnale entrante

`[ART]`/`[DOC]`, non congetturato:

- **Deve venire da un modello referenziato processore** per la via normale: i blocchi Register Read/Write stanno nel modello processore (`ProcessingUnit = APU`), il Register Channel nel top model (`ProcessingUnit = None`).
- **Deve stare in un task subsystem.** Nell'esempio, `Register Write1`/`Register Write2` sono dentro *"Processor Algorithm Wrapper"*, che contiene un `TriggerPort` (subsystem triggered), con un blocco `AsynchronousTaskSpecification` alla radice del modello. La doc di Register Read lo conferma: il blocco deve stare in un task subsystem timer-driven o event-driven, e i messaggi sono processati quando il Task Manager attiva il task.
- **Rate Transition: NON richiesto.** Nessun Rate Transition nei percorsi registro dei due esempi shipped, e nessuna prescrizione in doc o maschera.
- **Vincolo sui tipi** (dalla maschera): *"Set register Data Type and Dimension to match the values in the Register Read or Register Write blocks."* Il disallineamento tipo/dimensione è l'errore di configurazione classico.

## 2.7 Parametri programmabili

### `RegisterTable` — 5 colonne in R2026a

`[ART]` Default libreria: `{'reg1','Read','uint32','1','n/a'}`

| # | Colonna | Tipo | Valori |
|---|---|---|---|
| 1 | `Register Name` | edit | testo libero |
| 2 | `Direction` | popup | `Read`, `Write` |
| 3 | `Data Type` | popup | ` `, `single`, `int8`, `uint8`, `int16`, `uint16`, `int32`, `uint32`, `boolean`, `fixdt(1,16,0)`, `...` |
| 4 | `Dimension` | edit | default `1` |
| 5 | `Initial Value` | edit | `n/a` se Direction=Read |

`[ART]` **Il popup NON contiene `int64`/`uint64`.** Verificata la `<StringList>` completa nella maschera. Riassunti generati automaticamente della pagina doc li citano: è **sbagliato**.

`[ART]` **Tabelle legacy a 4 colonne esistono.** In `soc_hwsw_stream_top.slx` il valore salvato è
`{ 'LowFreqIndicator','Write','boolean','1'; 'HighFreqIndicator','Write','boolean','1' }`
senza Initial Value, che vive separato in `RegTableInitialValues={'0','0'}`. Il `LoadFcn` aggiorna al caricamento. **Non assumere 5 colonne leggendo un modello vecchio.**

### Parametri derivati (nascosti, `Evaluate="off"`, cell **come stringa**)

`[ART]`

| Parametro | Default | Note |
|---|---|---|
| `RegTableNames` | `{'reg1' }` | |
| `RegTableRW` | `{'Read' }` | |
| `RegTableDataTypes` | `{'uint32' }` | |
| `RegTableVectorSizes` | `{'1' }` | |
| `RegTableInitialValues` | `{'0' }` | |
| `NumRegisters` | `1` | conteggio righe |
| `RegTableDirty` | `0` | `Internal="on" Visible="off"`, callback `ResetTableCb` |
| `SampleTime` | `-1` | `Visible="off"`, prompt "Register write sample time:" |

Callback rilevanti `[ART]`:

```text
Block:  LoadFcn / PreSaveFcn / InitFcn  -> soc.blkcb.RegisterChannelCb(...)
Mask:   Initialization                  -> soc.blkcb.RegisterChannelCb('MaskInitFcn', gcbh, gcs)
RegisterTable -> EditTableRowCb     RegTableDirty -> ResetTableCb
Bottoni: AddTableRowCb / DeleteTableRowCb / ShiftTableRowUpCb / ShiftTableRowDownCb
```

## 2.8 Uso via API — configurare la tabella senza incoerenze silenziose

**Non esiste API programmatica documentata** per questo blocco: MathWorks documenta solo la GUI (New / Delete / Move Up / Move Down). Quanto segue è `[INFERENZA]` **derivata dalla struttura della maschera** e va **verificata sul modello reale**.

Il punto critico `[ART]`: `RegisterTable` è la sorgente di verità, ma `EditTableRowCb` è un **callback di dialog**, che `set_param` **non esegue**. Scrivere solo `RegisterTable` lascia `RegTableNames/RW/DataTypes/VectorSizes/InitialValues/NumRegisters` disallineati — e sono **questi** che `MaskInitFcn` usa per costruire le porte. Risultato: **porte che non corrispondono alla tabella, in modo silenzioso** (nessun errore).

Due strade coerenti:

```matlab
% STRADA 1 - scrivere tutto esplicitamente (i derivati sono Evaluate="off":
%            si passano come STRINGHE che rappresentano cell array)
set_param(blk,'RegisterTable', ...
    "{'ctrl','Write','uint32','1','0';'stat','Read','uint32','1','n/a'}");
set_param(blk,'RegTableNames',        "{'ctrl' 'stat' }");
set_param(blk,'RegTableRW',           "{'Write' 'Read' }");
set_param(blk,'RegTableDataTypes',    "{'uint32' 'uint32' }");
set_param(blk,'RegTableVectorSizes',  "{'1' '1' }");
set_param(blk,'RegTableInitialValues',"{'0' '0' }");
set_param(blk,'NumRegisters','2');

% STRADA 2 - forzare la ricostruzione dei derivati dalla tabella
set_param(blk,'RegisterTable', "...");
set_param(blk,'RegTableDirty','1');   % fa scattare ResetTableCb
```

**In entrambi i casi: dopo il `set_param`, verificare l'artefatto, non l'intenzione.** Confrontare `get_param(blk,'PortHandles')` (numero e lato delle porte) con la tabella attesa e rileggere i derivati. Un `set_param` andato a buon fine **non prova** che le porte siano state ricostruite.

## 2.9 Sample time, capienza, collocazione

`[ART]`/`[DOC]` **Sample time.** `SampleTime`, default `-1`, prompt *"Register write sample time:"*, **`Visible="off"`** — invisibile nel dialog R2026a ma presente e scrivibile via `set_param`. Doc: accetta `-1` (eredita) o `[sample_time offset]`, e *"This sample time represents the clock period on the hardware side."*

> Coerenza tra versioni: in `socmemlib2` il parametro **non esiste affatto**. Uno script che lo imposta **fallisce** su quella libreria.

`[ART]` Nell'esempio `soc_swhw_stream_proc.slx` gli Inport root dei registri Read portano `SampleTime = 0.1`, che coincide con il poll rate del Register Read.

`[DOC]`/`[ART]` **Massimo 32 registri** — doc: "up to 32 registers"; corroborato dall'implementazione (`Register1`…`Register32`, `rd_reg2`…`rd_reg32` terminati).

**Collocazione: solo top model? NON documentato come restrizione.** Da riportare onestamente:

- La pagina di riferimento **non ha sezione Limitations** e **nessuna affermazione** sul modello di appartenenza.
- Ricerca nel catalogo `resources\soc\en` di errori su placement/top-model del Register Channel: **nessuno**.
- *SoC Blockset Model Structure* dice che i sottosistemi comunicano "through a Memory Channel, Register Channel or Interrupt Channel block", ma **non prescrive dove il blocco vada messo**.
- In pratica entrambi gli esempi shipped lo mettono nella **radice del top model** (`ProcessingUnit = None`), ed è la conseguenza strutturale del fatto che collega un modello FPGA a un modello processore. Ma **"solo top model" è un'inferenza dalla struttura, non un vincolo documentato**.

`[ART]` Proprietà HDL sull'istanza dell'esempio, per completezza: `archSelection = Module`, `ProcessorFPGASynchronization = 'Free running'`.

**Fonti area 2**: [Register Channel](https://www.mathworks.com/help/soc/ref/registerchannel.html) · [Register Read](https://www.mathworks.com/help/soc/ref/registerread.html) · [Register Write](https://www.mathworks.com/help/soc/ref/registerwrite.html) · [Memory and Register Channel Connections](https://www.mathworks.com/help/soc/ug/create-new-soc-model-memory-connections.html) · [SoC Blockset Model Structure](https://www.mathworks.com/help/soc/ug/soc-blockset-model-structure.html)

---

<a name="3-software-to-axi4-stream"></a>
# 3. Software to AXI4-Stream

## 3.1 Porte — semantica, tipo, ordine

`[ART]` da `socmemlib.slx → simulink/systems/system_4324.xml` (`PortCounts in="2" out="4"`):

| # | Dir | Nome | Tipo | Semantica |
|---|-----|------|------|-----------|
| In 1 | in | **`msg`** | `SoCData` | Dato scritto dal software (via **Stream Write**). Scalare/vettore/matrice |
| In 2 | in | **`rdCtrlIn`** | `StreamS2MBusObj` | Backpressure dal consumatore FPGA (`tready`). Da **SoC Bus Creator** |
| Out 1 | out | **`rdData`** | dato | Beat letto dalla memoria verso lo stream (`tdata`) |
| Out 2 | out | **`rdCtrlOut`** | `StreamM2SBusObj` | Bus protocollo verso FPGA (`tvalid`/`tlast`). Da separare con **SoC Bus Selector** |
| Out 3 | out | **`event`** | `rteEvent` | Evento che triggera il **Task Manager** (buffer libero disponibile) |
| Out 4 | out | **`done`** | `boolean` | Notifica allo **Stream Write**: transazione completata, buffer liberato |

Raggruppamento logico (mask description `soc:ui:Sw2StreamBlockMaskDescr`, verbatim):

> "event, msg and done ports write data from software to memory using Stream Write block.
> rdData, rdCtrlIn and rdCtrlOut ports read data from memory to stream."

`[ART]` Disposizione grafica (`PortSchema`): lato **sinistro** = `event`, `msg`, `done` (dominio software); lato **destro** = `rdData`, `rdCtrlOut`, `rdCtrlIn` (dominio AXI4-Stream/FPGA).

> **ATTENZIONE — bug nella libreria stessa** `[ART]`: il campo `<Description>` inline del blocco (riga 1637 di `system_root.xml`) cita ancora porte `wrData`, `wrEvent`, `wrDone` — nomi **obsoleti che non esistono**. Il testo corretto è quello del catalogo `ui.xml`.

## 3.2 Parametri e default

`[ART]` Identici in `socmemlib.slx` e `socmemlib2.slx`:

| Parametro programmatico | Prompt GUI | Default | Tab |
|---|---|---|---|
| `MemorySimulation` | Memory simulation | **`Protocol accurate`** | radio top |
| `MemorySelection` | Memory selection | `PS memory` (read-only se board mono-memoria) | Main |
| `MRNumBuffers` | Number of buffers | `8` | Main |
| `BurstLengthReaderChIf` | Burst length | `256` | Main → Advanced |
| `FIFODepthReader` | FIFO depth (number of bursts) | `8` | Main → Advanced |
| `FIFOAFullDepthReader` | FIFO almost-full depth | `6` | Main → Advanced |
| `ICClockFrequencyReader` | Clock frequency (MHz) | `100` | Main → Advanced |
| `ICDataWidthReader` | Data width (bits) | `64` | Main → Advanced |
| `ChDimensionsWriterChIf` | Dimensions (Software data signal) | `1024` | Data Signal Attributes |
| `ChTypeWriterChIf` | Data type (Software) | `uint32` | Data Signal Attributes |
| `ChDimensionsReaderChIf` | Dimensions (Stream data signal) | `1` | Data Signal Attributes |
| `ChTypeReaderChIf` | Data type (Stream) | `uint32` | Data Signal Attributes |
| `ChFrameSampleTimeReaderChIf` | Sample time | `1` | Data Signal Attributes |
| `ChBitPackedReaderChIf` | Enable sample packing | `off` | Data Signal Attributes |
| `MRRegionSize` / `MRBufferSize` | Region/Buffer size (bytes) | `32768` / `4096` | derivati (hidden) |

`[ART]` I default sono **auto-consistenti**: `MRBufferSize` = 1024 × 4 B = 4096; `MRRegionSize` = 8 × 4096 = 32768; burst 256 × 4 B = 1024 B → 4 burst/buffer (intero); 1024/256 = 4 (intero).

Uso via API:

```matlab
blk = [mdl '/Software to AXI4-Stream'];
set_param(blk,'MemorySimulation','Protocol accurate');
set_param(blk,'MRNumBuffers','8');                  % 3..64
set_param(blk,'BurstLengthReaderChIf','256');
set_param(blk,'ICDataWidthReader','64');            % {32,64,128,256,512,1024}
set_param(blk,'ChDimensionsWriterChIf','1024');
set_param(blk,'ChTypeWriterChIf','uint32');         % SOLO unsigned, vedi 3.4
set_param(blk,'ChDimensionsReaderChIf','1');
set_param(blk,'ChTypeReaderChIf','uint32');
```

Callback (offuscati, `.p`): `...\fpga\simulation\+soc\+blkcb\Software2StreamCb.p` e `Software2StreamCb2.p`.

## 3.3 Vincoli realmente applicati (verbatim da `msgs.xml`)

`[ART]` da `C:\Program Files\MATLAB\R2026a\resources\soc\en\msgs.xml`. **In gran parte assenti dalla refpage**, che dice solo "scalar". Sono scopribili solo dal catalogo o provocando l'errore.

| Chiave messaggio | Vincolo |
|---|---|
| `NumBuffersGTE3` / `NumBuffersLSE64` | `3 <= MRNumBuffers <= 64` |
| `ICFIFODepth` | *"FIFO depth valid values are scalar integer: **2, 4, 8, 16, 32**"* |
| `ICFIFOAFullDepth` | *"must be less than or equal to FIFO depth... valid values are scalar integer between **1 and FIFO depth**"* |
| `ICDataWidth` | *"valid values are scalar integer: **32, 64, 128, 256, 512, 1024** bits"* |
| `ChAndBurstLength` | *"**Channel length must be integer multiple of burst length OR burst length must be integer multiple of channel length**"* |
| `BurstAndBufferLength` | *"Buffer size must be an integer multiple of burst size"* |
| `MisalignedMRBuffers` | *"The buffer size must be aligned to the interconnect data width"* (warning + auto-correzione) |
| `BurstLengthNotInt` | Burst length deve essere intero |
| `ChTDATAWidthGT128` | Word width del canale <= **128 bit** (TDATA) |
| `ChBitPackedWidth` | Word width bit-packed <= **512 bit** |
| `checkFpgaDmaDataWidthCase1` | `ICDataWidth >= channel data width` |
| `checkFpgaDmaBurstSize` | Burst size in *memory beats* <= **256** (limite AXI4) |
| `checkFpgaADIDmaFifoSize` | FIFO depth in bursts nel range **2–32** per implementazione DMA |

Chiarimenti su tre ipotesi ricorrenti:

- **"Burst length deve dividere il frame size"** — quasi, ma la relazione è **bidirezionale**: `ChAndBurstLength` accetta anche il caso inverso (burst multiplo della channel length). Non è un semplice "divide".
- **"Burst length deve essere potenza di 2"** — **NO** `[ART]`: `soc_hwsw_stream_set_parameters.m` usa `BurstLength = 75, 150, 200, 250`. È la **FIFO depth** a dover essere potenza di 2.
- **`ICDataWidth` ammessi** — `32, 64, 128, 256, 512, 1024` bit **e** `>= channel data width`.

## 3.4 Perché `ChTypeWriterChIf` accetta solo unsigned

`[ART]` Il vincolo è codificato nel *type spec* della maschera:

```text
ChTypeWriterChIf : unidt({a=ChTypeWriterChIf|||}{b=uint16|uint32|uint64}
                         {s=UDTBinaryPointMode}{g=UDTUnsignedSign})

ChTypeReaderChIf : unidt({a=ChTypeReaderChIf|||}{b=double|single|int8|uint8|int16|uint16|
                          int32|uint32|int64|uint64|boolean}
                         {s=UDTBinaryPointMode}{g=UDTSignedSign|UDTUnsignedSign})
```

`{b=...}` = tipi builtin offerti; `{g=...}` = segni ammessi per fixed-point. Il **writer** espone **solo** `UDTUnsignedSign`; il **reader** entrambi.

**Il *motivo* NON è documentato.** La refpage elenca i tipi ammessi senza alcuna spiegazione (verificato con interrogazione mirata della pagina).

`[INFERENZA]` — ricostruzione, **non** fonte MathWorks: il lato writer è software che deposita byte in un buffer DMA; il tipo lì non ha semantica aritmetica, definisce solo la **larghezza della word contenitore** (16/32/64 bit = 2/4/8 byte, gli unici allineamenti DMA legali) usata per calcolare `MRBufferSize` e la lunghezza del burst. L'interpretazione numerica avviene sul lato reader (`rdData`), che infatti ammette signed, float e boolean.

## 3.5 Frame-based vs sample-based — la risposta precisa

`[ART]` **Il modello FPGA riceve `tdata` come SCALARE.** In `soc_swhw_stream_fpga.slx` (l'esempio SW→HW, l'unico che usa Software to AXI4-Stream):

```text
Inport "tdata"        : OutDataTypeStr=int32,  PortDimensions=1, SamplingMode=Sample based
Inport "tvalid"       : Bus StreamM2SBusObj,   PortDimensions=1, SamplingMode=Sample based
Inport "streamEnable" : boolean,               PortDimensions=1
Outport "tready"      : Bus StreamS2MBusObj
```

Un beat per ciclo. `soc_swhw_stream_top.slx` referenzia direttamente e unicamente `soc_swhw_stream_fpga.slx` — **non esiste variante frame-based del modello FPGA in questo esempio**.

`[ART]` Il selettore frame/sample **non appartiene al blocco Software to AXI4-Stream**: è un meccanismo dell'esempio HW→SW (`soc_hwsw_stream_init.m`):

```matlab
switch simmode
    case 'Sample based processing'
        FPGASTime     = SourceSTime;   % rate veloce = clock FPGA
        FPGAFrameSize = 1;             % SCALARE
    case 'Frame based processing'
        FPGASTime     = ProcSTime;     % = SourceSTime*100*FrameSize (lento)
        FPGAFrameSize = FrameSize;     % VETTORE
end
```

`FPGAFrameSize` pilota `SamplesPerFrame` dei generatori. Controprova: la stringa `FPGAFrameSize` compare **2 volte** in `soc_hwsw_stream_fpga_frame.slx` e **0 volte** in `soc_hwsw_stream_fpga.slx`. Il variant cambia **due cose accoppiate**: dimensione del segnale (scalare ↔ vettore) e sample time (veloce ↔ rallentato di `FrameSize`). Il prodotto rate × dimensione è invariante: **frame-based esiste solo per velocizzare la simulazione**.

`[DOC]` [hwsw-stream](https://www.mathworks.com/help/soc/ug/hwsw-stream.html), sezione "Implement and Run on Hardware", verbatim:

> "Open the mask of the `FPGA` subsystem and set the model variant to **Sample based processing**."

**Il motivo NON è documentato** (verificato con query mirata su entrambe le pagine). `[INFERENZA]` la ragione ingegneristica: AXI4-Stream è beat-seriale (un `TDATA` per handshake `TVALID`/`TREADY`); HDL Coder mappa un vettore Simulink nello *spazio*, non nel tempo — 1024 elementi diventano 32768 bit paralleli, violando il limite TDATA <= 128 bit; e `FPGASTime` frame-based non corrisponde al clock FPGA.

### Il punto architetturale chiave

`[ART]` In `soc_swhw_stream_top.slx` il sottosistema processore si chiama letteralmente **`Processor - Frame based processing`**, mentre il modello FPGA è sample-based scalare.

**Il blocco Software to AXI4-Stream *è* il convertitore fra i due domini**: il software scrive frame interi (`ChDimensionsWriterChIf = 1024`) in un buffer DMA; il blocco li de-serializza in beat singoli (`ChDimensionsReaderChIf = 1`). Frame-based lato software e sample-based lato FPGA **coesistono per costruzione**, non sono un'alternativa. Conferma numerica sul parametro nascosto `ChFrameSampleTimeWriterChIf = [1024 0]` vs `ChFrameSampleTimeReaderChIf = 1`: rate matching esatto.

## 3.6 Formule di dimensionamento

`[DOC]` verbatim, corrette:

```text
(NumFrameBuffers + 1) * FramePeriod <= MaxLatency
FramePeriod > MeanTaskDuration
FramePeriod = FrameSize * FPGAOutputSampleTime
```

`[ART]` **La formula della FIFO depth nella doc è incompleta.** Da `soc_hwsw_stream_set_parameters.m`, righe 99-100:

```matlab
FIFODepth = FrameSize/BurstLength;
FIFODepth = 2^nextpow2(FIFODepth);     % <-- ARROTONDAMENTO A POTENZA DI 2
```

Formula corretta: **`FIFODepth = 2^nextpow2(FrameSize/BurstLength)`, clampata a {2,4,8,16,32}**.

`[ART]` L'almost-full è sempre `FIFODepth-1`, e le `set_param` vanno **riordinate** per non violare transitoriamente il vincolo `AFull <= Depth` (righe 122-128):

```matlab
if FIFODepth < currFIFOAFullDepth
    set_param(...,'FIFOAFullDepthWriter',num2str(FIFODepth-1));   % abbassa prima
    set_param(...,'FIFODepthWriter',     num2str(FIFODepth));
else
    set_param(...,'FIFODepthWriter',     num2str(FIFODepth));     % alza prima
    set_param(...,'FIFOAFullDepthWriter',num2str(FIFODepth-1));
end
```

Elenco completo dei vincoli di dimensionamento:

```text
MRBufferSize   = prod(ChDimensionsWriterChIf) * sizeof(ChTypeWriterChIf)
MRRegionSize   = MRNumBuffers * MRBufferSize
BurstSizeBytes = BurstLengthReaderChIf * sizeof(ChTypeWriterChIf)

3 <= MRNumBuffers <= 64
FIFOAFullDepthReader <= FIFODepthReader        (enforced; l'init usa Depth-1)
FIFODepthReader in {2,4,8,16,32}
ICDataWidthReader in {32,64,128,256,512,1024} AND >= channel data width
mod(MRBufferSize, BurstSizeBytes) == 0                 (BurstAndBufferLength)
mod(MRBufferSize, ICDataWidthReader/8) == 0            (MisalignedMRBuffers)
BurstSizeBytes / (ICDataWidthReader/8) <= 256          (limite beat AXI4)
channel word width <= 128 bit                          (TDATA)
packed word width  <= 512 bit                          (se sample packing on)
```

Verifica sui default: 1024 B burst / 8 B per beat = 128 beat <= 256. OK.

**Fonti area 3**: [Software to AXI4-Stream](https://www.mathworks.com/help/soc/ref/softwaretoaxi4stream.html) · [Streaming Data from Hardware to Software](https://www.mathworks.com/help/soc/ug/hwsw-stream.html) · [Streaming Data from Software to Hardware](https://www.mathworks.com/help/soc/ug/swhw-stream.html)

---

<a name="4-task-manager-e-asynchronous-task-specification"></a>
# 4. Task Manager e Asynchronous Task Specification

## 4.1 `AllTaskData` — l'unico parametro che definisce i task

`[ART]` `AllTaskData` è `Type="edit" Evaluate="off"`: una **stringa JSON**, oggetto singolo (1 task) o array di oggetti (N task), **in ordine = ordine dei task e delle porte**. Maschera verificata in `...\toolbox\shared\soc\processor\blocks\proctasklib.slx` → `simulink/systems/system_root.xml`, blocco `SubSystem Name="Task Manager" SID="102"`.

Default di libreria (`version` 2.0, 17 campi):

```json
{"taskName":"Task1","taskType":"Timer-driven","taskEvent":"<empty>","taskPeriod":0.1,
 "taskPriority":10,"coreSelection":"Specified core","coreNum":0,"dropOverranTasks":false,
 "playbackRecorded":false,"diagnosticsFile":"","taskDurationSource":"Dialog",
 "taskDuration":1E-6,"taskDurationDeviation":0,"logExecutionData":true,
 "logDroppedTasks":false,"version":"2.0",
 "taskDurationData":{"percent":100,"mean":1E-6,"dev":0,"min":1E-6,"max":1E-6}}
```

Schema **v2.6** — quello che R2026a scrive e che i modelli shipped contengono (25 campi):

| Campo | Tipo | Valori / note |
|---|---|---|
| `taskName` | string | lettere/cifre/`_`, deve iniziare con lettera, <=55 char, univoco, diverso dal nome del modello (`scheduler.xml:91,85,89`) |
| `taskType` | string | `"Timer-driven"` \| `"Event-driven"` |
| `taskEvent` | string | nome dell'evento che arma il task; convenzione `<taskName>Event`; `"<empty>"` se assente |
| `taskPeriod` | string o number | reale positivo; usato solo per Timer-driven |
| `taskPriority` | string o number | intero; range imposto dalla board (default 1..99) |
| `coreSelection` | string | `"Specified core"` in tutti i modelli shipped |
| `coreNum` | string o number | intero >=0 (oppure -1 = assegnato dall'OS) |
| `dropOverranTasks` | bool | richiede "Detect task overruns" abilitato |
| `playbackRecorded` | bool | playback di una sequenza registrata |
| `diagnosticsFile` | string | path CSV (es. `"dataReadTask.csv"`) |
| `taskDurationSource` | string | `"Dialog"` \| `"Input port"` \| `"Recorded task execution statistics"` |
| `taskDuration` | number | durata scalare |
| `taskDurationDeviation` | number | |
| `logExecutionData` | bool | |
| `logDroppedTasks` | bool | |
| `version` | string | `"2.0"`, `"2.3"`, `"2.6"` — tutte accettate |
| `taskDurationData` | object **o array di object** | ogni elemento: `percent`, `mean`, `dev`, `min`, `max` (numeri **o** stringhe **o** array-di-1-stringa: tutte e tre le forme sono presenti nei modelli shipped). Somma `percent` = 100 |
| `taskEventSource` | string | **nome del blocco sorgente evento** (es. `"Software to AXI4-Stream"`, `"mwinterrupt_generator1_ip0"`), oppure `"Internal"` (timer-driven), oppure `"Unspecified"` |
| `taskEventSourceAssignmentType` | string | `"Unassigned"` \| `"AutoAssigned"` \| `"ManuallyAssigned"` |
| `taskEventSourceType` | string | `"Unspecified"` in tutti i modelli shipped R2026a |
| `taskEventGroup` | string | famiglia della sorgente: `"FPGA"` o `"Unspecified"` |
| `taskEventInterrupt` | string | nome dell'interrupt nel gruppo, es. `"Interrupt Generator1"`, o `"Unspecified"` |
| `taskEventOrder` | number | intero, default 1 |
| `taskDisablePremption` | bool | (sic, **typo nel prodotto**: "Premption") — UI "Disable task preemption" |
| `taskClearInterruptFlagsAtEndOfEvent` | bool | |

### Significato dei tre campi `taskEventSource*`

`[EXP]`

- **`taskEventSource`** = *identità* della sorgente: nome del blocco che genera l'evento. Confermato da `soc.internal.taskmanager.getEventSourceForTask` (restituisce esattamente quella stringa) e da `getEventSourceBlockForTask` (restituisce l'handle del blocco reale).
- **`taskEventSourceAssignmentType`** = *come* è stata stabilita l'associazione. Verificato: chiamando `soc.internal.taskmanager.setTaskEventManuallyAssigned(tmBlock)` il campo passa da `AutoAssigned`/`Unassigned` a `ManuallyAssigned`. `autoassignTaskToEventSource` produce `AutoAssigned`.
- **`taskEventSourceType`** = *categoria* della sorgente; `Unspecified` ovunque nei modelli R2026a shipped, letta da `getEventSourceTypeForTask`. La coppia `taskEventGroup` + `taskEventInterrupt` è la variante "hardware": in `soc_hwsw_interrupt_top` valgono `"FPGA"` + `"Interrupt Generator1"`/`"Interrupt Generator2"`.

### Esempio reale (estratto da `soc_swhw_stream_top.slx`, `Processor/Task Manager`)

```json
[{"taskName":"WriteTask","taskType":"Event-driven","taskEvent":"WriteTaskEvent",
  "taskPeriod":"0.1","taskPriority":"50","coreSelection":"Specified core","coreNum":"1",
  "dropOverranTasks":false,"playbackRecorded":false,"diagnosticsFile":"",
  "taskDurationSource":"Dialog","taskDuration":1E-6,"taskDurationDeviation":0,
  "logExecutionData":true,"logDroppedTasks":false,"version":"2.6",
  "taskDurationData":[{"percent":["98"],"mean":["8e-4"],"dev":["1e-5"],"min":["7e-4"],"max":["9e-4"]},
                      {"percent":["2"],"mean":["2e-3"],"dev":["0"],"min":["2e-3"],"max":["2e-3"]}],
  "taskEventSource":"Software to AXI4-Stream","taskEventSourceAssignmentType":"AutoAssigned",
  "taskEventSourceType":"Unspecified","taskEventGroup":"Unspecified",
  "taskEventInterrupt":"Unspecified","taskEventOrder":1,
  "taskDisablePremption":false,"taskClearInterruptFlagsAtEndOfEvent":false},
 {"taskName":"ReadTask","taskType":"Timer-driven", ... ,"taskEventSource":"Internal", ...}]
```

`[EXP]` **Il JSON da solo non basta**: la porta `WriteTaskEvent` del Task Manager deve essere **fisicamente collegata** alla porta `event` del blocco `Software to AXI4-Stream` (nel modello reale: root → Inport `WriteTaskEvent` del sottosistema `Processor` → `Task Manager`). Verificato via `get_param(...,'PortHandles')`.

> **`set_param` NON valida `AllTaskData`** `[EXP]`. `"taskDurationSource":"bogus"` e `"coreSelection":"Any core"` vengono **accettati e memorizzati verbatim**. La validazione avviene a compile/update (messaggi in `resources\soc\en\scheduler.xml`: `InvalidTaskType`, `TaskEventNotFound`, `InvalidPriority`, `InvalidCoreNum`, `MultipleTasksHandleSameEvent`, `MaxNumTasksExceeded`, …).

### Altri parametri di maschera del Task Manager

`[EXP]` lista completa da `Simulink.Mask.get`: `AllTaskData`, `EnableTaskSimulation`, `StreamToSDI`, `WriteToFile`, `OverwriteFile`, `SupportEventPorts`, `UseScheduleEditor`, `TaskEditData` (NeverSave), `CustomizationInfo`.

`[EXP]` Limiti da `soc.internal.taskmanager.getCustomizationInfo(tmBlock)` (default, senza board):
`scheduleeditorsupported=1`, `maxnumtasks=99`, `tasktypessupported={'Event-driven','Timer-driven'}`, `coreassignmentsupported=1`, `taskdropsupported=1`, `taskprioritiessupported=[1 99]`, `taskpreemptionsupported=1`, `playbacksupported=1`, `taskdurationsourcesupported={'Dialog','Input port','Recorded task execution statistics'}`.

## 4.2 Porte del Task Manager

`[EXP]` Verificato sperimentalmente in R2026a (script `tm_probe*.m`).

- **Uscite** = 1 per task, sempre, nell'ordine di `AllTaskData`, con nome = `taskName`. Segnale function-call.
- **Ingressi** = generati per task, nell'ordine di `AllTaskData`; per ciascun task:
  1. `<taskName>Dur` **se** `taskDurationSource == "Input port"`
  2. `<taskName>Event` **se** `taskType == "Event-driven"` (messaggio `rteEvent`)

  → **`Dur` precede `Event` nello stesso task.** L'ordine della tabella nella doc (che elenca `Task1Event` prima di `Task1Dur`) **non** è l'ordine degli indici di porta.

| Config (ordine task) | in | out | Porte ingresso in ordine |
|---|---|---|---|
| 1 task Timer, Dialog (default libreria) | 0 | 1 | — |
| E1(evt,Dialog), T1(timer,Input port), E2(evt,Input port) | 4 | 3 | `E1Event`, `T1Dur`, `E2Dur`, `E2Event` |
| P(evt,Input port), Q(evt,Input port) | 4 | 2 | `PDur`, `PEvent`, `QDur`, `QEvent` |
| A(evt), B(evt), C(timer) tutti Dialog | 2 | 3 | `AEvent`, `BEvent` |

Coerente con i modelli shipped `[ART]`: `soc_hwsw_stream_top` (1 task event) → `in="1" out="1"`; `soc_swhw_stream_top` (1 event + 1 timer) → `in="1" out="2"`; `soc_hwsw_interrupt_top` (2 event) → `in="2" out="2"`.

`[EXP]` **`SupportEventPorts`** (non documentato, default `on`): verificato in entrambe le direzioni — portandolo a `off`, sia con link di libreria intatto, sia dopo `set_param(blk,'LinkStatus','none')`, sia riapplicando `AllTaskData` per forzare la mask-init — **il numero e l'ordine delle porte non cambiano**. Nessun modello shipped in `matlabroot` lo imposta a `off`.
**Conclusione onesta:** in R2026a, in un modello senza board SoC configurata, il conteggio porte dipende **solo** da `AllTaskData`; non è stato possibile osservare alcun effetto di `SupportEventPorts`. `[INCERTO]` È plausibile che sia consumato dalla DDG `taskmanagerdlg.TaskManagerMask` o dalla customizzazione board, entrambe p-coded e non verificabili.

## 4.3 Uso via API — configurazione programmatica dei task

**Non esiste una API pubblica documentata** per creare/modificare task. Il metodo supportato *di fatto* — usato da MathWorks stessa negli script degli esempi shipped — è `set_param` su `AllTaskData`:

`[ART]` `...\toolbox\soc\socexamples\soc_hwsw_stream_set_parameters.m` (riga 101) e `soc_swhw_stream_set_parameters.m` (righe 37-54) costruiscono la stringa JSON per concatenazione e fanno
`set_param([mdl,'/Processor/Task Manager'],'AllTaskData', jsonString)`.

Pattern più robusto `[EXP]` (round-trip completo verificato):

```matlab
tm = 'myTop/Processor/Task Manager';
t  = soc.internal.taskmanager.getTasks(tm);   % struct array, 25 campi
t(1).taskPriority = '77';
t(2).taskType     = 'Timer-driven';
t(2).taskPeriod   = '0.05';
set_param(tm, 'AllTaskData', jsonencode(t));
```

`soc.internal.taskmanager.getTasks` restituisce uno struct array i cui campi mappano 1:1 il JSON, quindi `jsonencode` produce un `AllTaskData` valido. **Non documentato** (`soc.internal.*`, p-coded), ma stabile e senza parsing manuale di stringhe.

`[EXP]` Altre funzioni p-coded in `...\toolbox\shared\soc\processor\+soc\+internal\+taskmanager\` (tutte undocumented, nessun testo di help): `getTaskNames`, `getSortedTaskNames`, `getEventDrivenTaskNames`, `getEventSourceForTask`, `getEventSourceTypeForTask`, `getEventSourceBlockForTask`, `getEventInterruptForTask`, `setTaskEventManuallyAssigned(tmBlock)` (1 solo argomento), `autoassignTaskToEventSource`, `getCustomizationInfo`, `applyTaskManagerCustomization`, `syncSchedules`, `getTaskToPartitionMapping`, `hasEventDrivenTasks`, `isUsingScheduleEditor`.

`[EXP]` In `+soc` (livello "pubblico" ma senza doc né help): `soc.registerTask`, `soc.registerEvent`, `soc.registerBlock` — esistono in `...\toolbox\shared\soc\processor\+soc\`, richiedono argomenti (errore `MATLAB:minrhs` / `narginchk`), nessuna pagina di documentazione pubblica. `[INFERENZA]` presumibilmente parte della Board Support API per registrare sorgenti evento custom.

**Alternativa non-JSON, documentata**: **Schedule Editor** — spuntare `Use Schedule Editor ordering` (`UseScheduleEditor`) e definire ordine/priorità lì, con **nomi partizione = nomi task**.

## 4.4 Blocco Asynchronous Task Specification (ATS)

`[EXP]` **Non è un blocco SoC Blockset**: è built-in Simulink Coder.

```matlab
% BlockType = 'AsynchronousTaskSpecification'
% path di libreria: rtwlib/Asynchronous/Asynchronous Task Specification
add_block('built-in/AsynchronousTaskSpecification', [procMdl '/ATS']);
set_param([procMdl '/ATS'],'TaskPriority','50');   % unico parametro, default 10
```

`TaskPriority` accetta intero o `[]`.

`[ART]` **Dove va**: nel **modello processore referenziato**, **al root**, non nel top model. Confermato dai modelli shipped: `soc_hwsw_stream_proc.slx` e `soc_swhw_stream_proc.slx` hanno al root `<Block BlockType="AsynchronousTaskSpecification">` con `TaskPriority=50`, alimentato dall'Inport function-call (`DataTask`, risp. `write_fcn`) con `<P Name="OutputFunctionCall">on</P>`, e uscita verso il Function-Call Subsystem.

`[DOC]` **Priorità**: deve coincidere con `taskPriority` del task nel Task Manager — *"The task priority of the Asynchronous Task Specification block must match the priority of task in the Task Manager block driving this task"*. Nell'esempio: `TaskPriority=50` <-> `"taskPriority":"50"`.

### I due vincoli topologici — testi esatti

`[ART]` da `C:\Program Files\MATLAB\R2026a\resources\Simulink\en\FcnCall.xml`:

- `AsyncTaskSpecBlkNotDrivenByRootInportFcnCall` (riga 778):
  > "Asynchronous Task Specification block ''{0}'' must be directly connected to the output port of a root-level Inport block that has been configured to output a function-call signal."

- `RootInportFcnCallWithAsyncTaskSpecBlkMultDsts` (riga 777):
  > "Inport block ''{0}'' has a connection that is not valid. Since an Asynchronous Task Specification block has been placed at the output port of this Inport block, the output signal of the Inport block cannot be connected to any other block (including another Asynchronous Task Specification block)."

Vincoli correlati nello stesso catalogo:

| Chiave | Regola |
|---|---|
| `AsyncTaskSpecBlkUnconnectedOutput` (779) | l'uscita non può restare scollegata né andare a un Terminator |
| `RootInportFcnCallNoAsyncTaskSpecBlk` (738) | se un Inport di root emette function-call, un ATS **deve** essere piazzato sulla sua uscita (alternativa: il modello dev'essere export-function) |
| `MixedRootFcnCallInportToAsyncTaskSpecConnections1/2` (707/710) | vietato mischiare Inport function-call con e senza ATS nello stesso modello |
| `InvMdlWithAsyncTaskSpecSetToExpFcns` (774) | un modello con ATS non può essere export-function model |
| `TwoAsyncTaskSpecTIDsAssignedSamePriority` (`SampleTime.xml:330`) | due ATS con la stessa priorità → diagnostica "Tasks with equal priority" |
| `NumRefMdlInstancesInvalid` (`soc\en\msgs.xml:1052`) | "Total number of instances of the reference model ''{0}'' allowed per top model must be set to ''One'' since this model has an event-driven task." |

## 4.5 Collegamento Task Manager → modello processore

`[ART]` Regole da `resources\soc\en\scheduler.xml` e `utils.xml`:

- L'uscita di ogni task va collegata a un **Model block** (il proc model referenziato), **non** direttamente a un function-call subsystem:
  - `TaskMgrDrivesFcnCallSubsystem`: *"Task Manager block is directly connected to a function-call subsystem. This modeling style is not supported. Place your function-call subsystem in a Model block and connect it with Task Manager block."*
  - `TaskMgrConnToSubsys` (`utils.xml:62`): *"…Task Manager block output port must be connected to a Model block."*
- `TaskManagerUnconnectedTask`: *"Connect the output to a periodic event port of a Model block or a function-call subsystem in a Model block."* → per un task **timer-driven** l'uscita va alla **porta di rate periodico** del Model block; per un task **event-driven** all'**Inport function-call** (che dentro il proc model è seguito dall'ATS).
- `TaskMgrDrivesMultipleModels`: un Task Manager non può pilotare più Model block.
- `TaskMgrFcnCallSplit`: vietato Function-Call Split sulle uscite.
- `TaskManagerUnexpectedTwoBlocks` / `TaskMgrTerminated` / `TaskManagerUnexpectedBlock`: una sola destinazione per porta, niente Terminator, niente blocchi intermedi.
- `TaskMgrMisplaced`: *"Task Manager must be either in the top model or in a virtual subsystem in the top model."*
- `MultipleTaskManagers`: un solo Task Manager per modello (eccetto multi-PU).
- `NegPriorityOrderNotSupported` (`utils.xml:54`): serve **"Higher priority value indicates higher task priority"** spuntato (Solver details), in **entrambi** i modelli.
- `HWBoardASICFPGA`: il Task Manager non va nel modello con device vendor ASIC/FPGA.
- `IOBlkNotInFcnCall` (`utils.xml:60`): un blocco IO event-driven deve stare in un function-call subsystem (o partizione aperiodica) collegato a una **uscita di task Event-driven** del Task Manager.
- Con Schedule Editor (`UseScheduleEditor`): `PartitionsMustHaveTasks` — i nomi delle partizioni nel proc model devono coincidere con i `taskName`.

`[ART]` Lato ingresso evento: la porta `<task>Event` va collegata alla porta *event* di un blocco generatore (Memory Channel, IO Data Source, `prociodatalib/Event Source`, `socmemlib/Software to AXI4-Stream`, Interrupt Channel). Se manca → `TaskEventNotFound`.

`[EXP]` Verificato sul modello reale `soc_swhw_stream_top`: entrambe le uscite del Task Manager vanno al Model block `Processor - Frame based processing`.

**Fonti area 4**: [Task Manager](https://www.mathworks.com/help/soc/ref/taskmanager.html) · [Task Execution](https://www.mathworks.com/help/soc/ug/task-execution.html) · [Event-Driven Tasks](https://www.mathworks.com/help/soc/ug/event-driven-task.html) · [Event-Driven Task (esempio)](https://www.mathworks.com/help/soc/ug/event-driven-task-example.html) · [Asynchronous Task Specification](https://www.mathworks.com/help/rtw/ref/asynchronoustaskspecification.html) · [Event Source](https://www.mathworks.com/help/soc/ref/eventsource.html) · [Software and Task Management on Processor](https://www.mathworks.com/help/soc/ug/create-new-soc-model-task-managment.html) · [Task Management with Schedule Editor](https://www.mathworks.com/help/soc/ug/task-management-with-scheduling-editor.html) · [Why do we need Asynchronous Task Specification block? (MATLAB Answers)](https://www.mathworks.com/matlabcentral/answers/2176526-why-do-we-need-asynchronous-task-specification-block)

---

<a name="5-generazione-hdl-da-un-modello-soc"></a>
# 5. Generazione HDL da un modello SoC

## 5.1 La DUT: scalare o vettore?

`[DOC]` **Entrambi ammessi, ma sono due modalità diverse e mutuamente esclusive.** Da *Sample-Based Modeling*, verbatim:

> "You can model the data signal as either a scalar or a vector."
> "If you model the data signal as a vector, in the HDL Coder Workflow Advisor **Task 1.2. Set Target Interface > Interface Options** set the **Sample Packing Dimension** to `All`."

Le tre modalità documentate:

| Modalità | Dato sulla porta DUT | Segnali da modellare | Note |
|---|---|---|---|
| **Sample-Based** | scalare (default) *oppure* vettore con `SamplePackingDimension='All'` | `Data` + `Valid` obbligatori; opzionali `Ready`, `TLAST`, `TKEEP`, `TID`, `TDEST`, `TUSER`, `TSTRB` | modalità raccomandata |
| **Frame-Based** | vettore / matrice / matrice complessa | **solo `Data`** — "The frame-to-sample conversion optimization generates the Ready and Valid signals" | richiede `FrameToSampleConversion = on` |
| **Legacy Frame-Based** | vettore, `SamplePackingDimension='None'` | Serializer1D / Deserializer1D espliciti | "This modeling style will be deprecated in a future release." |

`[ART]` Vincoli hard-coded, da `C:\Program Files\MATLAB\R2026a\resources\hdlcommon\en\interface.xml`:

- riga 24 — `AXIStreamVectorError`: *"Multiple AXI4-Stream interfaces cannot be mapped to vector ports. To use multiple AXI4-Stream interfaces, you must map only scalar ports to these interfaces."*
- riga 19 — `AXIStreamScalarError`: *"When one AXI4-Stream interface is mapped to a vector port, additional AXI4-Stream interfaces cannot be mapped to scalar ports."*
- riga 78 — `SubPortVectorPortIOMapping`: *"When "{0}" interface is assigned to vector port, "{1}" is the only choice for IOInterfaceMapping."* → **su porta vettoriale puoi mappare SOLO `Data`**, non `Valid`/`Ready`.
- riga 79 — `SubPortVectorPortOnly`: *"When assign "{0}" interface to vector port "{1}", only the vector port can be assigned to "{2}" interface."*

**Conseguenza operativa: se vuoi handshake valid/ready esplicito sulla DUT, il dato DEVE essere scalare.**

### Prova diretta dall'esempio installato

`[ART]` `...\toolbox\soc\socexamples\soc_swhw_stream_fpga.slx`:

- root Inport `tdata`: `OutDataTypeStr = int32`, `PortDimensions = 1` → **scalare, 32 bit**
- DUT = subsystem `sineWaveFilter` (da `hdlParams.xml`: `HDLSubsystem = $bdroot/sineWaveFilter`, `Workflow = IP Core Generation`)

| Porta DUT | `IOInterface` | `IOInterfaceMapping` |
|---|---|---|
| `tdata` (in) | `AXI4-Stream 0 Slave` | `Data` |
| `tvalid` (in) | `AXI4-Stream 0 Slave` | `Valid` |
| `tready` (out) | `AXI4-Stream 0 Slave` | `Ready` |
| `streamEnable` (in) | `AXI4-Lite` | `x"0100"` |
| `lowFreqReg` (out) | `AXI4-Lite` | `x"0104"` |
| `lowFreqLED` (out) | `External Port` | — |

Stesso schema in `soc_hwsw_stream_fpga.slx` (DUT = `FPGA Algorithm Wrapper`), che usa **slave + master**: `DataIn`/`ValidIn` → `AXI4-Stream 0 Slave` Data/Valid; `DataOut`/`ValidOut` → `AXI4-Stream 0 Master` Data/Valid; `RdyIn` → `AXI4-Stream 0 Master` Ready. Il dato è castato a `uint32` (blocco `Cast1`, `OutDataTypeStr = uint32`).

> **Uso via API — `[INCERTO]`, da confermare.** Nei `.slx` `IOInterface` e `IOInterfaceMapping` compaiono come coppie chiave/valore fra le HDL Block Properties della porta. L'accesso programmatico presumibile è `hdlset_param(<portBlock>,'IOInterface','AXI4-Stream 0 Slave')` e `hdlset_param(<portBlock>,'IOInterfaceMapping','Data')`. **Questa forma non è stata verificata nella ricerca**: prima di usarla in uno script, provarla su un modello di prova e rileggere con `hdlget_param`.

## 5.2 Vincoli: larghezza dati e numero di canali

### Larghezza dati — "<= 32 bit" è impreciso

`[ART]` In R2026a il RD AMD unificato ("Default system") espone la larghezza AXI4-Stream come **parametro del reference design**, non come limite fisso. Da `...\toolbox\hdlcoder\boards\amd\+common\+internal\addRDParameters.m`:

```matlab
pName = 'AXI4-Stream Slave data width';
pID = 'AXI4 stream to software data width';   % -> AXI4_STREAM_TO_SOFTWARE_DATA_WIDTH
availableDataWidths = {'32' '64' '128'};
defaultDataWidth = '32';
hRD.addParameter('ParameterID', pID, 'DisplayName', pName, ...
    'DefaultValue', defaultDataWidth, ...
    'ParameterType', hdlcoder.ParameterType.Dropdown, 'Choice', availableDataWidths);
% idem per 'AXI4-Stream Master data width' -> SOFTWARE_TO_AXI4_STREAM_DATA_WIDTH
```

**32 bit di default, massimo 128, valori ammessi solo {32, 64, 128}.** Il valore è passato all'interfaccia in `+common\+internal\addDMAInterfaces.m`:

```matlab
'MasterChannelDataWidth', str2double(param.AXI4_STREAM_TO_SOFTWARE_DATA_WIDTH), ...
'SlaveChannelDataWidth',  str2double(param.SOFTWARE_TO_AXI4_STREAM_DATA_WIDTH), ...
```

Nel RD legacy (`+ZedBoard\+vivado_stream_2022_1\plugin_rd.m`, nome `'Default system with AXI4-Stream interface'`) è invece **fisso a 32/32**.

Vincoli aggiuntivi `[ART]` (`interface.xml`):

- riga 80 — `TDATAPortWidth`: *"AXI4-Stream Protocol requires TDATA port width to be integer number of bytes."*
- riga 73 — `SubPortNotFitRDOverride`: *"Current reference design requires the TDATA port width of the interface "{0}" to be {1} bits. It cannot fit model port "{2}" with bit-width {3}."*
- riga 52 — `InterfaceNotEqualWidth`: *"Interface "{0}" requires exact bit-width of {1}, model port "{2}" with bit-width {3} does not fit."*
- `resources\fpgaio\en\fpgaio.xml` riga 57: *"Invalid packing configuration: A SamplePackingFactor of {0} for {1}-bit {2} elements results in a sample length of {3} bits, exceeding the specified data width of {4} bits."*

### Numero di canali

`[ART]` `addDMAInterfaces.m` fa **una sola** chiamata `addAXI4StreamInterface` con `InterfaceID = 'AXI4-Stream'`, `MasterChannelEnable = true`, `SlaveChannelEnable = true`. Idem per il RD legacy ZedBoard/ZC702/ZC706/ZCU102. Quindi **un master e uno slave** nel RD di default.

Vincoli di prodotto:
- `interface.xml` riga 53 — `LimitChannelNumber`: *"'MasterChannelNumber' or 'SlaveChannelNumber' can only be 0 or 1."*
- `interface.xml` riga 36 — `ChannelNumMaximum`: *"{0} interface currently only support {1} {2} channel."*
- `[DOC]` modalità legacy: *"In legacy frame-based mode, you can use at most one AXI4-Stream Master channel and one AXI4-Stream Slave channel."*

`[DOC]` **Precisazione**: `hdlcoder.ReferenceDesign.addAXI4StreamInterface` **può** essere chiamato più volte con `InterfaceID` distinti per avere più interfacce stream in un **RD custom** ([doc](https://www.mathworks.com/help/hdlcoder/ref/hdlcoder.referencedesign.addaxi4streaminterface.html)) — ma in quel caso **tutte** le porte mappate devono essere scalari (`AXIStreamVectorError`). Il RD di default AMD ne registra **una sola**.

> Nota: la pagina [addAXI4StreamInterface](https://www.mathworks.com/help/hdlcoder/ref/addaxi4streaminterface.html) senza prefisso di classe è **un'altra funzione** (oggetto `fpga` host-side, con `WriteDataWidth`/`ReadDataWidth` in {8,16,32,64,128}). Non confonderle.

## 5.3 Cosa succede con una porta dati vettoriale di N elementi

Dipende da **come è mappata**. Tre meccanismi distinti.

**(a) Vettore su AXI4-Stream con `SamplePackingDimension = 'All'`** `[DOC]`+`[ART]`
HDL Coder **impacchetta gli N elementi in UN solo campione TDATA largo N × bitwidth** (arrotondato al byte). Non genera N porte. Vincoli:
- la larghezza risultante deve stare nella `MasterChannelDataWidth`/`SlaveChannelDataWidth` del RD → **max 128 bit** (max 4 × int32, 8 × int16, 16 × int8);
- `SampleAlignment` = `PowerOf2Aligned` (obbligatorio per dati complessi) o `BitAligned`;
- su porta vettoriale **puoi mappare solo `Data`** (`SubPortVectorPortIOMapping`);
- tutte le porte AXI4-Lite della DUT devono passare per Rate Transition (`VectorModeRateTransitionNoConnect`, `interface.xml` riga 87).

**(b) Vettore su AXI4-Stream, legacy (`SamplePackingDimension = 'None'`)** `[DOC]`
Serializzazione esplicita: *"Connect each DUT input vector data port to a Serializer1D block"* / *"…output vector data port to a Deserializer1D block"*. Il vettore diventa uno **stream scalare di N campioni su N cicli**. Vincoli stretti su rate (`resources\hdlcoder\en\hdlstreaming.xml`): tutti i Serializer1D/Deserializer1D collegati a porte AXI4-Stream devono avere lo stesso rate, e le porte AXI4-Lite devono passare per Rate Transition con lo stesso rapporto. **Modalità deprecata.**

**(c) Vettore su `External Port`** `[DOC]`+`[ART]` — qui esplodono gli IOB
HDL Coder appiattisce i vettori al confine DUT in porte scalari. Da [Scalarization of Vector Ports](https://www.mathworks.com/help/hdlcoder/ug/scalarization-of-vector-ports.html) e [ScalarizePorts](https://www.mathworks.com/help/hdlcoder/ref/scalarizeports.html): `ScalarizePorts` in `off | on | dutlevel`; **"When target language is Verilog, HDL Coder flattens the vector signals to scalars by default"** — in Verilog l'appiattimento è il default e `ScalarizePorts` non ha effetto.

Check dedicato (`resources\hdlcoder\en\validate.xml`, righe 137-146):

> `IOThresholdExceeded`: *"IO pin count ''{0}'' exceeds the IO Mapping Threshold ''{1}''. Redesign the model or use HDL optimizations to reduce IOs. To generate code without changing the design, change the "Check for DUT pin count exceeding I/O Threshold" diagnostic to "Warning" or "None". **However, the generated code is not synthesizable.**"*
>
> `IOThresholdExceededSMT`: *"…Consider redesigning the model or use "Frame to sample" optimizations to reduce IO."*

Parametri: `IOThreshold` ("Max number of I/O pins for FPGA deployment") e `TreatIOThresholdAs` (`Error`/`Warning`/`None`) — `resources\hdlcoder\en\hdlconfig.xml` righe 130-133.

### Caso concreto: 25 elementi int32

**Un `tdata` vettoriale a 25 elementi mappato su AXI4-Stream nel reference design di default NON è generabile.** Non perché "il vettore sia vietato" (è ammesso), ma perché in modalità vettoriale i 25 × int32 = **800 bit** finiscono in un solo campione TDATA, contro un TDATA selezionabile solo fra 32/64/128 bit → errore `SubPortNotFitRDOverride`. Su `External Port` → 25 × N_bit pin fisici → `IOThresholdExceeded` → codice non sintetizzabile. **In nessuno dei due casi il modello arriva in hardware.**

Le tre uscite reali:

1. **Serializzare (raccomandato, = esempi MathWorks).** `tdata` scalare int32/uint32 (32 bit = default RD), `tvalid`, `tready`. I 25 elementi diventano un **pacchetto di 25 beat** consecutivi; marcane la fine con `TLAST` (mappabile come `IOInterfaceMapping = 'TLAST'` in Sample-Based Modeling). L'algoritmo nella DUT lavora a campione, con un contatore di indice 0..24. Costo: 25 cicli per vettore invece di 1 — a 25-50 MHz di target clock è quasi sempre irrilevante.
2. **Ridurre gli elementi per campione** fino a rientrare in 128 bit e alzare il RD data width: max **4 × int32**, **8 × int16**, **16 × int8** (`SamplePackingDimension='All'`, `SampleAlignment='PowerOf2Aligned'`). Non arriva a 25.
3. **Frame-based + `FrameToSampleConversion`**: possibile solo se il DUT non attraversa una model reference (vedi 5.5) — in un modello SoC Blockset è la strada più fragile.

## 5.4 Da frame-based (simulazione) a sample-based (hardware): il pattern Variant

`[ART]` **Esiste un pattern documentato ed è un Variant Subsystem**, implementato in `soc_hwsw_stream_top.slx` (`simulink/systems/system_675.xml`):

```xml
<Block BlockType="ModelReference" Name="Frame based processing" SID="688">
  <P Name="ModelNameDialog">soc_hwsw_stream_fpga_frame.slx</P>
  <P Name="VariantControl">Frame based processing</P>
</Block>
<Block BlockType="ModelReference" Name="Sample based processing" SID="689">
  <P Name="ModelNameDialog">soc_hwsw_stream_fpga.slx</P>
  <P Name="VariantControl">Sample based processing</P>
</Block>
```

Il blocco `FPGA` del top model è un **Variant Subsystem** con parametro maschera `simmode` che seleziona una di due **model reference**:
- `soc_hwsw_stream_fpga_frame.slx` → simulazione veloce, vettori
- `soc_hwsw_stream_fpga.slx` → generazione HDL, scalare

La callback `soc_hwsw_stream_init.m` deriva i parametri globali (`FPGASTime`, `FPGAFrameSize`; vedi 3.5). `FPGAFrameSize` è usato **solo** dal modello frame (`SamplesPerFrame = FPGAFrameSize`, `system_393.xml`); il modello sample non lo usa affatto. Entrambi hanno lo stesso set di porte (`SourceSelector`, `rdCtrlIn` bus `StreamS2MBusObj`, indicatori) → sono intercambiabili nel Variant.

Punti chiave del pattern:
1. Il *contratto di interfaccia* (nomi porte, bus `StreamM2SBusObj`/`StreamS2MBusObj`) è **identico** nelle due varianti.
2. Solo la variante sample-based porta i mapping `IOInterface`/`IOInterfaceMapping` verso AXI4-Stream ed è quella su cui gira l'IP Core Generation.
3. La conversione frame↔sample fisica **non avviene nel modello FPGA**: avviene nel **canale DMA** del top model (`AXI4-Stream to Software` / `Software to AXI4-Stream`), che presenta frame al processore e stream all'hardware.

## 5.5 Alternativa `FrameToSampleConversion` — con avvertenze pesanti

`[DOC]` Da [Model Design for Frame-Based IP Core Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-frame-based-IP-core-generation.html): *"Map vectors, complex vectors, matrices, and complex matrix data to AXI4-Stream interfaces"*, *"Model only the Data signals. The frame-to-sample conversion optimization generates the Ready and Valid signals"*.

Restrizioni `[ART]` verificate nei cataloghi installati:

- `resources\hdlcommon\en\streamingmatrix.xml` riga 10 — **"Frame-to-sample conversion is not supported through Model Reference hierarchy. Consider using Subsystem References instead."** → **critico in SoC Blockset, dove il modello FPGA È una model reference.**
- `resources\hdlcommon\en\workflow.xml` riga 490 — *"When frame to sample conversion is enabled, streamed scalar ports are not supported."*
- `workflow.xml` riga 180 — non si possono mescolare AXI4-Stream e AXI4-Stream Video.
- `workflow.xml` riga 174 — *"Frame to sample is not supported for multicore programming."*
- `resources\hdlcoder\en\matlabhdlcoder.xml` riga 32 — non supportato per design MATLAB nel workflow IP Core.
- `resources\hdlcoder\en\fil.xml` riga 11 — FPGA-in-the-loop non supportato con F2S.
- Richiede `AggressiveDataflowConversion = on` (`resources\hdlcoder_wfa\en\gui.xml` righe 555-556).

**Raccomandazione:** per un modello SoC Blockset il **Variant Subsystem** è il pattern sicuro ed è quello effettivamente shipped negli esempi. F2S è attraente ma collide con la gerarchia model-reference tipica di SoC Blockset.

## 5.6 Blocchi SoC Blockset e generazione HDL

`[DOC]` Supportati per HDL (Extended Capabilities → "Generate VHDL, Verilog and SystemVerilog code … using HDL Coder"):

| Blocco | Libreria installata | Doc |
|---|---|---|
| **SoC Bus Creator** | `toolbox\soc\fpga\simulation\hwlogicconnlib.slx` | [socbuscreator](https://www.mathworks.com/help/soc/ref/socbuscreator.html) |
| **SoC Bus Selector** | `hwlogicconnlib.slx` | [socbusselector](https://www.mathworks.com/help/soc/ref/socbusselector.html) |
| **Stream FIFO** | `hwlogicconnlib.slx` | [streamfifo](https://www.mathworks.com/help/soc/ref/streamfifo.html) |
| **Stream Connector** | `hwlogicconnlib.slx` | [streamconnector](https://www.mathworks.com/help/soc/ref/streamconnector.html) |
| **IP Core Register Read / Write** | `soclib.slx` | [ipcoreregisterread](https://www.mathworks.com/help/soc/ref/ipcoreregisterread.html) |
| Video Stream Connector / Video Stream FIFO | `hwlogicconnlib.slx` | — |

`SoC Bus Creator` costruisce i bus `StreamM2SBusObj` / `StreamS2MBusObj`. Parametri (prompt GUI): **Control protocol** = `Data stream` | `Pixel stream` | `Random access read` | `Random access write`; **Control type** = `Valid` | `Ready` | `Ready with frame sync`. `SoC Bus Selector` fa l'inverso.
> `[INCERTO]` I **nomi programmatici** di questi due parametri non sono stati estratti dalla maschera: leggerli con `get_param(blk,'DialogParameters')` prima di scriptarli.

NON supportati per HDL — solo software / simulazione architetturale:

| Blocco | Motivo |
|---|---|
| **Stream Read / Stream Write** | lato processore. [streamread](https://www.mathworks.com/help/soc/ref/streamread.html): Extended Capabilities elenca **solo C/C++ Code Generation** |
| **Memory Channel**, Memory Controller, Memory Traffic Generator | modelli architetturali di memoria/DDR (`socmemlib2.slx`) |
| **Task Manager**, **Register Channel** | scheduling / modellazione, lato top model |
| LED / Push Button / DIP Switch / IO Pin (`hwlogiciolib.slx`) | mappati come `External Port` del RD, non generati come logica |

### Regola strutturale osservata negli esempi ufficiali

`[ART]` **In `soc_swhw_stream_fpga` e `soc_hwsw_stream_fpga` i blocchi `SoC Bus Creator` / `SoC Bus Selector` / `Data Stream Wire Channel` stanno nel ROOT del modello FPGA, NON dentro la DUT.** La DUT (`sineWaveFilter`, `FPGA Algorithm Wrapper`) ha porte piatte scalari già scomposte in `tdata`/`tvalid`/`tready`. I bus SoC servono a connettersi ai canali del top model **in simulazione**; l'HDL viene generato dal subsystem interno.

> Nota su `AXI4-Stream to Software`: la sua pagina doc ([axi4streamtosoftware](https://www.mathworks.com/help/soc/ref/axi4streamtosoftware.html)) dichiara HDL Code Generation fra le Extended Capabilities (parametri **Data width (bits)** default 64, **Number of buffers** 3–64, **Burst length**, **FIFO depth**), ma negli esempi installati vive nel **top model**, non nel modello FPGA né dentro la DUT. Trattalo come blocco di canale, non come logica da mettere nella DUT.

**Fonti area 5**: [Model Design for AXI4-Stream Interface Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-axi4-stream-interface-generation.html) · [Model Design for Frame-Based IP Core Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-frame-based-IP-core-generation.html) · [hdlcoder.ReferenceDesign.addAXI4StreamInterface](https://www.mathworks.com/help/hdlcoder/ref/hdlcoder.referencedesign.addaxi4streaminterface.html) · [addAXI4StreamInterface (oggetto fpga)](https://www.mathworks.com/help/hdlcoder/ref/addaxi4streaminterface.html) · [Scalarization of Vector Ports](https://www.mathworks.com/help/hdlcoder/ug/scalarization-of-vector-ports.html) · [ScalarizePorts](https://www.mathworks.com/help/hdlcoder/ref/scalarizeports.html) · [Model Design for AXI4 Register Interface Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-axi4-slave-interface-generation.html) · [Use IP Core Generation Workflow with SoC Models](https://www.mathworks.com/help/soc/ug/use-ipcore-workflow-to-target-soc-example.html) · [Generate IP Core and Bitstream](https://www.mathworks.com/help/hdlcoder/generate-ip-core-and-bitstream.html) · [MATLAB Answers: vector port to AXI4-Stream / 32-bit width](https://www.mathworks.com/matlabcentral/answers/439297-when-mapping-input-output-data-vector-port-to-axi4-stream-is-there-any-way-to-enter-32-bit-width-da)

---

<a name="6-dove-la-documentazione-e-gli-artefatti-divergono"></a>
# 6. Dove la documentazione e gli artefatti divergono

Regola generale adottata in questo documento: **per il comportamento del prodotto prevale l'artefatto installato** (maschera, catalogo messaggi, script shipped), perché è ciò che viene eseguito. **Per l'intento di progetto prevale la doc.** Quando la divergenza è solo apparente (caso 1), la doc è corretta e il metodo di lettura è sbagliato.

| # | Punto | Doc online | Artefatto R2026a | Chi prevale |
|---|---|---|---|---|
| 1 | **Config del modello FPGA** | descrive board/PU/solver del modello FPGA | il `.slx` su disco è **board-agnostico**; i valori si materializzano al load del top | **La doc è CORRETTA.** Divergono su *quando* la configurazione esiste, non sul contenuto. Vedi 1.2 |
| 2 | Quale proprietà persistita classifica un modello referenziato | **non lo dice** | `ProdHWDeviceType='ASIC/FPGA->ASIC/FPGA'` per FPGA; board+FeatureSet persistiti per il processore | Artefatto/esperimento (§1.4). Lacuna documentale |
| 3 | `HardwareBoardFeatureSet` sul modello FPGA | presentato come requisito da impostare | template standalone riporta `EmbeddedCoderHSP`, esempio shipped `SoCBlockset`; **entrambi funzionano**, il valore è sovrascritto al load | Artefatto: non è affidabile né necessario sul modello FPGA |
| 4 | `ESB.ProcessingUnit` come parametro | usato nei testi come proprietà del modello | `get_param` **non lo espone**; serve `codertarget.data.get/setParameterValue` | Artefatto |
| 5 | Register Channel — tipi dati | riassunti generati citano `int64`/`uint64` | popup della maschera **non li contiene** | Artefatto |
| 6 | Register Channel — nome default registro | `reg_1`, `reg_2` | `reg1` | Artefatto |
| 7 | Register Channel — colonne `RegisterTable` | 5 | 5 nella libreria, ma **modelli legacy ne salvano 4** (+ `RegTableInitialValues` separato) | Entrambe vere: dipende dall'età del modello. Non assumere |
| 8 | Register Channel — sample time del Register Read | doc mostra `0.1` | valore promosso in libreria: `-1` (l'esempio usa 0.1 sugli Inport) | Artefatto |
| 9 | "Register write sample time" | documentato | presente ma **`Visible="off"`** in `socmemlib`; **assente** in `socmemlib2` | Artefatto |
| 10 | Register Channel — collocazione (top model?) | **nessuna restrizione documentata**, nessun messaggio d'errore in catalogo | entrambi gli esempi lo mettono nella radice del top | "Solo top model" è **inferenza**, non vincolo. Non presentarlo come regola |
| 11 | Software to AXI4-Stream — **Memory simulation default** | refpage dichiara `Burst accurate (default)` | **entrambe** le librerie R2026a spediscono `Protocol accurate` (riga 1649 di `system_root.xml`) | Artefatto |
| 12 | Software to AXI4-Stream — tipo software fixed-point | refpage mostra `fixdt(1,16,0)` (**signed**) | type spec ammette solo `UDTUnsignedSign` → usare `fixdt(0,16,0)` | Artefatto |
| 13 | Software to AXI4-Stream — vincoli numerici | refpage dice genericamente "scalar" | `msgs.xml` impone FIFO depth {2,4,8,16,32}, data width {32…1024}, almost-full <= depth, multipli burst/buffer | Artefatto (§3.3) |
| 14 | Formula FIFO depth | doc: `FIFODepth = FrameSize/FIFOBurstSize` | script shipped: `2^nextpow2(FrameSize/BurstLength)` | Artefatto (§3.6) |
| 15 | `<Description>` della maschera Software to AXI4-Stream | — | cita porte **inesistenti** `wrData`/`wrEvent`/`wrDone`; il testo corretto è in `ui.xml` | Bug del prodotto: ignorare la Description inline |
| 16 | Task Manager — ordine delle porte di ingresso | tabella doc elenca `Task1Event` prima di `Task1Dur` | ordine reale: **`Dur` prima di `Event`** nello stesso task | Esperimento (§4.2) |
| 17 | Task Manager — validazione di `AllTaskData` | — | `set_param` **accetta valori non validi in silenzio** | Artefatto/esperimento |
| 18 | Larghezza AXI4-Stream "<= 32 bit" | credenza diffusa | RD unificato R2026a: parametro dropdown {32, 64, 128}, default 32; RD legacy fisso 32/32 | Artefatto (§5.2) |
| 19 | `soc_hwsw_stream_top` "usa Software to AXI4-Stream" | — | l'esempio SW→HW che usa quel blocco è `soc_swhw_stream_*`; il variant frame/sample vive in `soc_hwsw_stream_*` | Artefatto: non confondere i due esempi |

---

<a name="7-trappole"></a>
# 7. Trappole

Messaggi riportati **verbatim** dai cataloghi installati, così da essere ricercabili (grep su `resources\**\*.xml`, o incollabili in un motore di ricerca). I placeholder `{0}`, `{1}` sono quelli del catalogo.

## 7.1 Struttura del modello

| Sintomo | Messaggio esatto / chiave | Causa e rimedio |
|---|---|---|
| Ispezioni il modello FPGA e "la configurazione è sbagliata" | `The model is not set for Coder Target.` (leggendo `ESB.ProcessingUnit` a modello standalone) | **Il top non è caricato.** Fai `load_system(top)` prima. Vedi 1.2 |
| `get_param` su ProcessingUnit fallisce sempre | `block_diagram does not have a parameter named 'ESB.ProcessingUnit'` | Non è un parametro di block-diagram. Usa `codertarget.data.getParameterValue(getActiveConfigSet(mdl),'ESB.ProcessingUnit')` |
| Il modello processore viene ignorato, **senza errori** | — (nessun messaggio: **fallimento silenzioso**) | `HardwareBoard`/`HardwareBoardFeatureSet` non persistiti nel proc model. Vedi 1.4 |
| Simulazione rifiutata | `UnsupportedSolver`: `Solver type ''{1}'' in ''{0}'' model is not supported for SoC Blockset simulation.` | Top model non Variable-step → `set_param(top,'SolverType','Variable-step')` |
| Build rifiutata | `Launch_InvalidPUFPGAInProc` / `Launch_InvalidPUProcInFPGA`: *"The top model processing unit must be set to 'None' or to the same value as the FPGA/processor model."* | PU del top diverso da None |
| Build rifiutata | `ProcModelProcessingUnitNone`: *"...make sure each processor model's processing unit is selected other than 'None'."* | |
| Build rifiutata | `NonUniqueProdMdlCPU` | Due modelli processore sulla stessa CPU |
| Build rifiutata | `modelToTaskManagerMismatchError`: *"Reference Model '{0}' with Processing Unit '{1}' is allowed to be driven only by a '{2}' Block."* | Il modello referenziato è pilotato dal blocco sbagliato |
| `socBuilder` rifiuta l'argomento | `Launch_InvalidInput`: *"Invalid input argument for socBuilder. Use top model name as input argument."* | Passa il nome del **top** model |
| Board custom, build fallisce | `InvalidHardwareType`: *"Only 'Zynq' and 'IntelSoC' hardware boards are supported"* | Custom board: simulazione sì, deploy no. Vedi 1.8 |
| Il progetto finisce nella home invece che nella cwd | — | `Simulink.createFromTemplate` **senza `'Folder'`** crea in `~\MATLAB\Projects\<nome>` ignorando la cwd |
| Creazione progetto da template fallisce | `Invalid argument name 'Template'. Name must be 'Name' or 'Folder'.` | `matlab.project.createProject` non accetta `Template`: usa `Simulink.createFromTemplate` |

## 7.2 Register Channel

| Sintomo | Messaggio esatto / chiave | Causa e rimedio |
|---|---|---|
| Porte che **non corrispondono** alla tabella, nessun errore | — (**fallimento silenzioso**) | Hai scritto solo `RegisterTable` via `set_param`: i callback di dialog non girano e i derivati restano disallineati. Vedi 2.8 |
| Dimensioni porta non definite | `NotDefinedPortDims`: *"Connect port ''{0}'' to register channel or define port dimensions."* | Porta non collegata al canale |
| Errore su un blocco messaggio che "non esiste" nel Register Channel | percorso del tipo `<modello>/.../Register Read/Variant/SIM/HWSW Message Receive` | **Il Register Channel non contiene blocchi messaggio.** L'errore è sul Register Read: hai collegato un segnale dove serve un messaggio. Vedi 2.4 |
| Register Read/Write **senza porta** verso il canale | — | Stai usando `prociolib2`: `SimulationInput` default `Zeros`, `SimulationOutput` default `Terminator`. Vedi 2.5 |
| Script che imposta `SampleTime` fallisce | — | Stai lavorando su `socmemlib2`, dove il parametro **non esiste**. Vedi 2.9 |
| Errori di tipo/dimensione a compile | — | *"Set register Data Type and Dimension to match the values in the Register Read or Register Write blocks."* (maschera) |

## 7.3 Software to AXI4-Stream

Tutti da `C:\Program Files\MATLAB\R2026a\resources\soc\en\msgs.xml`:

| Chiave | Messaggio / vincolo |
|---|---|
| `NumBuffersGTE3` / `NumBuffersLSE64` | `3 <= MRNumBuffers <= 64` |
| `ICFIFODepth` | *"FIFO depth valid values are scalar integer: 2, 4, 8, 16, 32"* |
| `ICFIFOAFullDepth` | *"must be less than or equal to FIFO depth... valid values are scalar integer between 1 and FIFO depth"* |
| `ICDataWidth` | *"valid values are scalar integer: 32, 64, 128, 256, 512, 1024 bits"* |
| `ChAndBurstLength` | *"Channel length must be integer multiple of burst length OR burst length must be integer multiple of channel length"* |
| `BurstAndBufferLength` | *"Buffer size must be an integer multiple of burst size"* |
| `MisalignedMRBuffers` | *"The buffer size must be aligned to the interconnect data width"* (warning + auto-correzione) |
| `BurstLengthNotInt` | Burst length non intero |
| `ChTDATAWidthGT128` | Word width del canale > 128 bit |
| `ChBitPackedWidth` | Word width bit-packed > 512 bit |
| `checkFpgaDmaDataWidthCase1` | `ICDataWidth < channel data width` |
| `checkFpgaDmaBurstSize` | Burst size in memory beats > 256 |
| `checkFpgaADIDmaFifoSize` | FIFO depth in bursts fuori da 2–32 |

**Trappola d'ordine**: impostare `FIFODepth` e `FIFOAFullDepth` nell'ordine sbagliato viola **transitoriamente** `AFull <= Depth` e fa fallire il `set_param`. Usa il pattern condizionale di §3.6.

**Trappola di tipo**: seguendo la doc si usa `fixdt(1,16,0)` sul lato software → rifiutato, il writer ammette solo unsigned. Usa `fixdt(0,16,0)`.

## 7.4 Task Manager e ATS

| Chiave | Messaggio / regola |
|---|---|
| `TaskEventNotFound` | *"The event ''{0}'' specified to drive the task ''{1}'' is not generated by any of the blocks in the model."* |
| `TaskMgrDrivesFcnCallSubsystem` | *"Task Manager block is directly connected to a function-call subsystem. This modeling style is not supported. Place your function-call subsystem in a Model block and connect it with Task Manager block."* |
| `TaskMgrConnToSubsys` | *"…Task Manager block output port must be connected to a Model block."* |
| `TaskManagerUnconnectedTask` | *"Connect the output to a periodic event port of a Model block or a function-call subsystem in a Model block."* |
| `TaskMgrDrivesMultipleModels` | un Task Manager non può pilotare più Model block |
| `TaskMgrFcnCallSplit` | vietato Function-Call Split sulle uscite |
| `TaskManagerUnexpectedTwoBlocks` / `TaskMgrTerminated` / `TaskManagerUnexpectedBlock` | una sola destinazione per porta, niente Terminator, niente blocchi intermedi |
| `TaskMgrMisplaced` | *"Task Manager must be either in the top model or in a virtual subsystem in the top model."* |
| `MultipleTaskManagers` | un solo Task Manager per modello (eccetto multi-PU) |
| `NegPriorityOrderNotSupported` | serve "Higher priority value indicates higher task priority" spuntato in **entrambi** i modelli |
| `HWBoardASICFPGA` | Task Manager non ammesso nel modello con device vendor ASIC/FPGA |
| `IOBlkNotInFcnCall` | blocco IO event-driven deve stare in un function-call subsystem collegato a un'uscita di task **Event-driven** |
| `PartitionsMustHaveTasks` | con Schedule Editor: nomi partizione = `taskName` |
| `NumRefMdlInstancesInvalid` | *"Total number of instances of the reference model ''{0}'' allowed per top model must be set to ''One'' since this model has an event-driven task."* |
| `InvalidTaskType`, `InvalidPriority`, `InvalidCoreNum`, `MultipleTasksHandleSameEvent`, `MaxNumTasksExceeded` | validazioni di `AllTaskData` **a compile/update**, non a `set_param` |
| `AsyncTaskSpecBlkNotDrivenByRootInportFcnCall` | *"Asynchronous Task Specification block ''{0}'' must be directly connected to the output port of a root-level Inport block that has been configured to output a function-call signal."* |
| `RootInportFcnCallWithAsyncTaskSpecBlkMultDsts` | *"Inport block ''{0}'' has a connection that is not valid. Since an Asynchronous Task Specification block has been placed at the output port of this Inport block, the output signal of the Inport block cannot be connected to any other block (including another Asynchronous Task Specification block)."* |
| `AsyncTaskSpecBlkUnconnectedOutput` | uscita ATS non può restare scollegata né andare a Terminator |
| `RootInportFcnCallNoAsyncTaskSpecBlk` | Inport root function-call **richiede** un ATS (o modello export-function) |
| `MixedRootFcnCallInportToAsyncTaskSpecConnections1/2` | vietato mischiare Inport function-call con e senza ATS |
| `InvMdlWithAsyncTaskSpecSetToExpFcns` | modello con ATS non può essere export-function |
| `TwoAsyncTaskSpecTIDsAssignedSamePriority` | due ATS con la stessa priorità |

**Trappola silenziosa n.1**: `set_param(tm,'AllTaskData', ...)` **accetta JSON semanticamente errato** (`"taskDurationSource":"bogus"`, `"coreSelection":"Any core"`). L'errore arriva molto dopo, a compile. Verifica sempre rileggendo con `soc.internal.taskmanager.getTasks` e controllando `PortHandles`.

**Trappola silenziosa n.2**: JSON corretto ma **porta evento non collegata fisicamente** → `TaskEventNotFound` solo a update.

## 7.5 Generazione HDL

| Chiave (file) | Messaggio |
|---|---|
| `AXIStreamVectorError` (`interface.xml:24`) | *"Multiple AXI4-Stream interfaces cannot be mapped to vector ports. To use multiple AXI4-Stream interfaces, you must map only scalar ports to these interfaces."* |
| `AXIStreamScalarError` (`interface.xml:19`) | *"When one AXI4-Stream interface is mapped to a vector port, additional AXI4-Stream interfaces cannot be mapped to scalar ports."* |
| `SubPortVectorPortIOMapping` (`interface.xml:78`) | *"When "{0}" interface is assigned to vector port, "{1}" is the only choice for IOInterfaceMapping."* |
| `SubPortVectorPortOnly` (`interface.xml:79`) | *"When assign "{0}" interface to vector port "{1}", only the vector port can be assigned to "{2}" interface."* |
| `TDATAPortWidth` (`interface.xml:80`) | *"AXI4-Stream Protocol requires TDATA port width to be integer number of bytes."* |
| `SubPortNotFitRDOverride` (`interface.xml:73`) | *"Current reference design requires the TDATA port width of the interface "{0}" to be {1} bits. It cannot fit model port "{2}" with bit-width {3}."* ← **l'errore del caso 25 × int32** |
| `InterfaceNotEqualWidth` (`interface.xml:52`) | *"Interface "{0}" requires exact bit-width of {1}, model port "{2}" with bit-width {3} does not fit."* |
| `LimitChannelNumber` (`interface.xml:53`) | *"'MasterChannelNumber' or 'SlaveChannelNumber' can only be 0 or 1."* |
| `ChannelNumMaximum` (`interface.xml:36`) | *"{0} interface currently only support {1} {2} channel."* |
| `VectorModeRateTransitionNoConnect` (`interface.xml:87`) | AXI4-Lite senza Rate Transition in modalità vettoriale |
| (`fpgaio.xml:57`) | *"Invalid packing configuration: A SamplePackingFactor of {0} for {1}-bit {2} elements results in a sample length of {3} bits, exceeding the specified data width of {4} bits."* |
| `IOThresholdExceeded` (`validate.xml:137-146`) | *"IO pin count ''{0}'' exceeds the IO Mapping Threshold ''{1}''. Redesign the model or use HDL optimizations to reduce IOs. … However, the generated code is not synthesizable."* |
| `IOThresholdExceededSMT` | *"…Consider redesigning the model or use "Frame to sample" optimizations to reduce IO."* |
| (`streamingmatrix.xml:10`) | **"Frame-to-sample conversion is not supported through Model Reference hierarchy. Consider using Subsystem References instead."** |
| (`workflow.xml:490`) | *"When frame to sample conversion is enabled, streamed scalar ports are not supported."* |
| (`workflow.xml:174`) | *"Frame to sample is not supported for multicore programming."* |

**Trappola di modalità**: dimenticare di commutare il Variant su **"Sample based processing"** prima dell'IP Core Generation. `[DOC]` istruzione esplicita in [hwsw-stream](https://www.mathworks.com/help/soc/ug/hwsw-stream.html): *"Open the mask of the `FPGA` subsystem and set the model variant to Sample based processing."*

---

<a name="8-cosa-non-e-documentato"></a>
# 8. Cosa NON è documentato e va scoperto sperimentalmente

Elenco esplicito: **niente qui è affermato da MathWorks**. Se ti serve certezza, va verificato sul tuo modello.

**Struttura del modello**
1. Che la configurazione del modello FPGA sia **iniettata al load** dal top e non persistita (§1.2).
2. Che il **discriminante persistito** del modello FPGA sia `ProdHWDeviceType`, e l'asimmetria FPGA (eredita la board) / processore (deve averla persistita) (§1.4).
3. Che `ProdHWDeviceType` **non** si aggiorni impostando `ESB.ProcessingUnit`.
4. Nessuna API pubblica per generare la terna top/fpga/proc configurata: `soc.internal.generateTopModel`/`generateFPGAModel`/`generateProcessorModel` sono `.p` interne.

**Register Channel**
5. **Nessuna API programmatica documentata**: MathWorks documenta solo la GUI (New/Delete/Move Up/Move Down). Le due strategie di §2.8 sono inferenza dalla struttura della maschera.
6. Il comportamento esatto di `RegTableDirty`/`ResetTableCb` sotto `set_param` (non provato end-to-end).
7. **Se il Register Channel possa stare fuori dal top model**: nessuna restrizione documentata, nessun messaggio d'errore in catalogo (§2.9).
8. Il contratto dei parametri derivati nascosti (`RegTableNames` ecc.) è privato: può cambiare fra release.

**Software to AXI4-Stream**
9. **Il motivo** per cui `ChTypeWriterChIf` ammette solo unsigned (§3.4: la ricostruzione è `[INFERENZA]`).
10. **Il motivo** per cui la doc impone "Sample based processing" prima della generazione HDL (§3.5: la ricostruzione è `[INFERENZA]`).
11. I vincoli numerici reali sono in `msgs.xml`, **non** nella refpage: scopribili solo dal catalogo o provocando l'errore.
12. I callback `Software2StreamCb.p` / `Software2StreamCb2.p` sono offuscati: il comportamento esatto di auto-correzione (es. `MisalignedMRBuffers`) è osservabile solo empiricamente.

**Task Manager**
13. **Nessuna API pubblica** per creare/modificare task. `soc.internal.taskmanager.*` è p-coded e senza help; `soc.registerTask` / `soc.registerEvent` / `soc.registerBlock` esistono ma non hanno documentazione pubblica né firma nota.
14. Lo schema completo di `AllTaskData` v2.6 (25 campi) **non è documentato**: è stato ricostruito dai modelli shipped e dalla maschera.
15. Il campo `taskDisablePremption` porta un **typo del prodotto**: va scritto così.
16. `SupportEventPorts`: **non documentato e senza effetto osservabile** in R2026a in un modello senza board SoC. `[INCERTO]` — potrebbe essere consumato dalla DDG p-coded o dalla customizzazione board.
17. L'ordine reale delle porte di ingresso (`Dur` prima di `Event`) contraddice l'ordine di presentazione della doc: verificato sperimentalmente.

**Generazione HDL**
18. `[INCERTO]` La forma programmatica per impostare `IOInterface`/`IOInterfaceMapping` sulle porte della DUT (presumibilmente `hdlset_param`) **non è stata verificata**: provarla e rileggere con `hdlget_param`.
19. `[INCERTO]` I nomi programmatici dei parametri di `SoC Bus Creator` ("Control protocol", "Control type"): leggerli con `get_param(blk,'DialogParameters')`.
20. La combinazione esatta RD-parameter ↔ larghezza TDATA effettiva va confermata sul reference design che userete davvero (il RD unificato è parametrico; il legacy è fisso 32/32).

---

<a name="9-file-locali-di-riferimento"></a>
# 9. File locali di riferimento (percorsi assoluti, R2026a)

**Librerie di blocchi**
- `C:\Program Files\MATLAB\R2026a\toolbox\soc\blocks\soclib.slx` — Library Browser (root)
- `C:\Program Files\MATLAB\R2026a\toolbox\soc\fpga\simulation\socmemlib.slx` — Register Channel (SID 4331…), Software to AXI4-Stream (SID 4324)
- `C:\Program Files\MATLAB\R2026a\toolbox\soc\fpga\simulation\socmemlib2.slx` — libreria v2, non esposta
- `C:\Program Files\MATLAB\R2026a\toolbox\soc\fpga\simulation\socmemlib_internal.slx` — implementazione registri (DataStore*)
- `C:\Program Files\MATLAB\R2026a\toolbox\soc\fpga\simulation\hwlogicconnlib.slx`, `hwlogiciolib.slx` — blocchi FPGA-side
- `C:\Program Files\MATLAB\R2026a\toolbox\shared\soc\processor\blocks\prociolib.slx` — Register Read / Write
- `C:\Program Files\MATLAB\R2026a\toolbox\shared\soc\processor\blocks\proctasklib.slx` — Task Manager (SID 102)

**Cataloghi messaggi (la fonte più preziosa per i vincoli reali)**
- `C:\Program Files\MATLAB\R2026a\resources\soc\en\msgs.xml` — vincoli canali DMA/registri
- `C:\Program Files\MATLAB\R2026a\resources\soc\en\scheduler.xml` — Task Manager, solver
- `C:\Program Files\MATLAB\R2026a\resources\soc\en\utils.xml` — connessioni Task Manager
- `C:\Program Files\MATLAB\R2026a\resources\soc\en\workflow.xml` — SoC Builder, processing unit
- `C:\Program Files\MATLAB\R2026a\resources\soc\en\ui.xml` — prompt e tooltip
- `C:\Program Files\MATLAB\R2026a\resources\Simulink\en\FcnCall.xml`, `SampleTime.xml` — vincoli ATS
- `C:\Program Files\MATLAB\R2026a\resources\hdlcommon\en\interface.xml`, `streamingmatrix.xml`, `workflow.xml`
- `C:\Program Files\MATLAB\R2026a\resources\hdlcoder\en\validate.xml`, `hdlconfig.xml`, `hdlstreaming.xml`, `matlabhdlcoder.xml`, `fil.xml`
- `C:\Program Files\MATLAB\R2026a\resources\fpgaio\en\fpgaio.xml`

**Esempi shipped**
- `...\toolbox\soc\socexamples\soc_swhw_stream_{top,fpga,proc}.slx` — SW→HW, tdata scalare int32, Register Channel 4 registri
- `...\toolbox\soc\socexamples\soc_hwsw_stream_{top,fpga,fpga_frame,proc}.slx` — HW→SW, Variant frame/sample
- `...\toolbox\soc\socexamples\soc_hwsw_interrupt_top.slx` — 2 task event-driven da interrupt FPGA
- `...\toolbox\soc\socexamples\soc_hwsw_stream_init.m` — logica variant frame/sample
- `...\toolbox\soc\socexamples\soc_hwsw_stream_set_parameters.m` — formula FIFO reale, ordine set_param
- `...\toolbox\soc\socexamples\soc_swhw_stream_set_parameters.m` — costruzione JSON `AllTaskData`

**Template, board, reference design**
- `C:\Program Files\MATLAB\R2026a\toolbox\soc\templates\*.sltx` — template di **progetto**
- `...\toolbox\soc\hardwareboards\zynq\registry\targethardware\XilinxZynqZC706evaluationkit.xml` — enum `APU`/`FPGA` + `productionhwdevicetype`
- `...\toolbox\hdlcoder\boards\amd\+common\+internal\addRDParameters.m` — larghezze {32,64,128}, default 32
- `...\toolbox\hdlcoder\boards\amd\+common\+internal\addDMAInterfaces.m` — singola interfaccia AXI4-Stream master+slave
- `...\toolbox\hdlcoder\boards\amd\+ZedBoard\+vivado_unified\plugin_rd.m` — RD "Default system" R2026a
- `...\toolbox\hdlcoder\boards\amd\+ZedBoard\+vivado_stream_2022_1\plugin_rd.m` — RD legacy (32/32)
- `...\toolbox\shared\soc\socmodelcreator\+soc\+internal\RD_Templates\createCustomBoardForSoCModelCreator.txt` — scheletro board custom

**Script di verifica prodotti durante la ricerca** (riutilizzabili; vivono in una scratchpad di sessione, **non** nel repository)
`C:\Users\user poco smart\AppData\Local\Temp\claude\D--Project-SoC\4d8203e1-d2eb-43ed-b52e-53f5ec65bafc\scratchpad\`
- `probe_{a,b,c,d,e,f,g}.{m,log}` — configurazione top/fpga/proc, gate di riconoscimento
- `tm_probe.m` … `tm_probe6.m` con output `tm_probe*_out.txt` — porte del Task Manager

> Se servono in futuro, **vanno copiati nel repository**: la scratchpad è volatile.

---

<a name="10-fonti"></a>
# 10. Fonti (documentazione online MathWorks)

**Struttura del modello / SoC Builder**
- [SoC Blockset Model Structure](https://www.mathworks.com/help/soc/ug/soc-blockset-model-structure.html)
- [Build Error When FPGA or Processor Model Not Detected](https://www.mathworks.com/help/soc/ug/build-error-for-fpga-or-processor-model-not-detected.html)
- [Use SoC Builder to Generate SoC Design](https://www.mathworks.com/help/soc/ug/generate-soc-design.html)
- [Project and Top-Level Model](https://www.mathworks.com/help/soc/ug/project-and-top-level-model.html)
- [Use Template to Create SoC Model](https://www.mathworks.com/help/soc/ug/use-templates-to-create-soc-model.html)
- [Create SoC Model](https://www.mathworks.com/help/soc/ug/create-new-soc-model.html)
- [socCreateModel](https://www.mathworks.com/help/soc/ref/soccreatemodel.html)
- [Processing Unit](https://www.mathworks.com/help/soc/ref/processingunit.html)
- [Custom Hardware Board Configuration](https://www.mathworks.com/help/soc/ug/custom-hardware-board-configuration.html)
- [Using a Custom Board with SoC Blockset](https://www.mathworks.com/help/soc/ug/Using-a-Custom-Board-with-SoC-Blockset.html)
- [Define Custom Pynq-Z2 Board](https://www.mathworks.com/help/soc/ug/define-custom-pynq-z2-board-with-socb.html)
- [Random Access of External Memory](https://www.mathworks.com/help/soc/ug/image-rotation.html)
- [SoC Blockset Supported Hardware](https://www.mathworks.com/help/soc/supported-hardware.html)

**Register Channel**
- [Register Channel](https://www.mathworks.com/help/soc/ref/registerchannel.html)
- [Register Read](https://www.mathworks.com/help/soc/ref/registerread.html)
- [Register Write](https://www.mathworks.com/help/soc/ref/registerwrite.html)
- [Memory and Register Channel Connections](https://www.mathworks.com/help/soc/ug/create-new-soc-model-memory-connections.html)

**Software to AXI4-Stream**
- [Software to AXI4-Stream](https://www.mathworks.com/help/soc/ref/softwaretoaxi4stream.html)
- [AXI4-Stream to Software](https://www.mathworks.com/help/soc/ref/axi4streamtosoftware.html)
- [Streaming Data from Hardware to Software](https://www.mathworks.com/help/soc/ug/hwsw-stream.html)
- [Streaming Data from Software to Hardware](https://www.mathworks.com/help/soc/ug/swhw-stream.html)

**Task Manager**
- [Task Manager](https://www.mathworks.com/help/soc/ref/taskmanager.html)
- [Task Execution](https://www.mathworks.com/help/soc/ug/task-execution.html)
- [Event-Driven Tasks](https://www.mathworks.com/help/soc/ug/event-driven-task.html)
- [Event-Driven Task (esempio)](https://www.mathworks.com/help/soc/ug/event-driven-task-example.html)
- [Asynchronous Task Specification](https://www.mathworks.com/help/rtw/ref/asynchronoustaskspecification.html)
- [Event Source](https://www.mathworks.com/help/soc/ref/eventsource.html)
- [Software and Task Management on Processor](https://www.mathworks.com/help/soc/ug/create-new-soc-model-task-managment.html)
- [Task Management with Schedule Editor](https://www.mathworks.com/help/soc/ug/task-management-with-scheduling-editor.html)
- [Why do we need Asynchronous Task Specification block? (MATLAB Answers)](https://www.mathworks.com/matlabcentral/answers/2176526-why-do-we-need-asynchronous-task-specification-block)

**Generazione HDL**
- [Model Design for AXI4-Stream Interface Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-axi4-stream-interface-generation.html)
- [Model Design for Frame-Based IP Core Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-frame-based-IP-core-generation.html)
- [Model Design for AXI4 Register Interface Generation](https://www.mathworks.com/help/hdlcoder/ug/model-design-for-axi4-slave-interface-generation.html)
- [hdlcoder.ReferenceDesign.addAXI4StreamInterface](https://www.mathworks.com/help/hdlcoder/ref/hdlcoder.referencedesign.addaxi4streaminterface.html)
- [addAXI4StreamInterface (oggetto fpga, host-side)](https://www.mathworks.com/help/hdlcoder/ref/addaxi4streaminterface.html)
- [Scalarization of Vector Ports in Generated VHDL Code](https://www.mathworks.com/help/hdlcoder/ug/scalarization-of-vector-ports.html)
- [ScalarizePorts](https://www.mathworks.com/help/hdlcoder/ref/scalarizeports.html)
- [Use IP Core Generation Workflow with SoC Models](https://www.mathworks.com/help/soc/ug/use-ipcore-workflow-to-target-soc-example.html)
- [Generate IP Core and Bitstream](https://www.mathworks.com/help/hdlcoder/generate-ip-core-and-bitstream.html)
- Blocchi: [SoC Bus Creator](https://www.mathworks.com/help/soc/ref/socbuscreator.html) · [SoC Bus Selector](https://www.mathworks.com/help/soc/ref/socbusselector.html) · [Stream FIFO](https://www.mathworks.com/help/soc/ref/streamfifo.html) · [Stream Connector](https://www.mathworks.com/help/soc/ref/streamconnector.html) · [Stream Read](https://www.mathworks.com/help/soc/ref/streamread.html) · [IP Core Register Read](https://www.mathworks.com/help/soc/ref/ipcoreregisterread.html)
- [MATLAB Answers: mapping vector port to AXI4-Stream / 32-bit width](https://www.mathworks.com/matlabcentral/answers/439297-when-mapping-input-output-data-vector-port-to-axi4-stream-is-there-any-way-to-enter-32-bit-width-da)