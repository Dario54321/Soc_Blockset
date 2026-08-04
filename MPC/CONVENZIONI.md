# Convenzioni di lavoro — filone MPC

Regole stabili per questo filone, distinte dallo stato del momento (che sta
in `wip_DAR/STATO.md` e nel router di ripresa). Valgono per qualunque
sessione futura su MPC, non solo per quella in cui sono state scritte.

## Chi modifica cosa

Su questo filone, le modifiche a codice/modello/git le fa **Dario**, non
l'assistente. L'assistente diagnostica, verifica, prepara comandi pronti da
eseguire e spiega — non applica fix a file di codice né esegue commit/push
senza che sia esplicitamente richiesto per quell'azione specifica. È una
correzione esplicita data da Dario in sessione (prima l'assistente aveva
applicato fix non richiesti, solo perché "controlla" era stato interpretato
come "controlla e sistema").

## Repo di Emanuele — limiti

- `MPC_Emanuele/` (dentro questo repo, `Soc_Blockset`) è uno **snapshot di
  sola lettura**. Non si modifica mai a mano: se serve aggiornarlo, si rifà
  il pull dal repo sorgente e si sostituisce tutto (vedi
  `MPC_Emanuele/PROVENIENZA.md` per la procedura e la cronologia). È successo
  più volte che un fix testato a mano finisse per sbaglio lì invece che in
  un'area di lavoro — attenzione a questo quando si suggerisce codice di
  esempio in chat, il rischio è che venga incollato nel posto sbagliato.
- Il repo vero (`emaema23/MPSoC-for-CACC`, privato) si può **clonare in
  lettura liberamente** (non modifica nulla). Commit/push lì — e più in
  generale qualunque azione che scrive su quel repo — solo su richiesta
  esplicita, e mai sul branch `main` di Emanuele: solo sul branch `Dario`
  (Dario ha accesso in scrittura concesso da Emanuele durante una call), poi
  eventualmente una Pull Request per farlo rivedere.

## Metodo davanti a un errore

Prima di tentare un fix a caso: leggere il messaggio d'errore esatto, il
codice sorgente vero, o introspettare l'oggetto reale. Per i modelli
Simulink `.slx`, non serve necessariamente MATLAB per ispezionarli: sono
archivi zip, apribili ed esplorabili nell'XML interno con Python
(`python -c "import zipfile; zipfile.ZipFile('modello.slx').extractall('cartella')"`
poi si legge l'XML sotto `simulink/stateflow/chart_*.xml` e simili) — è così
che si è trovato, senza aprire MATLAB, che il modello richiede variabili
`Simulink.Parameter` chiamate esattamente `Np`/`Nc` nel workspace base.

## Tono

Italiano, diretto, tecnico, senza fronzoli. Istruzioni date in blocco, non
passo-passo con conferma a ogni riga minima. Quando una conclusione
precedente risulta sbagliata, si corregge per iscritto nello stesso
documento invece di farla sparire silenziosamente.
