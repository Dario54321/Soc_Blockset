# 24 — Reference design AXI4-Lite per la PYNQ-Z1 (P12)

> Passo P12, **scritto qui, da costruire da chi ha Vivado 2022.1**.
> Verificabile con `check_refdesign` (coerenza) e `validate_refdesign` (Vivado).
> Ultima esecuzione: 2026-07-29.

## 24.1 Che cos'è

Il board plugin (P11) dice a HDL Coder *su quale silicio* costruire. Il
reference design dice *dentro quale sistema*: il Processing System, il bus su
cui l'ARM raggiunge i registri, il clock, il reset. HDL Coder ci innesta dentro
l'IP core generato dal wrapper.

```
hdlplugins/+PYNQZ1/
  hdlcoder_ref_design_customization.m     registra il reference design
  +vivado_base_2022_1/
    plugin_rd.m          dove attaccare clock, reset, registri
    system_top.tcl       il block design
    axilite.dtsi         i nodi device tree per Linux
```

## 24.2 Cosa è stato ricalcato e cosa no

Base: `+ZedBoard/+vivado_base_2022_1`, il reference design AXI4-Lite validato
da MathWorks per lo **stesso silicio**. Stessi IP, stesse connessioni, stessi
nomi di istanza — i nomi sono un contratto, `plugin_rd.m` li cita per indicare
dove attaccarsi.

Due differenze deliberate.

### Il Processing System non è configurato a mano

Quello della ZedBoard contiene **399 righe di `CONFIG.PCW_*`**: DDR, MIO, PLL,
tutto trascritto. Riscriverle per una board diversa è il modo più efficiente di
introdurre un errore che si manifesta solo a runtime.

Qui si applica il preset che sta nei board file della PYNQ-Z1:

```tcl
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { make_external "FIXED_IO, DDR" apply_board_preset "1" \
              Master "Disable" Slave "Disable" } \
    [get_bd_cells sys_cpu]
```

**Verificato che funzioni**: dopo l'automation, `PCW_UIPARAM_DDR_PARTNO` vale
`MT41J256M16 RE-125` — il chip DDR3 reale della PYNQ-Z1, che nessuno dei nostri
file nomina. È arrivato dal loro `preset.xml`.

Il preset descrive la board, non l'uso che ne facciamo: quel che riguarda il
confine verso la PL va impostato dopo, e **verificato che sopravviva** al
preset. `PCW_FPGA0_PERIPHERAL_FREQMHZ` = 100 e `PCW_USE_M_AXI_GP0` = 1 riletti
dal design costruito: sopravvivono.

### Le versioni degli IP si risolvono a runtime

Il file della ZedBoard le fissa (`processing_system7:5.5`, `clk_wiz:6.0`, …).
Qui un `mw_ip` le cerca e le stampa. Serve a due cose: rendere il design
indipendente dalla revisione minore di IP stabili da anni, e **fallire con un
messaggio comprensibile** invece che con un "IP not found" quando la versione
di Vivado è sbagliata.

## 24.3 Tre dettagli che costano un pomeriggio

**Il board part di Vivado è minuscolo.** `board.xml` dichiara
`name="PYNQ-Z1"`, ma Vivado registra la board come:

```
www.digilentinc.com:pynq-z1:part0:1.0
```

Verificato con `get_board_parts`, non dedotto — `get_board_parts *PYNQ*` non
trova nulla. In una prima stesura di [`23_BOARD_PYNQZ1`](23_BOARD_PYNQZ1.md)
avevo scritto la forma maiuscola. `check_refdesign` ora deriva la stringa
attesa da `board.xml` applicando il minuscolo, e confronta.

**`axi_interconnect` non esiste più dalla 2026.1.** Nella Vivado 2026.1
installata su questa macchina resta solo `smartconnect`. Ma **tutti** i
reference design MathWorks, incluso quello per la 2024.1, usano ancora
`axi_interconnect:2.1`, e nessuno dichiara versioni oltre la 2024.1. Quindi
l'IP giusto per il bersaglio è quello, e la 2026.1 non è una versione su cui
questo flusso girerebbe comunque.

**Il clock è 100 MHz, non 50.** La ZedBoard usa 50 MHz sul clock del core. Qui
serve 100, perché è il clock su cui è costruito tutto il budget
([`22_STUDIO_LATENZA`](22_STUDIO_LATENZA.md)). Il valore compare in **quattro
file**:

| dove | forma |
|---|---|
| `soc_params.m` | `p.budget.clockMHz = 100` ← la fonte |
| `plugin_rd.m` | `'DefaultFrequencyMHz', 100` |
| `system_top.tcl` | `CLKOUT1_REQUESTED_OUT_FREQ {100.0}`, `PCW_FPGA0_PERIPHERAL_FREQMHZ {100}` |
| `axilite.dtsi` | `clock-div = <1>` (rapporto FCLK/core) |

Quattro copie a mano di un numero da cui dipende ogni cifra di cicli che
comunichiamo. `check_refdesign` verifica che continuino a dire la stessa cosa —
compreso il divisore del device tree, che viene ricalcolato da FCLK e core.

## 24.4 Come si verifica

### `check_refdesign` — i legami fra i file

I quattro file si legano per nome e per numero, e **quando divergono nessuno
protesta**: il progetto costruisce e si comporta in modo diverso da come è
documentato. Il verificatore copre i quattro legami che possono rompersi in
silenzio: nome della board fra i due plugin, board part contro `board.xml`,
frequenza contro `soc_params`, nomi delle istanze che `plugin_rd` cita e
`system_top.tcl` deve creare.

Le estrazioni sono ancorate e **falliscono se non agganciano nulla**: un
`regexp` che torna vuoto in silenzio trasformerebbe il verificatore in un
controllo che passa sempre.

#### Provato in fallimento

| Mutazione | Esito |
|---|---|
| clock a 50 MHz in `plugin_rd` | ✅ `checkRd:clockRd` |
| nome della board diverso fra i due plugin | ✅ `checkRd:boardNameMismatch` |
| istanza rinominata nel `.tcl` | ✅ `checkRd:instMissing` |
| board part maiuscolo (`PYNQ-Z1`) | ✅ `checkRd:boardPartMismatch` |
| Vivado 2026.1 dichiarata supportata | ✅ `checkRd:vivado2026` |
| `clock-div` del device tree sbagliato | ✅ `checkRd:clockDtsi` |

### `validate_refdesign` — costruire davvero il block design

Esegue `system_top.tcl` in Vivado. Tre esiti, tenuti distinti:

| esito | significato |
|---|---|
| `completa` | il design si costruisce e valida. Serve Vivado 2022.1 o 2024.1 |
| `parziale` | Vivado c'è ma è troppo recente. Si verifica comunque il preset della board; il resto **non è provato** |
| `assente` | nessun Vivado. Niente è stato verificato |

**Su questa macchina l'esito è `parziale`** (Vivado 2026.1). Verificato: il
preset si applica dai vostri board file, e gli override sul confine PL
sopravvivono. Non verificato: interconnessione, clock del core, reset, e la
validazione del design.

> **La verifica completa è il primo atto di chi ha Vivado 2022.1.** Un solo
> comando: `validate_refdesign()`. Se l'esito non è `completa`, il messaggio
> dice cosa è mancato.

## 24.5 Cosa resta da fare a chi ha Vivado 2022.1

1. `addpath('<...>\HDL_Test\Prova_2\hdlplugins')`
2. `validate_refdesign()` → deve dare `completa`
3. Aprire l'HDL Workflow Advisor su `soc_wrapper_fpga`: *Digilent PYNQ-Z1* fra
   le target platform, *Default system (AXI4-Lite)* fra i reference design
   (è anche il gate G11b, la conferma manuale rimasta da P11)
4. Generare l'IP core e costruire il bitstream (P13)

Punti su cui aspettarsi attrito, tutti già noti e nessuno verificato da noi:

- **Il device tree**: `axilite.dtsi` descrive il bus PL e il rapporto di clock,
  ma non le periferiche del PS della PYNQ-Z1 (PHY ethernet, USB, SD), che
  differiscono da quelle della ZedBoard. Serve solo al flusso Linux.
- **`JTAGChainPosition = 2`**: preso dal precedente Zynq-7000, da confermare al
  primo collegamento.
- **Due CRITICAL WARNING sul DDR** all'applicazione del preset:
  `PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2/3` hanno valori negativi (−0.009,
  −0.033). Vengono dal `preset.xml` dei board file, non da noi. Sono attesi e
  vanno ignorati, non "corretti".
- **`MaxFrequencyMHz = 500`**: è il valore che MathWorks dichiara per lo stesso
  silicio sulla ZedBoard. È l'intervallo offerto nel Workflow Advisor, **non**
  una promessa di chiusura temporale: quella la dice il report di timing.

## 24.6 Un errore in cui sono caduto, per chi userà il banco

La prima versione di `validate_refdesign` ha dichiarato **`completa`** una
validazione che era certamente fallita.

Causa: Vivado in modo batch **rieccheggia il sorgente del tcl** (prefissato da
`# `). I miei pattern non erano ancorati, e `MWV: validazioneOk` agganciava la
riga `puts "MWV: validazioneOk"` dello script — che non era mai stata eseguita.
Il banco leggeva il proprio codice e lo scambiava per un risultato.

Si vede solo guardando l'output vero: `Vivado [version` come numero di versione
e una lista di celle contenente `[string`. Ancorare a inizio riga
(`'^MWV: …'` con `'lineanchors'`) risolve.

È lo stesso genere di errore del gate sul plugin board (§23.6): uno strumento
di misura che misura sé stesso. Vale la regola generale — **quando un banco
dice che è andato tutto bene, il primo dubbio è che stia leggendo la cosa
sbagliata**.
