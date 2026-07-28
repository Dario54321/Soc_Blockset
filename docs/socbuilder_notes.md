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

## Prossimo passo aperto

Installare il toolchain di cross-compilazione ARM (via Hardware Setup) e riprovare `buildModel` — a quel punto si dovrebbe ottenere un eseguibile ARM reale, pronto per essere caricato sulla scheda.
