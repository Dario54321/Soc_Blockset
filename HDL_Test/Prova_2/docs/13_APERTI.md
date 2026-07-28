# Punti aperti e prossimi passi

> Stato al 28/07/2026. Tutto ciò che segue è **noto, verificato e non ancora fatto**.
> Chi riprende il lavoro parte da qui.

---

## A1 — BLOCCANTE per l'hardware: `tdata` vettoriale non è generabile

**Stato attuale**: il modello FPGA riceve `tdata` come **vettore di 25 elementi
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

## A4 — Board PYNQ-Z1 da registrare in HDL Coder

Non ancora iniziato. Materiale già individuato:

- I board plugin AMD sono **nel prodotto base** (`toolbox\hdlcoder\boards\amd\`), non
  servono support package: `+ZedBoard`, `+ZynqZC702`, `+ZynqZC706`, `+ZCU102`, …
- Dentro `+ZedBoard` c'è già `+vivado_stream_2022_1` con `plugin_rd.m`,
  `system_top.tcl` (663 righe) e `axistream.dtsi`.
- Piano: copiare `+ZedBoard` → `+PYNQZ1`, cambiare `FPGAPackage` da `clg484` a
  `clg400`, rimappare i pin da *Digilent PYNQ-Z1 Reference Manual*, e nel `.tcl`
  sostituire il board part usando i **board files Vivado che il gruppo già possiede**
  (`apply_bd_automation … -config {apply_boardpreset "1"}` invece di trascrivere i
  `PCW_*` a mano).
- **Da fare per primo del blocco**: mezza giornata, e dice subito se la strada regge.

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

---

## Ordine consigliato

1. **A1** — variante sample-based + Variant Subsystem. È il blocco che separa "simula"
   da "va in hardware", e tutto il blocco C dipende da lui.
2. **A4** — board plugin PYNQ-Z1 (mezza giornata, sblocca il dubbio su A3/A4).
3. **A2** — chiudere i segnaposto di handshake e priming.
4. P8 register map → P9 generazione HDL → **Dario**: P11/P12.
