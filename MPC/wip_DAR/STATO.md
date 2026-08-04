# wip_DAR — cosa c'è e stato attuale

*(Aggiornato 2026-08-04. Per le convenzioni stabili di questo filone vedi
[`../CONVENZIONI.md`](../CONVENZIONI.md); questo file è solo lo stato del
momento.)*

## Cosa c'è nella cartella

| File | Cosa è |
|---|---|
| `README.md` | testo originale di Emanuele (istruzioni di setup) |
| `main_Controller_NMPC.m` | copia **modificata e funzionante** — vedi sotto |
| `GPCADMM_NL_Setup.m` | copia **modificata e funzionante** — vedi sotto |
| `CAccEma_v3_NMPC_MPSoC_2023b.slx` | copia del modello — **non identica a `MPC_Emanuele/`**: hash diverso, quasi certamente perché `main_Controller_NMPC.m` chiama `save_system(model)` durante il run e Simulink lo risalva. Già committata così (`git log` non mostra modifiche dopo). Nessun problema noto causato da questo, solo da sapere. |
| `TestBenchPar_NL.mat` | copia dei parametri del banco di prova, invariata |
| `Traces For Git/` | le 12 tracce di scenario originali, **più due file di
  output prodotti da un run completato** (`AccCmdSingleOut_Dec3.mat`,
  `ExSimSigDouble.mat`) — non ancora committati, da decidere se versionarli
  o no |
| `PROVENIENZA.md` | provenienza del materiale (repo di Emanuele) |
| `STATO.md` | questo file |
| `RIPRESA_MPC.md` | router per riprendere il lavoro in una chat nuova |
| `PROMPT_RIPRESA.txt` | il prompt di ripresa pronto da incollare |
| `SEGNALAZIONE_EMANUELE.md` | testo pronto della segnalazione del bug `Simulink.Parameter`, non ancora inviato |

`MPC_Emanuele/` resta la copia di riferimento non modificata — questa
cartella (`wip_DAR/`) è dove si sperimenta.

## I tre problemi trovati — stato: risolti qui, verificato con un run completo

### 1. `DataDir` non impostato — risolto

`main_Controller_NMPC.m` riga 45, valorizzato:
```matlab
DataDir = 'C:\Users\lenovo GAME\Desktop\Prove\MPC\wip_DAR\Traces For Git';
```
più un `addpath('C:\Users\lenovo GAME\Desktop\Prove\MPC\wip_DAR')` prima del
`cd(DataDir)`, altrimenti una seconda `load_system(model)` più avanti nello
script non trova più il modello (la cartella corrente è cambiata, e non era
mai stata aggiunta al path in modo permanente).

### 2. Bug `Simulink.Parameter` — aggirato, non risolto a monte

`main_Controller_NMPC.m` crea ancora `Np`/`Nc` come `Simulink.Parameter`
**prima** di chiamare `GPCADMM_NL_Setup` (che gira nello stesso workspace,
essendo uno script). Il fix applicato qui è **dentro `GPCADMM_NL_Setup.m`**,
riga 14:
```matlab
N2 = Np.Value;   % era N2 = Np;
```
Per la sola simulazione (MIL) funziona: dopo questa riga `GPCADMM_NL_Setup`
riassegna comunque `Np`/`Nc` a numeri semplici (righe successive), quindi il
wrapping `Simulink.Parameter` iniziale si perde — ma le chart Stateflow del
modello leggono `Np`/`Nc` dal workspace per nome, e un numero semplice va
bene quanto un oggetto per la sola simulazione (il wrapping serve solo per
la generazione di codice, non usata qui). **Non corretto a monte**: nel repo
di Emanuele (`MPSoC-for-CACC`, branch `Dario`) c'è ancora `N2 = Np;` senza
`.Value` — testo di segnalazione pronto in
[`SEGNALAZIONE_EMANUELE.md`](SEGNALAZIONE_EMANUELE.md), **non ancora
inviato** (Dario ha parlato con Emanuele in call, ma su questo bug specifico
non è chiaro se sia stato comunicato o dimenticato — verificare prima di
rimandarla, per non duplicare).

### 3. Vincolo sui nomi `Np`/`Nc` nel modello — confermato, rispettato

Trovato ispezionando l'XML dentro `.slx` (è uno zip): due Stateflow chart si
aspettano variabili chiamate esattamente `Np`/`Nc` nel workspace base. Il fix
del punto 2 li lascia con questi nomi (anche se non più `Simulink.Parameter`
alla fine — vedi sopra), quindi va bene.

## Verificato con un run reale

Con questi tre fix, `main_Controller_NMPC.m` è arrivato in fondo: esistono
`Traces For Git/AccCmdSingleOut_Dec3.mat` e `Traces For Git/ExSimSigDouble.mat`,
prodotti dallo script stesso a fine simulazione (`save(...)` alle ultime
righe). **Non ancora ispezionato il contenuto** (se `AccCmd` ha valori
sensati, se il controllore si comporta come atteso).

## Cosa NON è ancora stato fatto

- **Il clone `MPSoC-for-CACC-Dario` (fuori da questo repo, vedi
  [`RIPRESA_MPC.md`](RIPRESA_MPC.md)) è rimasto indietro**: ha il fix
  dell'Inf di Emanuele (lui l'ha pushato lì direttamente) ma **non** ha
  ancora il fix `.Value` di `GPCADMM_NL_Setup.m` né `DataDir`/`addpath` —
  quei fix esistono solo qui, mai portati là. È il prossimo passo naturale.
  **Attenzione a non copiare il percorso letteralmente**: `DataDir` e
  `addpath` qui puntano a `...\Soc_Blockset\MPC\wip_DAR\...` — nel clone
  vanno puntati alla `Traces For Git/` **di quel clone** (che esiste già lì,
  ha già i suoi 12 file), es.
  `C:\Users\lenovo GAME\Desktop\MPSoC-for-CACC-Dario\Traces For Git`, non il
  percorso di questa cartella.
- Il contenuto di `AccCmdSingleOut_Dec3.mat` non è stato guardato.
- Non è stato controllato se il bug `Simulink.Parameter` è stato comunicato
  a Emanuele nella call — vedi `SEGNALAZIONE_EMANUELE.md`.
