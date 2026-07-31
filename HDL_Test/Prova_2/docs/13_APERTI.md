# Punti aperti e prossimi passi

> Stato al **31/07/2026**. Tutto ciò che segue è **noto, verificato e non ancora
> fatto**. Chi riprende il lavoro parte da qui — e chi ha Vivado 2022.1 parte
> dalla sezione «Chi fa cosa adesso».

---

## A0 — RIORIENTAMENTO: il bersaglio è cambiato

Informazioni arrivate dopo la costruzione di `Prova_2`, che ne cambiano il target:

1. **Il calcolo non è nel nostro perimetro.** L'inversione 3×3 è dentro un blocco
   FPGA di un altro ingegnere, le cui scelte non sono negoziabili. Il nostro
   perimetro è il **trasporto + il wrapper** in cui quel blocco si innesta.
   → Contratto d'interfaccia in [`20_CONTRATTO_INTERFACCIA.md`](20_CONTRATTO_INTERFACCIA.md).
2. **Il payload reale è una 3×1**, non 25 elementi: **12–16 byte**, contro un
   break-even registri↔DMA di ~114 B bare-metal e ~900 B con driver Linux.
3. **Budget d'anello dichiarato: 33 µs** (da un paper, *non misurato da noi*).

### Conseguenza: il trasporto passa a AXI4-Lite

`budget_report()` calcola l'equazione di progetto. Con `nx=6, nu=1` a 100 MHz
(3300 cicli totali) — **due** vettori 3×1, non uno, come chiarito dopo la prima
stesura di questa sezione:

| trasporto | stack PS | trasporto | cicli per il calcolo |
|---|---|---:|---:|
| **axi4lite** | **baremetal (polling)** | **1.5 µs** | **3150** |
| axi4lite | linux mmap | 10 µs | 2300 |
| axi4lite | linux, driver kernel | 50 µs | **budget esaurito** |
| axi4stream | baremetal (polling) | 2.0 µs | 3100 |
| axi4stream | linux mmap / driver | 32 µs | 100 |

> La curva su altre taglie di payload è in
> [`20_CONTRATTO_INTERFACCIA` §9](20_CONTRATTO_INTERFACCIA.md); i cicli
> effettivamente disponibili al blocco di calcolo, tolto l'overhead del
> wrapper, in [`22_STUDIO_LATENZA`](22_STUDIO_LATENZA.md).

Due letture:

- **Il DMA su Linux lascia 100 cicli al calcolo**: è squalificato dall'aritmetica,
  non da una preferenza. Il costo fisso di setup+interrupt è ~32 µs
  indipendentemente dal fatto che i byte siano 12 o 12000.
- **Lo stack software pesa quanto il trasporto.** PYNQ/Python su Linux va benissimo
  per bring-up e debug; per l'anello a regime serve bare-metal o Linux+mmap in
  polling. Va misurato: le costanti in `soc_params` sono ordini di grandezza da
  letteratura, non misure sulla nostra board.

### Cosa si tiene e cosa cambia

| Si tiene | Cambia |
|---|---|
| struttura a tre modelli, ricette di configurazione | payload: 25 elementi → `nx` parametrico |
| suite di regressione e metodo dei gate | trasporto: AXI4-Stream → AXI4-Lite |
| board plugin PYNQ-Z1, reference design, bring-up | contenuto del modello FPGA: reshape → CSR + FSM start/done |
| regola R2023b, convenzioni, documentazione | reference design: `+vivado_stream_2022_1` → `+vivado_base_2022_1` (più piccolo) |

Il tempismo è favorevole: eravamo fermi prima di P9, cioè prima di investire sulla
parte specifica dello stream. E spariscono tre dei quattro segnaposto di
[A2](#a2--segnaposto-ancora-presenti): priming dei buffer, back-pressure, nome del
device DMA.

> **Stato del codice** *(aggiornato 29/07)*. `soc_params.m` contiene il bersaglio
> corrente e `p.transport.kind` è ormai `'axi4lite'`: il wrapper esiste ed è
> verificato. I modelli del Test 1 restano come implementazione AXI4-Stream della
> stessa interfaccia, per quando il payload supererà i ~10–12 elementi.
> Finché `p.mpc.confirmed` è `false`, ogni sessione emette un avviso: si sta
> progettando su ipotesi, e dev'essere visibile.

---

## A1 — ~~BLOCCANTE~~ superato dal riorientamento: `tdata` vettoriale non è generabile

> **Non è più un bloccante** dal 28/07: con AXI4-Lite il dato non viaggia più su
> AXI4-Stream. Resta qui perché l'analisi è valida e torna utile **se e quando**
> il payload supererà il break-even e si tornerà allo stream. Vedi §«Cosa resta
> di A1» in fondo.

**Stato allora**: il modello FPGA riceve `tdata` come **vettore di 25 elementi
`int32`**. Va bene in simulazione (la catena end-to-end è bit-esatta, gate G7 verde),
ma **non arriva in hardware**.

**Perché**, con le fonti (dettaglio in [`12_RICERCA_TOOLCHAIN.md` §5.3](12_RICERCA_TOOLCHAIN.md)):

- In modalità vettoriale (`SamplePackingDimension = 'All'`) i 25 × int32 = **800 bit**
  finiscono in **un solo campione TDATA**, mentre il reference design ammette solo
  32 / 64 / 128 bit → errore `SubPortNotFitRDOverride`.
- Su porta vettoriale si può mappare **solo `Data`**, non `Valid`/`Ready`
  (`SubPortVectorPortIOMapping`) → niente handshake esplicito.
- Mappando su `External Port`, HDL Coder appiattisce il vettore in porte scalari →
  `IOThresholdExceeded`, e il messaggio del prodotto è esplicito: *"the generated
  code is not synthesizable"*. **È esattamente il 729 % di IOB di `Prova_1`.**

**Soluzione, che è il pattern shipped di MathWorks** (`soc_hwsw_stream_top.slx`):
**due modelli FPGA dentro un Variant Subsystem.**

```
FPGA (Variant Subsystem, controllo 'simmode')
 ├── "Frame based processing"  → soc_fpga_frame.slx    tdata vettoriale (25)  · simulazione veloce
 └── "Sample based processing" → soc_fpga_sample.slx   tdata scalare          · generazione HDL
```

> **Attenzione ai nomi.** L'attuale `models/soc_fpga.slx` è **la variante
> frame-based** (`tdata` vettoriale a 25 elementi). Nel refactoring va rinominato
> in `soc_fpga_frame.slx`, e va scritto ex novo `soc_fpga_sample.slx`. Il blocco
> `FPGA` del top passa da Model block a Variant Subsystem che contiene i due.

Punti chiave del pattern:
1. Il **contratto di interfaccia** (nomi porte, bus `StreamM2SBusObj`/`StreamS2MBusObj`)
   è **identico** nelle due varianti: sono intercambiabili.
2. Solo la variante sample-based porta i mapping `IOInterface`/`IOInterfaceMapping`
   verso AXI4-Stream ed è quella su cui gira l'IP Core Generation.
3. La conversione frame↔sample **non avviene nel modello FPGA**: la fa il canale DMA
   del top (`Software to AXI4-Stream`), che presenta frame al processore e stream
   all'hardware.

**Cosa comporta scrivere la variante sample-based:**
- `tdata` scalare `int32`, più `tvalid` e `tready`;
- un contatore di indice 0..24 e un banco di registri che accumula i 25 beat;
- `TLAST` per marcare la fine del pacchetto;
- l'algoritmo (reshape + sonda) si attiva quando il pacchetto è completo.

Costo: 25 cicli per vettore invece di 1. A 25–50 MHz è irrilevante.

**Alternativa scartata**: `FrameToSampleConversion`. La doc lo permette per i vettori,
ma il catalogo messaggi installato dice *"Frame-to-sample conversion is not supported
through Model Reference hierarchy"* — e in SoC Blockset il modello FPGA **è** una
model reference. Strada fragile, scartata.

---

## A2 — Segnaposto ancora presenti

Funzionano, ma non sono veri. Tutti e tre **falsificherebbero una misura** di
throughput o latenza: vanno chiusi prima di P15.

| Dove | Segnaposto | Cosa manca | Quando |
|---|---|---|---|
| `soc_fpga/unpack` | `ready = streamEnable` | **back-pressure**: la PL non può mai rifiutare un dato | con la FSM di A1 |
| `soc_proc/Writer` | `streamEnable = true` costante | **priming dei buffer**: nell'esempio un sottosistema tiene basso il segnale finché i buffer non sono pieni | dopo P7 |
| `soc_params.stream.writeDevice` | `'ip:mm2s'` | il nome vero è `<nome_ip_core>:mm2s0`, noto solo dopo la generazione dell'IP core | P12 |
| `soc_params.regchan.deviceName` | `'/dev/mwipcore'` | idem | P12 |

> Nota su `ready = streamEnable`: **non** è tornare all'errore di prima. La versione
> precedente era `ready = streamEnable && valid`, che è uno **stallo**
> ([`11_NOTE_API` §7](11_NOTE_API.md)). Quella attuale è corretta ma permissiva:
> sempre pronto.

---

## A3 — Vivado: serve la 2022.1 o la 2024.1

Su questa macchina c'è **Vivado 2026.1**, che **R2026a HDL Coder non supporta**
(elenco completo verificato su disco in `toolbox\hdlcoder\hdlcommon\+downstreamtools`:
si ferma a **2024.1**).

L'HDL generato è indipendente dalla versione, ma i **workflow integrati** — IP Core
Generation, `addCustomVivadoDesign`, SoC Builder, FIL — fanno un controllo di versione.
Il reference design da copiare dichiara `SupportedToolVersion = {'2022.1','2023.1','2024.1'}`.

→ I passi **P11 (reference design) e P12 (bitstream) sono assegnati a Dario**, che ha
la 2022.1. In alternativa, installare qui la 2022.1 (stessa di Dario: toglie una
variabile invece di aggiungerla) o la 2024.1.

---

## A4 — Board PYNQ-Z1 registrata in HDL Coder ✅ *(29/07)*

Fatto: `hdlplugins/+PYNQZ1` + `hdlcoder_board_customization.m`, gate T14, tutto in
[`23_BOARD_PYNQZ1`](23_BOARD_PYNQZ1.md). I pin non sono stati trascritti da un
manuale: vengono dai board file Vivado che il gruppo ha già installato, e il gate
li riconfronta con quelli pin per pin.

**Confermato, 31/07/2026**: *Digilent PYNQ-Z1* compare fra le target platform
nell'HDL Workflow Advisor (Dario, in GUI) e viene accettata correttamente anche da
`hdlcoder.runWorkflow` da script (report IP core generato: `TargetPlatform: Digilent
PYNQ-Z1`) — vedi [`24_REFERENCE_DESIGN` §24.8](24_REFERENCE_DESIGN.md). Resta vero,
perché è una domanda diversa e non verificata qui, che il registro delle board di HDL
Coder non espone un'API pubblica per **elencare tutte** le board registrate (§23.6):
si può usare "Digilent PYNQ-Z1" con successo senza poter chiedere al prodotto "quali
board conosci".

**Punti aperti che scaricano su P12** (reference design, Dario):

- **Device tree**: il plugin non ne dichiara. La ZedBoard usa `zynq-zed.dtsi`, che
  descrive le periferiche del PS di *quella* board. Serve solo al flusso Linux.
- **`JTAGChainPosition = 2`**: preso dal precedente Zynq-7000, non verificato su
  questa board. Si conferma al primo collegamento.
- **Board file non versionati**: stanno in Vivado
  (`C:\AMDDesignTools\Boards_Drivers\pynq-z1\1.0` su questa macchina), non nel
  repository — sono di terze parti e il pacchetto scaricato non conteneva licenza.
  Chi costruisce il bitstream deve averli installati.
- **Identificatore della board**: `www.digilentinc.com:PYNQ-Z1:part0:1.0`, con il
  `www.`. La Zybo che MathWorks distribuisce non ce l'ha: copiando da quella si
  sbaglia.

---

## A5 — Cose non verificate, da non dare per buone

- **`hdlset_param(port,'IOInterface',…)`**: la forma programmatica per mappare le
  porte della DUT sulle interfacce AXI è **presunta**, non verificata
  ([`12_RICERCA_TOOLCHAIN` §5.1](12_RICERCA_TOOLCHAIN.md)). Provarla su un modello di
  prova e rileggere con `hdlget_param` prima di metterla in uno script.
- **Nomi programmatici dei parametri di `SoC Bus Creator`/`Selector`**: usati
  `Protocol` e `ctrltype`, presi dagli artefatti. Funzionano, ma non sono documentati:
  leggerli con `get_param(blk,'DialogParameters')` se qualcosa cambia.
- **Dimensionamento dei buffer**: le formule sono applicate come vincoli in
  `soc_params`, ma **non abbiamo ancora fatto lo studio di dropout** con durate di
  task variabili (è il vero contenuto di P7).
- **Costi di trasporto** (`p.psStack.catalog`: `tAccessLite`, `tFixedDMA`): sono
  **ordini di grandezza da letteratura**, non misure su questa board. Da P10 in
  poi non sono più solo un'ipotesi interna: ci poggia il numero di cicli che
  comunichiamo all'altro ingegnere ([`22_STUDIO_LATENZA`](22_STUDIO_LATENZA.md)).
  Reggono la decisione qualitativa — lo scarto fra bare-metal e driver di kernel
  è di trentatré volte, nessun errore di stima lo ribalta — ma **non la terza
  cifra**. Vanno sostituiti da misure a P16, ed è lì che il numero passa da
  "ordine dei 3000 cicli" a un valore.

---

## Chi fa cosa adesso

> Aggiornato **31/07/2026**, dopo il primo IP core reale (§24.8).

Tre cose sono pronte a partire e **nessuna delle tre dipende da chi scrive
codice qui**. Sono elencate per proprietario, non per ordine cronologico.

### ▶ Dario — l'unica cosa immediatamente eseguibile

Il reference design **si costruisce e valida**: `validate_refdesign()` dà
`completa` su Vivado 2022.1 (G12b chiuso il 31/07). Il primo IP core reale è
già stato generato — in GUI e da script, coppia di conferme indipendenti, vedi
[`24_REFERENCE_DESIGN` §24.8](24_REFERENCE_DESIGN.md). Resta un solo passo:

1. ~~Conferma manuale che *Digilent PYNQ-Z1* e *Default system (AXI4-Lite)*
   compaiano nell'HDL Workflow Advisor~~ ✅ **31/07**. Non era solo una
   conferma da fare a mano: c'era un vero bug in `plugin_rd.m` (API scritte
   per R2026a, assenti su R2023b), corretto — vedi §24.8.
2. ~~*Set Interfaces* e generazione dell'IP core~~ ✅ **31/07** — `soc_wrapp_ip`
   v1.0, 100 MHz, VHDL. Riproducibile da script con
   [`scripts/run_ipcore_generation.m`](../scripts/run_ipcore_generation.m),
   senza aprire la GUI.
3. ⬅ **Resta da fare: il bitstream** su `clg400` vero (P13). Criterio di
   accettazione e trappole note in [`05_PROCEDURA`](05_PROCEDURA.md) P13 — in
   particolare: slack positivo su un design **che contiene registri**, e
   confronto del conteggio `IBUF`/`OBUF` con quello atteso dalle porte. Non
   ancora tentato, né in GUI né da script.

Attrito già noto e da **non** scambiare per un problema: due CRITICAL WARNING
sul DDR all'applicazione del preset. Vengono dai board file Digilent, non da noi
([`24_REFERENCE_DESIGN` §24.5](24_REFERENCE_DESIGN.md)).

### ▶ Verso l'altro ingegnere — otto domande

[`20_CONTRATTO_INTERFACCIA` §8](20_CONTRATTO_INTERFACCIA.md). Le due che
contano davvero:

- **cosa sono** i due vettori 3×1 che attraversano il confine;
- **cos'altro** lo attraverserà (i dati grezzi radar/lidar restano sull'ARM?).

La seconda decide la taglia del progetto: sopra i ~10–12 elementi il trasporto
giusto torna a essere il DMA e metà architettura cambia. Ora c'è anche un numero
da dargli: **ordine dei 3000 cicli a 100 MHz** (§5 del contratto).

### ▶ Decisione del gruppo — cosa gira sull'ARM

Bare-metal (3150 cicli) o Linux con registri mappati (2300). Non è una scelta
tecnica in senso stretto: dipende da cosa deve fare il PS oltre a questo anello.
**Il prezzo di Linux è 850 cicli, il 26 % del budget**
([`22_STUDIO_LATENZA` §22.4](22_STUDIO_LATENZA.md)). Un driver di kernel è fuori
per aritmetica. Serve decisa prima di scrivere il software del PS (P14).

---

### Dopo, quando c'è la board

5. **Bring-up**, cinque passi senza saltarne nessuno: `ID_VER` → registro R/W →
   un vettore noto → **la prima lettura reale di `CYCLES`**. È lì che si scopre
   se i 33 µs sono raggiungibili.
6. **Misurare le costanti dello stack PS** e sostituirle in `soc_params`: oggi
   sono ordini di grandezza da letteratura ([A5](#a5--cose-non-verificate-da-non-dare-per-buone)),
   ed è quello che trasforma "ordine dei 3000 cicli" in un numero.

### Chiusi di recente

| | |
|---|---|
| Wrapper AXI4-Lite su registri | ✅ 28–29/07 |
| Board plugin PYNQ-Z1 | ✅ 29/07 |
| Reference design scritto | ✅ 29/07 |
| **Reference design validato su Vivado reale (G12b)** | ✅ **31/07** |

> Il blocco su `axi_interconnect` che compariva qui fino al 30/07 **è risolto**:
> non era un problema di catalogo da rigenerare, era `mw_ip` che sceglieva la
> versione da `get_ipdefs` — comando che non è una prova di esistenza
> ([`11_NOTE_API` §16](11_NOTE_API.md)). Versione ora fissata a `2.1`.

---

### Cosa resta di A1

Il pattern Variant Subsystem e l'analisi sulla non-generabilità dei vettori restano
validi e documentati: servono **se e quando** il payload crescerà oltre il
break-even e si tornerà allo stream. Non buttarli.
