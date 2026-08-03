# wip_DAR — cosa c'è e stato attuale

Solo documentazione: elenco e diagnosi, nessuna modifica ai file. Le
modifiche le fai tu.

## Cosa c'è nella cartella

| File | Cosa è |
|---|---|
| `README.md` | testo originale di Emanuele (istruzioni di setup), incollato qui com'era |
| `main_Controller_NMPC.m` | copia identica di `MPC_Emanuele/main_Controller_NMPC.m` — non modificata |
| `GPCADMM_NL_Setup.m` | copia identica di `MPC_Emanuele/GPCADMM_NL_Setup.m` — non modificata |
| `CAccEma_v3_NMPC_MPSoC_2023b.slx` | copia identica del modello — non modificata, non ancora aperta |
| `TestBenchPar_NL.mat` | copia identica dei parametri del banco di prova |
| `Traces For Git/` | copia identica delle 12 tracce di scenario |
| `PROVENIENZA.md` | nota sulla provenienza del materiale (repo di Emanuele, nessuna licenza dichiarata) |
| `STATO.md` | questo file |

Tutto qui è identico a [`MPC_Emanuele/`](../MPC_Emanuele/) — nessun nome
cambiato, nessuna riga toccata. `MPC_Emanuele/` resta la copia di
riferimento, non va comunque modificata neanche lei.

## Problemi noti, non risolti — solo diagnosi

### 1. `DataDir` non impostato

`main_Controller_NMPC.m` riga 45:
```matlab
% DataDir = %modify this row
```
Il README di Emanuele lo segnala come obbligatorio: va valorizzato col
percorso di `Traces For Git/` (qui, o dove preferisci tenerlo), altrimenti
lo script si ferma a `cd(DataDir)` poco dopo.

### 2. Bug `Simulink.Parameter` — riproducibile, causa nota

`main_Controller_NMPC.m` righe 15-21 crea `Np` e `Nc` come oggetti
`Simulink.Parameter` **prima** di chiamare `GPCADMM_NL_Setup` (riga 26).
`GPCADMM_NL_Setup` è uno **script**, non una funzione: gira nello stesso
workspace del chiamante, quindi eredita quell'`Np` come oggetto. Alla riga
14 del file:
```matlab
N2 = Np;        % prende l'oggetto, non il numero — servirebbe Np.Value
if N2*0.1 <= 5  % qui esplode
```
Errore che dà:
```
Operator '*' is not supported for operands of type 'Simulink.Parameter'.
Error in GPCADMM_NL_Setup (line 15)
Error in main_Controller_NMPC (line 26)
```
Stesso problema esiste per `Nc`, non ci si arriva perché lo script si ferma
prima. Segnalato a Emanuele (report preparato in una sessione precedente),
non ancora corretto a monte.

### 3. Vincolo trovato aprendo il modello: `Np`/`Nc` finali devono chiamarsi così

Ho ispezionato `CAccEma_v3_NMPC_MPSoC_2023b.slx` (è un archivio zip,
apribile senza MATLAB: `python -c "import zipfile; zipfile.ZipFile(...).extractall(...)"`)
e letto l'XML interno. Due Stateflow chart hanno dati con
`scope="PARAMETER_DATA"` chiamati **esattamente** `Np` e `Nc`, inizializzati
dal workspace base per nome esatto. Qualunque fix del punto 2 deve **finire**
con oggetti `Simulink.Parameter` chiamati proprio `Np`/`Nc` nel workspace
base — un nome diverso (es. `NpParam`) non verrebbe trovato dal modello.

Altri nomi che il modello si aspetta dal workspace, verificati con lo stesso
metodo: `nu`, `Ts`, `G_0`, `F_0`, `R_vincolo`, `rho`, `N_iter` — tutti già
creati con questi nomi esatti da `GPCADMM_NL_Setup.m` così com'è, nessun
problema lì. Nessun `InitFcn`/`StartFcn` nel modello che carichi altri file
per nome.
