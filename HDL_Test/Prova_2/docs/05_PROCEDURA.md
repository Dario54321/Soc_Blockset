# Procedura completa — Test di interfacciamento ARM ↔ FPGA

> Cosa questo test deve dimostrare, e nient'altro: **che un vettore prodotto sull'ARM
> arrivi alla PL, sia elaborato, e torni indietro identico al riferimento — con una
> latenza misurata e un percorso riproducibile da script.**
> Non dimostra nulla sull'MPC. Quello viene dopo, su questa infrastruttura.

Ogni passo ha: **azione** → **deliverable** → **gate**. Il gate è la condizione per
passare al successivo. Se non passa si torna indietro, non si prosegue.

---

## Blocco A — Ambiente e specifica

### P0 · Installare gli add-on e bloccare le versioni
Vedi la lista in `03_AMBIENTE.md` §Add-on. Al termine:
```matlab
v = ver; disp({v.Name}')                              % prodotti
matlabshared.supportpkg.getInstalled                  % support package
```
- **Deliverable**: `03_AMBIENTE.md` aggiornato con l'output reale.
- **Gate G0a**: `SoC Blockset`, `Embedded Coder`, `HDL Coder` compaiono in `ver`;
  i tre support package AMD compaiono in `getInstalled`; Vivado 2022.1 è raggiungibile
  (`hdlsetuptoolpath`).

### P1 · Congelare la specifica del test
Un documento di due pagine, scritto **prima** di toccare i modelli.
- Payload: 25 elementi `fixdt(1,32,16)` (vincolo C1: lo stream è a 32 bit).
- Cosa fa la PL: reshape in `matA` 3×3 e `matB` 4×4, più la sonda aritmetica
  (`Gain` su `matA`) che garantisce che si generi hardware vero e non solo cablaggio.
- Criterio di accettazione, in unità fisiche e **scritto ora**: uscita PL bit-identica
  al reference su tutte e tre le famiglie di vettori.
- Latenza attesa e budget.
- **Deliverable**: `docs/10_SPEC_TEST.md`.
- **Gate G1**: la specifica è firmata e datata. Da qui in poi ogni modifica richiede
  giustificazione scritta.

### P2 · Fonte unica dei parametri
`scripts/soc_params.m` restituisce una struct con: dimensioni, tipi/formati numerici,
`Ts`, frame size, numero di buffer, profondità FIFO, offset dei registri, nome board,
part number. **Nessun altro file definisce questi valori**: i modelli li leggono da qui
via mask/`preLoadFcn`, gli script anche.
- **Gate G2**: cercando un qualunque numero magico nei modelli non lo si trova.

---

## Blocco B — Modelli e simulazione

### P3 · Reference model e vettori di test
- `scripts/ref_model.m` — implementazione double, scritta **nell'ordine di operazioni
  dell'hardware** (stesso loop, stesso ordine di accumulo). È il giudice.
- `scripts/gen_vectors.m` — **seed fisso**, tre famiglie: scenari realistici, campioni
  casuali uniformi sul range dichiarato, corner case (saturazioni, estremi di range,
  valori al limite del formato `En16`).
- **Deliverable**: `test/vectors.mat` rigenerabile con un comando.
- **Gate G3**: `gen_vectors` è deterministico (due esecuzioni → file identici).

### P4 · `models/soc_fpga.slx`
```
Hardware Implementation → Feature set = SoC Blockset
                        → Processing Unit = FPGA
Solver                  → Type = Fixed-step
```
Contenuto: `tdata`/`tvalid`/`StreamEnable` → `SoC Bus Selector` (Valid) → algoritmo →
`SoC Bus Creator` (Ready) → `tready`/`computeDone` + uscite dati.
**Nessun `typecast` a `uint64`**: si nasce a 32 bit.
- **Gate G4**: `Update Diagram` pulito; rate singolo; nessun `double` sui segnali che
  attraversano il confine.

### P5 · `models/soc_proc.slx`
```
Hardware Implementation → Feature set = SoC Blockset
                        → Processing Unit = APU
```
Contiene l'algoritmo che oggi sta in `Subsystem` + `Stream Write`. Sarà pilotato dal
Task Manager del top: qui dentro **non** ci va il Task Manager.
- **Gate G5**: simula stand-alone con ingressi fittizi.

### P6 · `models/soc_top.slx`
```
Hardware Implementation → Feature set = SoC Blockset
                        → Processing Unit = None
Solver                  → Type = Variable-step
```
Contenuto: due blocchi `Model` (→ `soc_fpga`, `soc_proc`), `Task Manager` che pilota il
processor ref, `Software to AXI4-Stream` (**`ICDataWidth = 32`**, non più 64),
`Register Channel` per il piano di controllo, sorgenti/sink di test, scope.
La board deve essere **la stessa** nei tre modelli.
- **Gate G6**: il top simula senza errori di solver o di rate, **e** SoC Builder si apre
  riconoscendo entrambi i modelli referenziati (fine dell'errore *"FPGA or processor
  model not detected"*).

### P7 · Simulazione di sistema e dimensionamento
Con il Task Manager si simulano durate di task variabili e si dimensionano i buffer:
```
(NumFrameBuffers + 1) × FramePeriod  ≤  MaxLatency
FramePeriod                          >   MeanTaskDuration
FIFODepth                            =   FrameSize / FIFOBurstSize
```
- **Deliverable**: `docs/11_DIMENSIONAMENTO.md` con i tre numeri scelti e il motivo,
  più il grafico di occupazione buffer / sample dropout.
- **Gate G7**: zero campioni persi nello scenario nominale; il comportamento in
  overload è caratterizzato, non ignorato.

### P8 · Register map
Congelato **prima** del wrapper, con il formato numerico di ogni campo nella stessa
tabella del campo:
```
0x00  CTRL     R/W   bit0 START (autoclear) · bit1 SOFT_RESET · bit2 IRQ_EN
0x04  STATUS   R     bit0 DONE · bit1 BUSY · bit2 ERROR
0x08  ...      W     ingressi
0x40  ...      R     uscite
0x44  CYCLES   R     cicli dell'ultimo solve       ← strumento di misura
0x48  ITERS    R     iterazioni eseguite
0x4C  ID_VER   R     costante magica + versione    ← prima lettura del bring-up
```
- **Deliverable**: `docs/12_REGISTER_MAP.md` + generazione di header C e decode HW
  **dalla stessa descrizione**.
- **Gate G8**: nessuna copia sincronizzata a mano fra i due lati.

---

## Blocco C — Hardware

### P9 · Generazione HDL e verifica contro il modello
`scripts/build_hdl.m` esegue `makehdl` con i parametri da `soc_params`. Mai dalla GUI.
- **Gate G9a**: il Verilog generato riproduce il modello sulla suite di regressione
  (co-simulazione o confronto su vettori).
- **Gate G9b — verifica attiva del disallineamento**: confrontare gli indici sorgente
  con quelli generati, **e** il conteggio `IBUF`/`OBUF` del report di sintesi con quello
  atteso dalle porte. È così che è emerso il bug `matB` in `Prova_1`
  (`IBUF = 513` invece dei 803 attesi → nove ingressi scollegati).
  Questo gate va superato guardando i numeri, non dando per scontato che il tool abbia
  ragione.

### P10 · Board plugin PYNQ-Z1
Copiare `toolbox\hdlcoder\boards\amd\+ZedBoard` → `Prova_2/hdlplugins/+PYNQZ1` e
modificare `plugin_board.m`:
```matlab
hB.BoardName   = 'PYNQ-Z1';
hB.FPGADevice  = 'xc7z020';
hB.FPGAPackage = 'clg400';        % <- ZedBoard e' clg484
hB.FPGASpeed   = '-1';
hB.SupportedTool = {'Xilinx Vivado'};
hB.JTAGChainPosition = 2;
```
più i pin di LED/switch/pulsanti dal *Digilent PYNQ-Z1 Reference Manual* nelle
`addExternalIOInterface`. Registrare con `hdlcoder_board_customization.m`.
- **Gate G10**: la PYNQ-Z1 compare nella lista board dell'HDL Workflow Advisor.
  Mezza giornata. **Fatelo per primo fra i passi di questo blocco**: è il più economico
  e toglie subito il dubbio più grosso sulla fattibilità.

### P11 · Reference design PYNQ-Z1
Partire da `+ZedBoard/+vivado_stream_2022_1` (già per Vivado 2022.1, con
`plugin_rd.m` + `system_top.tcl` 663 righe + `axistream.dtsi`) e cambiare:
- `hRD.BoardName = 'PYNQ-Z1'`
- `addCustomVivadoDesign(..., 'VivadoBoardPart', '<board part della PYNQ-Z1>')`
  ← **qui entrano i board files che avete già**
- in `system_top.tcl`, il `set_property BOARD_PART ...` e il blocco `CONFIG.PCW_*`
  del `processing_system7`: usare il preset della scheda
  (`apply_bd_automation ... -config {apply_boardpreset "1"}`) invece di trascrivere
  a mano i parametri DDR/MIO.
- `axistream.dtsi`: verificare gli indirizzi.

Restano invariati (non toccarli): `addClockInterface`, `addRegisterInterface`,
`addAXI4StreamInterface` con `MasterChannelDataWidth = 32` / `SlaveChannelDataWidth = 32`.
- **Deliverable**: `docs/13_REFERENCE_DESIGN.md` con le differenze rispetto a ZedBoard.
- **Gate G11**: il reference design compare nel Workflow Advisor per la PYNQ-Z1 e il
  block design si costruisce in Vivado senza errori critici.
- **Uscita datata**: se a 2 settimane non converge → ZedBoard, e la PYNQ-Z1 diventa
  una limitazione dichiarata nel report.

### P12 · IP core, integrazione, bitstream
Mappatura porte → interfacce: `tdata` su AXI4-Stream Slave (32 bit), uscita su
AXI4-Stream Master, `CTRL`/`STATUS`/`ID_VER`/`CYCLES` su AXI4-Lite.
Sintesi **dentro l'IP core con AXI** o `out_of_context` — **mai** come top-level con
tutte le porte ai pin (origine dei 729 % di IOB in `Prova_1`).
- **Gate G12**: bitstream costruito; utilization e timing **con slack positivo su un
  design che contiene registri**. Un path combinatorio pad-to-pad non è timing closure.

---

## Blocco D — Software, bring-up, misura

### P13 · Software PS
Python su immagine PYNQ: `Overlay()`, `allocate()`, `dma.sendchannel.transfer()` /
`recvchannel.transfer()`, `MMIO` per i registri di controllo.
Il framework copre da solo tre delle quattro responsabilità che il DMA scarica sul
software (allocazione contigua, coerenza cache, descrittori); resta l'asincronia.
- **Deliverable**: `ps/driver.py` + un notebook che esegue la suite.

### P14 · Bring-up — cinque passi, in ordine, nessuno saltato
1. la board fa boot, la configurazione carica;
2. **leggere `ID_VER`** e confrontare con la costante — una lettura prova bus, decode,
   clock e reset insieme;
3. scrivere e rileggere un registro R/W;
4. **un vettore noto**: confrontare risultato **e** `CYCLES` con la simulazione;
5. la suite completa dal lato software → percentuale di match.

I tre guasti classici sono **fallimenti di contratto, non di logica**: mismatch di
offset fra header software e assegnazione del tool, polarità del reset, formati numerici
interpretati diversamente ai due capi. Tenete un ILA sulla FSM, sull'handshake
start/done e su un valore del datapath **già nella prima build**: toglierlo dopo non
costa niente, non averlo costa giorni.
- **Gate G14**: 100 % di match sulle tre famiglie di vettori.

### P15 · Campagna di misura — ordine fisso
1. risorse e timing dai report di implementazione (**con il WNS**, non solo il clock);
2. latenza hardware dal contatore on-chip;
3. latenza end-to-end dal lato software;
   → **la differenza fra 2 e 3 È il costo di data movement**, ed è il risultato
   principale di questo test dato che il payload sta sotto il break-even;
4. baseline software sulla stessa board, stesso ambiente, compilatore e flag dichiarati;
5. ripetizioni: riportare distribuzione, caso peggiore e **jitter**, non un numero solo.
- **Deliverable**: `docs/14_MISURE.md`, ogni numero rigenerabile da script.

### P16 · Chiusura
- **Deliverable finale**: `docs/15_REPORT_TEST1.md` — cosa è stato dimostrato, con quali
  numeri, con quali limiti dichiarati; e le sei decisioni architetturali con
  **l'alternativa scartata e il motivo**.
- **Gate G16**: qualcuno che non ha lavorato al progetto rigenera tutti i risultati
  partendo dal repo e da `README.md`, con i comandi documentati.

---

## Riepilogo dei gate

| Gate | Condizione | Stato |
|---|---|---|
| G0a | add-on installati e verificati | ✅ |
| G1 | specifica del test congelata e datata | ✅ |
| G2 | nessun numero magico fuori da `soc_params.m` | ✅ |
| G3 | generatore vettori deterministico | ✅ |
| G4 | `soc_fpga` compila, rate singolo | ✅ T6 |
| G5 | `soc_proc` compila | ✅ T8 |
| G6 | il top referenzia i due modelli e compila | ✅ **T10** |
| G7 | catena end-to-end bit-esatta | ✅ **T11** |
| G7b | buffer dimensionati, zero dropout nominale | ⬜ manca lo studio di dropout |
| G8 | register map congelato, due lati da una sola fonte | ⬜ |
| G9a/b | HDL == modello, **verificato attivamente** anche sui conteggi IBUF/OBUF | ⬜ bloccato da [A1](13_APERTI.md) |
| G10 | PYNQ-Z1 nella lista board del Workflow Advisor | ⬜ |
| G11 | reference design costruisce in Vivado *(uscita datata: 2 settimane)* | ⬜ Dario |
| G12 | bitstream, slack positivo, design con registri | ⬜ Dario |
| G14 | 100 % match on-board sulle tre famiglie | ⬜ serve la board |
| G16 | tutto rigenerabile da un altro operatore | ✅ |

> **Nota su G4.** Il gate era stato scritto come "rate singolo **e pari a Ts_FPGA**".
> Sbagliato: in SoC Blockset il rate di simulazione del modello FPGA non è il clock
> della PL ma il rate del flusso dati. Il gate ora verifica solo che il rate sia
> **uno solo**, che è il requisito vero della generazione HDL
> ([`11_NOTE_API` §6](11_NOTE_API.md)).
