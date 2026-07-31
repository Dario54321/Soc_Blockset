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

## 11. MATLAB Function con `persistent`: tre trappole in fila

Costruendo il wrapper (`build_wrapper_fpga.m`) ne abbiamo incontrate tre di
seguito. Sono tutte e tre invisibili leggendo il codice: si manifestano solo
compilando.

### 11.1 Anello algebrico con `persistent`: la soluzione è documentata

> *"'…/wrapper_fsm' or the model referenced by it contains a block that updates
> persistent or state variables while computing outputs and is not supported in an
> algebraic loop."*

Di default una MATLAB Function è **direct feedthrough su tutti gli ingressi**:
scrivere il codice "alla Moore" non basta, perché Simulink non lo deduce dal
codice. Ma la soluzione **non** è aggiungere un ritardo a mano — è disattivare il
direct feedthrough sul blocco che deve rompere l'anello:

```matlab
cfg = get_param(blk, 'MATLABFunctionConfiguration');
cfg.AllowDirectFeedthrough = 0;
```

> *"When Allow direct feedthrough is cleared, the output of the block depends on
> the internal state and properties and does not depend on the input."*
> — [Using Persistent Variables and fi Objects Inside MATLAB Function Blocks for HDL Code Generation](https://www.mathworks.com/help/hdlcoder/ug/using-persistent-variables-inside-matlab-function-blocks-for-hdl-code-generation.html)

**In cambio il codice deve rispettare una regola**: *"You must read the persistent
variable's value BEFORE updating it."* Le uscite si calcolano in cima, dallo stato;
gli aggiornamenti stanno tutti dopo. Violarla non dà errore: dà risultati sbagliati.

**Due vincoli scoperti applicandola:**

1. **Nessuna** uscita può dipendere da un ingresso — non basta che *quella* uscita
   non ci dipenda. Con un `u_raw = x(1:nu)` accanto a `done_o`:
   > *"Stateflow:cdr:CannotDisallowDirectFeedthrough — Property 'Allow direct
   > feedthrough' is not supported for MATLAB Function '…', but Simulink is not
   > able to enforce this constraint."*

   Nel wrapper il percorso dati è stato tolto dal segnaposto: un blocco `Selector`
   prende `x(1:nu)` e lo porta al latch. Il segnaposto è così solo *un ritardo con
   handshake*, che è anche ciò che deve essere.

2. Va applicato **solo** al blocco che deve rompere l'anello. `wrapper_fsm` resta
   direct feedthrough, perché `start_o` dipende davvero da `start_cmd` nello stesso
   ciclo.

> **Errore commesso e corretto.** In una prima versione avevamo concluso che
> «serve un ritardo esplicito» e messo un `Unit Delay`. Funzionava, ma era un
> rimedio a un problema con una soluzione di prima classe, e generava HDL
> peggiore. Trovato leggendo la documentazione invece di continuare per
> tentativi.

Dalla stessa pagina, utile per la generazione HDL: usare `hdlfimath` invece del
`fimath` di default, perché *"avoids the additional resource usage and saves area
on the target FPGA device"* (arrotondamento Floor e overflow Wrap invece di
Saturate).

### 11.2 `zeros(N,1,'like',x(1))` non si compila

> *"Errors occurred during parsing of '…/compute_stub'."* — messaggio generico,
> nessun dettaglio.

Isolato costruendo un modello minimo con il solo blocco: la causa è
**l'espressione indicizzata dentro `'like'`**.

| forma | esito |
|---|---|
| `zeros(N,1,'like',x(1))` | ❌ errore di parsing |
| `zeros(N,1,'like',x)` | ✅ parsa |
| `zeros(N,1)` | ✅ parsa |

In MATLAB puro `zeros(N,1,'like',x(1))` è valido e `checkcode` non segnala nulla:
è una restrizione del contesto MATLAB Function.

**Come l'abbiamo aggirata, ed è la soluzione migliore comunque**: niente
`persistent` in virgola fissa. Il segnaposto produce `u_raw = x(1:nu)` — tipo e
dimensione derivati dall'ingresso — e **il latch appartiene al wrapper**
(`Switch` + `Unit Delay`), che è anche ciò che dice la specifica. Il latch resta
visibile nel modello invece che sepolto nel codice.

### 11.3 L'inferenza dei tipi non si chiude attorno a un anello

> *"Output 'done_o' is a signal of data type 'boolean'. However, it is driving a
> signal of data type 'double'."*

Con un anello `fsm → stub → fsm`, l'inferenza dei tipi diventa circolare e
Simulink degrada un segnale a `double`.

**Rimedio**: dichiarare i tipi delle porte invece di lasciarli inferire. Via API,
sui dati della chart:

```matlab
ch  = sfroot().find('-isa','Stateflow.EMChart','Path',[mdl '/wrapper_fsm']);
all = ch.find('-isa','Stateflow.Data');
d   = all(arrayfun(@(z) strcmp(z.Name,'done_i'), all));
d.DataType = 'boolean';
d.Props.Array.Size = '3';     % solo per i vettori
```

È comunque la scelta giusta: sono le porte di un'interfaccia, non un dettaglio
interno.

---

## 12. Verificare il tempo: simulare il modello, non emularlo

Il banco di prova del wrapper estraeva le MATLAB Function dal modello e le faceva
girare in un anello MATLAB. Va bene per la logica, **non per le misure di tempo**.

Simulink separa la fase *uscite* dalla fase *aggiornamento di stato*; una funzione
MATLAB fa entrambe in una chiamata atomica. In un anello a due blocchi l'emulazione
introduce quindi **un ciclo in più**, ovunque si metta la chiamata, e non è
aggirabile riordinando. Misurato: emulazione 502 cicli, modello 501.

Adattare l'atteso a 502 avrebbe reso verde la suite nascondendo il problema, **e
avrebbe fatto passare indisturbata la mutazione che sfasa il contatore di uno**.

**Come si pilota un modello da script**, senza Simulink Test:

```matlab
ds = createInputDataset(mdl);          % dataset GIA' coi tipi giusti delle porte
for k = 1:ds.numElements
    e = ds{k};                          % NB: e' un timeseries, non ha campo .Values
    proto = e.Data(1);                  % il tipo della porta sta in .Data
    ds{k} = timeseries(cast(v,'like',proto), t, 'Name', e.Name);
end
in  = Simulink.SimulationInput(mdl);
in  = in.setExternalInput(ds);
in  = in.setModelParameter('SaveOutput','on','OutputSaveName','yout', ...
                           'SaveFormat','Dataset');
out = sim(in);
```

[createInputDataset](https://www.mathworks.com/help/simulink/slref/createinputdataset.html)
risolve il problema dei tipi: genera il dataset con il tipo compilato di ciascuna
porta, virgola fissa inclusa.

Due inciampi:

- **Gli elementi di `yout` non portano il nome del blocco Outport.**
  `y.get('done')` avvisa *"Did not find any Dataset element using 'done'"* e
  restituisce vuoto. Si accede per **indice**, che corrisponde al numero di porta.
- **Costruire una variante del modello con lo STESSO NOME** in una cartella
  temporanea la rende inutilizzabile:
  > *"The file containing block diagram '…' is shadowed by a file of the same name
  > higher on the MATLAB path."*

  Simulink carica quello sul path, non quello che credi. Il gate passa **per il
  motivo sbagliato, in silenzio**. Rimedio: il builder deriva il nome del modello
  dal nome del file, così la variante muta si chiama diversamente.

---

## 13. Altre note minori

### Due trappole nel `regexp` di MATLAB, entrambe silenziose

Scoperte scrivendo `check_refdesign` e `validate_refdesign`, e ciascuna è
costata un risultato sbagliato prima di essere vista.

**`\b` non è un word boundary.** In MATLAB non aggancia nulla — nemmeno
`regexp('foo bar','\bbar','match')`, che restituisce vuoto. L'inizio-parola è
`\<` (e la fine `\>`). Sintomo: un pattern che funziona ovunque altro qui non
trova mai niente, e se il codice non asserisce il match, passa in silenzio.

**Il punto matcha anche il newline.** `'^X: (.+)'` su un output multiriga si
mangia le righe successive. L'opzione per escluderlo è `'dotexceptnewline'`;
più chiaro scrivere direttamente `([^\r\n]+)`.

Regola pratica che ne segue: **ogni estrazione con `regexp` va seguita da
un'asserzione che ha agganciato qualcosa.** Un `tokens` vuoto restituito in
silenzio trasforma un verificatore in un controllo che passa sempre.

### Vivado in modo batch rieccheggia il proprio sorgente

`vivado -mode batch -source x.tcl` stampa le righe dello script (prefissate da
`# `) mescolate al loro output. Un parser non ancorato legge lo **script** invece
del **risultato**: `puts "MARK: ok"` viene letto come se `MARK: ok` fosse stato
prodotto, anche quando quel ramo non è mai stato eseguito. Ancorare a inizio
riga (`'^MARK: '` con `'lineanchors'`). Costato una validazione dichiarata
riuscita quando era fallita ([`24_REFERENCE_DESIGN` §24.6](24_REFERENCE_DESIGN.md)).



- `sfroot.find(...)` senza parentesi è errore di sintassi in R2026a: serve `sfroot()`.
- Il Model block si aggiunge da `simulink/Ports & Subsystems/Model` e poi
  `set_param(blk,'ModelNameDialog','nome.slx')`. Passare il percorso del `.slx` come
  sorgente di `add_block` fallisce con `Simulink:Commands:InvBlockSpecifier`.
- `Simulink.exportToVersion` emette **sempre** *"To find blocks that were removed
  during the export operation…"*, anche quando non rimuove nulla. Si verifica
  censendo i blocchi e lo stato dei link di libreria, non fidandosi del messaggio.
- Il codice di una MATLAB Function si scrive con
  `ch = sfroot().find('-isa','Stateflow.EMChart','Path',[mdl '/nome']); ch.Script = codice;`
- **`matlab -batch` esce 255 se si tronca la pipeline PowerShell.** Filtrare
  l'output con `| Select-Object -First N` chiude la pipe mentre MATLAB sta ancora
  scrivendo, PowerShell termina il processo e il codice d'uscita diventa 255 —
  che si legge come "la regressione è fallita" mentre invece è passata. Successo
  il 29/07 con `run_regression`: 255 con il filtro, 0 senza. Se serve filtrare,
  usare `Select-String` da solo (non consuma tutto l'input in anticipo ma non
  chiude la pipe) e leggere il verdetto, non il codice d'uscita.

---

## 14. `hdlcoder.Board` non costruisce un `hdlcoder.Board`

```
PYNQZ1.plugin_board ha restituito un hdlturnkey.plugin.BoardIP,
non un hdlcoder.Board.
```

`hB = hdlcoder.Board` è una **facciata**: l'oggetto che restituisce è di classe
`hdlturnkey.plugin.BoardIP`. Quindi:

```matlab
isa(hB, 'hdlcoder.Board')      % <- FALSO, anche su un plugin corretto
```

Verificare la classe è comunque la cosa sbagliata da fare: `hdlturnkey.plugin.BoardIP`
è un nome interno che può cambiare. Ciò che conta è che l'oggetto **esponga e abbia
popolato** le proprietà che descrivono la board:

```matlab
need = {'BoardName','FPGAVendor','FPGAFamily','FPGADevice','FPGAPackage','FPGASpeed'};
for k = 1:numel(need)
    assert(isprop(hB, need{k}) && ~isempty(hB.(need{k})), ...);
end
```

**Le interfacce non si rileggono.** Ciò che si aggiunge con
`addExternalIOInterface` finisce in stato privato: non esiste una proprietà
pubblica `ExternalIOInterfaces`. Chi vuole verificare i pin dichiarati deve
tenerli in una fonte propria — è il motivo per cui esistono
`+PYNQZ1/board_pins.m` e la regola R2 applicata lì
([`23_BOARD_PYNQZ1` §23.4](23_BOARD_PYNQZ1.md)).

**Non c'è API pubblica per elencare le board registrate.** Il registro è p-coded
(`toolbox\hdlcoder\ipcore\+hdlcoder\Workflow.p`); l'unico `.m` leggibile in quel
pacchetto è `Board.m` e `ReferenceDesign.m`. `hdlcoder.WorkflowConfig(...,'TargetWorkflow','IP Core Generation')`
restituisce un `hwcli.config.IPCoreConfig` che **non ha** `TargetPlatform`:

```
Unrecognized property 'TargetPlatform' for class 'hwcli.config.IPCoreConfig'.
```

Da cui una trappola in cui sono caduto: una prova costruita su quella proprietà
*sembrava* discriminare (accettava la nostra board, rifiutava una inesistente) ma
**entrambi i rami fallivano con lo stesso errore**. Una controprova che fallisce
per lo stesso motivo della prova non è una controprova — è un gate che non ha mai
funzionato in nessuna delle due direzioni.

---

## 15. Il comando è riuscito, l'artefatto no — R1 violata per otto commit

Il caso peggiore di questo diario, perché non è un errore del toolchain: è un
errore di metodo, e la regola che l'avrebbe evitato era già scritta.

**Sintomo, scoperto solo perché qualcuno ha aperto il repository su R2023b.**
I modelli versionati in `models/` erano **R2026a**. Chi lavora su R2023b non
poteva aprirli — cioè la regola R1, quella che esiste apposta, era violata nel
repository mentre `export_r2023b` stampava a ogni giro:

```
Tutti i modelli sono compatibili R2023B.
```

**Verifica del fatto**, prima di spiegarlo:

```matlab
Simulink.MDLInfo('models/soc_wrapper_fpga.slx').ReleaseName   % -> R2026a
export_r2023b();
Simulink.MDLInfo('models/soc_wrapper_fpga.slx').ReleaseName   % -> R2023b
```

**Causa.** `export_r2023b` funzionava: convertiva e riscriveva i file. Ma dopo
averlo eseguito, vedendo i `.slx` comparire come modificati in `git status`, li
ho **ripristinati con `git checkout`** per non fare un commit di rumore —
liquidando la differenza binaria come *"solo timestamp interni"*. Non l'avevo
verificato. Era una spiegazione plausibile appiccicata a un dato anomalo, e ha
buttato via esattamente il risultato dell'export.

**Due cose erano sbagliate, non una:**

1. Un `.slx` che cambia dopo un export **non è rumore**: è il prodotto. Un diff
   binario non si spiega, si guarda.
2. `export_r2023b` verificava che il *comando* riuscisse, mai che il *file* fosse
   diventato R2023b. Un gate che non rilegge il prodotto non è un gate — e
   soprattutto non poteva accorgersi che qualcuno, a valle, lo scartasse.

**Correzioni:**

- `export_r2023b` rilegge ogni file con `Simulink.MDLInfo` e fallisce se la
  release non è quella attesa;
- gate **T16** in regressione: tutti i `.slx` in `models/` devono essere R2023b.
  Provato in fallimento ricostruendo un modello (che lo riscrive R2026a): la
  regressione scatta. Così R1 diventa una proprietà del repository, e non di un
  comando che qualcuno deve ricordarsi di lanciare **e di committare**.

> Vale anche come regola generale, ed è la stessa già scritta in `04_CONVENZIONI`
> R7: *verificare l'artefatto, non l'intenzione*. Qui il messaggio "tutti
> compatibili" era vero al momento in cui veniva stampato e falso trenta secondi
> dopo. Nessuno se n'è accorto per otto commit.
