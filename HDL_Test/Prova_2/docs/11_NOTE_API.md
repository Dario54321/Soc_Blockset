# Note API — scoperte operative su SoC Blockset (R2026a)

> **Cos'è questo documento.** Il diario delle cose che abbiamo scoperto **facendo**,
> quasi sempre a colpi di errore, costruendo i tre modelli per script. Ogni voce
> riporta il messaggio d'errore esatto (così è ricercabile), la causa e la
> soluzione verificata.
>
> **Documento gemello**: [`12_RICERCA_TOOLCHAIN.md`](12_RICERCA_TOOLCHAIN.md) — ricerca
> sistematica sulla documentazione MathWorks e sugli artefatti installati, con
> marcatori di affidabilità `[DOC]` / `[ART]` / `[EXP]`. **Per una domanda nuova si
> guarda prima lì.** Questo file resta il registro di ciò che è costato tempo qui.
>
> Ambiente: MATLAB R2026a, SoC Blockset + Embedded Coder + support package AMD.

---

## Regola zero — come leggere la configurazione di un modello

**Caricare il top model altera in memoria i modelli referenziati.**
`soc.internal.postModelLoadCallback` → `codertarget.<board>.internal.forwardingHook`
propaga la board del top ai referenziati. Stesso file, due letture diverse:

| `soc_swhw_stream_fpga` | dopo aver caricato il top | in sessione pulita, dal file |
|---|---|---|
| `HardwareBoard` | `Xilinx Zynq ZC706 evaluation kit` | **`None`** |
| `ESB.ProcessingUnit` | `FPGA` | **errore**: *"The model is not set for Coder Target"* |

→ **Ogni lettura di configurazione va fatta in una sessione MATLAB che carica quel
modello e basta**, oppure leggendo `simulink/configSet0.xml` dentro l'`.slx`
(un `.slx` è un archivio ZIP). Le due letture si confrontano al minimo dubbio.

Su questo abbiamo perso tempo due volte: la prima tabella `ProcessingUnit` che
avevamo scritto era interamente basata su letture contaminate.

---

## 1. La firma dei tre modelli

Ciò che conta è **quale proprietà è persistita nel file**:

| | top | fpga | proc |
|---|---|---|---|
| `SolverType` | **Variable-step** | Fixed-step | Fixed-step |
| `FixedStep` | — | **`auto`** (vedi §6) | `auto` |
| `HardwareBoard` | board reale | **`None`** | **board reale** |
| `HardwareBoardFeatureSet` | `SoCBlockset` | `SoCBlockset` | `SoCBlockset` |
| `ProdHWDeviceType` | ARM Cortex-A (32-bit) | **`ASIC/FPGA->ASIC/FPGA`** | ARM Cortex-A (32-bit) |
| `ProdEqTarget` | `on` | **`off`** | `on` |
| `ESB.ProcessingUnit` | `None` | non impostabile | **`APU`** ← vedi §2 |

**Il discriminante di un modello FPGA è `ProdHWDeviceType`, non `ProcessingUnit`.**
Un FPGA model non ha una board: la eredita dal top al caricamento.

### Quella combinazione non si costruisce per gradi

`HardwareBoard='None'` **insieme a** `HardwareBoardFeatureSet='SoCBlockset'` non è
raggiungibile con l'API pubblica. Sei sequenze provate:

| sequenza | esito |
|---|---|
| board → FS → `ProdHW=ASIC` | `configset:diagnostics:CannotChangeProp` — con una board scelta è read-only |
| board=None → FS=SoC | `codertarget:build:HardwareBoardFeatureSetSOCInvalid` — serve una board supportata |
| board → FS → board=None → ProdHW | ProdHW ok ma **FS torna a `EmbeddedCoderHSP`** |
| board → FS → `ESB.ProcessingUnit='FPGA'` | FS ok ma **ProdHW resta ARM** |

→ **Soluzione adottata: trapiantare il config set dell'esempio shipped.**

```matlab
src = fullfile(matlabroot,'toolbox','soc','socexamples','soc_swhw_stream_fpga.slx');
load_system(src);
cs = getActiveConfigSet('soc_swhw_stream_fpga').copy();
cs.Name = 'SocFpgaConfig';
attachConfigSet(mdl, cs, true);
setActiveConfigSet(mdl, cs.Name);
```

Provenienza dichiarata, riproducibile, allineata all'artefatto che MathWorks valida.
Verifica: la configurazione salvata coincide con quella dell'esempio su tutti i campi.

`ESB.ProcessingUnit` non è un parametro del block diagram:
`get_param(mdl,'ProcessingUnit')` fallisce con *"block_diagram does not have a
parameter named 'ProcessingUnit'"*. Si usa:

```matlab
codertarget.data.setParameterValue(mdl, 'ESB.ProcessingUnit', 'APU');   % 'FPGA' | 'None'
```

---

## 2. `soc:scheduler:SimInProgress` — il modello processore va marcato APU

> *"You cannot simulate two models in the same folder at the same time."*

Compare **simulando il top model**, dopo ~2 minuti di compilazione. Fuorviante: non
c'entra la cartella (gli esempi shipped hanno i tre modelli nella stessa) e non
c'entrano lock file (cercati, non ce ne sono).

**Causa**: il modello processore non era marcato come processore. Con
`ESB.ProcessingUnit` assente, lo scheduler di SoC Blockset lo tratta come un
**secondo modello SoC di primo livello** invece che come modello referenziato.

**Soluzione**, nel `build_soc_proc`:

```matlab
codertarget.data.setParameterValue(procMdl, 'ESB.ProcessingUnit', 'APU');
```

E per simmetria, sul top: `'None'`.

> Nota sulla divergenza doc/artefatto: il **file** dell'esempio shipped memorizza
> `None` sul proc model, ma quando viene caricato **sotto il suo top** la hook lo
> porta a `APU`. La doc MathWorks prescrive `APU` ed è quella che descrive lo stato
> effettivo. Noi lo scriviamo esplicitamente nel file: funziona ed è meno fragile.

---

## 3. Register Channel — il lato software scrive tramite un blocco accessore

> *"Invalid connection between message and signal ports. 'Output Port 2' of
> 'soc_top/Processor/Processor Algorithm' is not compatible with 'Input Port 1' of
> 'soc_top/Register Channel/Register1/Variant/SW To HW/HWSW Message Receive/Message Receive'."*

Il lato software del Register Channel espone una **porta messaggio**. Collegarci un
segnale booleano non funziona.

**Il pattern corretto** (trovato dentro `soc_swhw_stream_proc/Writer/Priming/sendCmd`):

```
valore ──> prociolib/Register Write ──> Outport del proc model ──> Register Channel
```

`Register Write` è il blocco accessore lato processore: è **lui** a produrre il
messaggio. Configurazione:

```matlab
add_block('prociolib/Register Write', [wr '/Register Write']);
set_param([wr '/Register Write'], ...
    'RegisterName',  'streamEnable', ...
    'DeviceName',    '/dev/mwipcore', ...
    'OffsetAddress', 'hex2dec(''0100'')', ...
    'OutputSink',    'To output port');
```

Simmetricamente, in lettura si usa `prociolib/Register Read`.

> `Prova_1` aveva questi blocchi ed era giusto; li avevamo tolti ricostruendo.

### La tabella dei registri ha CINQUE colonne in R2026a

> *"The value of parameter 'RegisterTable' is inconsistent with the column data in
> block '…'. The dimension of the value must match with the column data for the
> Custom Table."*

Default: `{'reg1','Read','uint32','1','n/a'}` → **nome, R/W, tipo, dimensione,
valore di default**. In R2023b (vedi `Prova_1_ref.slx`) erano **quattro**: chi porta
avanti un modello vecchio deve aggiungere la quinta colonna.

E i parametri di colonna **non si aggiornano da soli** quando si scrive la tabella:
restano al default `'reg1'`/`'Read'` e la configurazione diventa incoerente **in
silenzio**. Vanno impostati tutti insieme:

```matlab
set_param(rc, ...
    'RegisterTable',       '{''streamEnable'',''Write'',''boolean'',''1'',''n/a''}', ...
    'RegTableNames',       '{''streamEnable''}', ...
    'RegTableRW',          '{''Write''}', ...
    'RegTableDataTypes',   '{''boolean''}', ...
    'RegTableVectorSizes', '{''1''}', ...
    'NumRegisters',        '1', ...
    'RegTableDirty',       '1', ...
    'SampleTime',          '-1');
```

---

## 4. Software to AXI4-Stream — tipi e vincoli

> *"'fixdt(1,32,16)' resolves to a fixed-point data type for parameter
> 'ChTypeWriterChIf' … but the sign mode of the resolved data type is not supported."*

Il canale trasporta **bit grezzi** e accetta solo tipi interi builtin. Inoltre:

| parametro | vincolo verificato |
|---|---|
| `ChTypeWriterChIf` | **solo unsigned** (`int32` → *"Invalid data type specification"*) |
| `ChTypeReaderChIf` | anche signed |

Stessa asimmetria dell'esempio shipped (writer `uint32`, reader `int32`).
La larghezza è la stessa, quindi l'interpretazione in virgola fissa si fa **agli
estremi** con conversioni *Stored Integer*, che preservano il pattern di bit:

```matlab
% lato ARM, prima di Stream Write
set_param(dtc,'OutDataTypeStr','uint32','ConvertRealWorld','Stored Integer (SI)');
% lato PL, subito dopo tdata
set_param(dtc2,'OutDataTypeStr','fixdt(1,32,16)','ConvertRealWorld','Stored Integer (SI)');
```

È anche la semantica hardware corretta, e rende superfluo il vecchio
`typecast(...,'uint64')` di `Prova_1`.

### I parametri vanno impostati tutti insieme

> *"Error in '…': Failed to evaluate mask initialization commands."*

Impostando `BurstLengthReaderChIf`, `ChDimensionsWriterChIf` o
`ChDimensionsReaderChIf` **uno alla volta** si passa da combinazioni transitorie
incoerenti e la maschera fallisce. Gli stessi valori in **un'unica chiamata**
`set_param` passano senza problemi. Verificato su quattro combinazioni.

---

## 5. Asynchronous Task Specification — in cascata, non in parallelo

Blocco **built-in**, non di libreria: `add_block('built-in/AsynchronousTaskSpecification', …)`.

Due vincoli complementari che insieme lasciano una sola topologia:

1. *"Asynchronous Task Specification block must be directly connected to the output
   port of a root-level Inport block that has been configured to output a
   function-call signal."*
2. *"Since an Asynchronous Task Specification block has been placed at the output
   port of this Inport block, the output signal … cannot be connected to any other
   block."*

→ **`write_fcn → ATS → Writer/Trigger`**, in cascata.

L'inport function-call: `set_param([mdl '/write_fcn'],'OutputFunctionCall','on')`.

> Perché non si vedeva dal dump dell'esempio: un `find_system` che stampa
> `SrcBlockHandle`/`DstBlockHandle` delle **linee** perde le diramazioni — il
> segmento padre ha `DstBlockHandle = -1`. Per ricostruire una topologia usare
> `get_param(blk,'PortConnectivity')`, che le riporta tutte.

---

## 6. Il rate del modello FPGA non è il clock della PL

Avevamo fissato `FixedStep = Ts_FPGA = 10 ns` "per non lasciare un rate accidentale".
**Sbagliato**, e costoso: con `StopTime = 2 s` servono 2·10⁸ passi — la simulazione
non termina in 10 minuti (misurato).

In SoC Blockset il rate di **simulazione** del modello FPGA è il rate del flusso dati
che gli arriva dal canale. Il clock a 100 MHz è un **parametro del modello di canale**
(`ICClockFrequencyReader`, usato per i tempi di burst), non il passo del solutore.

- modello FPGA: `FixedStep = 'auto'`
- il rate lo fissa `ChFrameSampleTimeReaderChIf` sul blocco `Software to AXI4-Stream`

Con `frameSampleTime = 0.1 s` e `StopTime = 0.5 s` la simulazione completa gira in
~2 minuti e produce 6 campioni.

Il gate di regressione è stato riscritto di conseguenza: non verifica più *quale*
rate, verifica che sia **uno solo** (requisito vero della generazione HDL).

---

## 7. Handshake: `ready` non deve dipendere da `valid` — stallo garantito

Sintomo: la simulazione gira, ma **tutte le uscite della PL restano a zero**.

Diagnosi (instrumentando le linee di primo livello):

```
RegisterChannel/1          max = 1     -> streamEnable arriva alla PL      OK
SoftwareToAXI4_Stream/2    .valid = 0  -> tvalid non si alza mai
FPGA/1                     .ready = 0  -> tready non si alza mai
SoftwareToAXI4_Stream/1    max = 0     -> nessun dato
```

Il segnaposto era `ready = streamEnable && valid`. Il canale non alza `valid` finché
non vede `ready`; `ready` non sale perché aspetta `valid`. **Stallo.**

È la regola AXI4-Stream: **VALID non aspetta READY, e READY non è funzione di VALID.**
Correzione: `ready = streamEnable`. Dopo la modifica la catena consegna e le uscite
coincidono con il riferimento.

### Come instrumentare i segnali (R2026a)

`DataLogging` **non è un parametro della linea** (*"line does not have a parameter
named 'DataLogging'"*), è della **porta**:

```matlab
ph = get_param(line,'SrcPortHandle');
set_param(ph,'DataLogging','on');
set_param(ph,'DataLoggingNameMode','Custom');
set_param(ph,'DataLoggingName','mio_segnale');
```

---

## 8. `sim` dentro una funzione non scrive nel base workspace

`sim(mdl)` in modalità legacy scrive le variabili *To Workspace* nel workspace del
**chiamante**. Da script lanciato nel base sembra funzionare; **da dentro una
funzione** le variabili finiscono nel workspace della funzione e `evalin('base',…)`
fallisce con *"Unrecognized function or variable"*.

Forma robusta, indipendente dal contesto di chiamata:

```matlab
in  = Simulink.SimulationInput(mdl);
in  = in.setModelParameter('ReturnWorkspaceOutputs','on');
out = sim(in);
ts  = out.('fpga_matA_out');
```

---

## 9. Il coefficiente di un blocco Gain è quantizzato

Confrontando la sonda della PL con l'atteso, restava 1 LSB di errore su 2 elementi
su 9. **L'errore era nel riferimento, non nel modello.**

Con uscita a 16 bit, Simulink quantizza anche il **coefficiente**: per 3.7 servono
2 bit interi + segno → `sfix16_En13`, e il valore effettivo è
`round(3.7·2¹³)/2¹³ = 3.699951171875`, non 3.7.

Il riferimento deve riprodurre l'aritmetica del modello, non la matematica reale:

```matlab
kFl = wordLength - 1 - ceil(log2(abs(gain)));
K   = round(gain * 2^kFl) / 2^kFl;
a   = min(max(floor(x / q) * q, lo), hi);      % DTC: Floor + Saturate
y   = min(max(floor(a * K / q) * q, lo), hi);  % Gain: Floor + Saturate
```

Con questa correzione l'errore va a **zero esatto** su tutte le uscite.

---

## 10. `Stream Write` ha due uscite

> *"'Output Port 2 (Left:2)' of block 'soc_proc/Writer/Stream Write' is not connected."*

Il blocco `prociolib/Stream Write` espone **due** porte di uscita; l'esempio shipped
collega la prima al dato e **termina esplicitamente la seconda**. Lasciarla
penzolante non rompe niente, ma produce l'avviso a ogni simulazione — e un avviso
che si impara a ignorare è un avviso che un giorno nasconderà qualcosa d'altro.

Regola pratica: dopo il primo `Update Diagram` di un modello nuovo, leggere **tutti**
gli avvisi e chiuderli, anche quelli innocui. Costa minuti una volta sola.

---

## 11. Altre note minori

- `sfroot.find(...)` senza parentesi è errore di sintassi in R2026a: serve `sfroot()`.
- Il Model block si aggiunge da `simulink/Ports & Subsystems/Model` e poi
  `set_param(blk,'ModelNameDialog','nome.slx')`. Passare il percorso del `.slx` come
  sorgente di `add_block` fallisce con `Simulink:Commands:InvBlockSpecifier`.
- `Simulink.exportToVersion` emette **sempre** *"To find blocks that were removed
  during the export operation…"*, anche quando non rimuove nulla. Si verifica
  censendo i blocchi e lo stato dei link di libreria, non fidandosi del messaggio.
- Il codice di una MATLAB Function si scrive con
  `ch = sfroot().find('-isa','Stateflow.EMChart','Path',[mdl '/nome']); ch.Script = codice;`
