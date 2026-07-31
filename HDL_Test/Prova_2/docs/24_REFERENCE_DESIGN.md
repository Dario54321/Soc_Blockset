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

**~~`axi_interconnect` non esiste più dalla 2026.1.~~ — SBAGLIATO, vedi §24.7.**
Questa conclusione era scritta qui il 29/07 sulla base di `get_ipdefs`, che
restituisce vuoto. È falsa: l'IP c'è su disco, si istanzia, e il design valida
anche su Vivado 2026.1. `get_ipdefs` non è una prova di esistenza
([`11_NOTE_API` §16](11_NOTE_API.md)).

Resta vero che l'IP giusto è **`axi_interconnect:2.1`**, quello di tutti i
reference design MathWorks, e che **HDL Coder R2026a supporta Vivado fino alla
2024.1** — ma quel limite viene dal prodotto MathWorks, non dal block design.

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

## 24.6bis — G12b risolto (31/07/2026): `axi_interconnect` "Discontinued" sulla 2.1 di questa istanza Vivado 2022.1

`validate_refdesign()` su questa macchina (Vivado 2022.1 reale, non 2026.1) dava
`esito='parziale'` anche **dopo** aver installato i board file corretti (preset
applicato, `ddrPart` giusto — quindi non era più il problema del §24.5). Causa
reale, dal log completo (non dal riassunto stampato per il ramo `parziale`, che
è testo fisso pensato per la 2026.1 e qui fuorviante):

```
ERROR: [BD 5-313] Found unsupported IP 'xilinx.com:ip:axi_interconnect:1.7' in design.
```

**`mw_ip` (risoluzione dinamica via `get_ipdefs` con wildcard) trova solo la
versione `1.7`**, che il catalogo IP di questa installazione marca
`Discontinued` per **tutte** le famiglie (verificato via
`get_property SUPPORTED_FAMILIES`) — non solo zynq, non è quindi (solo) il
"rimosso dopo la 2024.1" ipotizzato sopra. `create_bd_cell` rifiuta di
istanziare un IP così marcato, a prescindere dalla parte target: confermato
isolando il problema (`axi_gpio`/`clk_wiz` si istanziano senza problemi sulla
stessa parte, quindi non è un blocco della parte).

**La versione `2.1`** — quella che usa il reference design **ufficiale
MathWorks** (`+ZedBoard/+vivado_base_2022_1/system_top.tcl` riga 188, cablata
senza `get_ipdefs`) — **esiste realmente su disco**
(`data/ip/xilinx/axi_interconnect_v2_1/component.xml`, `name=axi_interconnect
version=2.1`), ma `get_ipdefs` (anche con VLNV esatto, anche dopo
`update_ip_catalog -rebuild`, anche aggiungendola come `ip_repo_paths`
esplicito — Vivado la ignora perché "already part of the Xilinx supplied IP
repositories") **non la elenca**. Solo l'istanziazione **diretta** per VLNV
(`create_bd_cell -vlnv xilinx.com:ip:axi_interconnect:2.1`, bypassando
`get_ipdefs`) funziona — verificato isolatamente prima di toccare il file
reale.

**Fix applicato**: `mw_ip` ora restituisce `xilinx.com:ip:axi_interconnect:2.1`
per un valore fisso quando `name eq "axi_interconnect"`, **senza** passare
dalla ricerca dinamica — esattamente come fa il file MathWorks originale.
Nessun'altra chiamata a `mw_ip` (per altri IP) è toccata: il meccanismo
dinamico resta per tutto il resto, dove ha sempre funzionato.

**`validate_refdesign()` dopo il fix**: `esito='completa'` (confermato). G12b
chiuso.

> Nota per chi legge questo su una macchina diversa: se lì il catalogo IP
> espone correttamente la 2.1 in `get_ipdefs`, il fix è comunque innocuo (la
> restituisce comunque, solo non dinamicamente) — non introduce una
> regressione su installazioni dove il problema originale non si presenta.

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

---

## 24.7 Prima esecuzione su Vivado 2022.1 reale (Dario, 30/07/2026)

Il reference design è stato eseguito per la prima volta su una Vivado davvero
supportata. Esito e correzioni che ne sono seguite.

### Cosa ha funzionato

- I board file della PYNQ-Z1, installati nel percorso di default di Vivado
  (`<Vivado>\data\boards\board_files\pynq-z1\1.0\`), sono riconosciuti **senza
  bisogno di `board.repoPaths`**. Le impronte SHA-256 combaciano con
  `board_files_manifest.m`: la stessa revisione su due macchine.
- Prima dei board file: `esito='fallita'` con
  `ERROR: [Board 49-71] The board_part definition was not found for
  www.digilentinc.com:pynq-z1:part0:1.0` — l'identificatore minuscolo di §24.3 è
  quello giusto anche lì.
- Dopo: `esito='parziale'`, **preset della board applicato**,
  `ddrPart='MT41J256M16 RE-125'`, `fclk0='100'`. La parte più incerta del design
  — che il PS si configuri dal preset invece che da 399 righe trascritte — regge
  su una Vivado vera.

### Il blocco, e perché era colpa di questo file

```
ERROR: [BD 5-313] Found unsupported IP 'xilinx.com:ip:axi_interconnect:1.7' in design.
```

La 1.7 non è la versione che questo design vuole: vuole la **2.1**, che è quella
usata da **tutti** i reference design MathWorks e dagli esempi SoC Blockset (385
occorrenze nell'installazione, nessuna diversa). Su quella macchina la 2.1 è
presente **su disco** (`axi_interconnect_v2_1\`) ma non era **in catalogo**.

La causa prossima è quella installazione; la causa vera è stata questo file.
`mw_ip` risolveva la versione a runtime prendendo *la più alta in catalogo*.
Verificato che la logica in sé sceglie correttamente la 2.1 quando entrambe sono
in catalogo — quindi lì il catalogo esponeva solo la 1.7, e lo script l'ha
**istanziata senza dire nulla**, lasciando morire il progetto duecento righe
dopo con un errore che non nomina la causa.

**Scegliere una versione di IP è una configurazione, non un dettaglio da
dedurre.** Le versioni ora stanno in una tabella esplicita (`MW_IP_VER` in cima
a `system_top.tcl`) e sono quelle di MathWorks.

> Nota sul difetto latente scoperto verificando: l'ordinamento era
> **lessicografico**, quindi fra `1.9` e `1.10` avrebbe scelto `1.9`. Non è il
> problema incontrato, ma sarebbe arrivato. Con le versioni fissate non esiste
> più.

### E una seconda correzione, perché la prima era ancora sbagliata

La prima versione di questa correzione fissava sì le versioni, ma **verificava
con `get_ipdefs` che l'IP fosse in catalogo prima di usarlo**, fermandosi con un
messaggio se non c'era. Sembrava prudente. Su quella stessa macchina **avrebbe
bloccato un design perfettamente costruibile**: `get_ipdefs` non elenca
`axi_interconnect:2.1`, ma `create_bd_cell` la istanzia senza alcun problema e
il design intero valida ([`11_NOTE_API` §16](11_NOTE_API.md)).

Il catalogo IP **non è una fonte affidabile di esistenza**. Ora `mw_ip` usa la
versione fissata e basta; `get_ipdefs` resta solo come **diagnostica** — se non
elenca ciò che stiamo per istanziare lo dice, e se poi `create_bd_cell` fallisce
quel messaggio è il contesto per capire perché. Avvisa, non sbarra.

È la stessa lezione di §24.6 in un'altra forma: uno strumento di verifica che
non è stato provato sul caso vero rischia di bloccare il caso giusto invece di
prendere quello sbagliato.

### Il banco stampava una spiegazione, non una causa

Segnalato da chi l'ha eseguito: nel ramo `parziale`, `validate_refdesign`
stampava un testo fisso — *"questo Vivado non ha axi_interconnect, rimosso dopo
la 2024.1"* — che era vero sulla macchina dove il banco era stato scritto e
**falso e depistante** su una 2022.1, dove la causa era un'altra.

È la trappola peggiore di uno strumento di misura: dare una spiegazione
plausibile al posto del dato. Ora il banco riporta la **causa osservata** —
l'errore del tcl per intero e le righe `ERROR`/`CRITICAL WARNING` del log — e
non ipotizza nulla.

### Esito: G12b chiuso

Con `axi_interconnect` fissato a `2.1` e istanziato direttamente,
`validate_refdesign()` su Vivado 2022.1 reale dà **`esito='completa'`,
`designValidato=1`**. Il reference design non è più solo scritto: **si costruisce
e valida**. Log e dettagli in §24.6bis.

Resta aperto il punto 2 di P12bis: la conferma manuale che *Digilent PYNQ-Z1*
compaia nel menu del Workflow Advisor (gate G11b).
