# Prova_2 — Diagnosi: perché Prova_1 non arriva in fondo

> Documento di lavoro. Fonti: documentazione MathWorks SoC Blockset (R2023b),
> skill `soc-expert` (ch03, ch06, ch22), skill `fpga-expert` (ch08, ch10).

## Riepilogo in una riga

Il modello `Prova_1.slx` **non ha la struttura che SoC Blockset richiede**: è un modello
unico che contiene il subsystem FPGA, mentre SoC Builder pretende un *top model* che
referenzia un *FPGA model* e un *processor model* come **Model reference**. Tutti i
problemi riportati (Model reference, Variable vs Fixed, socBuilder che non parte)
discendono da questa singola causa.

---

## D1 — La struttura a tre modelli è obbligatoria, non una scelta di stile

Regola MathWorks, verbatim: *"The top model must reference an FPGA model or processor
model (or both) that include a Model block."* L'errore *"FPGA or processor model not
detected"* si presenta esattamente quando SoC Builder viene lanciato da un modello che
non ha questa struttura.

| Modello | `Processing Unit` | Solver | Contenuto |
|---|---|---|---|
| **top** | `None` | **Variable-step** | Model ref FPGA + Model ref processor, Memory/Register/Interrupt Channel, sorgenti e sink di test |
| **FPGA ref** (max 1) | `FPGA` | **Fixed-step** | logica PL, SoC Bus Creator/Selector, algoritmo da sintetizzare |
| **processor ref** (1+) | `APU` | (ereditato) | algoritmo SW, **deve essere pilotato da un Task Manager** nel top |

Su **tutti e tre**: `Hardware Implementation → Feature set for selected hardware board = SoC Blockset`,
e la board deve essere **la stessa** in tutti e tre.

## D2 — "Prima Variable, poi Fixed" non è un conflitto: sono due modelli diversi

Questo è il punto che sta facendo perdere più tempo. Non è che il modello debba
cambiare solver: sono **due file diversi con due solver diversi**.

- Il **top** è Variable-step perché deve simulare eventi asincroni: il Task Manager con
  durate di task stocastiche, la memoria burst-accurate, gli interrupt. È un modello di
  *sistema*, non di *datapath*.
- L'**FPGA ref** è Fixed-step perché è l'unica cosa che HDL Coder può generare: un
  datapath sincrono a rate singolo.

In `Prova_1.slx` oggi coesistono nello stesso file un `Task Manager` event-driven
(che vuole Variable-step) e un subsystem FPGA a `SampleTime = 1e-08`
(che vuole Fixed-step). Il conflitto è strutturale e non si risolve con le impostazioni:
si risolve separando i file.

## D3 — La PYNQ-Z1 non è una board supportata da SoC Blockset

Board Zynq-7000 ufficialmente supportate: **ZC702, ZC706, ZedBoard, PicoZed,
ADRV9361-Z7035**. PYNQ-Z1 e Zybo **non ci sono**.

Conseguenze verificate nel repo:
- `Prova_1.slx` → `HardwareBoard = Custom Hardware Board` (nessuna board reale)
- `Prova_1_socbuilder.slx` → `HardwareBoard = ZedBoard` (ripiego)
- tutti gli `synth.tcl` → `xc7z020clg484-1` = **ZedBoard**, non PYNQ-Z1 (`xc7z020clg400-1`)

Stesso die XC7Z020 (53200 LUT, 220 DSP, 140 BRAM → i conteggi risorse restano validi),
**package diverso**: pinout, board file, DDR e vincoli non sono trasferibili.

Due strade, entrambe legittime, ma **vanno decise adesso** perché cambiano tutto a valle
(vedi `01_PIANO.md`, Decisione A).

## D4 — Il trasporto scelto è sovradimensionato per il payload

Payload attuale: 25 × 64 bit = **200 byte**. Modello a due termini del costo di
trasferimento (soc-expert ch06):

```
N* = F / (t_acc/4 − 1/B_eff)          break-even registri ↔ DMA
```

| Ambiente | t_acc | F | N* |
|---|---|---|---|
| Bare-metal, polling | 0.15 µs | ~2 µs | **~57 B** |
| Bare-metal, interrupt | 0.15 µs | ~4 µs | **~114 B** |
| Linux, driver kernel, interrupt | ~0.15 µs | ~32 µs | **~0.9 kB** |
| Linux, mmap user-space | ~1 µs | ~32 µs | **~130 B** |

200 byte cade **nella zona grigia**, e sotto Linux con driver kernel (il caso PYNQ)
è **sotto** la soglia: l'AXI4-Lite mappato a registri è più veloce del DMA.
Per l'MPC vero il payload sarà ancora più piccolo (vettore di stato n_x ≈ 3–4 double).

**Il canale AXI4-Stream + DMA che state combattendo non serve a questo problema.**
Serve un `Register Channel`. Lo stream diventa giustificato solo se un giorno mandate
batch di problemi o traiettorie lunghe.

## D5 — Debito tecnico che sta amplificando tutto il resto

- 8 modelli `.slx`, 4 copie quasi identiche della funzione di reshape in 3 varianti
  (con `typecast`, senza, parziale). Nessuna singola fonte di verità.
- **L'HDL committato non corrisponde ai sorgenti**: in
  `vivado_synth/` e `vivado_synth_fixedpoint/` il Verilog legge `matB` da `U[0..15]`
  invece di `U[9..24]` (offset `+9` mancante). Confermato dai report: `IBUF = 513 =
  512 (U₀..U₁₅) + StreamEnable`, quindi `tdata_16..24` risultano scollegati.
  Solo `vivado_synth_fpga_real/` è corretto (`out0_1[0..15] = U_9..U_24`).
  → Un contratto dati esplicito + un test di regressione avrebbero preso questo bug
  in simulazione invece che in sintesi.
- Nessun README, nessuno script di build versionato → la catena non è riproducibile.

---

## Cosa è invece già giusto e va tenuto

- Scelta dei blocchi: `Task Manager` event-driven, `Stream Write`, `Software to AXI4-Stream`,
  `Register Channel`, `SoC Bus Creator/Selector` — è l'architettura di riferimento corretta.
- **R2023b + Vivado 2022.1 è la coppia ufficialmente supportata.** Non aggiornare nulla
  a metà progetto (soc-expert ch22, risk register: *"pin versions in week 0"*).
- L'idea della sonda aritmetica in `FPGA_Prova1_fixedpoint` (DTC → `sfix16_En10` + `Gain 3.7`
  → 9 DSP48E1) è metodologicamente buona: serviva a verificare che il flusso producesse
  hardware vero e non solo cablaggio. Da riusare come *smoke test*.
