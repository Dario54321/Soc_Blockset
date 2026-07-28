# Note su `socBuilder` e la struttura corretta del modello

`socBuilder` è il tool di SoC Blockset che genera *davvero* il software per il processore (ARM) e il bitstream per la FPGA a partire da un modello Simulink, e li carica sulla scheda. È diverso dalla semplice simulazione: la simulazione tollera scorciatoie strutturali che la build reale non accetta.

## Il primo blocco: serve un Model Reference, non un subsystem qualsiasi

Il blocco `Task Manager` decide *quando* deve eseguire un pezzo di algoritmo (agganciandosi a un evento, es. "il canale dati ha ricevuto qualcosa di nuovo"). In simulazione, l'algoritmo triggerato da `Task Manager` può stare in un semplice `Subsystem` con una porta Trigger a function-call — funziona bene per vedere se i numeri tornano giusti.

Per `socBuilder`, però, questo **non basta**: l'algoritmo deve vivere in un **Model Reference** vero (un file `.slx` separato, richiamato come blocco "Model"). Il messaggio d'errore reale che si ottiene altrimenti:

```
Connecting the output port of Task manager block ... to a function-call or triggered
subsystem block ... is not supported. Task manager block output port must be connected
to a Model block.
```

### Come si costruisce un Model Reference con trigger a function-call

Il file referenziato ha bisogno di:
1. Un **Inport a livello radice** con il parametro `OutputFunctionCall` impostato su `on` (non una porta Trigger classica) — questo è ciò che permette al blocco Model, quando referenziato, di ricevere un segnale di trigger a function-call dall'esterno come un ingresso "quasi normale".
2. Un blocco **`Asynchronous Task Specification`** in serie subito dopo quell'Inport — imposta la priorità del task (deve combaciare con quella impostata nel `Task Manager`) ed è richiesto esplicitamente da Simulink quando un Inport a function-call non è altrimenti collegato a un contesto di task asincrono.
3. Solo dopo l'`Asynchronous Task Specification`, il segnale arriva a un **subsystem annidato** con una vera porta Trigger (function-call) — è lì dentro che vive il vero algoritmo (nel nostro caso: moltiplicazione matrici + conversione + invio sul canale streaming).
4. Impostazioni di modello specifiche per questo file referenziato (diverse dal modello principale): `Solver Type = Fixed-step`, `Save Format = StructureWithTime` (non il default `Dataset`, incompatibile con gli Inport a function-call), `Hardware Board` impostata esplicitamente (non eredita dal modello principale).

## Il secondo blocco, più insidioso: la posizione del Task Manager nella gerarchia

Anche con tutto il punto precedente sistemato, la generazione falliva ancora con un errore poco chiaro:

```
Unable to find a corresponding event for block, .../Stream Write.
Either change the block parameters to disable event-driven execution or set the
task-type in Task manager block ... to 'Event-driven' and add a block that
generates this event.
```

Il blocco `Task Manager` aveva il campo interno `taskEventSource` impostato su `"Unassigned"` — normalmente questo campo si auto-rileva da solo guardando i collegamenti, ma restava bloccato su "non assegnato" indipendentemente da quanti tentativi si facessero (aggiornare il diagramma, ricaricare il modello da zero, persino impostare a mano il valore corretto nel campo interno — nessuno di questi bastava).

**La causa vera**, trovata confrontando un esempio ufficiale MathWorks funzionante con la stessa identica architettura: `Task Manager` **non deve stare allo stesso livello** del blocco che genera l'evento (nel nostro caso `Software to AXI4-Stream`) — va **annidato in un subsystem dedicato** (per convenzione chiamato "Processor") **insieme** al Model Reference che contiene l'algoritmo. `Software to AXI4-Stream` resta invece sempre al livello root, fuori da quel subsystem.

Una volta applicata questa struttura (creare un subsystem "Processor", spostarci dentro sia `Task Manager` sia il Model Reference dell'algoritmo, e far attraversare il confine del subsystem solo ai segnali realmente necessari: l'evento in ingresso, il segnale "done" in ingresso, e i dati/messaggio in uscita) — il campo `taskEventSource` si è auto-risolto correttamente da solo, senza bisogno di impostarlo a mano:

```json
"taskEventSource": "Software to AXI4-Stream",
"taskEventSourceAssignmentType": "AutoAssigned"
```

E il modello completo compila senza errori. `socBuilder(nomemodello)` si avvia senza eccezioni.

## Schema della struttura corretta

```
ModelloPrincipale (root)
├── Software to AXI4-Stream   ← il canale dati, sempre a livello root
├── FPGA (Model Reference)     ← la logica hardware
└── Processor (subsystem)      ← QUESTO livello di annidamento è necessario
    ├── Task Manager
    └── ComputeAlgorithm (Model Reference)   ← l'algoritmo software
        └── (Inport function-call) → Asynchronous Task Specification → subsystem con Trigger
                                                                          └── vero algoritmo (es. Stream Write)
```

## La build vera si può scriptare: `socModelBuilder`

`socBuilder(nomemodello)` è solo un **lanciatore di interfaccia grafica** (apre l'app SoC Builder e ci carica dentro il modello) — non ha parametri per eseguire una build reale da riga di comando.

L'oggetto giusto per farlo davvero è **`socModelBuilder`** (introdotto in R2023a):

```matlab
obj = socModelBuilder(nomemodello, 'ProjectFolder', percorso, 'BuildType', 'Processor only');
buildModel(obj);
```

`BuildType` può essere `'Processor only'` (solo software ARM), `'FPGA only'`, o `'Processor and FPGA'` (build completa).

⚠️ **Scoperta importante**: anche se si sceglie `'FPGA only'`, il pipeline genera comunque il sistema software ed esegue comunque la compilazione del lato processore (`ComputeAlgorithm`) — perché il modello ha i due lati co-progettati insieme (Task Manager/canale streaming), quindi anche una build "solo FPGA" richiede che il toolchain ARM sia a posto. Non è un modo per aggirare il requisito del toolchain di cross-compilazione.

**Attenzione al percorso**: `ProjectFolder` **non accetta percorsi con spazi** — se il proprio nome utente Windows contiene uno spazio (es. `C:\Users\Nome Cognome\...`), va usata una cartella su un percorso pulito (es. `D:\NomeCartella\`, senza spazi) sia per il modello sia per `ProjectFolder`.

### Risultato ottenuto con `BuildType='Processor only'`

Il pipeline arriva molto lontano prima di fermarsi:
1. Genera il sistema software estratto dal modello completo (`<nomemodello>_sw.slx`).
2. Genera **codice C reale** per l'algoritmo (Model Reference `ComputeAlgorithm`): `.c`/`.h` completi, tramite Embedded Coder.
3. Si ferma solo alla cross-compilazione finale, con un errore chiaro:
   ```
   The required third-party tools have not been installed during hardware setup.
   Please install the tools to deploy the model to hardware. To start the hardware
   setup process, open Add-Ons Manager.
   ```

Questo significa: **il modello e il pipeline di generazione software funzionano correttamente** — quello che manca è il **toolchain di cross-compilazione ARM** (il compilatore che trasforma il codice C generato in un eseguibile per il processore della scheda, lanciato da un PC Windows/x86). Va installato tramite il wizard interattivo "Hardware Setup" (MATLAB Home → Add-Ons → Manage Add-Ons → Setup) — un passo che richiede probabilmente una connessione internet per scaricare il toolchain, e la registrazione di un "sysroot" (l'insieme di header/librerie del sistema operativo target) valido per la scheda scelta.

## Quale pacchetto installare per il toolchain ARM

Controllato quali Add-On risultano già installati (`matlab.addons.installedAddons`): solo il toolbox base "Embedded Coder", nessun support package specifico per Xilinx/Zynq. Nell'Add-Ons Manager compaiono 5 pacchetti simili per nome — solo uno è quello giusto:

| Pacchetto | Adatto? | Perché |
|---|---|---|
| HDL Coder Support Package for Xilinx **RFSoC** Devices | No | Solo schede RFSoC, non Zynq-7000 generico |
| HDL Coder Support Package for **Intel** FPGA Boards | No | Intel/Altera, non Xilinx |
| HDL Coder Support Package for Xilinx **FPGA Boards** | No | Solo workflow IP Core Generation puro, niente software embedded/ARM |
| HDL Coder Support Package for **Intel** FPGA and SoC Devices | No | Intel, non Xilinx |
| **HDL Coder Support Package for AMD FPGA and SoC Devices** | **Sì** | Unico che menziona esplicitamente "Embedded Software" oltre all'HDL — include il toolchain di cross-compilazione ARM per il lato processore delle schede SoC (Zynq) |

("AMD" perché Xilinx è stata acquisita da AMD — è lo stesso ecosistema Zynq/Xilinx di sempre, solo il nome del produttore nel catalogo è cambiato.)

## Come è andato il wizard "Hardware Setup" nella pratica

1. **Scelta board**: tra ZC702, ZC706, ZedBoard, ZCU102, VCK190 → **ZedBoard** (stesso chip xc7z020 della Pynq-Z1 — il toolchain dipende dal chip, non dalla board esatta, quindi va bene anche se Pynq-Z1 non è tra le opzioni).
2. **Scelta scheda di rete (NIC)**: serve solo per la futura comunicazione con la scheda fisica — se non la possiedi ancora, scegli semplicemente la tua scheda Ethernet fisica reale (non VPN virtuali, non Bluetooth). Si può cambiare più avanti.
3. **Schermata "Select a Drive" (scrittura immagine SD boot)**: richiede una vera SD card fisica in un lettore. **Se non hai la scheda fisica, questo passo va annullato ("Cancel")** — non è necessario per installare solo il toolchain di compilazione.

   ⚠️ **Attenzione di sicurezza**: questo campo vuole una vera SD **rimovibile**, mai una partizione del disco fisso locale (anche se contiene un sistema Linux) — selezionarla per errore rischierebbe di sovrascriverla con l'immagine di boot della scheda.

4. **Verifica che annullare quella schermata non comprometta l'installazione**: usare `matlabshared.supportpkg.getInstalled` (NON `matlab.addons.installedAddons`, che non mostra i support package hardware) per controllare cosa risulta davvero installato:
   ```matlab
   matlabshared.supportpkg.getInstalled
   ```
   Nel nostro caso, dopo aver annullato solo il passo 3, risultava comunque installato **"HDL Coder Support Package for Xilinx Zynq Platform"** — confermato che annullare la sola scrittura della SD non cancella il resto.

## Il vero blocco: manca il compilatore ARM Linux vero e proprio

Dopo aver completato parzialmente il wizard "Hardware Setup" (annullando solo la schermata di scrittura SD card, per cui serve una vera SD/USB fisica che non era disponibile), `buildModel` dà ancora lo stesso errore. Controllando i file scaricati sul disco:

- ✅ **Sysroot** (le librerie di sistema del target) — già scaricato.
- ✅ **Immagine di boot SD** per ZedBoard — già scaricata.
- ❌ **Il vero compilatore GCC per ARM Linux** (`arm-linux-gnueabihf-gcc` o simile) — **non presente**. L'unico compilatore ARM trovato sul disco è quello per Arduino (`arm-none-eabi-gcc`), completamente diverso: è per microcontrollori senza sistema operativo, non compatibile con Linux embedded.

Il download del vero compilatore avviene probabilmente in un passo del wizard **successivo** a quello di scrittura della SD card — che quindi va completato per intero (non solo annullato) per ottenere il compilatore.

### Tentativo di aggirare il requisito "SD card fisica" con un disco virtuale — non ha funzionato

Provato a creare un file VHD (disco virtuale) via `diskpart`, montarlo come unità e usarlo al posto di una vera SD nel wizard. **Non ha funzionato**, a nessuna dimensione (provato 4GB e 4.1GB): un disco montato da un file VHD risulta sempre classificato da Windows come `DriveType: Fixed` (non "Removable"), indipendentemente dai parametri usati per crearlo — è una limitazione strutturale (la classificazione "rimovibile" dipende dal vero controller USB/SD fisico sottostante, che un file VHD non ha). Il wizard filtra evidentemente solo le unità genuinamente rimovibili.

*Nota per chi prova a fare lo stesso*: l'icona "Espelli" che Esplora Risorse mostra per i dischi VHD montati non è un indizio affidabile — è solo una comodità dell'interfaccia per i VHD, non riflette la vera classificazione di sistema (verificabile con `Get-Volume`/`Get-PhysicalDisk` in PowerShell).

## Ricerca del punto di controllo interno — vicolo cieco (per ora)

Cercato nel codice del toolbox (`grep` mirato su `toolbox/shared/soc`, `toolbox/hdlcoder`, `toolbox/shared/hwconnectinstaller`, e una ricerca più ampia su tutto `toolbox/`) il testo esatto dell'errore, per capire se esiste un modo per registrare manualmente un toolchain scaricato altrove (bypassando il wizard). **Nessun risultato in nessuna delle due ricerche** — il controllo è quasi certamente dentro codice compilato/protetto (p-code) di MathWorks, non ispezionabile in questo modo. Non proseguire su questa via se non emergono nuovi indizi.

## Le opzioni rimaste per completare il compilatore ARM

1. **Procurarsi una vera chiavetta USB o SD card** e ripetere il wizard per intero (compresa la schermata di scrittura SD) — l'unica strada verificata come potenzialmente risolutiva.
2. Mettere in pausa questo aspetto specifico e lavorare nel frattempo su altre parti del progetto che non richiedono il toolchain ARM — es. sintesi Vivado diretta (via TCL, bypassando `socModelBuilder` interamente) sull'algoritmo MPC vero quando sarà pronto, o affinamento della demo di simulazione.

## Tentativo di download manuale del toolchain — analisi approfondita, nessuna scorciatoia trovata

Prima di scartare l'opzione "scaricare il toolchain manualmente", è stata condotta un'indagine approfondita nel codice reale di MATLAB (non supposizioni) per capire se fosse possibile registrare il compilatore ARM senza passare dal wizard con la SD card.

**Cosa è stato trovato e verificato**:
- Il manifest interno di SoC Blockset (`toolbox/soc/supportpackages/xilinxsoc/thirdpartytools/instrset/linarogcctoolchain_aarch32.instrset/win64/win64.xml`) indica il vero compilatore richiesto: **Linaro GCC 6.3.1 per `arm-linux-gnueabihf`**, scaricabile direttamente dai server MathWorks (`ssd.mathworks.com`, nessun login richiesto), con un checksum di verifica.
- Il file è stato **scaricato, verificato (checksum MD5 combaciante) ed estratto** nella cartella dove MATLAB se lo aspetta (`3P.instrset/linarogcctoolchain_aarch32.instrset/`) — e il compilatore **funziona davvero** (`arm-linux-gnueabihf-gcc.exe -dumpversion` → `6.3.1`).
- **Nonostante questo, `buildModel` continua a dare lo stesso errore identico**, incluso l'avviso "sysroot not registered". Conclusione: MATLAB non fa una scansione automatica dei file per "scoprire" il toolchain — serve una registrazione interna esplicita (una preferenza/stato scritto dal wizard stesso), che i soli file sul disco non attivano.
- Cercato nel codice il punto esatto che scrive/legge questa registrazione — non trovato in nessun file di testo cercabile, né nell'installazione base di MATLAB né nei support package: quasi certamente dentro codice compilato/protetto (p-code) di MathWorks, stesso esito già visto per altri controlli interni di questo toolbox.
- Testato anche il wizard di un terzo pacchetto correlato, **"SoC Blockset Support Package for Xilinx Devices"** (mai configurato prima): la schermata "Select Embedded OS Image" offre solo due opzioni, **entrambe legate a hardware reale** — scrivere una vera SD/MMC, oppure (opzione testata concretamente) aprire lo strumento "OS Customizer", che però chiede subito di collegare una scheda fisica. Nessuna scorciatoia trovata nemmeno qui.

**Conclusione**: il download manuale del compilatore è stato ottenuto con successo ed è pronto sul disco, ma **non è sufficiente da solo** — resta necessaria una vera SD card/USB per completare la registrazione tramite il wizard ufficiale. Questa strada (opzione 2 elencata sopra nelle versioni precedenti di questo documento) è quindi **esclusa** come scorciatoia praticabile.

⚠️ **Questa conclusione si è rivelata sbagliata — vedi la sezione finale di questo documento.** Non serviva nessuna SD/USB: erano tre problemi software indipendenti, tutti risolti da riga di comando.

## RISOLTO DEFINITIVAMENTE — build ARM completa senza SD/USB, causa radice reale di tutti i blocchi precedenti

Riprendendo l'indagine con un approccio diverso (cercare file di stato/nomi di funzione invece del testo letterale dell'errore, e **chiamare direttamente** le funzioni interne anche quando il loro corpo è p-code protetto — chiamare una funzione non richiede di poterne leggere il sorgente), sono stati trovati e risolti tre problemi concreti, tutti verificati con build reali eseguite fino in fondo.

### Problema 1 — il controllo "third-party tools not installed" in realtà passa già

Il controllo che genera l'errore `"The required third-party tools have not been installed..."` è in `onBuildEntryHook.m` (sorgente leggibile, non protetto):
```matlab
instrSets = matlab.hwmgr.internal.getInstructionSetsForSpPkg(rootDir);
if ~matlab.hwmgr.internal.areAllTpToolsInstalled(instrSets)
    error(message('zynq:utils:AllTpToolsNotInstalled'));
end
```
Chiamando queste funzioni direttamente: `areAllTpToolsInstalled` restituisce **vero**, perché riconosce il compilatore Linaro scaricato manualmente (vedi sezione precedente). Il vero problema non era mai la "registrazione" mancante di questo controllo specifico.

### Problema 2 — il compilatore va reso visibile con una chiamata esplicita

Il Makefile generato usa una variabile d'ambiente (`LINARO_TOOLCHAIN_6_3_1_AARCH32`) mai impostata di default. Esiste una funzione pubblica dedicata proprio a questo:
```matlab
codertarget.zynq.internal.addCompilerPath('6.3.1','AARCH32');
```
Risolve da sola il percorso del compilatore già scaricato (nota: la cartella reale ha suffisso `_soc` — `linarogcctoolchain_aarch32_soc.instrset`, non quella senza suffisso) e imposta la variabile d'ambiente. Va chiamata prima di ogni `buildModel`.

### Problema 3 — bug generico di MATLAB su Windows: `system()` non cerca nella cartella corrente

Dopo il fix precedente, nuovo errore: `"ComputeAlgorithm.bat" non è riconosciuto come comando interno o esterno...`. Il file `.bat` esiste davvero nella cartella di build, e lanciandolo a mano da PowerShell (nella stessa cartella) funziona senza problemi. **Causa reale, riprodotta e isolata**: `system('ComputeAlgorithm.bat')` chiamato da dentro MATLAB, nella stessa identica cartella, fallisce con lo stesso errore — a differenza di una shell interattiva, il `system()`/`dos()` di MATLAB **non include la cartella corrente nella ricerca di un eseguibile senza percorso esplicito**. Fix:
```matlab
setenv('PATH', ['.;' getenv('PATH')]);
```
Aggiunge "." (cartella corrente) al PATH usato dai processi lanciati da MATLAB. **Effetto collaterale positivo scoperto**: questo stesso bug rompeva silenziosamente anche il meccanismo automatico di collegamento del sysroot (il warning "sysroot not registered" visto in ogni tentativo precedente) — con questo fix, il flag `--sysroot=...` compare da solo nei comandi di compilazione generati, senza nessun intervento aggiuntivo.

### Problema 4 — un header pubblico mancava dalla cartella giusta

La compilazione falliva su un file di utilità condivisa (`iio_helper.c`, non related al nostro algoritmo) con `fatal error: iio.h: No such file or directory`. L'header esiste già sul disco (scaricato da MATLAB stesso in `3P.instrset/libiio.instrset/win64/include/iio.h`), ma il Makefile generato cerca in una cartella diversa (`toolbox/shared/libiio/base/include/`) che contiene solo header di supporto, non l'header vero. **Fix one-time, permanente**: copiare il file (nessuna licenza o registrazione richiesta, è un header pubblico già scaricato da MathWorks):
```
copy 3P.instrset\libiio.instrset\win64\include\iio.h  →  toolbox\shared\libiio\base\include\iio.h
```

### Risultato finale, verificato sul disco

Con questi tre fix (nessuna modifica manuale al Makefile generato — viene rigenerato da zero a ogni build e funziona così com'è), lo script:
```matlab
cd('D:\SocBuilderBuild');
hdlsetuptoolpath('ToolName','Xilinx Vivado', 'ToolPath','D:\Xilinx\Vivado\2022.1\bin\vivado.bat');
codertarget.zynq.internal.addCompilerPath('6.3.1','AARCH32');
setenv('PATH', ['.;' getenv('PATH')]);
obj = socModelBuilder('Prova_1_socbuilder', 'ProjectFolder', 'D:\SocBuilderBuild\soc_prj', 'BuildType', 'Processor only');
buildModel(obj);
```
completa l'intera pipeline: genera il codice C, compila con il vero `arm-linux-gnueabihf-gcc`, e **linka con successo un eseguibile reale**:
```
arm-linux-gnueabihf-gcc ... -liio -lxml2 -lz -lserialport -lusb-1.0 --sysroot=...sysroot_zynq7000... -o Prova_1_socbuilder_sw.elf ...
```
Verificato con il comando `file` sul risultato:
```
Prova_1_socbuilder_sw.elf: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 2.6.32
```
Un vero eseguibile Linux ARM, pronto per il Cortex-A9 dello Zynq-7020 — ottenuto interamente via software, **senza nessuna SD card o chiavetta USB fisica**.

### Perché tutti i tentativi precedenti sembravano indicare "serve hardware"

Il warning "sysroot not registered" e l'errore finale sulla cross-compilazione sono sempre apparsi identici in ogni tentativo, dando l'impressione di un singolo blocco strutturale legato alla registrazione del wizard. In realtà erano **tre cause indipendenti che si sommavano**, nessuna delle quali richiedeva hardware: (a) il compilatore non veniva reso visibile senza una chiamata esplicita, (b) un bug generico del `PATH` di MATLAB rompeva sia l'invocazione dei file `.bat` di build sia — quasi certamente — l'estrazione/collegamento automatico del sysroot, (c) un header pubblico non era nella cartella attesa. Il wizard "Hardware Setup" con SD/USB probabilmente risolverebbe tutti e tre come effetto collaterale (scaricando tutto in un unico flusso "sano"), ma non era l'unica via.

### API trovata per completare anche la registrazione di Pynq-Z1 (esplorata, non ancora usata)

Durante l'indagine, dissezionando `soc.sdk.en.setupSoftwareTools.m`, è stata trovata `soc.sdk.internal.setupSysRootForReferenceTarget(tgtObj, hwBoardName)`, usata dalla classe pubblica e documentata **`soc.sdk.BoardSupport`** (introdotta in SoC Blockset R2019b — `doc soc.sdk.BoardSupport`, workflow ufficiale per registrare board SoC personalizzate via script). Testata con successo:
```matlab
tgtObj = soc.sdk.BoardSupport('PynqZ1Test','Board Support for Xilinx Zynq-7000 SoC','<cartella>');
soc.sdk.internal.setupSysRootForReferenceTarget(tgtObj,'ZedBoard');
tgtObj.save();  % "Registering the target 'PynqZ1Test'... Done."
```
Crea davvero una board personalizzata registrata in MATLAB, riusando la configurazione del target Zynq-7000 di riferimento — **senza nessuna SD card**. Non ancora usata per registrare una vera "PynqZ1" definitiva (la build riuscita sopra usa ancora `ZedBoard`), ma è la via giusta per completare quell'obiettivo separato in futuro.

### Prossimi passi reali

1. Ripetere il build con `BuildType='Processor and FPGA'` per ottenere anche il bitstream (non ancora tentato con questi fix).
2. Rendere i tre fix permanenti in modo più pulito di una chiamata manuale a ogni sessione (es. uno script di setup del progetto, o un `startup.m`).
3. Usare `soc.sdk.BoardSupport` per registrare una vera board "PynqZ1" invece di continuare a riusare `ZedBoard` come proxy.
