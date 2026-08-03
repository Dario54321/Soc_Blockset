# wip_DAR

Area di lavoro di Dario dentro [`MPC/`](../README.md). Non integrato: quando
qualcosa qui è stabile, si promuove a `MPC/` (root).

## Copie di lavoro (suffisso `_Test`)

Tutti i file di [`MPC_Emanuele/`](../MPC_Emanuele/) copiati qui con suffisso
`_Test` — così non c'è conflitto di nome col path MATLAB quando entrambe le
cartelle sono aggiunte insieme, e si lavora su copie senza mai toccare
l'originale (`PROVENIENZA.md` esclusa: è metadato sulla fonte, non c'è nulla
da "lavorare" lì sopra).

| File qui | Copia di | Modifiche |
|---|---|---|
| `main_Controller_NMPC_Test.m` | `main_Controller_NMPC.m` | `DataDir` valorizzato (locale), chiama `GPCADMM_NL_Setup_Test`/`TestBenchPar_NL_Test.mat`, `Simulink.Parameter` spostato dopo il setup (`NpParam`/`NcParam`) — vedi bug in `confronto_paper_vs_MPC_Emanuele.md` |
| `GPCADMM_NL_Setup_Test.m` | `GPCADMM_NL_Setup.m` | solo il riferimento al `.mat` aggiornato a `_Test` |
| `CAccEma_v3_NMPC_MPSoC_2023b_Test.slx` | stesso file | copia identica, non ancora aperta/verificata |
| `TestBenchPar_NL_Test.mat` | stesso file | copia identica |
| `Traces For Git/` | stessa cartella | copia identica, nomi file interni invariati |
| `README_Test.md` | `README.md` | copia identica, per riferimento |

**Stato**: il modello ora c'è (prima mancava), quindi in teoria eseguibile —
ma nessuno l'ha ancora aperto/lanciato da questa copia. Il bug
`Simulink.Parameter` è aggirato qui; non è chiaro se il modello si aspetti
variabili workspace chiamate esattamente `Np`/`Nc` invece di
`NpParam`/`NcParam` — da verificare al primo run.
