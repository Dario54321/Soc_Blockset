# 2. HDL Coder e il concetto di DUT

## Cos'è HDL Coder, in generale

HDL Coder è lo strumento MATLAB/Simulink che traduce un sottoinsieme di un modello Simulink (o di codice MATLAB scritto in un blocco "MATLAB Function") in **VHDL o Verilog** — i due linguaggi standard con cui si descrive un circuito digitale a livello di registri e porte logiche (RTL, "Register-Transfer Level"). Non è la stessa cosa della simulazione: quando simuli un modello in Simulink, MATLAB esegue il modello interpretandolo o eseguendo codice C compilato al volo, su un normale processore x86 — nessun hardware viene descritto. HDL Coder invece genera un file di testo (il `.vhd`/`.v`) che descrive letteralmente come devono essere collegati i componenti logici di un chip per implementare quel comportamento.

**Limite fondamentale, generale**: non tutto quello che puoi scrivere/disegnare in Simulink è traducibile in hardware reale. Un algoritmo che alloca memoria dinamicamente, che usa ricorsione illimitata, o che dipende dal tempo di esecuzione di un processore generico, semplicemente non ha un equivalente diretto in un circuito fisico (che è fatto di un numero fisso di componenti, cablati in un certo modo, che eseguono sempre nello stesso numero di cicli di clock). HDL Coder impone quindi vincoli sui blocchi/costrutti che puoi usare nella parte di modello che vuoi tradurre.

## Il concetto di DUT (Design Under Test / Device Under Test)

Quando generi HDL, devi sempre indicare **quale singolo blocco** (di solito un Subsystem, o un Model Reference) è il "DUT": la porzione esatta del modello che diventerà hardware. Tutto quello che sta fuori dal DUT (es. sorgenti di test, blocchi di visualizzazione per la simulazione) resta fuori dalla generazione — serve solo per verificare in simulazione che il DUT si comporti come previsto, ma non genera nessun circuito.

### Vincolo pratico: un blocco MATLAB Function "nudo" non basta

Se il tuo DUT è letteralmente un blocco `MATLAB Function` (un blocco che contiene codice MATLAB scritto a mano, tradotto internamente da Simulink in una rappresentazione eseguibile) posizionato direttamente nel modello, **non puoi generare HDL direttamente da lì**. Il tentativo dà:
```
HDL code generation is not directly supported for a MATLAB Function Block.
This object must be enclosed within a subsystem.
```
Il motivo è tecnico ma il succo è: HDL Coder genera codice per confini di gerarchia Simulink (Subsystem), non per singoli blocchi funzionali isolati — un blocco MATLAB Function deve quindi stare **dentro** un Subsystem, e sarà quel Subsystem (non il blocco MATLAB Function da solo) il DUT che passi agli strumenti.

**Fix generico**: incapsula il blocco in un nuovo Subsystem, spostandolo dentro senza cambiarne il comportamento. Simulink offre una funzione per farlo senza doverlo fare a mano nell'editor:
```matlab
h = get_param('NomeModello/NomeBloccoMATLABFunction', 'Handle');   % handle NUMERICO, vedi nota sotto
Simulink.BlockDiagram.createSubsystem(h, 'Name', 'NomeNuovoSubsystem');
save_system('NomeModello');
```
**Insidia incontrata, generale**: `Simulink.BlockDiagram.createSubsystem` si aspetta come primo argomento un **handle numerico** del blocco (un identificatore interno di Simulink, un numero), non una stringa col percorso del blocco dentro una cell array. Passando `{'NomeModello/NomeBlocco'}` (una cell array di stringa, che sembrerebbe naturale vista la sintassi di altre funzioni Simulink) si ottiene un errore interno poco chiaro (`CELL2MAT does not support cell arrays containing cell arrays or objects`, dentro `createSubsystemImpl`). Serve invece `get_param(...,'Handle')` per ottenere il numero, e passare quello.

## Verificare la compatibilità PRIMA di generare: `checkhdl`

Generare codice HDL per un modello complesso può richiedere tempo. Prima di farlo, conviene eseguire un controllo statico di compatibilità:
```matlab
checkhdl('NomeModello/NomeDUT');
```
**Comportamento da sapere, generale**: `checkhdl` **non lancia un errore MATLAB (`try`/`catch` non lo intercetta) se trova problemi** — semplicemente scrive un report HTML e stampa nella console qualcosa come `"HDL check ... complete with 1 errors, 0 warnings"`. Se scrivi uno script che deve fermarsi/reagire in caso di problemi, non basta un `try/catch` intorno a `checkhdl`: devi leggere l'esito (il conteggio nel messaggio, o aprire il report HTML) esplicitamente.

## Il problema dei numeri in virgola mobile (`double`)

### Perché è un problema, in generale

Un circuito digitale "di base" (i blocchi logici standard di una FPGA — LUT, registri, DSP dedicati) lavora nativamente con numeri **interi/fixed-point** (virgola fissa: un numero intero a cui si assegna convenzionalmente un certo numero di bit come parte frazionaria). Un numero in virgola mobile IEEE 754 (il tipo `double` di MATLAB, 64 bit) è una rappresentazione molto più complessa (segno, esponente, mantissa, casi speciali come NaN/infinito) che richiede circuiti dedicati molto più costosi (in area, potenza, e velocità) per essere manipolata correttamente — moltiplicare due `double` in hardware non è "come moltiplicare due interi ma con più bit", è un'operazione strutturalmente diversa.

Per questo, se il tuo DUT ha segnali di tipo `double` che devono passare per un vero calcolo aritmetico, HDL Coder si rifiuta di generare codice sintetizzabile per default, e segnala:
```
The model contains "Double" type signals. To generate synthesizable HDL code,
either select the "Use Floating Point" check box or change the "Double" type
signals to fixed-point data type.
```

### Le due strade, spiegate

1. **Convertire i segnali a fixed-point**: la strada "leggera" — riprogetti il modello in modo che i segnali che entrano nella parte da sintetizzare siano dichiarati come tipi fixed-point (es. `fixdt(1,16,10)`, un numero con segno a 16 bit di cui 10 di parte frazionaria) invece di `double`, fin dall'ingresso della regione HDL. Costa meno hardware (spesso una moltiplicazione fixed-point costa solo 1 blocco DSP dedicato del chip, vedi [`../hdl_findings.md`](../hdl_findings.md)), ma richiede di scegliere a mano quanta precisione/range serve per il tuo problema (un lavoro di analisi che si chiama "quantizzazione" o "word-length optimization").
2. **Abilitare il supporto floating-point nativo** (`Native Floating Point`): la strada "pesante" — dici a HDL Coder di generare comunque hardware che lavora davvero in virgola mobile, usando IP dedicati (più LUT/DSP, più lenti) invece di richiederti di riprogettare i tipi di dato. Utile quando non vuoi/non puoi cambiare la rappresentazione dei dati nel modello (es. perché deve restare bit-esatta rispetto al lato software fino a quel punto), o in fase di test rapido quando non ti interessa ancora ottimizzare l'area.

Il comando per abilitare l'opzione 2 su un modello:
```matlab
hdlset_param('NomeModello', 'UseFloatingPoint', 'on');
```
**Insidia incontrata, generale**: il report HTML dell'errore contiene un link che apre `configset.internal.open(mdl,'UseFloatingPoint')` — sembrerebbe suggerire che `'UseFloatingPoint'` sia un parametro normale del Configuration Set, impostabile con `set_param(getActiveConfigSet(mdl),'UseFloatingPoint','on')`. **Non è così**: quel nome non è un parametro valido per `set_param` sul config set standard (dà `Property 'UseFloatingPoint' does not exist`). I parametri specifici di HDL Coder (quelli che appaiono nella scheda "HDL Code Generation" dei Configuration Parameters) vanno impostati con la funzione dedicata **`hdlset_param`** (e letti con `hdlget_param`), non con `set_param`/`get_param` generici.

## Generare il codice reale: `makehdl`

Una volta che `checkhdl` riporta 0 errori, si genera il codice vero:
```matlab
makehdl('NomeModello/NomeDUT', 'TargetDirectory', 'C:\percorso\di\output');
```
Produce (tipicamente, per VHDL):
- Un file `.vhd` per ogni sotto-blocco del DUT (uno per il DUT stesso, uno per ciascun blocco interno che genera la sua parte).
- Un file `_pkg.vhd` con le definizioni di tipo custom usate nel design (necessario perché VHDL è un linguaggio fortemente tipizzato, a differenza di Verilog).
- Un file `_compile.do`: un piccolo script che elenca in che **ordine** questi file vanno compilati/letti da un tool di sintesi — importante perché un file che definisce tipi o usa un sotto-modulo deve essere letto PRIMA del file che lo usa.

Questi file `.vhd`/`.v` sono il vero output di questo capitolo: da qui in poi non serve più MATLAB/Simulink, si passa a Vivado (capitolo successivo).
