# Provenienza di questa cartella

Copia di studio di [`emaema23/MPSoC-for-CACC`](https://github.com/emaema23/MPSoC-for-CACC)
(GitHub), commit `acd7b03` (precedente pull: `2f61735`, sostituito il
2026-08-03 perché mancava il modello Simulink e sono state fatte modifiche
a monte), scaricata il 2026-08-03.

**Nessun file `LICENSE` nel repo sorgente**, confermato di nuovo su questo
pull. Il `README.md` originale (lasciato intatto in questa cartella) lo
descrive come "la repo per i tesisti" — materiale didattico interno, non un
progetto open source con termini di riuso dichiarati. Trattarlo di
conseguenza: **materiale di riferimento e studio, non redistribuire oltre
questo repo senza verificare con Emanuele**, sullo stesso principio già
applicato ai board file Vivado PYNQ-Z1 in `HDL_Test/Prova_2/hdlplugins/`
(vedi `board_files_manifest.m`).

**Questa copia non va modificata.** Il sorgente autorevole resta il repo
GitHub originale; se qualcosa qui va corretto o aggiornato, si rifà il pull
da lì, non si edita a mano. (Regola violata due volte nel pull precedente —
vedi cronologia commit di questo file/cartella. Se serve testare un fix, farlo
in `MPC/wip_DAR/` o `MPC/wip_CAR/`, non qui.)

## Cosa è cambiato rispetto al pull precedente (commit `2f61735` → `acd7b03`)

| | Prima (`2f61735`) | Ora (`acd7b03`) |
|---|---|---|
| Modello Simulink | **assente** | **presente**: `CAccEma_v3_NMPC_MPSoC_2023b.slx` (~780 KB) |
| `main_Controller_NMPC.m` | `model = 'CAccEma_v3_NMPC_ARM_2023b'` | `model = 'CAccEma_v3_NMPC_MPSoC_2023b'` — aggiornato per combaciare col nuovo file |
| `GPCADMM_NL_Setup.m` | — | **invariato byte per byte** (a parte fine riga) |
| `TestBenchPar_NL.mat` | — | **invariato** (stesso SHA-256) |
| `Traces For Git/` | 12 file | **invariati** |
| `README.md` | — | due righe in più: ordine di esecuzione (`main_Controller_NMPC.m` chiama `GPCADMM_NL_Setup.m`) e nota sul ciclo `for` commentato |

**Il bug `Simulink.Parameter` segnalato (vedi `wip_DAR/`) non è stato
corretto**: `GPCADMM_NL_Setup.m` è identico, `N2 = Np;` c'è ancora invece di
`N2 = Np.Value;`. La segnalazione a Emanuele resta valida.

## Cosa contiene ora

| File | Cosa fa |
|---|---|
| `README.md` | istruzioni originali (ordine di esecuzione, percorso dati da configurare a riga 45 di `main_Controller_NMPC.m`) |
| `CAccEma_v3_NMPC_MPSoC_2023b.slx` | **il modello Simulink del controllore** — prima assente, ora disponibile per lo studio |
| `GPCADMM_NL_Setup.m` | setup offline del GPCADMM non lineare: matrici di peso, vincoli, parametri ADMM |
| `main_Controller_NMPC.m` | harness di test MIL/PIL: carica il modello, itera sugli scenari in `Traces For Git/`, salva `AccCmd` |
| `TestBenchPar_NL.mat` | parametri del banco di prova (`m_ego`, `Ts`, ...) |
| `Traces For Git/*.mat` | tracce di scenario per il test PIL, una per combinazione di orizzonte di predizione (`Np`) e decelerazione (`Dec`) |
