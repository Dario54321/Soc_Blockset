# Segnalazione per Emanuele — bug `Simulink.Parameter` in `GPCADMM_NL_Setup.m`

*(Preparata 2026-08-03/04. Stato: non è chiaro se comunicata a voce nella
call con Emanuele del 2026-08-03 — verificare con Dario prima di rimandarla,
per non duplicare.)*

Testo pronto da inviare:

---

Ciao Emanuele,

girando `main_Controller_NMPC.m` da un clone pulito del repo (con `DataDir`
impostato come da istruzioni nel README), ottengo questo errore:

```
Operator '*' is not supported for operands of type 'Simulink.Parameter'.

Error in GPCADMM_NL_Setup (line 15)
if N2*0.1 <= 5

Error in main_Controller_NMPC (line 26)
GPCADMM_NL_Setup;
```

**Causa**: in `main_Controller_NMPC.m`, prima della chiamata a
`GPCADMM_NL_Setup`, `Np` viene creato come oggetto `Simulink.Parameter`:

```matlab
Np = Simulink.Parameter;
Np.Value = NpRange(i);
Np.CoderInfo.StorageClass = 'Auto';
```

`GPCADMM_NL_Setup` è uno script (non una function), quindi gira nello stesso
workspace ed eredita quell'oggetto. Alla riga 14 fa:

```matlab
N2 = Np;
```

invece di `N2 = Np.Value;` — quindi `N2` è l'oggetto `Simulink.Parameter`,
non il numero, e la riga successiva (`N2*0.1`) fallisce. Stesso problema
esiste per `Nc` (creato anch'esso come `Simulink.Parameter` prima della
chiamata), solo che non ci si arriva perché lo script si ferma prima.

**Fix locale che ho verificato funzionare** (per la sola simulazione MIL):
dentro `GPCADMM_NL_Setup.m`, riga 14, cambiare in `N2 = Np.Value;`. Con
questo unico cambio lo script arriva in fondo — l'ho testato con un run
completo, produce `AccCmd` in uscita. Effetto collaterale da sapere: più
avanti nello stesso script `Np`/`Nc` vengono riassegnati a numeri semplici
(`Np = N2 - N1 + 1;` e il calcolo di `Nc`), quindi perdono il wrapping
`Simulink.Parameter` — per la sola simulazione non sembra avere conseguenze
(le chart Stateflow del modello leggono `Np`/`Nc` dal workspace per nome, e
un numero semplice funziona quanto un oggetto), ma se in futuro serve
generare codice trattandoli come parametri tunabili va ripristinato il
wrapping dopo la chiamata a `GPCADMM_NL_Setup`, non prima.

**Domanda per te**: era pensato così, o è una svista? Se conta anche per la
generazione di codice, forse ha più senso spostare tu il wrapping
`Simulink.Parameter` dopo la chiamata a `GPCADMM_NL_Setup` invece che dentro
lo script di setup.

Grazie!

---

**Nota aggiuntiva, non ancora inclusa nel testo sopra**: `Nc.Value = 3`
impostato in `main_Controller_NMPC.m` prima della chiamata non ha mai
effetto — `GPCADMM_NL_Setup` lo ricalcola sempre (a `5`, per qualunque `Np`
nel range `15:5:35` usato nello script). Vale la pena menzionarlo insieme al
resto se non ne avete già parlato.
