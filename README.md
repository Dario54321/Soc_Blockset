# Soc_Blockset — accelerazione di un MPC su PYNQ-Z1

Progetto di co-design HW/SW su **Zynq-7000 (PYNQ-Z1, `xc7z020-clg400-1`)**.

**Obiettivo finale**: accelerare un controllore MPC sulla logica programmabile,
lasciando all'ARM la parte di supervisione e I/O.

**Perimetro di questo lavoro**: costruire il **trasporto** fra l'ARM e un blocco di
calcolo FPGA, dentro un budget d'anello di **33 µs**. Il calcolo dell'MPC
(inversione 3×3 e altro) è dentro un blocco di **un altro ingegnere** e non è nel
nostro perimetro: il nostro deliverable è
**[un contratto d'interfaccia](HDL_Test/Prova_2/docs/20_CONTRATTO_INTERFACCIA.md)
più il suo wrapper**.

**Stato**: l'infrastruttura simula ed è verificata bit-esatta (Test 1, concluso).
Il wrapper AXI4-Lite — CSR, handshake `start`/`done`, watchdog, contatore di cicli —
è costruito e verificato in simulazione; la PYNQ-Z1 è registrata in HDL Coder e il
reference design che le sta attorno è scritto (Test 2).

**Niente è ancora girato su hardware.** Da qui in poi serve Vivado 2022.1, che ha
Dario: costruire il reference design e il bitstream. La parte scritta qui è
verificata per quanto si può senza quel tool — e dove non si è potuto, è detto quale
verifica manca.

> ### ⚠ Otto domande in attesa
> Il [contratto d'interfaccia](HDL_Test/Prova_2/docs/20_CONTRATTO_INTERFACCIA.md) §8
> elenca otto domande che servono per chiudere la bozza — sul protocollo, sul
> formato numerico e sul payload. Le più urgenti: **cosa sono i due vettori 3×1** che
> attraversano il confine, e **cos'altro lo attraverserà** (i dati grezzi di
> radar/lidar restano sull'ARM?). La seconda decide la taglia del progetto.

> ### ▶ Il prossimo passo, per chi ha Vivado 2022.1
> Tre comandi in ordine, con un esito atteso ciascuno:
> [`24_REFERENCE_DESIGN` §24.5](HDL_Test/Prova_2/docs/24_REFERENCE_DESIGN.md).
> Il primo è `validate_refdesign()`, che deve rispondere `completa`.

> ### ⚠ Una decisione da prendere: cosa gira sull'ARM
> Bare-metal o Linux con registri mappati. Non è una scelta tecnica in senso
> stretto — dipende da cosa deve fare il PS oltre a questo anello — ma **il prezzo
> ora è quantificato: 850 cicli, il 26 % del budget**
> ([D3 in `01_PIANO`](HDL_Test/Prova_2/docs/01_PIANO.md)). Un driver di kernel Linux
> è invece **fuori per aritmetica**: costerebbe 50 µs di solo trasporto contro 33 di
> budget. Serve decidere prima del reference design.

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
    models/                   soc_top · soc_fpga · soc_proc · soc_wrapper_fpga
    hdlplugins/               board PYNQ-Z1 + reference design per HDL Coder
```

`Prova_1` e le cartelle `HDL_Test/vivado_synth*` sono **materiale storico**: si
conservano perché documentano i tentativi e i loro risultati, ma non si sviluppano
più. Il lavoro attivo è in `HDL_Test/Prova_2`.

---

## Cosa è stato dimostrato finora

**Test 1 — infrastruttura.** La catena completa simula ed è numericamente corretta:

```
ARM: calcola due matrici  → impacchetta in 25 elementi sfix32_En16
   → reinterpreta a uint32 (Stored Integer: stessi bit)  → Stream Write
      → Software to AXI4-Stream (PS memory, 8 buffer, 100 MHz, 32 bit)
         → PL: reinterpreta  → spacchetta  → sonda aritmetica in virgola fissa
```

Verifica end-to-end contro il modello di riferimento: **errore 0**.

Ha prodotto ciò che serve indipendentemente dal payload: struttura a tre modelli,
ricette di configurazione, suite di gate, note API sul toolchain.

**Test 2 — il wrapper.** `soc_wrapper_fpga` implementa il confine verso il blocco di
terzi: registri AXI4-Lite, macchina a stati insensibile alla latenza, **watchdog**
(l'unica cosa che impedisce all'ARM di restare appeso se il blocco tace) e un
contatore che espone la latenza reale nel registro `CYCLES`.

Da lì esce il numero da mettere in mano all'altro ingegnere:

> **ordine dei 3000 cicli a 100 MHz** — ~3150 con PS bare-metal, ~2300 con Linux e
> registri mappati. → [`22_STUDIO_LATENZA`](HDL_Test/Prova_2/docs/22_STUDIO_LATENZA.md)

**Board PYNQ-Z1 registrata in HDL Coder.** Non è fra le sedici che MathWorks
fornisce: `HDL_Test/Prova_2/hdlplugins/+PYNQZ1`. I pin non vengono da un manuale ma
dai **board file Vivado che il gruppo ha già installato**, e un gate li riconfronta
con quelli pin per pin.
→ [`23_BOARD_PYNQZ1`](HDL_Test/Prova_2/docs/23_BOARD_PYNQZ1.md)

**Reference design scritto.** `hdlplugins/+PYNQZ1/+vivado_base_2022_1`: il sistema
dentro cui HDL Coder innesta l'IP core — Processing System, bus AXI, clock, reset,
device tree. Il PS **non** è trascritto a mano come nei reference design MathWorks
(399 righe di parametri): si applica il preset dei vostri board file, e che
funzioni è verificato — il design costruito riporta `MT41J256M16 RE-125`, il DDR3
reale della PYNQ-Z1.
→ [`24_REFERENCE_DESIGN`](HDL_Test/Prova_2/docs/24_REFERENCE_DESIGN.md)

**15 gate di regressione, tutti provati anche in fallimento** — compresi il watchdog
(fatto tacere di proposito), il contatore dei cicli, la mappatura dei pin e la
coerenza fra i quattro file del reference design.

### Cosa NON è ancora dimostrato

- **Niente è mai girato su hardware reale.**
- I 33 µs vengono da un paper, **non sono stati misurati da noi**.
- I costi di trasporto ARM↔FPGA sono **ordini di grandezza da letteratura**, non
  misure su questa board. Bastano a scartare un'alternativa che costa trenta volte
  più di un'altra, non a garantire la terza cifra del numero qui sopra.
- La latenza del blocco di calcolo di terzi è **ignota**: si misurerà con il
  registro `CYCLES` del wrapper, senza toccare il loro codice.
- Handshake e priming del canale del Test 1 sono segnaposto: **qualunque misura di
  throughput o latenza fatta adesso sarebbe falsa**.

### Perché il Test 1 non è il bersaglio finale

Il payload reale sono **due vettori 3×1** (~28 byte), non 25 elementi, e il budget è
33 µs. A quella taglia il DMA lascia **100 cicli** al calcolo contro i **3150** dei
registri: il trasporto corretto è **AXI4-Lite**. Il percorso AXI4-Stream costruito
nel Test 1 non è sprecato — resta come seconda implementazione della stessa
interfaccia, e torna in gioco oltre i ~10–12 elementi.

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
