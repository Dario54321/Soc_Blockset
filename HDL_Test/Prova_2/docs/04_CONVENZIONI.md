# Convenzioni di progetto

Regole vincolanti. Cambiarle richiede una giustificazione scritta, come le decisioni.

---

## R1 · Compatibilità release: i modelli versionati sono sempre R2023b

**Regola.** Qualunque release si usi per lavorare (R2025b, R2026a), ogni `.slx` che
finisce sotto controllo di versione deve essere **salvato in formato compatibile
R2023b** prima del commit.

**Perché.** Il repo è condiviso con chi lavora in R2023b, e l'aggiornamento di formato
di un `.slx` è **irreversibile**: una volta salvato con una release più recente il file
non si riapre più con quella vecchia. Un solo commit distratto blocca l'altro
sviluppatore, e il danno si scopre a valle.

**Come si applica.**
```matlab
run('scripts/export_r2023b.m')      % prima di ogni commit che tocca dei .slx
```
Lo script esporta **in place** tutti i `.slx` di `models/` con
`Simulink.exportToVersion(..., 'R2023B')`. Se un modello non è esportabile
(usa un blocco o una feature che in R2023b non esiste) **si ferma con errore e lo
dice**: non salta in silenzio. Quel caso va risolto scegliendo un costrutto
equivalente disponibile in R2023b, non ignorando l'avviso.

**Corollario.** Non introdurre volontariamente blocchi o feature posteriori a R2023b
senza prima verificare che il progetto possa davvero rinunciare alla compatibilità.

---

## R2 · Una decisione, un posto solo

Se due file possono definire la stessa cosa, uno dei due è di troppo.
Dimensioni, formati numerici, `Ts` e offset dei registri stanno **solo** in
`scripts/soc_params.m`; da lì si generano gli altri lati (header C, decode HW, parametri
dei blocchi). Mai copie sincronizzate a mano — è così che è nato il disallineamento
fra `.slx` e Verilog in `Prova_1`.

## R3 · Niente hardware prima della simulazione

Quattro gate, in ordine: modello finite-precision vs reference → HDL generato vs
modello finite-precision → simulazione bus-level del wrapper → regressione automatica
con un comando. Nessun salto.

## R4 · Ogni risultato è rigenerabile da script

Un comando per il bitstream, uno per la suite di test. Niente numeri prodotti da
sequenze di clic non registrate. Se un report non si rigenera, non è un risultato.

## R5 · Ogni decisione architetturale si documenta quando si prende

Con l'alternativa scartata e il motivo. Sei decisioni, sei paragrafi. Scritte al
momento della scelta, non ricostruite dopo: le ricostruzioni omettono esattamente le
decisioni che erano difficili.

## R6 · Versioni bloccate

MATLAB e Vivado si fissano all'inizio e **non si aggiornano a metà progetto**.
Stato corrente in `03_AMBIENTE.md`.

---

## R7 · Un gate mai visto fallire non è un gate

Ogni controllo aggiunto a `run_regression.m` va provato **in entrambe le
direzioni**: deve accettare il caso vero **e rifiutare un caso falso.**

Il modo pratico: si copia il progetto in una cartella temporanea, si introduce di
proposito il difetto che il gate dovrebbe intercettare, e si guarda il gate
scattare. Mutazioni già usate e conservate come riferimento:

| Mutazione | Gate che deve scattare |
|---|---|
| `matB` legge `U(1:16)` invece di `U(10:25)` *(il bug storico di Prova_1)* | T4 / T2 |
| `matB` srotolata row-major invece che column-major | T7 |
| ordine di impacchettamento invertito lato ARM | T9 |
| `Register Write` rimosso, segnale grezzo verso il Register Channel | T10 |

**Perché conta.** Nel corso del lavoro un gate è passato su un modello sbagliato
perché controllava la proprietà sbagliata (`ESB.ProcessingUnit` invece di
`ProdHWDeviceType`). Un gate che non è mai stato visto fallire non dimostra nulla:
dimostra solo che qualcosa è vero, non che il controllo funzioni.

---

## R8 · Le scoperte sul toolchain si scrivono con il messaggio d'errore esatto

Ogni errore del toolchain risolto va registrato in
[`11_NOTE_API.md`](11_NOTE_API.md) riportando **il testo esatto del messaggio**,
la causa e la soluzione verificata.

**Perché:** il messaggio esatto è ciò che la prossima persona cercherà — nel file,
o su un motore di ricerca. Una parafrasi non si trova. Molti di questi
comportamenti non sono documentati da MathWorks, e riscoprirli costa ore.
