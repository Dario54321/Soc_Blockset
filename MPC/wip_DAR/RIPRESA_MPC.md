# Ripresa — filone MPC

*(2026-08-04. Questo file = punto d'ingresso per riprendere il lavoro sul
filone MPC in una chat nuova. NON è la procedura generale di lavoro — quella
sta in [`../CONVENZIONI.md`](../CONVENZIONI.md) — e NON duplica lo stato
tecnico, che sta in [`STATO.md`](STATO.md). Questo file collega i pezzi.)*

## Topologia — tre posti diversi, non confonderli

| Cosa | Dove | Ruolo |
|---|---|---|
| **`Soc_Blockset`** (questo repo) | `C:\Users\lenovo GAME\Desktop\Prove`, branch `main` | Home base. `MPC/` qui dentro contiene la documentazione del filone e `wip_DAR/` come area di sperimentazione. Contiene anche `HDL_Test/Prova_2/` — **filone completamente separato** (esercizio pratico di Dario sul flusso SoC Blockset, non il progetto MPC — non mescolare i due). |
| **`MPC_Emanuele/`** | dentro `Soc_Blockset`, `MPC/MPC_Emanuele/` | Snapshot di sola lettura del repo di Emanuele. Mai modificarlo — vedi `PROVENIENZA.md` lì dentro. |
| **`MPSoC-for-CACC-Dario`** | `C:\Users\lenovo GAME\Desktop\MPSoC-for-CACC-Dario` (repo git separato, **fuori** da `Soc_Blockset`) | **Il lavoro vero succede qui**, da quando Emanuele ha dato a Dario accesso in scrittura al suo repo. Clone reale, branch `Dario` (traccia `origin/Dario`). Push qui non toccano mai `main` di Emanuele finché non c'è un merge esplicito. |

`wip_CAR/` (dentro `Soc_Blockset`, area di Carmine) è **vuota** — solo un
README segnaposto, nessun lavoro ancora iniziato lì.

## Stato tecnico — leggi questi due file, in ordine

1. [`STATO.md`](STATO.md) — i tre bug trovati e risolti (`DataDir`, il bug
   `Simulink.Parameter`, il vincolo sui nomi `Np`/`Nc` nel modello), **verificati
   con un run completato** in `wip_DAR/`. Legge da qui i dettagli tecnici,
   non ripetuti in questo file.
2. Confronta con lo stato di `MPSoC-for-CACC-Dario`: **quel clone è rimasto
   indietro**. Ha il fix dell'Inf-a-`t=0` (Emanuele l'ha pushato lì
   direttamente, commit `e67fb77`, usando `getsamples(...,2:end)` per
   scartare il primo campione da tutti e quattro i segnali — tecnica diversa
   da quella discussa in `wip_DAR` ma stesso risultato). **Non ha** il fix
   `.Value` di `GPCADMM_NL_Setup.m` né `DataDir`/`addpath` — quei tre restano
   solo nella copia `wip_DAR/`, mai portati nel clone vero.

## Azioni pendenti, in ordine

1. **Portare i fix mancanti in `MPSoC-for-CACC-Dario`**: il fix `.Value` in
   `GPCADMM_NL_Setup.m` (riga 14, vedi `STATO.md` §2) si copia identico. Il
   fix `DataDir`/`addpath` **non va copiato letteralmente** — nel clone deve
   puntare alla `Traces For Git/` **di quel clone**
   (`C:\Users\lenovo GAME\Desktop\MPSoC-for-CACC-Dario\Traces For Git`), non
   al percorso di `wip_DAR` — dettaglio in `STATO.md`, sezione finale. Poi
   far girare `main_Controller_NMPC.m` da lì per confermare che il run
   completa anche nel clone vero, non solo nella copia di prova. Poi commit
   + push sul branch `Dario`.
2. **Ispezionare `Traces For Git/AccCmdSingleOut_Dec3.mat`** (prodotto dal
   run completato in `wip_DAR/`) per vedere se il comando di accelerazione
   ha senso — non ancora fatto.
3. **Verificare/segnalare a Emanuele il bug `Simulink.Parameter`** — non è
   chiaro se ne abbia già parlato lui e Dario nella call o se sia ancora da
   comunicare. Testo pronto in
   [`SEGNALAZIONE_EMANUELE.md`](SEGNALAZIONE_EMANUELE.md), non ancora
   inviato.
4. Capire, guardando le chart Stateflow del modello (non ancora fatto), se
   `H`/`H̃`/la sua inversa vengono ricalcolate a ogni campione (coerente con
   `_NL_` = non lineare) o con qualche altro schema — collegamento con le
   formule del paper di riferimento (`../Paper_MPC.pdf`), non ancora chiuso.

## Modi di lavoro e tono

Vedi [`../CONVENZIONI.md`](../CONVENZIONI.md) — vincolante, leggerlo per
intero prima di agire. Non riassunto qui apposta, per non avere due versioni
da tenere allineate.

## Istruzioni per chi riprende in una chat nuova

Ricostruisci lo stato leggendo, in questo ordine: questo file →
[`STATO.md`](STATO.md) → [`../CONVENZIONI.md`](../CONVENZIONI.md) →
[`../README.md`](../README.md) (per il quadro generale del filone) →
`MPC_Emanuele/PROVENIENZA.md` (per la provenienza del materiale esterno).
Non dare per scontato che le azioni pendenti sopra siano ancora valide così
come scritte: verifica lo stato reale (`git log`/`git status` in entrambi i
repo, contenuto attuale dei file citati) prima di agire, specialmente se è
passato tempo — Emanuele pusha in autonomia sul suo repo.

Poi **riporta** all'utente: stato attuale, azione pendente concreta,
collocazione (quale dei tre posti sopra), modi di lavoro, e conferma di aver
capito il tono. **Fermati e aspetta conferma** prima di agire.
