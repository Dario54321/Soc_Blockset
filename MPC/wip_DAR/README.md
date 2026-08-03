# MPSoC-for-CACC
La repo per i tesisti.

Questo dovrebbe essere il minimo per partire, fatemi sapere se trovate problemi.

Per configurare il modello, dovresti runnare prima main_Controller_NMPC.m, che richiamerà GPCADMM_NL_Setup.m

in particolare, in main_Controller_NMPC.m vi è un ciclo for che ho commentato per poter analizzare la singola simulazione. Potete anche de-commentarlo, basta che non committiate

MOLTO IMPORTANTE
in questa repo ho caricato delle simulazioni per le varie run di test. Nel git troverete la cartella "Traces For Git" che le conterranno. Un volta installata la repo da git sul vostro pc, dovete andare alla riga 45 del file "main_Controller_NMPC.m" e immettere il percorso su dove scaricherete le traccie, altrimenti non funziona
