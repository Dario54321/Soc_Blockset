# Provenienza di questa cartella

Copia di studio di [`emaema23/MPSoC-for-CACC`](https://github.com/emaema23/MPSoC-for-CACC)
(GitHub), commit `2f61735b3cfe41df8a6f68de365133320fa09812`, scaricata il
2026-08-03.

**Nessun file `LICENSE` nel repo sorgente.** Il `README.md` originale (lasciato
intatto in questa cartella) lo descrive come "la repo per i tesisti" — materiale
didattico interno, non un progetto open source con termini di riuso dichiarati.
Trattarlo di conseguenza: **materiale di riferimento e studio, non redistribuire
oltre questo repo senza verificare con Emanuele**, sullo stesso principio già
applicato ai board file Vivado PYNQ-Z1 in `HDL_Test/Prova_2/hdlplugins/`
(vedi `board_files_manifest.m`).

**Questa copia non va modificata.** Il sorgente autorevole resta il repo
GitHub originale; se qualcosa qui va corretto o aggiornato, si rifà il pull
da lì, non si edita a mano.

## Cosa manca in questa copia

`main_Controller_NMPC.m` (riga 29) carica un modello Simulink,
`CAccEma_v3_NMPC_ARM_2023b` — **non presente in questo repo**: solo gli
script di setup/test e i dati di simulazione (`Traces For Git/`) sono
qui. Il modello vero e proprio (dove presumibilmente vivono le formule in
forma eseguibile) va richiesto a parte.

## Cosa contiene

| File | Cosa fa |
|---|---|
| `README.md` | istruzioni originali dell'autore (percorso dati da configurare a riga 45 di `main_Controller_NMPC.m`) |
| `GPCADMM_NL_Setup.m` | setup offline del GPCADMM non lineare: matrici di peso, vincoli, parametri ADMM |
| `main_Controller_NMPC.m` | harness di test MIL/PIL: carica il modello, itera sugli scenari in `Traces For Git/`, salva `AccCmd` |
| `TestBenchPar_NL.mat` | parametri del banco di prova (`m_ego`, `Ts`, ...) |
| `Traces For Git/*.mat` | tracce di scenario per il test PIL, una per combinazione di orizzonte di predizione (`Np`) e decelerazione (`Dec`) |
