# MPC — l'algoritmo vero, non il trasporto

Cartella per il lavoro sull'**MPC reale** del progetto: la formulazione, le
formule, il modello Simulink e la sua eventuale conversione per SoC Blockset.

**Perimetro diverso da `HDL_Test/Prova_2/`**: quel filone tratta il calcolo
MPC come un blocco di terzi e si occupa solo del trasporto ARM↔FPGA attorno
ad esso. Qui invece si lavora sull'algoritmo stesso.

## Riferimento

[`Paper_MPC.pdf`](Paper_MPC.pdf) — "Fast Constrained
Generalized Predictive Control with ADMM Embedded in an FPGA" (Peccin, Lima,
Flesch, Normey-Rico, IEEE Latin America Transactions 2020): fonte da cui sono
prese le formule (GPC + ADMM, GPCADMM). **È materiale metodologico, non la
formulazione finale**: l'MPC reale del progetto è un'istanza diversa, ancora
da ricevere (file Simulink), e va confrontato da zero con quanto descritto
nel paper, non assunto identico.

## Struttura

```
MPC/
  CONVENZIONI.md  regole di lavoro stabili per questo filone
  wip_DAR/        lavoro in corso di Dario — non ancora integrato
  wip_CAR/        lavoro in corso di Carmine — non ancora integrato
  MPC_Emanuele/   copia di studio di un repo esterno — vedi PROVENIENZA.md, non modificare
```

**Un quarto posto, fuori da questo repo, dove succede il lavoro vero ora**:
vedi [`wip_DAR/RIPRESA_MPC.md`](wip_DAR/RIPRESA_MPC.md) — topologia
completa, non ripetuta qui.

`MPC_Emanuele/` è un caso a parte rispetto a `wip_*`: non è lavoro nostro,
è materiale di riferimento importato da un repo esterno (Emanuele, "la repo
per i tesisti" — CACC/NMPC via GPCADMM). Nessuna licenza dichiarata nella
fonte: dettagli e limiti d'uso in
[`MPC_Emanuele/PROVENIENZA.md`](MPC_Emanuele/PROVENIENZA.md).

Le due sottocartelle sono aree di lavoro individuali, isolate perché due
persone toccano lo stesso argomento in parallelo. Quando qualcosa è stabile
e condiviso, si promuove in `MPC/` (root di questa cartella), non resta
disperso nelle sottocartelle di lavoro.

**Branch.** Per lavoro non banale, si isola anche a livello di branch git
(es. `mpc-dario`, `mpc-carmine`) e si merge in `main` quando pronto — le
sottocartelle evitano conflitti di file mentre si è ancora su `main` o su
branch condivisi, i branch evitano di sporcare la storia di `main` con lavoro
non finito. Non sono due meccanismi ridondanti: le sottocartelle sopravvivono
anche dopo il merge, come traccia di chi ha esplorato cosa — vedi come
`prove_2/` (esplorazione di un singolo) convive con `HDL_Test/Prova_2/`
(filone principale) nel resto del repository.
