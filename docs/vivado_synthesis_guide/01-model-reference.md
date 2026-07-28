# 1. Model Reference: perché e come isolare un pezzo di modello

## Il concetto, in generale

In Simulink esistono due modi per raggruppare blocchi dentro un "contenitore":

- **Subsystem**: è solo un raggruppamento *visivo*. I blocchi al suo interno restano parte dello stesso file `.slx` del modello principale, condividono le stesse impostazioni di configurazione (Configuration Parameters) del modello che li contiene, e vengono compilati/analizzati insieme a tutto il resto ogni volta.
- **Model Reference** (blocco "Model"): è un **file `.slx` separato**, richiamato dal modello principale come se fosse un blocco. Ha le proprie impostazioni di configurazione indipendenti (può avere un target hardware diverso, un solver diverso, parametri di generazione codice diversi dal modello che lo contiene), e viene compilato come unità a sé stante.

Perché la differenza conta per la generazione di hardware: molti strumenti di generazione di codice (sia Embedded Coder per il software, sia HDL Coder per l'hardware) hanno bisogno di sapere **esattamente dove finisce un'unità di compilazione e dove inizia l'altra**, perché generano file di codice/hardware distinti per ciascuna unità, con le proprie impostazioni. Un Subsystem qualsiasi non basta a definire questo confine in modo affidabile per gli strumenti di build "seri" (quelli che generano davvero codice per un target, non solo per la simulazione) — un Model Reference sì, perché è letteralmente un file separato con la propria configurazione.

**Regola pratica generale**: se un pezzo del tuo modello deve essere tradotto in codice reale (C per un processore, VHDL/Verilog per una FPGA) con impostazioni proprie (es. un target hardware diverso dal resto del modello), quel pezzo deve quasi sempre diventare un Model Reference, non restare un Subsystem.

## Come si converte un Subsystem in Model Reference (comando generico)

Simulink offre una funzione ufficiale che fa la conversione automaticamente — crea il nuovo file, sposta dentro il contenuto, e sostituisce il vecchio Subsystem con un blocco Model che punta al nuovo file, ricollegando da solo tutti i fili nello stesso punto:

```matlab
Simulink.SubSystem.convertToModelReference( ...
    'NomeModelloPrincipale/NomeSubsystemDaConvertire', ...  % percorso del subsystem, dentro il modello aperto
    'NomeNuovoFileModello', ...                              % nome del NUOVO file .slx che verrà creato
    'ReplaceSubsystem', true, ...   % sostituisce il Subsystem originale con un blocco Model
    'AutoFix', true, ...            % prova a correggere automaticamente problemi minori di conversione
    'Force', true);                 % completa la conversione anche in presenza di avvisi non bloccanti
```

Da fare **prima**: caricare il modello principale con `load_system('NomeModelloPrincipale.slx')`. Da fare **subito dopo**: salvare sia il modello principale sia il nuovo file:
```matlab
save_system('NomeModelloPrincipale');
save_system('NomeNuovoFileModello', 'C:\percorso\dove\salvarlo\NomeNuovoFileModello.slx');
```

### Un'alternativa esistente ma meno indicata: `copyContentsToBlockDiagram`

Esiste anche `Simulink.SubSystem.copyContentsToBlockDiagram(subsystem, nuovoModello)`, che **copia** il contenuto del Subsystem in un nuovo file — ma **non sostituisce** il Subsystem originale con un blocco Model, e non ricollega nulla automaticamente. Va bene solo se vuoi *estrarre* il contenuto per lavorarci separatamente, non se vuoi che il modello principale continui a referenziarlo come un vero Model Reference. Per l'obiettivo "voglio che questo pezzo diventi un Model Reference vero e collegato", usa `convertToModelReference`.

## Esempio da questo progetto

Nel modello `Prova_1_socbuilder.slx`, il subsystem `FPGA` (la parte che deve girare su hardware programmabile) doveva diventare un Model Reference perché il resto della pipeline (sia `socModelBuilder` sia, indipendentemente, HDL Coder per la sintesi diretta) richiede quel confine netto per riconoscerlo come un blocco traducibile in hardware a sé stante:

```matlab
load_system('D:\SocBuilderBuild\Prova_1_socbuilder.slx');
Simulink.SubSystem.convertToModelReference( ...
    'Prova_1_socbuilder/FPGA', ...
    'FPGA_HW', ...
    'ReplaceSubsystem', true, 'AutoFix', true, 'Force', true);
save_system('Prova_1_socbuilder');
save_system('FPGA_HW', 'D:\SocBuilderBuild\FPGA_HW.slx');
```

**Insidia incontrata, generale, da tenere a mente**: il nome scelto per il nuovo Model Reference deve essere un nome MATLAB valido **e non deve collidere con nessuna funzione/nome già esistente sul path di MATLAB**. Il primo tentativo, chiamandolo `'FPGA'`, è fallito con un errore poco chiaro:
```
Unable to use 'FPGA' as a new referenced model name.
The model 'FPGA' already exists on the path.
```
La causa vera: esiste già una funzione toolbox chiamata `fpga.m` (parte del pacchetto di supporto FPGA I/O), e Simulink/MATLAB trattano quel nome come "già occupato" indipendentemente dal fatto che non sia un modello Simulink. **Lezione generale**: se la conversione a Model Reference fallisce con un errore simile a "already exists on the path" pur non avendo tu creato nulla con quel nome, prova un nome diverso — quasi certamente collide con una funzione MATLAB esistente da qualche parte nell'installazione. Nel progetto è stato usato `'FPGA_HW'` invece di `'FPGA'`, e ha funzionato subito.
