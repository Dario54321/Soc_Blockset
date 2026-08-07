# Storia tecnica: registrazione Pynq-Z1 per SoC Blockset / SoC Builder

Questo file è per chiunque (umano o AI) riprenda questo lavoro senza
contesto pregresso. Racconta cosa è stato fatto, perché, quali bug reali
sono stati trovati e come sono stati risolti — non solo lo stato finale.

**Ambiente in cui è stato fatto**: MATLAB R2023b, Windows, board Pynq-Z1
(`xc7z020clg400-1`), Vivado 2022.1. Se riprendi il lavoro su una versione
diversa di MATLAB, rileggi la sezione "Cose che dipendono dalla versione"
in fondo.

## 1. Obiettivo e perché esisteva un problema

SoC Blockset (a differenza di HDL Coder puro, già usato altrove in questo
repository per la Pynq-Z1 — vedi `HDL_Test/Prova_2/hdlplugins/`) ha una
lista chiusa di board "ufficiali" per il workflow completo SoC Builder
(FPGA+Processore, co-design hardware/software): ZedBoard, ZC702, ZC706,
ZCU102 e poche altre. **La Pynq-Z1 non c'è**, essendo una board di terze
parti (Digilent), non un prodotto Xilinx/AMD ufficiale.

Serviva registrarla come board custom (`soc.sdk.BoardSupport`) perché
comparisse come `HardwareBoard` selezionabile nei tool SoC Blockset e
permettesse di usare il vero workflow SoC Builder — non solo simulazione
o generazione HDL isolata.

## 2. Come è stata creata (script riusabile)

Punto di partenza: il template MathWorks reale
`toolbox\shared\soc\socmodelcreator\+soc\+internal\RD_Templates\
createCustomBoardForSoCModelCreator.txt` (scritto per Zynq UltraScale+
MPSoC, ma la sequenza API è la stessa per Zynq-7000). Non esiste altro
template pubblicato specifico per SoC Builder — cercato esaustivamente
in GitHub, File Exchange, MATLAB Answers, letteratura: nulla trovato per
la Pynq-Z1 specificamente.

Adattato in uno script (`create_PynqZ1_BoardSupport.m`, non incluso in
questo repository, ma la sequenza è riproducibile leggendo il template)
che:
1. Crea `soc.sdk.BoardSupport('Board Support for Pynq-Z1', 'Board
   Support for Xilinx Zynq-7000 SoC', <cartella>)`
2. Crea `soc.sdk.Hardware('PynqZ1Test')`, `DeviceID = 'ARM Cortex-A9'`
   (valore esatto ottenuto dall'errore di MATLAB stesso quando si prova
   un valore sbagliato — l'errore elenca l'enum valido)
3. Popola `ProcessingSystem` con porte/latenze reali (vedi tabella sotto)
4. Aggiunge Clock (125 MHz, pin `H16`) e Reset (workaround su `D19`,
   vedi §5) — **obbligatori**: `save()` rifiuta senza entrambi
   ("the board must have both a Reset and a Clock since it is designated
   for deployment")
5. `setDisplayNameForHardware` + `mapFeaturesAndHardware` (Deployer, PIL,
   OperatingSystem, ExternalMode, Profiler) + `save()`

**Punto importante, non ovvio**: il nome che compare in Simulink
(`set_param(cs,'HardwareBoard','Pynq-Z1')`) è il **display name** scelto
in `setDisplayNameForHardware`, non il nome interno dell'oggetto
`soc.sdk.BoardSupport` (`'Board Support for Pynq-Z1'`) né il nome
dell'oggetto `soc.sdk.Hardware` (`'PynqZ1Test'`). Usare il nome sbagliato
dà un errore silenzioso poco chiaro.

## 3. Bug reali trovati e risolti (in ordine cronologico)

Tutti trovati per differenza diretta con la registrazione di una board
reale funzionante (ZedBoard, built-in in
`toolbox\soc\hardwareboards\zynq\registry\`) — `validate()` da solo **non
li rileva mai**, è un controllo solo strutturale.

### 3.1 — Token duplicato/rotto (`XilinxZynqDeployerPynqZ1.xml`)
Il file generato dal template aveva due righe che definivano lo stesso
token `XILINXZYNQ_ROOT_DIR`, la seconda con
`matlabshared.target..getReferenceTargetRootFolder` — doppio punto,
segmento di pacchetto vuoto, riferimento non risolvibile. La seconda
riga sovrascriveva la prima (corretta). **Fix**: rimossa la riga rotta.

Lo stesso identico bug (stesso doppio punto) è comparso **altre due
volte** in file diversi, generati dallo stesso processo automatico:
- `rtwTargetInfo.m`, riga `ConfigClass = 'matlabshared.target..
  ConnectivityConfig'` — la più grave delle tre, eseguita
  **automaticamente a ogni registrazione della board** (è il file che
  MATLAB scansiona per scoprire i target registrati).
- `+soc\+internal\+customboard\+register\Plugin.m`, una classe plugin
  **orfana e duplicata** (stesso `TgtName` di `boardsupportforpynqz1Plugin.m`,
  che invece era corretta) — rimossa interamente.

### 3.2 — Mancava "Processing Unit" nel pannello Hardware Implementation
Il campo Model Settings → Hardware Implementation → **"Processing Unit"**
(quello che decide se un modello è FPGA/APU/None per SoC Builder) non
compariva affatto nella GUI per questa board — mentre per ZedBoard sì.

**Causa reale**: il dato esiste sempre (`get_param(configSet,
'CoderTargetData').ESB.ProcessingUnit`, scrivibile via `set_param`), ma
la sua **visibilità nella GUI** dipende da due entry XML che il template
generico non include:
- `<boardforwardingfcn>codertarget.zynq.internal.forwardingHook</
  boardforwardingfcn>` in `registry\targethardware\PynqZ1.xml`
- `<parameter ForwardingFcn="codertarget.zynq.internal.
  forwardESBParameters" Name="ESB.ProcessingUnit" Scope="CoderTarget"/>`
  in `registry\forwarding\forwarding.xml` (che aveva già una entry per
  `FPGADesign`, ma con la funzione generica `soc.internal.
  forwardFPGAParameters` invece di quella specifica Zynq
  `codertarget.zynq.internal.forwardFPGAParameters`)

**Fix**: copiate entrambe le entry da ZedBoard, adattando solo il nome
della board. Verificato byte-per-byte identico a ZedBoard su questo
punto dopo il fix.

**Nota per chi debugga un problema simile su un'altra board custom**:
questo fix **non è documentato da nessuna parte** nei materiali
ufficiali MathWorks (template, guide, pagine di help) — trovato solo per
confronto diretto con una board reale funzionante. Se il sintomo è "il
campo Processing Unit non compare", è il primo posto da controllare.

### 3.3 — Cache di MATLAB, non un bug della board
Dopo aver corretto `rtwTargetInfo.m` (§3.1), il fix non aveva effetto
finché non si chiamava `RTW.TargetRegistry.getInstance('reset')` (o si
riavviava MATLAB). La registrazione del target viene letta e messa in
cache una sola volta per sessione — `sl_refresh_customizations` (per le
customization Simulink generiche) **non** invalida questa cache
specifica.

### 3.4 — Mancava `registry\interrupts\PynqZ1FPGAInterrupts.xml`
Presente su **ogni** board SoC-Builder-capable installata (ZedBoard,
ZC706, ZCU102 — tutte con la stessa famiglia PS7), assente sulle board
solo-IP-Core-Generation. Aggiunto con dati reali coerenti con la
`InterruptInterfacePort` già dichiarata:
```xml
<productinfo version="3.0">
  <NumOfInterfaces>1</NumOfInterfaces>
  <TotalNumInterrupts>16</TotalNumInterrupts>
  <InterruptInterface>
    <InterfacePortName>processing_system7_0/IRQ_F2P</InterfacePortName>
    <InterfacePortWidth>16</InterfacePortWidth>
  </InterruptInterface>
</productinfo>
```

### 3.5 — Campo "Device Address" nascosto
In `registry\parameters\PynqZ1.xml` il parametro Device Address aveva
`Visible="0"`, `ValueType=""` — impossibile inserire l'IP reale della
board. Confrontato con la board reale con deploy fisico più simile
disponibile sulla macchina (ZedBoard nel pacchetto "Embedded Coder
Support Package for Xilinx Zynq Platform", non lo stub SoC Blockset
sim-only): quella aveva `Visible="1"`, `ValueType="callback"`. Copiato.

### 3.6 — File TCL della Processing System mai creato
`ProcessingSystem.TCLFile` (impostato nello script di creazione,
§2) punta a `<cartella board>\tcl\PynqZ1_PS.tcl` — file che lo script
**non crea mai da solo** (il campo va compilato a mano). Non emerge da
`validate()`, solo al passo "Build info" del wizard SoC Builder reale
("Could not open file ... No such file or directory").

**Fix**: creato estraendo la sezione "Processing System" da un reference
design HDL Coder già validato per questa board
(`HDL_Test/Prova_2/hdlplugins/+PYNQZ1/+vivado_base_2022_1/
system_top.tcl`), **ma riscritto nel formato che SoC Blockset si
aspetta per questo tipo di file**: solo `create_bd_cell` + `set_property`
della cella `processing_system7` (niente interconnect/clock
wizard/reset gen — quelli SoC Builder li genera da solo dalle proprietà
già dichiarate nello script di creazione board). Formato confermato
confrontando con un file reale equivalente di un'altra board
(`ZCU111PS.tcl`, in `ProgramData\MATLAB\SupportPackages\R2023b\toolbox\
soc\supportpackages\rfsoc\src\tcl\`).

**Attenzione al nome dell'istanza**: nel `system_top.tcl` sorgente la
cella si chiama `sys_cpu` (nome scelto a mano). Nel nuovo `PynqZ1_PS.tcl`
deve chiamarsi **`processing_system7_0`** — deve combaciare esattamente
con il prefisso già usato nelle porte dichiarate nello script di
creazione board (`ClockOutputPort = 'processing_system7_0/FCLK_CLK0'`,
ecc.). Usare un nome diverso rompe silenziosamente i collegamenti che
SoC Builder genera.

Contenuto del file risultante (`custom_board_pynqz1_v2\tcl\
PynqZ1_PS.tcl`, incluso in questo repository):
```tcl
if { [get_projects -quiet] ne "" } {
    catch { set_property BOARD_PART www.digilentinc.com:pynq-z1:part0:1.0 [current_project] }
}
set processing_system7_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { make_external "FIXED_IO, DDR" apply_board_preset "1" \
              Master "Disable" Slave "Disable" } \
    [get_bd_cells processing_system7_0]
set_property -dict [ list \
    CONFIG.PCW_USE_M_AXI_GP0             {1} \
    CONFIG.PCW_EN_CLK0_PORT              {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ  {100} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT      {1} \
    CONFIG.PCW_IRQ_F2P_INTR              {1} \
] $processing_system7_0
```
Il preset (`apply_board_preset`) viene letto dai board file Vivado veri
della Pynq-Z1, non trascritto a mano — stessa scelta deliberata già fatta
nel `system_top.tcl` sorgente, per evitare di introdurre errori copiando
a mano ~400 parametri `CONFIG.PCW_*` di una board diversa.

### 3.7 — LED, DIP switch e pulsanti non registrati
I blocchi Simulink "DIP Switch"/"LED"/"Push Button" (libreria
`hwlogiciolib`) leggono da un mask che interroga la board per sapere
quanti switch/LED/pulsanti esistono realmente. Senza periferiche
registrate sulla board, il caricamento del modello dava warning
`Invalid setting ... for parameter 'NumHMI'`/`'NumLeds'`, e in fase di
build (`Build info`) un errore secco `Unrecognized field name
"PushButton"` (la board di riferimento Zynq-7000 si aspetta quel campo
anche se vuoto).

**Fix**: aggiunti via `soc.sdk.Hardware.addNewLED` / `addNewDIPSwitch` /
`addNewPushButton`, con pin reali verificati in `part0_pins.xml`:
- 4 LED: `R14, P14, N16, M14`
- 2 DIP switch: `M20, M19`
- **3 pulsanti** (non 4): `D20, L20, L19` — **`D19` (btn0) escluso di
  proposito**, vedi §5.

`ActiveHigh = true` per tutti — inizialmente marcato `[DEDOTTO]`
(`board.xml` non specifica la polarità), **poi confermato** dal [PYNQ-Z1
Reference Manual](https://digilent.com/reference/programmable-logic/pynq-z1/reference-manual)
Digilent (fonte primaria, non i file Vivado): i 4 LED sono
"anode-connected... si accendono con un livello logico alto", i 4
pulsanti "generano un output basso a riposo, alto solo quando premuti" —
`ActiveHigh = true` è quindi corretto per LED e pulsanti, non solo
un'ipotesi ragionevole. Per i DIP switch il manuale non è stato
controllato altrettanto a fondo: resta un'assunzione per analogia,
ragionevole ma non verificata quanto le altre due.

## 4. Prova finale: cross-compilazione ARM reale riuscita

Con tutti i fix di §3 applicati, testato con
`openExample('soc/StreamingDataFromHardwareToSoftwareExample')`
(un esempio SoC Blockset **nativo per R2023b** — vedi §6 sul perché
questo dettaglio conta) ritargettizzato su Pynq-Z1:

- **Validate**: tutti i controlli verdi (FPGA model e DUT blocks,
  prodotti/tool richiesti, compilazione modello, task map, memory map,
  build info).
- **Build**: codice C generato e **compilato con successo** dal vero
  cross-compilatore `arm-linux-gnueabihf-gcc` (Linaro AArch32 Linux
  v6.3.1) per **entrambi** i modelli (`soc_hwsw_stream_proc` e
  `soc_hwsw_stream_top_sw`, il "software system" auto-generato da SoC
  Builder che include il modello processore).
- Fallisce solo l'**ultimo passo, il link finale**, per librerie ARM di
  terze parti mai state presenti in questa installazione (`libiio`,
  `libxml2`, `libz`, `libserialport`, `libusb-1.0` — verificato con
  `find` su tutto il sysroot Linaro, non ci sono nemmeno le versioni
  Windows-host, figuriamoci quelle cross-compilate ARM). `libiio` in
  particolare è per dispositivi IIO (schede RF/SDR Analog Devices): è
  una dipendenza di **questo esempio specifico**, scelto per il test
  probabilmente perché usa un canale di streaming AXI4-Stream realistico
  — non della board Pynq-Z1 in generale, e non vale la pena inseguirla.

**Questo è considerato il criterio di successo per il bring-up**: non
serve arrivare al bitstream con *questo* esempio specifico. Il punto era
verificare che SoC Builder riconoscesse la board, partizionasse
correttamente FPGA/Processore, e generasse/compilasse codice ARM reale —
tutto verificato.

## 5. Perché `D19` è riservato (non un dettaglio da ignorare)

**Precisazione importante** (verificata dopo la prima stesura di questo
documento, confrontando col vero reference manual Digilent, non solo coi
file Vivado): la Pynq-Z1 **ha** un pulsante di reset di sistema fisico,
etichettato **`SRST`** sul PCB — ma è collegato al pin **MIO 12** dello
Zynq (Processing System), non a un pin lato PL/fabric come `D19`. I pin
`MIO` sono un tipo di connessione diversa dai pin PL generici che
compaiono in `board.xml`/`part0_pins.xml` (quei file elencano solo le
interfacce lato PL, con vincolo `LOC` su un pin FPGA — `SRST`/MIO12 non
c'è per questo, non perché non esista: è configurato dentro il blocco
Zynq stesso, non come porta HDL top-level con `LOC`). Fonte: [PYNQ-Z1
Reference Manual](https://digilent.com/reference/programmable-logic/pynq-z1/reference-manual)
(Digilent).

**Perché il workaround su `D19` resta comunque necessario**: il
componente `Reset` che si registra su un `soc.sdk.Hardware` (via
`addNewReset`) è specificamente un segnale di reset **lato PL/fabric**
— alimenta la IP `proc_sys_reset` nel block design generato da SoC
Builder, esattamente come `Clock`. `SRST`/MIO12 è un reset di sistema
gestito internamente dallo Zynq PS, non un segnale PL instradabile con
un vincolo `LOC` — non è utilizzabile per questo scopo, quindi non
cambia nulla nella scelta fatta: serve comunque un pin PL da usare come
reset lato fabric, e la Pynq-Z1 non ne definisce uno dedicato in
`board.xml` (verificato con una ricerca esaustiva del file — nessun
componente/interfaccia di tipo reset lato PL da nessuna parte). Lo
script di creazione board (§2) usa perciò il primo pulsante utente, pin
`D19`, come reset PL — un workaround esplicito, non un vero pulsante di
reset del board.

Se in futuro si registra anche `D19` come `PushButton` (per esempio per
avere tutti e 4 i pulsanti disponibili), quel pin fisico riceverebbe due
vincoli `LOC` diversi nel file di constraint generato per due porte
top-level HDL diverse — Vivado lo rifiuterebbe come violazione DRC in
fase di place/route. Non è stato testato direttamente (nessun tentativo
di registrare `D19` due volte), ma la conclusione è diretta dai dati di
`board.xml`/`part0_pins.xml`, non un'ipotesi.

**Se serve davvero un pulsante su `D19`**: l'unica soluzione pulita è
scegliere un pin di reset diverso (es. un altro pulsante, sacrificando
quello) o accettare che la board resti senza un vero pulsante di reset
dedicato per software — non provare a condividere lo stesso pin per due
scopi.

## 6. Cose che dipendono dalla versione MATLAB

- Verificato (sessione precedente, non in questo lavoro) che nessuno dei
  blocchi SoC Blockset trovati/aggirati dipende dalla versione MATLAB —
  stesso comportamento su R2023b e R2026a.
- **Ma occhio agli esempi**: l'esempio `xilinxsoc/
  GettingStartedwithSoCBlocksetExample` ("Get Started with SoC
  Blockset") è **nuovo di R2026a, non esiste nativamente per R2023b**.
  Una copia scaricata/esportata da R2026a e riaperta in R2023b ha
  causato un bug reale e fuorviante: `FixedStep` (Solver → step size sul
  modello FPGA) puntava a una variabile `SampleInterval` **mai definita
  da nessuna parte nel progetto** — non nel workspace, non nei callback
  del modello, non altrove. Il sintomo era identico a un problema della
  board ("FPGA Model: None" nel wizard SoC Builder), ma **dimostrato non
  esserlo**: lo stesso identico modello, ritargettizzato sulla ZedBoard
  reale built-in, dava lo stesso identico fallimento. Solo passando a un
  esempio nativo R2023b (`soc/StreamingDataFromHardwareToSoftwareExample`)
  il problema è sparito.
- **Lezione generale**: se un esempio SoC Blockset scaricato/convertito
  da un'altra versione MATLAB dà errori di rilevamento FPGA/Processore
  nel wizard SoC Builder, sospetta prima il file (variabili non definite
  nei parametri del solver, blocchi rimossi in conversione) e solo dopo
  la registrazione della board — verificalo ritargettizzando
  temporaneamente lo stesso modello su una board ufficiale già
  funzionante (es. ZedBoard) prima di dedicare tempo a debuggare la
  board custom.

## 7. Metodo usato per trovare i bug (utile se ne servono altri)

Nessuno di questi bug era documentato. Trovati tutti per **confronto
diretto** tra i file di registrazione della board custom
(`custom_board_pynqz1_v2\registry\**`) e quelli di una board reale
funzionante già installata con MATLAB
(`toolbox\soc\hardwareboards\zynq\registry\**`, ZedBoard) — stesso
schema di cartelle (`attributes`, `parameters`, `targethardware`,
`forwarding`, `interrupts`), diff file per file.

Per capire cosa succede dentro il wizard SoC Builder senza doverlo
aprire ogni volta, utile la classe interna (non documentata ma pubblica)
`soc.internal.SoCGenWorkflow(topModelName)` — proprietà `FPGAModel`,
`ProcessorModel`, `HasFPGA`, `ModelType`; metodo `ValidateModel` esegue
(quasi) la stessa validazione del wizard reale. **Attenzione**: non
riproduce perfettamente lo stato del wizard vero (mancano argomenti che
il wizard passa in automatico, es. cartella di progetto) — utile per
diagnosi rapide, non come sostituto definitivo di un test nella GUI
reale.
