# Confronto: paper GPCADMM vs codice `MPC_Emanuele` (CACC/NMPC)

Analisi riga per riga di [`GPCADMM_NL_Setup.m`](../MPC_Emanuele/GPCADMM_NL_Setup.m)
e [`main_Controller_NMPC.m`](../MPC_Emanuele/main_Controller_NMPC.m) contro
[`../Paper_MPC.pdf`](../Paper_MPC.pdf) ("Fast Constrained Generalized
Predictive Control with ADMM Embedded in an FPGA", Peccin et al., 2020).
**Analisi statica**: il modello Simulink vero (`CAccEma_v3_NMPC_ARM_2023b.slx`)
manca, quindi alcune conclusioni sono ipotesi da confermare quando arriva —
segnalate esplicitamente come tali.

---

## 1. Sintesi

Il codice implementa **lo stesso schema algoritmico del paper** (GPC + ADMM,
proiezione sui vincoli, dual update) ma lo applica a un problema strutturalmente
diverso: non un SISO lineare stazionario, ma un **MIMO non lineare** (CACC —
Cooperative Adaptive Cruise Control, inseguimento di un veicolo leader). Il
nome dei file (`_NL_`, `main_Controller_NMPC`) lo dichiara esplicitamente. La
differenza non è cosmetica: è il motivo per cui, a differenza del paper, qui
**non tutto può essere precalcolato offline** — punto che condiziona qualunque
scelta di accelerazione hardware si farà su questo progetto (vedi §5).

---

## 2. Mappa dei simboli: paper → codice

| Paper | Codice | Valore/nota |
|---|---|---|
| `Nu` (orizzonte di controllo) | `Nc` | **non fisso**: `Nc = 5` se `Np*0.1 ≤ 5`, altrimenti `Nc = Np*0.1` (vedi §4.3) |
| `N` = `N2-N1+1` (orizzonte di predizione) | `Np` (dopo riassegnazione, riga 20) | testato con `Np ∈ {15,20,25,30,35}`, nel run effettivo `Np=35` |
| `Qδ`, `Qλ` | `Q_delta`, `R_lambda` | diagonali a blocchi, stessa struttura del paper |
| `R̄`, `r̄` | `R_vincolo`, (`r_du_block`+`r_acc_static`) | stessa forma generica `R̄Δu ≤ r̄`, vedi §4.2 |
| `ρ` | `rho` | **1.0** nel codice, **50** nel case study del paper — problemi diversi, non è un refuso |
| `jmax` (cap iterazioni) | `N_iter = 20` | nel paper il caso peggiore osservato è 33 iterazioni — vedi §4.4 |
| `y ∈ R^N`, `Δu ∈ R^Nu` (SISO) | generalizzazione MIMO, `no=3` uscite (§II del paper, eq. 7-9) | nel codice: `ny=3`, `nu=1` |
| `G ∈ R^(N×Nu)`, `f ∈ R^N` | `G_0`, `F_0` | qui **allocati a zero** (`Np*3 × Nc`, `Np*3 × 3`), non calcolati offline — vedi §5 |
| `H̃⁻¹` precalcolata offline (`H̆`) | **assente da questo file** | coerente con "NL": va ricalcolata online, vedi §5 |

---

## 3. Cosa il codice eredita esattamente dal paper

- **Struttura del vincolo**: `R_vincolo = [eye(Nc); -eye(Nc); Tril_mat; -Tril_mat]`
  è un'istanza concreta della forma generica `R̄Δu ≤ r̄` che il paper descrive
  a parole ("vincoli di magnitudine, tasso di variazione..." fine sez. II) ma
  non mostra mai con questo dettaglio implementativo. La parte `Tril_mat`
  (matrice triangolare inferiore di 1) è il trucco standard per esprimere un
  vincolo sul valore assoluto di `u` quando il QP è scritto in `Δu`: sommando
  cumulativamente gli incrementi si ricostruisce la traiettoria di `u`
  rispetto a `u(k-1)`.
- **Adimensionalizzazione**: `s_u=400` (coppia massima) usato per scalare
  vincoli e presumibilmente segnali — la stessa raccomandazione di normalizzare
  ingresso/uscita fatta dal paper (§V.A) per rendere l'aritmetica a virgola
  fissa praticabile con poca dinamica.
- **Filosofia dei pesi**: `Q_delta_diag = [1; 400; 0.1]` ripetuto sull'orizzonte,
  stessa struttura a blocchi diagonali di `Qδ` nel paper (eq. 2/5), qui con
  peso molto più alto (400) su una delle tre componenti di stato — quasi
  certamente l'errore di velocità, coerente con le priorità tipiche del CACC
  (string stability: l'errore di velocità va tenuto stretto più di quello di
  posizione).

---

## 4. Le estensioni reali rispetto al paper

### 4.1 — MIMO invece di SISO

Il paper deriva il caso SISO per esteso e liquida il caso MIMO in un paragrafo
a fine sezione II. Il codice è MIMO da subito (`ny=3`), usando esattamente la
struttura a blocchi che il paper accenna (`Gpl`, `f^(p)`, eq. 7-9) ma non
sviluppa in un esempio.

### 4.2 — Vincoli anche sul valore assoluto di `u`, non solo su `Δu`

Il case study del paper (sez. VI) usa **solo** vincoli su `Δu` (`nrin=2·Nu=10`
con `Nu=5`). Il codice aggiunge anche vincoli assoluti su coppia (`u_max`,
`u_min = ±400 Nm`, quindi `±1.0` normalizzato) via `Tril_mat`, portando
`R_vincolo` a `4·Nc` righe. È un uso più completo della stessa formulazione
generica — non richiede modifiche all'algoritmo ADMM, solo un `R̄`/`r̄` più
grandi.

**Nota**: il vettore `r̄` completo (concatenazione di `r_du_block` due volte
più `r_acc_static`) non compare in questo file — deve essere assemblato altrove
(nel modello Simulink mancante, o in codice non incluso in questa copia).

### 4.3 — `Nc` legato a `Np`, non un parametro indipendente

Nel paper `Nu` è una scelta di progetto fissa, indipendente da `N`. Qui
`Nc = f(Np)` (soglia a `Np*0.1`, minimo 5) — l'orizzonte di controllo scala
con quello di predizione. Non è spiegato nel codice **perché**; è plausibile
che serva a mantenere un rapporto ragionevole fra i due orizzonti quando si
esplorano `Np` diversi (15→35) nello studio di sensibilità che
`main_Controller_NMPC.m` fa girare.

**Comportamento concreto per il run effettivo**: `main_Controller_NMPC.m` usa
`i = numel(NpRange)` con `NpRange = 15:5:35`, quindi **solo l'ultimo valore,
`Np=35`**, viene davvero eseguito (il ciclo `for i=1:numel(NpRange)` è commentato
riga per riga, resta solo l'ultima iterazione). Con `Np=35`: `35*0.1=3.5 ≤ 5`
→ **`Nc=5`**. Questo sovrascrive silenziosamente l'`Nc.Value=3` che
`main_Controller_NMPC.m` aveva impostato poco prima come `Simulink.Parameter`
— stesso meccanismo del bug già segnalato (script, non funzione, workspace
condiviso). Vale la pena aggiungerlo alla segnalazione a Emanuele: **`Nc=3`
impostato a monte non ha mai effetto**, per qualunque `Np` nel range dato
(`Np*0.1` è sempre ≤ 5 per `Np≤50`).

### 4.4 — `N_iter=20` fisso, non convergenza verificata

Il paper usa un criterio di stop sui residui (`εp`, `εd`) con `jmax` come
**tetto di sicurezza**, e osserva un caso peggiore di 33 iterazioni. Nel
codice `N_iter=20` è l'unico parametro ADMM di iterazione visibile in questo
file, senza tracce di soglie di residuo (`epsilon_p`/`epsilon_d` non
compaiono). Due letture possibili, da verificare col modello:

1. È un tetto fisso, e il criterio di convergenza vero vive nel modello
   Simulink (fedele al paper, solo non visibile qui).
2. È una scelta deliberata di **iterazioni fisse, sempre eseguite tutte**,
   più coerente con l'obiettivo dichiarato dal paper stesso (determinismo,
   WCET prevedibile — §I) portato all'estremo: se il numero di iterazioni
   non dipende dai dati, il tempo di esecuzione è costante per costruzione,
   non solo limitato superiormente.

Se è la (2), è un irrigidimento rispetto al paper ma coerente con la sua
stessa motivazione — e toglierebbe di mezzo qualunque ambiguità sul WCET.

---

## 5. Il punto architetturale chiave: perché qui serve calcolo online

Il vantaggio computazionale centrale del paper è che, per un impianto
**lineare stazionario**, `H`, `H̃` e soprattutto `H̆ = H̃⁻¹` si calcolano **una
volta sola, offline**: a runtime resta solo `Δu = -H̆·b̃`, una moltiplicazione
matrice-vettore, mai un'inversione.

In `GPCADMM_NL_Setup.m` non c'è **nessuna traccia di `H`, `H̃` o della sua
inversa** — solo l'allocazione a zero di `F_0`/`G_0`. Per un impianto non
lineare (`_NL_`), `G` e `f` dipendono dal punto di funzionamento corrente e
**non possono essere fissati una volta per tutte**: vanno ricalcolati (o
almeno riaggiornati) a ogni campione, il che nella maggior parte degli schemi
di questo tipo (successive linearization / real-time iteration) implica
ricalcolare anche `H`, `H̃` e la sua inversa **online**.

**Correzione (03/08)**: nella prima stesura qui si ipotizzava un collegamento
diretto con `HDL_Test/Prova_2` (il blocco "inversione 3×3"). **Errato**:
`Prova_2` è un esercizio a parte, fatto per imparare il flusso SoC Blockset —
non fa parte di questo progetto e non va usato come riferimento per
dimensioni, budget o scelte architetturali dell'MPC vero. Il punto tecnico
resta comunque valido in astratto (per un impianto non lineare l'inversione
non può essere offline, e questo è presumibilmente il motivo per cui servirà
accelerazione hardware anche qui) — ma le dimensioni, i tempi e i vincoli
vanno ridefiniti da zero su questo progetto, senza ereditare nulla da
`Prova_2`.

---

## 6. Bug/anomalie già trovate nel codice di Emanuele

| Cosa | Dove | Effetto | Segnalato? |
|---|---|---|---|
| `Np` passato come `Simulink.Parameter` invece che come numero | `main_Controller_NMPC.m` → `GPCADMM_NL_Setup.m` riga 15 | `Operator '*' is not supported for operands of type 'Simulink.Parameter'` | ✅ report preparato, in attesa di girarlo a Emanuele |
| `Nc.Value=3` impostato a monte, mai usato | idem, §4.3 di questo documento | `Nc` diventa sempre 5 per `Np≤50`, silenziosamente | ⬜ da aggiungere alla stessa segnalazione |

---

## 7. ~~Ipotesi sul budget dei 33 µs~~ — rimossa, non pertinente

La prima stesura di questa sezione confrontava un numero preso da
`HDL_Test/Prova_2` (33 µs) con le 33 iterazioni del case study del paper.
Rimossa: `Prova_2` è un esercizio separato, i suoi numeri non sono un
riferimento per questo progetto. Se e quando questo progetto avrà un suo
budget di ciclo dichiarato, andrà verificato per conto proprio, non per
somiglianza con un numero di un altro lavoro.

---

## 8. Cosa resta non verificabile senza il modello

- Se `H`/`H̃`/`H̆` sono davvero ricalcolate online o se esiste una qualche
  linearizzazione periodica invece che per-campione.
- Come viene assemblato il vettore `r̄` completo.
- Se `N_iter=20` è un tetto o un numero fisso di iterazioni sempre eseguite.
- Il criterio di arresto (`εp`/`εd`), se esiste nel modello.
- Cosa rappresentano esattamente le tre componenti di stato pesate
  `[1; 400; 0.1]` (ipotesi: posizione/velocità/altro — da confermare).

## 9. Domande da fare a Emanuele

1. `H̃`/`H̆` si ricalcolano davvero a ogni campione, o c'è una qualche forma
   di precompute (es. gain scheduling su un set di punti di linearizzazione)?
2. Qual è il budget di ciclo reale per questo controllore (sampling time,
   tempo massimo di calcolo per campione) — non assunto da altro, dichiarato
   per questo progetto.
