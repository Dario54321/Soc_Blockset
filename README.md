# Soc_Blockset — accelerazione di un MPC su PYNQ-Z1

Progetto di co-design HW/SW su **Zynq-7000 (PYNQ-Z1, `xc7z020-clg400-1`)**.

**Obiettivo finale**: accelerare un controllore MPC sulla logica programmabile,
lasciando all'ARM la parte di supervisione e I/O.

**Stato attuale**: si sta costruendo e verificando l'**infrastruttura di
interfacciamento** fra ARM (PS) e FPGA (PL) con MATLAB SoC Blockset. L'MPC non è
ancora in gioco: viene innestato su questa infrastruttura quando sarà solida.

---

## Da dove si comincia

| Se vuoi… | Vai a |
|---|---|
| **capire lo stato e far girare qualcosa** | [`HDL_Test/Prova_2/README.md`](HDL_Test/Prova_2/README.md) |
| **sapere cosa manca e cosa fare dopo** | [`HDL_Test/Prova_2/docs/13_APERTI.md`](HDL_Test/Prova_2/docs/13_APERTI.md) |
| **non ripetere errori già fatti** | [`HDL_Test/Prova_2/docs/11_NOTE_API.md`](HDL_Test/Prova_2/docs/11_NOTE_API.md) |
| **una domanda sul toolchain** | [`HDL_Test/Prova_2/docs/12_RICERCA_TOOLCHAIN.md`](HDL_Test/Prova_2/docs/12_RICERCA_TOOLCHAIN.md) |
| **il piano completo con i gate** | [`HDL_Test/Prova_2/docs/05_PROCEDURA.md`](HDL_Test/Prova_2/docs/05_PROCEDURA.md) |

---

## Struttura del repository

```
Prova_1.slx              modello storico: primo test di interfacciamento (R2023b)
Prova_1.slx.original     versione precedente, una sola matrice
FPGA_TEST.slx            subsystem FPGA isolato per la codegen HDL

HDL_Test/
  FPGA_Prova1.slx                  varianti FPGA-only: double → fixed-point
  FPGA_Prova1_fixedpoint.slx
  Prova_1_HDLtest.slx
  socbuilder_test/                 tentativo SoC Builder (ComputeAlgorithm + top)
  vivado_synth*/                   tre run di sintesi Vivado 2022.1 con report

  Prova_2/                    ← LAVORO CORRENTE
    README.md                 stato, comandi, architettura
    docs/                     diagnosi, piano, procedura, note API, punti aperti
    scripts/                  tutto è generato da script
    models/                   soc_top · soc_fpga · soc_proc (rigenerabili)
```

`Prova_1` e le cartelle `HDL_Test/vivado_synth*` sono **materiale storico**: si
conservano perché documentano i tentativi e i loro risultati, ma non si sviluppano
più. Il lavoro attivo è in `HDL_Test/Prova_2`.

---

## Cosa è stato dimostrato finora

La catena completa **simula ed è numericamente corretta**:

```
ARM: calcola A·B (3×3) e C·D (4×4)
  → impacchetta in 25 elementi sfix32_En16
  → reinterpreta a uint32 (Stored Integer: stessi bit)
  → Stream Write
     → Software to AXI4-Stream (PS memory, 8 buffer, 100 MHz, 32 bit)
        → PL: reinterpreta a sfix32_En16
           → spacchetta in matA (3×3) e matB (4×4)
           → sonda aritmetica: fixdt(1,16,3) × 3.7
```

Verifica end-to-end contro il modello di riferimento: **errore 0** su `matA`, `matB`
e sonda. Undici gate di regressione, tutti provati anche in fallimento.

### Cosa NON è ancora dimostrato

- Niente è mai girato su hardware reale.
- Il modello FPGA **non è ancora generabile in HDL**: riceve `tdata` come vettore di
  25 elementi, che in hardware non è sintetizzabile
  ([A1](HDL_Test/Prova_2/docs/13_APERTI.md)).
- Handshake e priming del canale sono ancora segnaposto: **qualunque misura di
  throughput o latenza fatta adesso sarebbe falsa**.

---

## Ambiente

| | versione |
|---|---|
| MATLAB / Simulink / HDL Coder / SoC Blockset / Embedded Coder | **R2026a** |
| Support package | SoC Blockset e Embedded Coder **for AMD FPGA and SoC Devices** |
| Vivado per i workflow integrati | **2022.1** (o 2024.1) — la **2026.1 non è supportata** da R2026a |
| Board di simulazione | ZedBoard (stesso die `xc7z020` della PYNQ-Z1) |
| Board di deploy | PYNQ-Z1, via HDL Coder IP Core Generation con board registrata a mano |

> La PYNQ-Z1 **non è fra le board supportate da SoC Blockset**: si usa SoC Blockset per
> architettura e simulazione, e HDL Coder per il deployment. Decisione e alternative
> scartate in [`01_PIANO.md`](HDL_Test/Prova_2/docs/01_PIANO.md).

---

## Regole di progetto

Vincolanti. Per esteso in [`04_CONVENZIONI.md`](HDL_Test/Prova_2/docs/04_CONVENZIONI.md).

1. **I `.slx` versionati restano apribili con R2023b.** Il repo è condiviso con chi
   lavora su R2023b e l'aggiornamento di formato è irreversibile. Prima di ogni commit
   che tocca un modello:
   ```matlab
   run('HDL_Test/Prova_2/scripts/export_r2023b.m')
   ```
2. **Una decisione, un posto solo.** Dimensioni, formati, tempi e offset stanno solo in
   `scripts/soc_params.m`.
3. **Niente hardware prima della simulazione.** Quattro gate in ordine, nessun salto.
4. **Ogni risultato è rigenerabile da script.** Se un report non si rigenera, non è un
   risultato.
5. **Ogni decisione architetturale si documenta quando si prende**, con l'alternativa
   scartata e il motivo.
6. **Versioni bloccate**: MATLAB e Vivado si fissano all'inizio e non si aggiornano a
   metà progetto.

---

## Come contribuire senza rompere niente

1. Leggi [`13_APERTI.md`](HDL_Test/Prova_2/docs/13_APERTI.md) e
   [`11_NOTE_API.md`](HDL_Test/Prova_2/docs/11_NOTE_API.md).
2. **Non modificare i `.slx` a mano**: modifica lo script che li costruisce e
   rigenerali.
3. Aggiungi un gate in `run_regression.m` per ciò che affermi, e **verifica che sappia
   fallire** (rompi di proposito ciò che verifica e guarda il gate scattare).
4. Esegui `run_regression` — deve essere verde.
5. Esegui `export_r2023b()`.
6. Se hai scoperto qualcosa sul toolchain, scrivilo in `11_NOTE_API.md` con il
   **messaggio d'errore esatto**: è così che diventa ricercabile per chi verrà dopo.
