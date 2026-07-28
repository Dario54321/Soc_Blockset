> **Stato aggiornato al 28/07/2026.** Le fasi F0–F3 (qui) corrispondono ai passi
> P0–P7 della [procedura](05_PROCEDURA.md) e sono **completate**: la catena
> ARM→FPGA simula ed è bit-esatta contro il riferimento. Il blocco successivo è
> fermo su un punto tecnico noto, descritto in [`13_APERTI.md`](13_APERTI.md).
> Questo documento resta il registro delle **decisioni** e dei **rischi**; per lo
> stato operativo vedere il [README](../README.md).

# Prova_2 — Piano per portare in fondo il test di interfacciamento ARM ↔ FPGA

> Obiettivo finale del progetto: accelerare un MPC su PYNQ-Z1.
> Obiettivo di **questa** fase: un canale ARM↔FPGA che funziona, misurato, riproducibile,
> e su cui l'MPC si possa poi innestare senza rifare l'infrastruttura.

Metodo: **catena di artefatti, ognuno verificato contro il precedente**
(soc-expert ch22). Ogni fase ha un *gate* — se il gate non passa non si prosegue,
si torna indietro. Questo è ciò che trasforma il debug da ricerca a bisezione.

---

## Decisioni prese — 28/07/2026

Sotto controllo di modifica: cambiarle richiede una giustificazione scritta.

### Decisione A = **A3** · SoC Blockset per simulare, HDL Coder per deployare su PYNQ-Z1

SoC Blockset resta il modello di **architettura e simulazione** (funziona con
`Custom Hardware Board`: non serve una board supportata per simulare). Il deployment
passa per **HDL Coder IP Core Generation con board registrata a mano**.

*Alternative scartate*: A1 board supportata (ZedBoard) — scartata perché la PYNQ-Z1 è un
vincolo di progetto; A2 custom board support completo per SoC Blockset (device tree +
immagine Linux + board support API + `test(boardSupportObj)`) — scartata perché è un
sotto-progetto a sé e storicamente il punto dove i progetti si fermano.

**Cosa si guadagna**: la PYNQ-Z1, e settimane di calendario.
**Cosa si perde**: l'automatismo di SoC Builder. Il reference design in Vivado e il
software PS diventano deliverable *vostri*.

### Decisione B = **B2** · AXI4-Stream + Software to AXI4-Stream

Confermata dall'utente dopo che è stata sollevata la riserva sul dimensionamento
(200 B è sotto il break-even registri↔DMA: ~114 B bare-metal, ~900 B con driver Linux —
vedi `00_DIAGNOSI.md` D4). Si procede su stream.

**Assunzione dichiarata**: a questa taglia di payload la latenza end-to-end sarà
dominata dal costo fisso del trasferimento, non dalla banda. Questo va **misurato e
riportato**, non nascosto: il contatore on-chip dà il tempo di calcolo, il lato software
dà l'end-to-end, e la differenza *è* il costo di data movement. È un risultato valido —
ma è un risultato sul *canale*, non sull'acceleratore.

**Nota che riconcilia le due**: anche in un design streaming il piano di controllo resta
a registri. `START`/`DONE`/`ID_VER`/`CYCLES` sono AXI4-Lite comunque; il reference design
shipped di HDL Coder prevede infatti un AXI4-Lite opzionale accanto allo stream.
Non è quindi un aut-aut: F2 (register map) resta obbligatoria.

---

## Conseguenze tecniche di A3 + B2 — da leggere prima di F1

Questa combinazione ha tre vincoli concreti che cambiano il design attuale.

### C1 · Lo stream deve essere ≤ 32 bit. Il `typecast` a `uint64` va eliminato.

Il reference design shipped *"Default system with AXI4-Stream interface"* per Zynq-7000
documenta: **«AXI4-Stream Data signal: less than or equal to 32 bits»** e **«only one
AXI4-Stream Slave and one AXI4-Stream Master channel»**.

Il design attuale usa 64 bit (`ICDataWidthReader = 64`, payload `uint64`,
`typecast(U(:),'uint64')`). **Non è deployabile così.** Tre opzioni:

| | Cosa comporta |
|---|---|
| **C1a · passare a `sfix32_En16` sullo stream** *(consigliata)* | 25 beat da 32 bit su un canale. È **esattamente** la forma già prototipata in `FPGA_Prova1_fixedpoint.slx` (`fixdt(1,32,16)`, dim 25). Anticipa la decisione fixed-point, che per l'MPC va presa comunque |
| C1b · spezzare ogni double in due beat da 32 bit | conserva la precisione double ma raddoppia i beat e aggiunge logica di ricomposizione lato PL; il double resta comunque non sintetizzabile senza Native FP |
| C1c · reference design custom con DMA a 64 bit | possibile ma vi togliete l'unico pezzo che potevate riusare così com'è |

→ **Adottata C1a.** Effetto collaterale positivo: elimina l'intero problema del
`typecast`, che è la fonte delle tre varianti divergenti della funzione di reshape.

### C2 · Il reference design è un deliverable vostro

Non partite da zero: **copiate il plugin del reference design shipped** e cambiategli
board. Servono tre file su path MATLAB:

```
hdlcoder_board_customization.m        →  registra il board plugin
+pynqz1/plugin_board.m                →  hdlcoder.Board
                                          FPGAVendor='Xilinx', FPGAFamily='Zynq'
                                          FPGADevice='xc7z020', FPGAPackage='clg400'
                                          FPGASpeed='-1', SupportedTool={'Xilinx Vivado'}
                                          JTAGChainPosition=2
hdlcoder_ref_design_customization.m   →  registra il reference design plugin
+pynqz1/+axistream/plugin_rd.m        →  hdlcoder.ReferenceDesign
                                          BoardName='PYNQ-Z1'
                                          addAXI4StreamInterface(...)   ← verso l'AXI DMA
                                          addAXI4SlaveInterface(...)    ← AXI4-Lite di controllo
                                          addClockInterface(...)
                                          CustomFiles = { <tcl del base system> }
```

Il `.tcl` del base system va adattato alla PYNQ-Z1: configurazione PS7 (DDR3 della
scheda, clock, MIO), AXI Interconnect, AXI DMA, reset. È la parte di lavoro reale di C2.

### C3 · Il lato PS: usate il framework PYNQ, non un driver scritto a mano

DMA significa quattro responsabilità che passano al software: allocazione fisicamente
contigua, asincronia, manutenzione cache (**flush prima che il device legga, invalidate
dopo che il device ha scritto**), descrittori. Il framework PYNQ le copre quasi tutte:
`allocate()` per il buffer contiguo, `dma.sendchannel.transfer()` /
`recvchannel.transfer()` per il movimento.

→ Il lato ARM del *test di interfacciamento* si scrive in Python su PYNQ.
Quando arriverà l'MPC vero sull'ARM (per il confronto di baseline) quello sarà C
generato da Embedded Coder, compilato sulla stessa board — sono due cose distinte
e non vanno confuse.

---

## Struttura target della cartella

```
Prova_2/
  models/
    soc_top.slx        Variable-step · ProcessingUnit=None · Task Manager · Software to AXI4-Stream
    soc_fpga.slx       Fixed-step    · ProcessingUnit=FPGA · algoritmo PL (target HDL codegen)
    soc_proc.slx       ProcessingUnit=APU · algoritmo SW (pilotato dal Task Manager)
  scripts/
    soc_params.m       UNICA fonte di verità: dimensioni, formati, Ts, offset registri
    gen_vectors.m      generatore vettori di test, seed fisso
    build_hdl.m        codegen HDL + IP core scriptata
    run_regression.m   un comando → pass/fail
  hdlplugins/          ← su path MATLAB (Decisione A3)
    hdlcoder_board_customization.m
    hdlcoder_ref_design_customization.m
    +pynqz1/plugin_board.m
    +pynqz1/+axistream/plugin_rd.m
    +pynqz1/+axistream/base_system.tcl
  ps/                  lato ARM: notebook / script Python PYNQ + driver
  vivado/              progetto e report, tutti rigenerabili da script
  docs/                questo piano + il contratto dati + le decisioni
```

Regola: **una decisione, un posto solo**. Se due file possono definire la stessa cosa,
uno dei due è di troppo — è esattamente così che è nato il bug `matB`.

---

## Le fasi, con i loro gate

### F0 · Congelare il benchmark  *(mezza giornata)*
Non "due matrici a caso": il **vero** benchmark MPC, scritto e messo sotto controllo
di modifica. Servono: modello del plant, `n_x`, `n_u`, orizzonte `N`, periodo `Ts`,
pesi, insieme dei vincoli, algoritmo QP scelto **con giustificazione hardware**
(quante divisioni? quante radici? le matrici per iterazione hanno forma costante?
il numero di iterazioni è certificabile?).

Per il car-following i valori di riferimento comparabili con MathWorks sono:
`Ts = 0.1 s`, `N = 30`, `t_gap = 1.4 s`, `d₀ = 10 m`, `u ∈ [−3, +2] m/s²`, `v ∈ [0, 50] m/s`.

> **Gate G0**: benchmark scritto; baseline software misurata su ARM con compilatore e
> flag dichiarati (`-O3`, non `-O0`); versioni tool bloccate (R2023b, Vivado 2022.1).

Nota: le due matrici 3×3 e 4×4 attuali restano utili — ma come **payload di prova
dell'infrastruttura**, non come benchmark. Vanno dichiarate tali.

---

### F1 · Ristrutturazione in tre modelli  *(1–2 giorni)*
Questo è il passo che sblocca socBuilder e chiude il problema Variable/Fixed.

1. `soc_fpga.slx` — nuovo modello, `Processing Unit = FPGA`, **Solver Fixed-step**.
   Ci va dentro solo ciò che diventerà hardware. Rate singolo.
2. `soc_proc.slx` — nuovo modello, `Processing Unit = APU`. L'algoritmo che oggi sta
   in `Subsystem`/`ComputeAlgorithm`.
3. `soc_top.slx` — `Processing Unit = None`, **Solver Variable-step**, con due blocchi
   `Model` che referenziano i due sopra, il `Task Manager` che pilota il processor ref,
   e il `Register Channel` (Decisione B1).
4. `Feature set = SoC Blockset` e **stessa board** su tutti e tre.

> **Gate G1**: il top model simula senza errori di solver o di rate; SoC Builder si apre
> e riconosce entrambi i modelli referenziati (niente più *"model not detected"*).

---

### F2 · Il contratto dati  *(mezza giornata — è il passo che vi avrebbe salvato)*
Un solo file, `docs/02_REGISTER_MAP.md` + `scripts/soc_params.m`, che definisce
offset, nome, accesso, significato **e formato numerico** di ogni campo.

```
0x00  CTRL     R/W   bit0 START (autoclear), bit1 SOFT_RESET, bit2 IRQ_EN
0x04  STATUS   R     bit0 DONE, bit1 BUSY, bit2 ERROR
0x08  X0..Xn   W     stato corrente — formato dichiarato qui
0x40  U_OPT    R     uscita — formato dichiarato qui
0x44  CYCLES   R     cicli dell'ultimo solve      ← lo strumento di misura
0x48  ITERS    R     iterazioni eseguite
0x4C  ID_VER   R     costante magica + versione   ← la prima lettura del bring-up
```

Quattro proprietà da copiare: ogni registro scrivibile ha un reset default sensato;
il formato numerico sta **nella stessa tabella** del campo; il contatore di cicli fa
parte del design dal primo giorno (~30 flip-flop, l'unica misura di latenza che il SO
non può contaminare); l'`ID_VER` esiste solo per rendere possibile il passo 2 del bring-up.

> **Gate G2**: register map congelato; header C e decode HW generati **dalla stessa
> descrizione** (mai copie sincronizzate a mano).

---

### F3 · Vettori di test e modello di riferimento  *(1 giorno)*
- Reference model in double, scritto **nell'ordine di operazioni dell'hardware**
  (stesso loop, stesso ordine di accumulo, stesso numero fisso di iterazioni).
  Non è una chiamata a `quadprog`: `quadprog` è il *cross-check*, non il giudice.
- Tre famiglie di vettori da `gen_vectors.m` con **seed fisso**: scenari realistici,
  campioni casuali uniformi sul range dichiarato, corner case (saturazioni, estremi,
  stati al bordo della feasibility).

> **Gate G3**: `run_regression.m` esiste e stampa pass/fail. Il reference è validato
> una volta contro un solver di libreria su N stati casuali, e poi mai più.

---

### F4 · Conversione fixed-point  *(1–2 settimane — è qui che si consuma il buffer)*
Sette passi (soc-expert ch03), e il criterio di accettazione si scrive **prima** del passo 1,
in unità fisiche:

1. reference double congelato → 2. raccolta range **per simulazione E per derivazione**
(la simulazione sottostima, l'analisi statica sovrastima: servono entrambe) →
3. formato iniziale volutamente largo che funziona → 4. restringimento iterativo sotto
test di accettazione fisso → 5. verifica bit-true su stimolo held-out → 6. sign-off →
7. **decisione di uscita datata**.

Leva più potente del numero di bit: **precondizionare** (equilibrazione di Ruiz).
Il riscalamento è gratis a design time e permanente; i bit si pagano in ogni
moltiplicatore, ogni ciclo, ogni joule.

> **Gate G4**: bit-true entro tolleranza su tutte e tre le famiglie di vettori.
> Fallback datato: single-precision floating point a costo di risorse maggiore.

---

### F5 · Board plugin, reference design e generazione IP core  *(1–2 settimane, il pezzo pesante di A3)*

Ordine consigliato, dal più economico al più costoso:

1. **Board plugin** (`+pynqz1/plugin_board.m`) — mezza giornata. Verifica: la PYNQ-Z1
   compare nel target selection dell'HDL Workflow Advisor.
2. **Reference design**: copiare il plugin shipped *"Default system with AXI4-Stream
   interface"* dal support package, cambiare `BoardName`, e **adattare il `.tcl` del base
   system** alla PYNQ-Z1 (PS7 con la DDR3 della scheda, clock, MIO, AXI Interconnect,
   AXI DMA, reset). Questa è la parte di lavoro reale.
   > Prima di scriverlo: cercare se esiste già un board/RD plugin PYNQ-Z1 di comunità.
   > Un'ora di ricerca contro giorni di `.tcl`.
3. **Mappatura porte → interfacce** nell'HDL Workflow Advisor: `tdata` su AXI4-Stream
   Slave (32 bit, C1a), l'uscita su AXI4-Stream Master, `CTRL`/`STATUS`/`ID_VER`/`CYCLES`
   su AXI4-Lite.
4. **`makehdl` / IP core generation scriptata** da `build_hdl.m`, mai dalla GUI.

Regole di sintesi che vengono dagli errori di `Prova_1`:
- Mai sintetizzare il subsystem come top-level con tutte le porte ai pin — è l'origine
  dei **729 % di IOB**. Dentro l'IP core con AXI, oppure `out_of_context`.
- Il design deve avere **registri**. Il `WNS = +1.029 ns` di `vivado_synth_fixedpoint`
  è un path combinatorio pad-to-pad e sparirà appena entrano pipeline e AXI: non è
  un risultato di timing closure.

> **Gate G5**: il Verilog generato riproduce il modello fixed-point sulla suite di
> regressione; bitstream costruito; utilization e timing con slack positivo, da report
> salvati e rigenerabili da script.
> **Verifica esplicita e attiva**: che l'HDL corrisponda al modello. Il bug `matB`
> (offset `+9` mancante) va *cercato*, non dato per assente. Controllo economico:
> confrontare il conteggio IBUF/OBUF con quello atteso dalle porte — è così che è
> emerso la prima volta.

---

### F6 · Software PS e bring-up  *(1 settimana)*
Lato ARM in Python su immagine PYNQ (C3): `Overlay()`, `allocate()`,
`dma.sendchannel.transfer()` / `recvchannel.transfer()`, e accesso ai registri di
controllo via `MMIO`.
Cinque passi, in ordine, senza saltarne uno:
1. la board fa boot e la configurazione carica;
2. **leggi `ID_VER`** e confronta con la costante → prova l'intero percorso bus,
   decode, clock, reset con una sola lettura;
3. scrivi e rileggi un registro R/W → le scritture funzionano;
4. **un vettore noto**, confronta risultato **e conteggio cicli** con la simulazione;
5. la suite completa dal lato software → validazione di massa in percentuale.

I tre guasti classici sono **fallimenti di contratto, non di logica**: mismatch di
indirizzo/offset, polarità del reset, formati numerici interpretati diversamente ai
due capi. Tenete un ILA che instrumenta la FSM, l'handshake start/done e un valore del
datapath già nella prima build.

> **Gate G6**: il solve on-board coincide con il reference.

---

### F7 · Chiusura dell'anello e campagna di misura
Ordine fisso, così che i risultati successivi non invalidino i precedenti:
risorse e timing dai report → latenza hardware dal **contatore on-chip** →
latenza end-to-end dal lato software (**la differenza fra le due È il costo di data
movement**) → baseline software sulla stessa board nello stesso ambiente →
metrica di qualità closed-loop.

Regola non negoziabile: uno speedup è un risultato solo se la baseline era ottimizzata
e la finestra di misura era la stessa. Riportate caso peggiore e jitter, non un numero
singolo — per un anello di controllo il jitter quasi nullo di un solver a iterazioni
fisse **è** l'argomento forte, più dello speedup medio.

---

## Ordine consigliato di attacco (prossimi 3 passi concreti)

1. **F1: ristrutturare in tre modelli** in `Prova_2/models/`, riusando il payload
   attuale (matrici 3×3 + 4×4) come dato di prova, **già a 32 bit** (C1a: `fixdt(1,32,16)`,
   niente `typecast` a `uint64`). Portare fino al Gate G1.
2. **F2: scrivere il register map** e generare i due lati da lì.
3. **In parallelo, a costo quasi zero**: cercare se esiste un board plugin PYNQ-Z1 di
   comunità per HDL Coder, e fare il board plugin (punto 1 di F5) — mezza giornata che
   toglie subito il dubbio più grosso su A3.

Solo dopo si tocca il fixed-point serio e l'MPC. La tentazione è saltare a F4/F7: è
esattamente la tentazione che ha prodotto tre generazioni di HDL non confrontabili
fra loro.

---

## Registro dei rischi (con uscite datate)

| Rischio | Probabilità | Mitigazione e uscita |
|---|---|---|
| Reference design PYNQ-Z1 (il `.tcl` del base system) non converge | **alta** | partire dal plugin shipped e cambiare solo board + PS7. **Data di fallback: 2 settimane** → si passa a ZedBoard e la PYNQ-Z1 diventa una limitazione dichiarata nel report |
| Il vincolo ≤32 bit dello stream costringe a rifare il payload | **certa, già nota** | C1a adottata in F1: si nasce a 32 bit, non si converte dopo |
| Conversione fixed-point non converge | alta | equilibrazione prima di quantizzare; parole più larghe; fallback datato a single-precision |
| Timing non chiude | media | più stadi di pipeline, registri nei DSP; dimezzare il clock e documentare il trade-off |
| Incompatibilità versioni tool | media | R2023b + Vivado 2022.1 **bloccati oggi**; mai aggiornare a metà progetto |
| Scope creep | alta | benchmark congelato (F0); ogni modifica richiede giustificazione scritta |
| Risultati non riproducibili | media | tutto da script, un comando per la regressione, uno per il bitstream |

---

## Fonti

- MathWorks — [SoC Blockset Model Structure](https://www.mathworks.com/help/soc/ug/soc-blockset-model-structure.html)
- MathWorks — [Build Error When FPGA or Processor Model Not Detected](https://www.mathworks.com/help/soc/ug/build-error-for-fpga-or-processor-model-not-detected.html)
- MathWorks — [Supported Third-Party Tools and Hardware](https://www.mathworks.com/help/soc/ug/supported-third-party-tools-and-hardware.html)
- MathWorks — [Using a Custom Board with SoC Blockset](https://www.mathworks.com/help/soc/ug/Using-a-Custom-Board-with-SoC-Blockset.html)
- MathWorks — [Streaming Data from Hardware to Software](https://www.mathworks.com/help/soc/ug/hwsw-stream.html)
- MathWorks — [SoC Model Creator](https://www.mathworks.com/help/soc/ref/socmodelcreator.html)
- MathWorks — [Default System with AXI4-Stream Interface Reference Design](https://www.mathworks.com/help/hdlcoder/xilinxzynq7000/ug/default-system-with-axi4-stream-reference-design.html) *(vincolo ≤32 bit, un solo canale slave + un master)*
- MathWorks — [Register a Custom Board](https://www.mathworks.com/help/hdlcoder/ug/register-a-custom-board.html) · [Register a Custom Reference Design](https://www.mathworks.com/help/hdlcoder/ug/register-a-custom-reference-design.html) · [hdlcoder.ReferenceDesign](https://www.mathworks.com/help/hdlcoder/ref/hdlcoder.referencedesign-class.html) · [addAXI4StreamInterface](https://www.mathworks.com/help/hdlcoder/ref/hdlcoder.referencedesign.addaxi4streaminterface.html)
- MathWorks — [Generate HDL IP Core with Multiple AXI4-Stream and AXI4 Master Interfaces](https://www.mathworks.com/help/hdlcoder/ug/map-dut-ports-to-multiple-axi-interfaces.html)
- MathWorks Answers — [Which versions of Vivado are supported with which release of HDL Coder?](https://www.mathworks.com/matlabcentral/answers/518421-which-versions-of-vivado-are-supported-with-which-release-of-hdl-coder)
- skill `soc-expert` — ch03 (fixed-point come metodologia), ch06 (data movement e soglia registri/DMA), ch22 (progetto end-to-end)
- skill `fpga-expert` — ch08 (AXI, handshake valid/ready), ch10 (Zynq, soglia AXI-Lite↔DMA), ch17 (ILA), ch30 (misura HW vs SW)
