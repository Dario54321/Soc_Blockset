# 24 — Reference design AXI4-Lite per la PYNQ-Z1 (P12)

> Passo P12, **scritto qui, da costruire da chi ha Vivado 2022.1**.
> Verificabile con `check_refdesign` (coerenza) e `validate_refdesign` (Vivado).
> Ultima esecuzione: 2026-07-31 — primo bitstream reale costruito, G13 chiuso (§24.8).

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

1. ~~`addpath('<...>\HDL_Test\Prova_2\hdlplugins')`~~ ✅
2. ~~`validate_refdesign()` → deve dare `completa`~~ ✅ **31/07, G12b chiuso**
3. ~~Aprire l'HDL Workflow Advisor su `soc_wrapper_fpga`: *Digilent PYNQ-Z1* fra
   le target platform, *Default system (AXI4-Lite)* fra i reference design~~ —
   **il caricamento del reference design ora funziona anche via script su
   R2023b** (`hdlcoder.runWorkflow`), vedi §24.8. Restava un vero bug di
   `plugin_rd.m` (API di R2026a assenti su R2023b), non solo una conferma da
   fare a mano — quel bug avrebbe molto probabilmente bloccato anche
   l'apertura da GUI su questa installazione.
4. ~~*Set Interfaces*: mappare gli outport del DUT ai registri AXI4-Lite
   dichiarati in `plugin_rd.m`~~ ✅ **31/07, fatto in due modi indipendenti**:
   da Dario in GUI (HDL Workflow Advisor), e da script con
   `downstream.DownstreamIntegrationDriver.setTargetInterface` — 13 porte
   assegnate ad `AXI4-Lite` in entrambi i casi, indirizzi auto-generati
   `0x100`–`0x130` (vedi §24.8 per l'anomalia sull'ordine di `x0`/`x1`/`x2`,
   confermata dal report reale, e per come si è scoperto che il passo è
   scriptabile e non solo GUI-only).
5. ~~Generare l'IP core~~ ✅ **31/07 — primo successo reale su questo
   progetto, ottenuto in due modi indipendenti che si confermano a vicenda**:
   a mano in GUI da Dario, e da script con
   [`run_ipcore_generation.m`](../scripts/run_ipcore_generation.m) — stesso
   esito: HDL Coder 23.2, VHDL, `Digilent PYNQ-Z1`, `xc7z020clg400-1`,
   100 MHz, workflow *IP Core Generation*, `soc_wrapp_ip` v1.0. Report
   completo in §24.8.
6. ~~Costruire il bitstream (fase "4. Embedded System Integration" nel
   Workflow Advisor, P13)~~ ✅ **31/07 — G13 chiuso, primo bitstream reale
   di Prova_2 sul `clg400` vero**. Fatto da Dario in GUI, da
   `D:\SocBuilderBuild\Prova_2_build` (serviva un percorso senza spazi, vedi
   §24.8 per il perché e per il fix). File:
   `D:\SocBuilderBuild\prova2_vivado_prj\vivado_ip_prj\vivado_prj.runs\impl_1\system_top_wrapper.bit`
   (~4 MB, timing chiuso — non rinominato `..._timingfailure.bit`).
7. ⬅ **SI RIPARTE DA QUI.** Programmare la scheda reale — due tentativi, due
   cause distinte, nessuna delle due nel bitstream in sé: (a) via
   HDL Workflow Advisor (4.4 Program Target Device, metodo SSH/IP), fallito
   per assenza di `dtc` su questa macchina; (b) via JTAG diretto
   (`vivado_download.tcl`), fallito perché la scheda non risultava collegata
   al PC. Servono entrambi: installare `dtc` (es. via WSL) **e** collegare
   fisicamente la PYNQ-Z1. Vedi §24.8 per la diagnosi completa.

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

## 24.8 — Dai punti 3-4 di §24.5 al primo IP core reale, da script e da GUI (Dario, 31/07/2026)

Tentando di scriptare i punti 3-4 di §24.5 con `hdlcoder.WorkflowConfig` +
`hdlcoder.runWorkflow` (per evitare l'interazione GUI dove possibile), sono
emersi tre problemi distinti, ciascuno verificato leggendo il codice reale
installato — non per tentativi sui nomi dei parametri.

### `hdlcoder.WorkflowConfig`: il costruttore accetta solo due proprietà

`help hdlcoder.WorkflowConfig` mostra un elenco di proprietà (`ProjectFolder`,
`RunTaskGenerateRTLCodeAndIPCore`, `RunTaskBuildFPGABitstream`, ...) che sembra
passabile al costruttore. **Non lo è.** Il sorgente reale
(`toolbox\hdlcoder\hdlcommon\+hdlcoder\WorkflowConfig.m`) dichiara esplicitamente
che il costruttore accetta solo `'SynthesisTool'` e `'TargetWorkflow'`; è un
thin wrapper su `hwcli.WorkflowConfig(varargin{:})`. L'oggetto restituito è di
classe `hwcli.config.IPCoreConfig` (verificato con `class()`): tutte le altre
proprietà esistono davvero (verificato con `properties()`/`metaclass()`) ma
vanno assegnate **dopo**, per notazione punto (`cfg.RunTaskCreateProject =
false`), non come coppie nome-valore del costruttore.

Serve anche allineare il modello: `hdlset_param(mdl,'Workflow','IP Core
Generation')`, altrimenti `hdlcoder:workflow:ModelWorkflowMismatchConfig`.

### `plugin_rd.m` chiama due metodi che su R2023b non esistono

Lanciando `hdlcoder.runWorkflow` sul vero `soc_wrapper_fpga.slx`, il plugin
`PYNQZ1.vivado_base_2022_1.plugin_rd` viene scartato con *"Unrecognized method,
property, or field 'addRegisterInterface' for class
'hdlturnkey.plugin.ReferenceDesignVivado'"*. Verificato con
`methods(hdlcoder.ReferenceDesign('SynthesisTool','Xilinx Vivado'))` su questa
installazione R2023b: **`addRegisterInterface` non esiste**, e nemmeno
`addFPGADataCaptureInterface` (usato più sotto nello stesso file). Il commento
originale a riga 22-24 del file lo conferma: *"Queste sono le versioni
supportate da HDL Coder R2026a"* — il plugin è stato scritto e verificato
contro l'API di R2026a, non R2023b. Su questa macchina è installato solo
R2023b.

Questo non è "serve la GUI": è un plugin che su questa release **non si carica
proprio**, il che avrebbe molto probabilmente impedito anche alla GUI di
mostrare *Digilent PYNQ-Z1* / *Default system (AXI4-Lite)* come opzioni, dato
che il reference design viene scartato come invalido prima di qualunque
interazione utente.

**Fix verificato, applicato al file reale:**

- `addRegisterInterface(...)` → `addAXI4SlaveInterface(...)`, con
  `'MasterAddressSpace'` al posto di `'ManagerAddressSpace'`. Non è una
  supposizione: l'esempio ufficiale in
  `toolbox\hdlcoder\hdlcommon\+hdlcoder\ReferenceDesign.m` usa esattamente
  questa firma. `HasProcessorConnection` e `DeviceTreeBusNode` non compaiono
  in quell'esempio (il metodo è un builtin p-coded, "undocumented", senza
  `help` consultabile) ma sono stati accettati senza errore in esecuzione
  reale.
- `addFPGADataCaptureInterface(...)` commentato, non riscritto: non è un
  rinomino, è una funzionalità assente da tutto il toolbox `hdlcoder` di
  R2023b (nessuna occorrenza di "DataCapture", nessun metodo simile in
  `methods()`). Per commento originale di Carmine "non serve al
  funzionamento" — da confermare con lui se serve un'alternativa (es. ILA
  manuale nel block design Vivado) o se questa capability resta riservata a
  R2026a.

Risultato dopo il fix: il reference design si carica, nessun warning "Invalid
plugin", e `hdlcoder.runWorkflow` procede fino alla compilazione HDL vera del
modello.

**Attenzione per chi lavora anche su R2026a**: `addRegisterInterface` lì
esisteva (è per cosa il file era scritto). Se questo plugin deve tornare a
girare anche su R2026a, va verificato che `addAXI4SlaveInterface` esista
ancora in quella release con lo stesso significato prima di assumere che la
patch sia valida ovunque.

### Il passo "Set Interfaces": prima conclusione sbagliata, poi corretta

Dopo i due fix sopra, `hdlcoder.runWorkflow` arriva più avanti e si ferma con
*"At least one subsystem outport need to be assigned with Interface"*
(`hdlcommon:workflow:NoInterfaceAssigned`) — serve mappare ogni outport del DUT
al registro AXI4-Lite corrispondente.

Prima ricerca: nessun riscontro nei cataloghi messaggi, nessun metodo
pertinente in `hdlcoder.Board`/`hdlcoder.ReferenceDesign`, nessuna chiave
rilevante negli schema JSON della Workflow Advisor app
(`hdlcoder_apps\hdlconfig_app\schemas\params\ports.json` copre solo opzioni di
I/O bit-width). Il sorgente del toolstrip
(`toolbox\hdlcoder\toolstrip\mfiles\hdlToolStrip.m`) mostrava solo un oggetto
interno (`hDI.hTurnkey.hTable`, con `savePortInterfaceToModel`) raggiungibile
dalla catena di callback GUI. Su questa base la prima stesura di questo
paragrafo concludeva **"è genuinamente GUI-only"**. **Era sbagliato — vedi
sotto.** È la stessa lezione di §24.3 sull'`axi_interconnect`: una ricerca
onesta ma non ancora sufficientemente a fondo può comunque produrre una
conclusione falsa.

**Correzione (stesso giorno, dopo che Dario aveva già completato il passo a
mano in GUI — vedi sottosezione successiva):** esiste un'API pubblica, non
ristretta, che fa esattamente questo:
`downstream.DownstreamIntegrationDriver`, ottenibile con
`hDI = downstream.DownstreamIntegrationDriver(mdl)` seguito da
`hDI.loadTopLevelSettings(); hDI.loadModelSettings();` (questi due leggono la
configurazione già scritta sul modello via `hdlset_param` — non serve
richiamare `loadTool`/`setBoardName`/`setReferenceDesign`, che sono invece
`MethodRestricted`, verificato con l'identifier esatto
`MATLAB:class:MethodRestricted`, quindi quelli sì non richiamabili da fuori).
Poi:

```matlab
hDI.setTargetInterface('start_cmd', 'AXI4-Lite');   % e così per ogni porta
```

Le scelte valide non erano da indovinare: **il messaggio d'errore stesso le
elenca** quando si passa un valore non valido — `getTargetInterface`/
`setTargetInterface` sono un'API di sola lettura/scrittura per porta, senza
bisogno della classe `hdlturnkey.table.TargetInterfaceTable` (che esiste ma
richiede uno stato interno più complesso da popolare, non necessario qui).
Assegnando `'AXI4-Lite'` a tutte le 13 porte e richiamando
`hdlcoder.runWorkflow` nello **stesso processo MATLAB** (lo stato vive
sull'oggetto modello in memoria, non su file), il workflow è arrivato a
`WORKFLOW_OK` — RTL, VHDL, IP core packaging Vivado reale, IP
`soc_wrapp_ip` v1.0 — **interamente da script, zero interazione GUI**, in
parallelo e indipendentemente dal risultato ottenuto da Dario in GUI (stesso
identificatore `AXI4-Lite`, stesse 13 porte: doppia conferma incrociata).

Conclusione corretta: il punto 4 di §24.5 **è scriptabile**. Resta vero,
invece, che senza i due fix precedenti (WorkflowConfig, plugin_rd.m) né lo
script né la GUI arrivavano a questo punto.

La ricetta è formalizzata in
[`scripts/run_ipcore_generation.m`](../scripts/run_ipcore_generation.m):
`addpath('hdlplugins'); run_ipcore_generation()` rigenera RTL + IP core da
zero, senza toccare l'HDL Workflow Advisor. Verificato di nuovo, come script
autonomo (non solo inline in una prova), stesso esito `WORKFLOW_OK`.

### Conferma: la GUI si apre davvero, dopo `addpath('hdlplugins')` nella sessione interattiva

Eseguito da Dario il 31/07/2026, HDL Workflow Advisor su `soc_wrapper_fpga`,
Vivado 2022.1 reale:

- **1.1 Set Target Device and Synthesis Tool**: *Digilent PYNQ-Z1* non compariva
  nel menu "Target platform" finché non si è eseguito `addpath('hdlplugins')`
  **nella sessione MATLAB interattiva stessa** (non basta averlo fatto in uno
  script batch separato — ovvio con il senno di poi, ma vale la pena scriverlo:
  la GUI legge il path della sessione in cui gira, non quello di un processo
  MATLAB diverso). Dopo l'`addpath`, la board compare e i campi Family/Device/
  Package/Speed risultano già `Zynq`/`xc7z020`/`clg400`/`-1` — corretti.
- **1.2 Set Target Reference Design**: *Default system (AXI4-Lite)* si carica
  senza errori — conferma diretta che il fix di §24.8 funziona anche lato GUI,
  non solo da script. HDL Verifier non è licenziato su questa macchina
  (verificato con `license('test','HDL_Verifier')` → `0`): sia "Insert AXI
  Manager" sia "FPGA Data Capture" vanno lasciati su `off`.
- **1.3 Set Target Interface**: le 13 porte del wrapper (`start_cmd`,
  `timeout_thr`, `x0..x5`, `done`, `busy`, `timeout_flag`, `cycles`, `u0`)
  assegnate tutte a `AXI4-Lite`, indirizzi auto-generati `0x100`–`0x130`.
  **Nota per chi scriverà il driver software**: gli indirizzi di `x0`, `x1`,
  `x2` NON sono nell'ordine "naturale" che ci si aspetterebbe scorrendo la
  tabella dall'alto (sarebbe `x0=0x108, x1=0x10C, x2=0x110`); HDL Coder li ha
  assegnati come `x1=0x108, x2=0x10C, x0=0x110` — il blocco di tre indirizzi è
  giusto, ma scambiato fra le tre porte. Da `x3` in poi torna sequenziale.
  **Non ritrascrivere questi offset a mano in nessun driver C**: vanno presi
  dall'header/report generato da questo stesso passaggio (task "Generate
  Software Interface" più avanti nel workflow), esattamente per lo stesso
  motivo per cui §6 diceva di non trascrivere a mano la mappa registri — qui
  vale doppio, visto l'ordine non intuitivo.
- **2.1 Check Model Settings**: "Modify All" applicato senza rischio —
  `Algebraic Loop` warning→error (coerente con l'accorgimento nondirect
  feedthrough già in `build_wrapper_fpga.m`), `Block reduction` on→off,
  `Conditional input branch execution` on→off (riguarda anche `u_latch`, uno
  Switch). Sono le tre raccomandazioni standard di HDL Coder, non specifiche
  al progetto.
- **3.2 Generate RTL Code and IP Core**: ✅ **successo, primo su questo
  progetto**. Nessuna opzione toccata rispetto ai default (FPGA Data Capture
  in grigio per assenza di licenza HDL Verifier, coerente col punto 1.2).
  Dal report generato (`hdl_prj3\hdlsrc`, HDL Coder 23.2, VHDL):

  ```
  IP core name:     soc_wrapp_ip        IP core version: 1.0
  ModulePrefix:      soc_wrapp_ip_src_
  TargetPlatform:    Digilent PYNQ-Z1    ReferenceDesign: Default system (AXI4-Lite)
  SynthesisTool:     Xilinx Vivado       Chip: Zynq xc7z020 clg400 -1
  TargetFrequency:   100 MHz             Workflow: IP Core Generation

  Mappa registri (IOInterfaceMapping), confermata dal generatore — fonte
  autorevole, non il documento §6 (che descriveva uno schema CTRL/STATUS a
  bit impacchettati, superato dalla scelta di una porta scalare per registro):
    0x100  start_cmd (W)     0x110  x0 (W)      0x120  done (R)
    0x104  timeout_thr (W)   0x108  x1 (W)      0x124  busy (R)
                              0x10C  x2 (W)      0x128  timeout_flag (R)
                              0x114  x3 (W)      0x12C  cycles (R)
                              0x118  x4 (W)      0x130  u0 (R)
                              0x11C  x5 (W)
  ```

  Resta da fare: **costruire il bitstream** (fase "4. Embedded System
  Integration"), non ancora eseguita al momento di scrivere questo paragrafo.

### G13 chiuso — bitstream reale costruito (Dario, 31/07/2026)

**Problema d'ambiente serio, non di HDL Coder**: **4.1 Create Project** falliva
con *"contains white space in project path"*, sempre citando
`C:\Users\lenovo GAME\Desktop\Prove\HDL_Test\Prova_2` — lo spazio è nel nome
del profilo Windows dell'utente. Cambiare il campo GUI "Project folder" **non
basta**: il controllo guarda la *current directory di MATLAB* (`pwd`), non
quel campo. Verificato empiricamente che una **junction NTFS non risolve il
problema**: `cd` in una junction senza spazi, poi `disp(pwd)` in MATLAB
restituisce comunque il percorso fisico reale (con lo spazio) — MATLAB risolve
le junction, non le tratta come alias opachi.

**Fix reale**: copiare fisicamente `models/`, `hdlplugins/`, `scripts/` in un
percorso senza spazi (`D:\SocBuilderBuild\Prova_2_build\`), **dopo** aver
fatto salvare a Dario il modello nella sua sessione GUI live (`Ctrl+S`/
`save_system`) — la configurazione HDL Coder (piattaforma, reference design,
interfacce) è tutta nei parametri del modello, verificato che sopravviva alla
copia (`hdlget_param`/`hdlget_param` per-porta, stessi valori, stessa mappa
indirizzi). Poi un secondo errore, *"Duplicate plugin path... found from two
registration functions"*: la vecchia `hdlplugins` (dal path della sessione)
e la nuova coesistevano su MATLAB path — risolto con `rmpath` sulla vecchia
più `sl_refresh_customizations` (necessario: la cache di registrazione plugin
di Simulink non si aggiorna da sola solo togliendo dal path).

**Risultato, da `D:\SocBuilderBuild\Prova_2_build`**: 4.1 Create Project → 4.2
Generate Software Interface → **4.3 Build FPGA Bitstream, tutti ✅**. Bitstream
reale confermato su disco:
`D:\SocBuilderBuild\prova2_vivado_prj\vivado_ip_prj\vivado_prj.runs\impl_1\system_top_wrapper.bit`
(~4 MB, non `..._timingfailure.bit` — quindi timing chiuso, non solo "si è
costruito"). **Primo bitstream reale di Prova_2 sul silicio vero (`clg400`)**,
diverso dal bitstream del filone A (`prove_2/MatMul_*`, quello era su ZedBoard
proxy via SoC Builder).

**4.4 Program Target Device: fallito, causa diagnosticata, non bloccante.**
Log troncato ("Device tree compilation failed with message:" e basta).
Verificato (`where dtc`/`where dtc.exe`, ricerca in tutto l'albero Vivado
2022.1): **nessun `dtc` (device tree compiler) installato su questa macchina**
— non solo assente dal path, assente proprio dall'installazione Vivado.
`dtc` viene normalmente da un toolchain PetaLinux/Linux, non è incluso in
Vivado su Windows. Il task fallisce prima ancora di provare la connessione
SSH alla scheda (`Programming method: Download`, IP/SSH — non JTAG, come
inizialmente ipotizzato in §24.5). **Non blocca il bitstream**, che resta
valido e utilizzabile indipendentemente da questo passo; da riprendere
quando serve davvero programmare la scheda (serve installare `dtc`, es. via
WSL o un binario Windows precompilato — non ancora fatto, non urgente).

**Tentativo alternativo, via JTAG diretto**: bypassando l'interfaccia
software (che richiede `dtc`), un tentativo con un `.tcl` scritto a mano
(`vivado_download.tcl`, flusso classico Vivado Hardware Manager —
`open_hw`/`connect_hw_server`/`get_hw_targets`) fallisce con un errore
**diverso e indipendente**: `ERROR: [Labtoolstcl 44-199] No matching targets
found on connected servers: localhost`. Verificato (`Get-PnpDevice` su
Windows): nessun dispositivo Digilent/FTDI/JTAG risultava collegato al PC nel
momento del tentativo. Non è quindi (solo) un problema di `dtc`: **anche il
percorso JTAG, che non ne ha bisogno, resta bloccato finché la scheda non è
fisicamente collegata**. I due tentativi falliscono per due cause distinte e
indipendenti — entrambe da risolvere prima di programmare davvero la scheda.
