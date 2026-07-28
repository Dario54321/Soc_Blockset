# Audit dell'ambiente — macchina di sviluppo, 28/07/2026

Rilevato direttamente sulla macchina, non dichiarato.

---

## ✅ STATO POST-INSTALLAZIONE (verificato 28/07/2026)

L'installazione degli add-on è **riuscita**. Verifiche eseguite su R2026a:

```
=== PRODOTTI (ver) ===
  SoC Blockset          ✔ (prima assente)
  Embedded Coder        ✔ (prima assente)
  HDL Coder · HDL Verifier · Fixed-Point Designer · Simulink Coder ·
  Optimization Toolbox · Control System Toolbox · Stateflow    ✔

=== SUPPORT PACKAGE (matlabshared.supportpkg.getInstalled) ===
  SoC Blockset Support Package for AMD FPGA and SoC Devices    26.1.5   ✔
  Embedded Coder Support Package for AMD SoC Devices           26.1.5   ✔
  Embedded Coder Support Package for ARM Cortex-A Processors   26.1.0   ✔
  root: C:\ProgramData\MATLAB\SupportPackages\R2026a

=== LIBRERIE ===
  socmemlib · prociolib · proctasklib · hwlogicconnlib          tutte OK
  procspkglib_internal  →  RISOLTA
  (era la libreria mancante che faceva avvisare Simulink caricando Prova_1)

=== HardwareBoard impostabile ===
  'Custom Hardware Board' · 'ZedBoard' · 'Xilinx Zynq ZC706 evaluation kit'   OK

=== API custom board (nuove, dal support package) ===
  soc.sdk.BoardSupport · loadBoardSupport · packageBoardSupport ·
  setupSoftwareTools · testBoardSupport · ReferenceBoardSupportMap
  in ...\SupportPackages\R2026a\toolbox\soc\supportpackages\sdk\+soc\+sdk\
```

**Il passo che ha chiesto la board è l'*Hardware Setup*, non l'installazione.**
È una procedura guidata separata e posticipabile: scrive l'immagine su microSD,
configura rete e IP e prova la connessione. Si rilancia in qualunque momento da
*Add-Ons → Manage Add-Ons → \<support package\> → Setup*.

> Per il percorso scelto (A3, PYNQ-Z1) l'Hardware Setup delle board di serie
> (ZedBoard/ZC706) **non serve comunque**: scriverebbe un'immagine per schede che non
> avete. Quando la board torna, il setup rilevante è l'immagine PYNQ più il custom
> board, non questo wizard.

### Cosa richiede la board fisica, e cosa no

| | Serve la board? | Serve Vivado? |
|---|---|---|
| P1–P8 · specifica, `soc_params`, reference, vettori, i tre modelli, simulazione di sistema, register map | **no** | no |
| P9 · `makehdl` e verifica HDL ↔ modello | **no** | no |
| P10 · board plugin PYNQ-Z1 | **no** | no (solo per validarlo nell'Advisor) |
| P11 · reference design, build del block design | no | **sì, 2022.1 o 2024.1** |
| P12 · IP core e bitstream | no | **sì, 2022.1 o 2024.1** |
| P13 · driver PS | no | no |
| P14–P15 · bring-up e misure · FPGA-in-the-Loop · Hardware Setup | **sì** | sì |

**Il limite operativo su questa macchina è P10 compreso**: non per mancanza di
Vivado, ma perché la versione presente (2026.1) non è supportata dai workflow
integrati di R2026a. P11 e P12 sono assegnati a Dario, che ha la 2022.1.

## MATLAB installati

| Release | SoC Blockset | HDL Coder | HDL Verifier | Fixed-Point Designer | Embedded Coder | Simulink Coder | Optimization | Control System | MPC Toolbox |
|---|---|---|---|---|---|---|---|---|---|
| **R2026a** | ❌ | ✔ | ✔ | ✔ | ❌ | ✔ | ✔ | ✔ | ❌ |
| **R2025b** | ✔ | ✔ | ✔ | ✔ | ❌ | ❌ | ❌ | ❌ | ❌ |
| R2020a | ❌ | (solo `toolbox\hdlcoder`) | — | — | — | — | — | — | — |

- **R2023b non è installata su questa macchina.** I modelli del repo sono salvati con
  MATLAB 23.2 e i report Vivado riportano host `LAPTOP-RTJL1V6U`: sono stati prodotti
  altrove.
- **Vivado 2026.1** è installato in `C:\AMDDesignTools\2026.1\Vivado`.
  ⚠️ **R2026a HDL Coder non la supporta**: si ferma a 2024.1 (elenco completo sotto).
  I workflow integrati (IP Core Generation, SoC Builder, FIL) fanno un controllo di
  versione. Serve **2022.1** (quella di Dario) o 2024.1.
  > *Correzione*: una prima ricerca aveva concluso "Vivado non installato" perché
  > cercava solo in `C:\Xilinx\Vivado` e simili. AMD ha cambiato percorso di default
  > in `C:\AMDDesignTools\<versione>\Vivado`.
- I toolbox sono **spezzati fra due release**: R2025b è la release "SoC/FPGA",
  R2026a è la release "controllo/algoritmi". Nessuna delle due le ha entrambe.
- **Nessun support package installato** in nessuna release
  (`matlabshared.supportpkg.getSupportPackageRoot` vuoto).

## Entitlement di licenza

Licenza **online** (`licmode = onlinelicensing`, account MathWorks), quindi i prodotti
non installati possono essere aggiunti dall'Add-On Explorer se l'account li copre.
`license('test',...)` su R2026a riporta *entitled* per `SoC_Blockset`,
`RTW_Embedded_Coder`, `MPC_Toolbox`, `Optimization_Toolbox`, `Control_Toolbox`.

> ⚠️ Il test non è del tutto affidabile: riporta `entitled=0` anche per `HDL_Coder`,
> che invece è installato e funzionante. Prima di pianificarci sopra, **verificare con
> un clic** nell'Add-On Explorer di R2026a che SoC Blockset ed Embedded Coder siano
> effettivamente installabili.

## Versioni Vivado supportate da HDL Coder — verificate su disco

Da `toolbox\hdlcoder\hdlcommon\+downstreamtools\+XilinxVivado_*`:

| Release MATLAB | Vivado supportate (ultime) |
|---|---|
| **R2026a** | 2019.2, 2020.1, 2020.2, 2021.1, 2021.2, **2022.1**, 2023.1, 2024.1 |
| **R2025b** | 2019.1, 2019.2, 2020.1, 2020.2, 2021.1, **2022.1**, 2023.1, 2024.1 |

→ **Vivado 2022.1 è supportata da entrambe.** La versione di Vivado non è un vincolo
sulla scelta della release MATLAB.

## Board plugin HDL Coder già presenti nel prodotto base

`toolbox\hdlcoder\boards\amd\` — **non serve alcun support package** per il board plugin:

`+ZedBoard`, `+ZynqZC702`, `+ZynqZC706`, `+ZCU102`, `+ZCU106`, `+Zynq`, `+XilinxArty`,
`+XilinxKC705`, `+XilinxVC707`, `+VCK190`, `+ZynqRFSoC`, `+mpsoc`, `+rfsoc`, `+versal`
(R2026a; R2025b ha un sottoinsieme, senza `+ZCU106` e `+Zynq`).

Dentro `+ZedBoard` ci sono i reference design pronti:

```
+vivado_stream_2022_1\   plugin_rd.m · system_top.tcl (663 righe) · axistream.dtsi
+vivado_ddr_2024_1\      plugin_rd.m · system_top.tcl · ddr_access_sharedmem.dtsi
+vivado_base_2022_1\     plugin_rd.m · system_top.tcl · axilite.dtsi
+vivado_unified\         base.tcl · axi_stream_common.tcl · add_extmem.tcl · ...
```

`+vivado_stream_2022_1\plugin_rd.m` **conferma il vincolo a 32 bit** letto nella
documentazione, e dà la struttura esatta da copiare:

```matlab
hRD.ReferenceDesignName = 'Default system with AXI4-Stream interface';
hRD.BoardName           = 'ZedBoard';
hRD.SupportedToolVersion = {'2022.1','2023.1','2024.1'};
hRD.addCustomVivadoDesign('CustomBlockDesignTcl','system_top.tcl', ...
                          'VivadoBoardPart','avnet.com:zedboard:part0:1.4');   % ← qui vanno i board files
hRD.addDeviceTree('axistream.dtsi');
hRD.addClockInterface('ClockConnection','core_clkwiz/clk_out1', ...);
hRD.addRegisterInterface('InterfaceConnection','axi_cpu_interconnect/M00_AXI', ...
                         'BaseAddress','0x400D0000', ...);
hRD.addAXI4StreamInterface( ...
    'MasterChannelConnection','axi_dma_s2mm/S_AXIS_S2MM', ...
    'SlaveChannelConnection', 'axi_dma_mm2s/M_AXIS_MM2S', ...
    'MasterChannelDataWidth', 32, ...     % ← il vincolo C1
    'SlaveChannelDataWidth',  32, ...
    'HasDMAConnection', true, ...);
```

## Automazione

`matlab -batch "..."` funziona da PowerShell su entrambe le release (verificato).
Quindi la costruzione dei modelli (`new_system`, `add_block`, `set_param`, `sim`,
`makehdl`) è **scriptabile e automatizzabile**, senza GUI. Costo: ~40 s di avvio per
chiamata, quindi conviene raggruppare le operazioni in un unico script per invocazione.

## Add-on da installare in R2026a

Da Add-On Explorer. `[P]` = prodotto (licenza), `[SP]` = support package hardware.

### Necessari — senza questi il flusso non si chiude

| | Nome esatto | Perché |
|---|---|---|
| `[P]` | **SoC Blockset** | assente in R2026a. È il prodotto su cui poggia tutto il modello di sistema |
| `[P]` | **Embedded Coder** | assente in **entrambe** le release. Serve per generare il codice ARM del processor model (`Processing Unit = APU`). Senza, SoC Blockset simula ma non deploya il lato software |
| `[SP]` | **SoC Blockset Support Package for AMD FPGA and SoC Devices** | fornisce `procspkglib_internal` (la libreria che oggi manca: caricando `Prova_1_ref.slx` in R2025b Simulink avvisa *"Failed to load library 'procspkglib_internal'"*), le definizioni board, e il `soc.sdk` completo per il custom board support |
| `[SP]` | **Embedded Coder Support Package for AMD SoC Devices** | toolchain di cross-compilazione ARM Cortex-A, external mode, deploy su Linux target |

### Consigliati

| | Nome esatto | Perché |
|---|---|---|
| `[SP]` | **HDL Coder Support Package for AMD FPGA and SoC Devices** | i board plugin base (`+ZedBoard`, `+ZynqZC706`, …) sono **già** nel prodotto base in R2026a, quindi non è bloccante; aggiunge board, reference design e il flusso di programmazione della scheda |
| `[SP]` | **HDL Verifier Support Package for AMD FPGA Boards** | FPGA-in-the-Loop: verifica l'HDL sulla board reale contro il modello prima di avere l'intero sistema. È il gate G9 fatto sull'hardware invece che in simulazione |
| `[P]` | **Model Predictive Control Toolbox** | non serve a questo test. Serve dopo, per *progettare* l'MPC e come cross-check. Il reference model del solver va comunque scritto a mano nell'ordine di operazioni dell'hardware, non generato da libreria |

### Già presenti in R2026a, nessuna azione

HDL Coder · HDL Verifier · Fixed-Point Designer · Simulink Coder · MATLAB Coder ·
Optimization Toolbox (`quadprog` per il cross-check) · Control System Toolbox ·
Stateflow · Simulink Control Design

### ✔ Stato dopo l'installazione (28/07/2026, verificato)

```
ver                                   → SoC Blockset ✔  Embedded Coder ✔  HDL Coder ✔
matlabshared.supportpkg.getInstalled  → SoC Blockset Support Package for AMD
                                        FPGA and SoC Devices  26.1.5
load_system('socmemlib')              → OK
load_system('procspkglib_internal')   → OK   ← la libreria che mancava
```

**R2026a è operativa per tutta la parte di modellazione e simulazione.** I tool di terze
parti rimasti indietro (vedi sotto) servono solo al *deployment*, non ai passi P1–P8
della procedura.

**Esito (28/07/2026):** procedura di sblocco applicata con successo. Il file FTDI messo
a mano è stato accettato (checksum verificato) e la catena è ripartita fino in fondo:
**9 tool su 9 installati, 6,07 GB** in `3P.instrset`, fra cui
`linarogcctoolchain_aarch32_soc` (1,77 GB) — il cross-compilatore Cortex-A9 per
Zynq-7000 — e `xilinxlinuxbinaries_soc` (2,26 GB).

### ⛔ Passo "Select Embedded OS Image" — da annullare

Dopo i tool di terze parti il wizard propone di scrivere un'immagine firmware MathWorks
su scheda SD. **Annullare (`Cancel`).** Due motivi:

1. È distruttivo: *"removes any existing software from the SD/MMC card"*.
2. **Nel flusso di questo progetto non va mai eseguito.** L'immagine MathWorks è
   costruita per le board supportate (ZedBoard, ZC706, ZCU102); con la Decisione A3
   il deployment passa da HDL Coder e il boot dall'**immagine PYNQ**, che è quella che
   fornisce `Overlay()`, `allocate()` e il DMA pilotabile da Python.

⚠️ Non puntare mai questo wizard alla SD della PYNQ-Z1: sovrascriverebbe l'immagine PYNQ
con un firmware per un'altra scheda. Il passo è comunque rilanciabile in qualunque
momento da **Add-Ons → ⚙ → Setup**, e annullarlo non tocca i tool già installati.

### ⚠ Intoppo noto: Hardware Setup si blocca su "FTDI JTAG D2XX library"

Osservato il 28/07/2026 durante l'installazione del *SoC Blockset Support Package for
AMD FPGA and SoC Devices*. **Sintomo**: la finestra Hardware Setup resta con lo spinner
su `FTDI JTAG D2XX library` a tempo indefinito.

**Causa accertata**, non ipotizzata: il file scaricato
`SupportPackages\R2026a\downloads\CDM-v2.12.36.4-WHQL-Certified.zip` è di **5583 byte**
e inizia con `3C 21 44 4F` (`<!DO`) invece della firma ZIP `50 4B 03 04`. Il contenuto è
la pagina **Cloudflare "Just a moment…"**: il sito FTDI ha risposto con una sfida
anti-bot invece del driver. L'installer ha salvato la pagina HTML come `.zip` e si è
piantato senza segnalare l'errore.

Indizi corroboranti: zero scritture sotto la support-package root per 14 minuti, nessuna
connessione TCP esterna da alcun processo MATLAB, nessun prompt UAC in attesa.

**Come uscirne.** Reinstallare il support package non serve — è già installato, e infatti
MATLAB risponde *"già installato"*. Quello che è rimasto incompleto è **Hardware Setup**,
che si rilancia separatamente:

- **Add-Ons → Manage Add-Ons →** icona ⚙ accanto al support package **→ Setup**, oppure
- in Simulink, scheda **System on Chip → Setup Hardware**

Non esiste un comando da riga di comando: `which('hardwareSetup')` è vuoto e MathWorks
lo documenta come strumento solo-GUI.

Arrivati alla schermata *Download and Install Third-Party Tools*: **premere `Next`, non
`Install`** — la finestra stessa dice *"If you have already installed the tools, click
'Next'"*. Si salta lo stadio dei tool di terze parti e il wizard arriva in fondo.

**Alla schermata *Support Package Installation Status*** (che elenca i tool falliti e
propone due azioni): scegliere **"Continue with Hardware Setup"**, **non** la
*"(Recommended) Uninstall the support package and third-party tools"*.

Il "Recommended" di MathWorks è coerente dal suo punto di vista — un'installazione
parziale è uno stato inconsistente — ma qui butterebbe via 1,5 GB di support package
**già verificato funzionante** (`procspkglib_internal` carica) per rimediare a tool che
servono solo al deployment, fra settimane. La finestra stessa chiarisce che i tool
falliti si possono ritentare in qualunque momento rilanciando Hardware Setup.

**Gli altri sei tool falliscono solo per effetto a catena.** I download sono sequenziali
e FTDI è il primo: finché non passa, gli altri non vengono nemmeno tentati. Provando le
URL direttamente (28/07/2026, dalla stessa rete) risulta che **solo ftdichip.com è
irraggiungibile**:

| Tool | Host | Prova diretta |
|---|---|---|
| FTDI D2XX | ftdichip.com | ✗ errore server (Cloudflare) |
| Linaro AArch32 | ssd.mathworks.com | ✔ HTTP 206, GZIP valido |
| Xilinx Linux Binaries | github.com | ✔ HTTP 206, ZIP valido |
| Ne10 1.2.1 | github.com | ✔ HTTP 200, ZIP valido |
| libiio | ssd.mathworks.com | ✔ HTTP 206, ZIP valido |

Non è quindi un problema di rete o di proxy: sbloccato FTDI, il resto scorre.

Le URL stanno in
`SupportPackages\R2026a\toolbox\soc\supportpackages\xilinxsoc\thirdpartytools\instrset\<tool>.instrset\...\*.xml`,
campo `<downloadUrl>`; lo stesso file contiene il `<checksum>` MD5 atteso.

**Procedura di sblocco:**

1. cancellare lo stub HTML:
   `del "C:\ProgramData\MATLAB\SupportPackages\R2026a\downloads\CDM-v2.12.36.4-WHQL-Certified.zip"`
2. scaricare con un **browser** (che supera la sfida Cloudflare)
   `https://ftdichip.com/wp-content/uploads/2023/09/CDM-v2.12.36.4-WHQL-Certified.zip`
3. metterlo in `C:\ProgramData\MATLAB\SupportPackages\R2026a\downloads\`
   con lo **stesso identico nome**
4. **verificare il checksum** — l'installer lo controlla:
   `certutil -hashfile "<...>\downloads\CDM-v2.12.36.4-WHQL-Certified.zip" MD5`
   deve dare `6004a4f36fe7beb06dc86245c4ec3d1b`
5. rilanciare Hardware Setup → `Install`

**Cosa serve davvero fra i tool di terze parti** (gli altri si possono deselezionare):

| Tool | Serve? |
|---|---|
| **Linaro Toolchain AArch32 v6.3.1** | ✔ **sì** — cross-compilatore ARM per Zynq-7000 (Cortex-A9 a 32 bit), necessario a Embedded Coder |
| **Xilinx Linux Binaries** | ✔ utile — immagini di boot precostruite, riferimento per il custom board |
| Ne10 Library | ○ opzionale — libreria NEON per ARM |
| Linaro AArch64 Linux | ✗ solo MPSoC/UltraScale+, non Zynq-7000 |
| FTDI JTAG D2XX | ✗ per PYNQ-Z1 no: si fa boot da SD e Vivado usa il proprio driver JTAG. Serve solo per FIL su JTAG FTDI |
| ADI HDL IP · AD936x Filter Wizard · IIO | ✗ solo per schede radio Analog Devices |

Il problema è che FTDI viene **prima** in lista degli item che servono davvero: finché
non lo si supera, Linaro e Xilinx Linux Binaries non vengono nemmeno tentati.

### Verifica dopo l'installazione

```matlab
v = ver; disp(sort({v.Name})')
matlabshared.supportpkg.getInstalled
hdlsetuptoolpath('ToolName','Xilinx Vivado','ToolPath','<...>\bin\vivado.bat')
```
Attesi in `ver`: `SoC Blockset`, `Embedded Coder`. Attesi in `getInstalled`: i support
package AMD. Vivado 2022.1 raggiungibile.

> Se SoC Blockset **non** risulta installabile (entitlement assente), il ripiego è:
> R2025b per la parte SoC/FPGA, R2026a per la parte algoritmi. Funziona, ma paga
> il costo della regola R1 due volte e va evitato se possibile.

## Compatibilità dei modelli fra release

I `.slx` del repo sono R2023b. Aprirli in R2025b/R2026a li **aggiorna in modo
irreversibile**. Se il repo è condiviso con chi lavora in R2023b serve una convenzione
esplicita: *Save As → Previous Version → R2023b* a ogni commit, oppure il branch passa
in blocco alla nuova release. Da decidere, non da scoprire al primo merge conflict.
