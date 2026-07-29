# Procedura — dai modelli alla misura sull'hardware

> Ogni passo ha: **azione** → **deliverable** → **gate**. Il gate è la condizione
> per passare al successivo. Se non passa si torna indietro, non si prosegue.
>
> Aggiornata il 28/07/2026 dopo il riorientamento del perimetro
> ([`01_PIANO.md` §1](01_PIANO.md)). La procedura del Test 1 (payload 25 elementi,
> AXI4-Stream) è conclusa; i suoi passi restano qui marcati ✅ perché ciò che hanno
> prodotto — struttura, ricette, gate, note API — vale ancora.

---

## Blocco A — fondamenta *(concluso)*

| | Azione | Gate | |
|---|---|---|---|
| **P0** | ambiente: R2026a, SoC Blockset, Embedded Coder, support package AMD | `ver` e `getInstalled` li mostrano | ✅ |
| **P1** | specifica congelata, criterio di accettazione scritto **prima** | documento firmato e datato | ✅ |
| **P2** | `soc_params.m` fonte unica: dimensioni, formati, tempi, offset | nessun numero magico fuori da lì | ✅ |
| **P3** | reference model nell'ordine di operazioni dell'hardware + vettori a seed fisso | `run_regression` esiste e stampa PASS/FAIL | ✅ |

## Blocco B — modelli e simulazione *(concluso sul Test 1)*

| | Azione | Gate | |
|---|---|---|---|
| **P4** | `soc_fpga.slx` — Fixed-step, `ProdHWDeviceType = ASIC/FPGA` | compila, **rate singolo** | ✅ T6 |
| **P5** | `soc_proc.slx` — `ProcessingUnit = APU`, pilotato dal Task Manager | compila | ✅ T8 |
| **P6** | `soc_top.slx` — Variable-step, i due Model reference | **G6**: struttura riconosciuta, insieme compilante | ✅ T10 |
| **P7** | simulazione di sistema e confronto numerico | **G7**: catena end-to-end **bit-esatta** | ✅ T11 |

> Il Test 1 ha superato entrambi i gate che contavano. La catena restituisce
> `matA`, `matB` e la sonda con **errore 0** contro il reference model.

---

## Blocco C — wrapper AXI4-Lite *(in corso)*

Bersaglio corrente: [`21_SPEC_WRAPPER.md`](21_SPEC_WRAPPER.md).

### P8 · Contratto d'interfaccia
Congelare segnali, protocollo, formato numerico, watchdog e proprietà.
- **Deliverable**: [`20_CONTRATTO_INTERFACCIA.md`](20_CONTRATTO_INTERFACCIA.md) ✅ *(bozza)*
- **Gate G8**: le otto domande del §8 hanno risposta dall'altro ingegnere. ⬜
  *Non blocca P9–P11: il wrapper è parametrico.*

### P9 · Wrapper: CSR, FSM, watchdog, contatore ✅ *(28/07)*
Il wrapper è `models\soc_wrapper_fpga.slx`, generato da
`scripts\build_wrapper_fpga.m`; il blocco di calcolo è un **segnaposto a latenza
configurabile**.
- **Gate G9** ✅ T12: invarianti I1–I7 di `21_SPEC_WRAPPER` §3 verificate; criteri
  B1–B4 superati, **compreso B3 provato facendo tacere il blocco di proposito**.
  Tre mutazioni catturate (`21_SPEC_WRAPPER` §6).

### P10 · Studio di sensibilità alla latenza ✅ *(29/07)*
Far variare la latenza del segnaposto e trovare dove il budget si rompe, per ogni
stack software del PS. → [`22_STUDIO_LATENZA`](22_STUDIO_LATENZA.md),
`scripts\latency_study.m`.
- **Deliverable**: overhead del wrapper **misurato** (1 ciclo, costante su tre
  ordini di grandezza) e il numero di cicli per l'altro ingegnere: **~3000 con
  bare-metal, ~2300 con Linux mappato**, da confermare a misura.
- **Gate G10** ✅ T13: riproducibile da script, con le ipotesi dichiarate.
  Provato in fallimento con uno stadio di registro in più sul percorso `done`.
- **Ricaduta su D1/D3**: `linux_driver` eliminato per aritmetica; trasporto e
  stack software risultano accoppiati, non indipendenti.

### P11 · Board plugin PYNQ-Z1 ✅ *(29/07)*
`hdlplugins/+PYNQZ1` + `hdlcoder_board_customization.m`, sul modello dell'esempio
Trenz spedito nel prodotto. → [`23_BOARD_PYNQZ1`](23_BOARD_PYNQZ1.md).
- I pin **non** vengono dal *Reference Manual* ma dai board file Vivado che il
  gruppo ha già installato, che sono la stessa fonte che legge Vivado.
- **Gate G11** ✅ T14 (parte automatica): registrazione esercitata attraverso il
  riferimento registrato, e i 10 pin dichiarati riconfrontati con
  `part0_pins.xml` — sigla e standard di I/O. Quattro mutazioni catturate.
- **Resta la conferma manuale**: che la board compaia nel menu del Workflow
  Advisor non è verificabile da script (registro p-coded, §23.6).

---

## Blocco D — hardware *(richiede Vivado 2022.1 → Dario)*

### P12 · Reference design
Partire da `+ZedBoard/+vivado_base_2022_1` (AXI4-Lite: **più piccolo** di quello
stream), cambiare `BoardName` e il board part usando i **board files Vivado che il
gruppo già possiede**, e lasciare che `apply_boardpreset` riempia i `PCW_*` invece
di trascriverli.
- **Gate G12**: il reference design compare nel Workflow Advisor e il block design
  si costruisce senza errori critici.
- **Uscita datata**: se a 2 settimane non converge → ZedBoard, e la PYNQ-Z1 diventa
  una limitazione dichiarata nel report.

### P13 · IP core e bitstream
Mappatura porte → AXI4-Lite. Sintesi **dentro l'IP core**, mai come top-level con
tutte le porte ai pin.
- **Gate G13**: bitstream costruito; timing con **slack positivo su un design che
  contiene registri**. Un percorso combinatorio pad-to-pad non è timing closure.
- **Verifica attiva**: confrontare il conteggio `IBUF`/`OBUF` con quello atteso
  dalle porte. È così che in `Prova_1` è emerso il disallineamento di `matB`.

---

## Blocco E — software, bring-up, misura

### P14 · Software PS
Decisione D3 (bare-metal vs Linux) presa e motivata. Driver dietro un'astrazione,
così il trasporto resta sostituibile.

### P15 · Bring-up — cinque passi, nessuno saltato
1. la board fa boot e la configurazione carica;
2. **leggere `ID_VER`** — una lettura prova bus, decodifica, clock e reset insieme;
3. scrivere e rileggere un registro R/W;
4. **un vettore noto**: confrontare risultato **e `CYCLES`** con la simulazione;
5. la suite completa → percentuale di match.

I tre guasti classici sono **fallimenti di contratto, non di logica**: mismatch di
offset, polarità del reset, formati numerici interpretati diversamente ai due capi.
Tenere un ILA su FSM, handshake e un valore del datapath **già nella prima build**.

- **Gate G15**: 100 % di match, e **la prima lettura reale di `CYCLES`**.

### P16 · Campagna di misura — ordine fisso
1. risorse e timing dai report (**con il WNS**, non solo il clock);
2. latenza del blocco di calcolo da `CYCLES`;
3. latenza end-to-end dal lato software;
   → **la differenza fra 2 e 3 è il costo del trasporto**, e a questo budget è il
   risultato principale;
4. ripetizioni: distribuzione, caso peggiore e **jitter**, non un numero solo.

- **Gate G16**: ogni numero rigenerabile da script; le costanti di latenza dello
  stack PS in `soc_params` sostituite con **misure**, non più stime da letteratura.

---

## Riepilogo dei gate

| Gate | Condizione | Stato |
|---|---|---|
| G0–G3 | ambiente, specifica, fonte unica, regressione | ✅ |
| G6 | struttura a tre modelli riconosciuta e compilante | ✅ T10 |
| G7 | catena end-to-end bit-esatta | ✅ T11 |
| G8 | le otto domande del contratto hanno risposta | ⬜ altro ingegnere |
| G9 | invarianti del wrapper, **watchdog provato in fallimento** | ✅ T12 |
| G10 | numero di cicli disponibili, riproducibile | ✅ T13 |
| G11 | plugin PYNQ-Z1: registrazione + pin verificati | ✅ T14 |
| G11b | PYNQ-Z1 nel menu del Workflow Advisor | ⬜ conferma manuale |
| G12 | reference design costruisce *(uscita datata: 2 settimane)* | ⬜ Dario |
| G13 | bitstream, slack positivo su design con registri | ⬜ Dario |
| G15 | 100 % match on-board + prima lettura di `CYCLES` | ⬜ board |
| G16 | tutto rigenerabile, costanti sostituite da misure | ⬜ |

> **Nota su G4** *(storica)*. Il gate era "rate singolo **e pari a `Ts_FPGA`**".
> Sbagliato: in SoC Blockset il rate di simulazione del modello FPGA non è il clock
> della PL ma il rate del flusso dati. Verifica solo che il rate sia **uno solo**,
> che è il requisito vero della generazione HDL ([`11_NOTE_API` §6](11_NOTE_API.md)).
