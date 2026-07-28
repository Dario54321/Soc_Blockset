# Prova_2 — test di interfacciamento ARM ↔ FPGA (Zynq-7000 / PYNQ-Z1)

Ricostruzione del test di interfacciamento del progetto, con metodo:
**ogni modello è generato da script, ogni affermazione ha un gate che la verifica,
e ogni gate è stato provato anche in fallimento.**

Propedeutico all'obiettivo finale del progetto: accelerare un MPC sulla PYNQ-Z1.

---

> ### ⚠ Riorientamento in corso
>
> Il bersaglio del progetto è stato precisato dopo la costruzione di questi modelli:
> il payload reale è una **3×1** (12–16 byte, non 25 elementi), il calcolo è dentro
> un **blocco di terzi** che non controlliamo, e il budget d'anello è **33 µs**.
>
> Conseguenza: il trasporto passa da **AXI4-Stream a AXI4-Lite** — con i numeri, non
> per preferenza. Vedi [`docs/13_APERTI.md` §A0](docs/13_APERTI.md) e il nuovo
> [contratto d'interfaccia](docs/20_CONTRATTO_INTERFACCIA.md).
>
> I modelli qui descritti implementano ancora lo stream: restano validi come
> infrastruttura verificata e come seconda implementazione della stessa interfaccia.

## Stato

**Simulazione di sistema completa e verificata.** La catena
ARM → impacchettamento → AXI4-Stream → PL → spacchettamento restituisce le matrici
attese **bit per bit** contro il modello di riferimento.

```
matA : errore max = 0
matB : errore max = 0
sonda: errore max = 0        (LSB del formato = 0.125)
```

| Passo | Stato |
|---|---|
| P0 · ambiente | ✅ R2026a + SoC Blockset + Embedded Coder + 3 support package AMD |
| P1 · specifica congelata | ✅ [`docs/10_SPEC_TEST.md`](docs/10_SPEC_TEST.md) |
| P2 · fonte unica dei parametri | ✅ `scripts/soc_params.m` |
| P3 · reference model + vettori | ✅ 510 vettori, seed fisso |
| P4 · `soc_fpga.slx` | ✅ generato da script |
| P5 · `soc_proc.slx` | ✅ generato da script |
| P6 · `soc_top.slx` — **gate G6** | ✅ struttura a 3 modelli riconosciuta e compilante |
| P7 · simulazione di sistema — **gate G7** | ✅ catena end-to-end bit-esatta |
| P8 · register map | ⬜ |
| P9 · generazione HDL | ⬜ **bloccato da [A1](docs/13_APERTI.md)** |
| P10 · board plugin PYNQ-Z1 | ⬜ |
| P11–P12 · reference design, bitstream | ⬜ **assegnati a Dario** (serve Vivado 2022.1) |
| P13–P16 · software PS, bring-up, misure | ⬜ (serve la board) |

**Prima di proseguire verso l'hardware leggere [`docs/13_APERTI.md`](docs/13_APERTI.md):**
il modello FPGA riceve `tdata` come vettore di 25 elementi, il che funziona in
simulazione ma **non è generabile in hardware**. La soluzione (pattern Variant
Subsystem, lo stesso degli esempi MathWorks) è descritta lì.

---

## Come si usa

```matlab
cd D:\Project_SoC\Soc_Blockset\HDL_Test\Prova_2
addpath('scripts')

p = soc_params();      % configurazione + controlli di coerenza
gen_vectors(p);        % rigenera test/vectors.mat (seed fisso, deterministico)

build_soc_fpga();      % ricostruisce models/soc_fpga.slx da zero
build_soc_proc();      % ricostruisce models/soc_proc.slx da zero
build_soc_top();       % ricostruisce models/soc_top.slx da zero

run_regression;        % PASS/FAIL dell'intera suite (~4 minuti)
run_system_sim;        % solo la simulazione di sistema (~2 minuti)
budget_report;         % quanti cicli restano al blocco di calcolo, per stack PS

export_r2023b();       % REGOLA R1 — prima di ogni commit che tocca .slx
```

I modelli in `models/` (esclusi i `*_ref.slx`) sono **artefatti rigenerabili**:
non si modificano a mano, si modifica lo script che li costruisce.

---

## La suite di regressione

Un comando, 11 gate. **Ognuno è stato verificato anche in fallimento**, con
mutazioni che riproducono difetti reali del progetto.

| Gate | Cosa verifica |
|---|---|
| T1 | `soc_params` è internamente coerente |
| T2 | i controlli **rifiutano** configurazioni sbagliate (partizione sovrapposta, stream a 64 bit, formato sonda insufficiente) |
| T3 | `gen_vectors` è deterministico |
| T4 | il reference model coincide con il cross-check indipendente |
| T5 | copertura delle tre famiglie e range dichiarato |
| T6 | `soc_fpga` compila: rate singolo, tipi, bus |
| T7 | l'algoritmo **dentro** `soc_fpga` == reference, su 510 vettori |
| T8 | `soc_proc` compila |
| T9 | **contratto ARM→FPGA**: pack e unpack sono operazioni inverse |
| T10 | **gate G6**: struttura a 3 modelli, riconosciuta e compilante |
| T11 | **gate G7**: catena end-to-end bit-esatta (simula il sistema completo) |

Mutazioni usate per validare i gate:

| Mutazione | Gate che la prende |
|---|---|
| `matB` legge `U(1:16)` invece di `U(10:25)` — **il bug storico di `Prova_1`** | T4 / T2 |
| `matB` srotolata row-major invece che column-major | T7 |
| ordine di impacchettamento invertito lato ARM | T9 |
| `Register Write` rimosso (segnale grezzo verso il Register Channel) | T10 |

---

## Struttura

```
docs/
  00_DIAGNOSI.md           perché Prova_1 non arrivava in fondo (causa strutturale unica)
  01_PIANO.md              decisioni, conseguenze tecniche, fasi con gate, registro rischi
  03_AMBIENTE.md           audit macchina, add-on installati, versioni Vivado supportate
  04_CONVENZIONI.md        regole di progetto vincolanti (R1…R6)
  05_PROCEDURA.md          i 17 passi del test, con deliverable e gate
  10_SPEC_TEST.md          specifica congelata + criterio di accettazione A1–A6
  11_NOTE_API.md           ⚠️ diario delle scoperte: errori esatti, cause, soluzioni
  12_RICERCA_TOOLCHAIN.md  ricerca sistematica su doc MathWorks e artefatti installati
  13_APERTI.md             ⚠️ punti aperti e prossimi passi — DA LEGGERE PER PRIMI
  20_CONTRATTO_INTERFACCIA.md  ⚠️ confine con il blocco di calcolo di terzi
models/
  soc_top.slx              Variable-step · contenitore · Task Manager · canali
  soc_fpga.slx             Fixed-step    · ProdHWDeviceType = ASIC/FPGA · logica PL
  soc_proc.slx             Fixed-step    · ProcessingUnit = APU · algoritmo ARM
  *_ref.slx                copie congelate da Prova_1, sola lettura — non modificare
scripts/
  soc_params.m             UNICA fonte di verità + controlli di coerenza
  ref_model.m              il giudice, scritto nell'ordine di operazioni dell'hardware
  gen_vectors.m            510 vettori, seed 20260728
  build_soc_{fpga,proc,top}.m
  run_system_sim.m         simulazione di sistema + confronto numerico
  budget_report.m          equazione di progetto: cicli disponibili per il calcolo
  run_regression.m         un comando → PASS/FAIL
  export_r2023b.m          REGOLA R1
test/                      vectors.mat (rigenerabile, non versionato)
hdlplugins/                (vuota) board plugin + reference design PYNQ-Z1
ps/                        (vuota) lato ARM: Python/PYNQ
vivado/                    (vuota) progetto e report, rigenerabili
```

---

## Architettura realizzata

```
 ┌─────────────────────── soc_top.slx  (Variable-step) ────────────────────────┐
 │                                                                             │
 │  ┌──── Processor (subsystem) ────┐                                          │
 │  │  WriteTaskEvent → Task Manager│                                          │
 │  │        ↓ function-call        │                                          │
 │  │  Model → soc_proc.slx ────────┼──> dataOut ──┐                           │
 │  │  done ────────────────────────┤              │                           │
 │  │  streamEnable ────────────────┼──┐           │                           │
 │  └───────────────────────────────┘  │           ↓                           │
 │                                     │   Software to AXI4-Stream             │
 │                          Register Channel   │  │      ↑                     │
 │                                     │       │  │      │ tready              │
 │                                     ↓       ↓  ↓      │                     │
 │                                  ┌── Model → soc_fpga.slx ──┐               │
 │                                  │  streamEnable, tdata, tvalid│            │
 │                                  │  → unpack → matA, matB      │            │
 │                                  │  → DTC + Gain → sonda       │            │
 │                                  └─────────────────────────────┘            │
 └─────────────────────────────────────────────────────────────────────────────┘
```

**Dentro `soc_proc`**: `compute_payload` (A·B 3×3 e C·D 4×4) → `fixdt(1,32,16)` →
reinterpretazione *Stored Integer* a `uint32` → `Stream Write`.
`streamEnable` passa per un blocco `Register Write`, che è ciò che produce il
messaggio atteso dal Register Channel.

**Dentro `soc_fpga`**: `tdata` (`int32`) → reinterpretazione *Stored Integer* a
`fixdt(1,32,16)` → `unpack` (indici generati da `soc_params`) → `matA`/`matB`,
più la sonda aritmetica `DTC → fixdt(1,16,3)` + `Gain 3.7`, che esiste per
garantire che il flusso generi hardware vero e non solo cablaggio.

---

## Ambiente

| | versione |
|---|---|
| MATLAB / Simulink / HDL Coder / SoC Blockset | **R2026a** |
| Vivado per i workflow integrati | **2022.1** o 2024.1 (la 2026.1 **non** è supportata) |
| Compatibilità dei modelli versionati | **R2023b** (regola R1) |

## ⚠ Prima di ogni commit che tocca un `.slx`

```matlab
export_r2023b()
```

I modelli versionati devono restare apribili con **R2023b** (regola R1): il repo è
condiviso e l'aggiornamento di formato di un `.slx` è irreversibile. Lo script si
ferma con errore se un modello non è esportabile — non salta mai in silenzio.
