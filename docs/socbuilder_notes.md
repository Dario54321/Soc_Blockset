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

`BuildType` può essere `'Processor only'` (solo software ARM, il più veloce da testare), `'FPGA only'`, o `'Processor and FPGA'` (build completa).

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

## Le opzioni rimaste per completare il compilatore ARM

1. **Procurarsi una vera chiavetta USB o SD card** e ripetere il wizard per intero — la strada più semplice.
2. **Scaricare il toolchain manualmente** (es. da Linaro) e provare a registrarlo senza passare dal wizard — non ancora verificato se `buildModel` lo accetterebbe.
3. Mettere in pausa questo aspetto specifico e lavorare nel frattempo su altre parti del progetto (es. il lato FPGA della build, indipendente da questo).

## Prossimo passo

Indagare se esiste un modo per registrare un toolchain manualmente, cercando nel codice sorgente del toolbox cosa verifica esattamente `buildModel` per decidere se il compilatore è installato.
