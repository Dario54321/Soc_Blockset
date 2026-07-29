# 23 — Board plugin PYNQ-Z1 (P11)

> Passo P11, gate G11. Verificabile con `check_board_plugin` dalla cartella
> `scripts`. Ultima esecuzione: 2026-07-29, MATLAB R2026a.

## 23.1 Il problema

La PYNQ-Z1 non è fra le board che MathWorks fornisce. HDL Coder ne conosce
sedici (`toolbox\hdlcoder\boards\amd\`: ZedBoard, ZC702, ZC706, ZCU102, …) e
nessuna è questa. Senza registrarla, il flusso *IP Core Generation* non ha un
bersaglio.

## 23.2 Quello che esisteva già — e che ha evitato di reinventare

Prima di scrivere qualsiasi cosa vale la pena guardarsi intorno. Qui è servito
tre volte:

**Il precedente ufficiale per una board di terze parti.** Nel prodotto c'è già
una board non-MathWorks registrata a mano, la Trenz TE0820:

```
toolbox\shared\hdlmotorcontrol\socMotorControl\refdesigns\trenzboard\
    hdlcoder_board_customization.m      <- il file di registrazione
    +zynqmpTE0820FOC\
        plugin_board.m                  <- la definizione
        hdlcoder_ref_design_customization.m
```

È il template esatto, spedito e funzionante. Non c'era bisogno di dedurre il
meccanismo dalla documentazione.

**I board file Vivado, già installati dal gruppo.**

```
C:\AMDDesignTools\Boards_Drivers\pynq-z1\1.0\
    board.xml   part0_pins.xml   preset.xml   pynq_z1_board.png
```

Sono la fonte autorevole dei pin — la stessa che legge Vivado quando si sceglie
la board. Trascrivere pin da un manuale, o peggio ricordarli, sarebbe stato
sostituire una supposizione a una conoscenza disponibile a due directory di
distanza.

**Il precedente di MathWorks sui board file di terzi.** MathWorks stessa
distribuisce i board file Digilent della Zybo dentro il prodotto
(`toolbox\shared\hdlrd\common\boards\zybo\`), con un `board_project.tcl` che
fissa part e board:

```tcl
proc board_set_board_info {} {
    mw_project_set project_part "xc7z010clg400-1"
    mw_project_set project_board "digilentinc.com:zybo:part0:1.0"
}
```

Serve come modello per il reference design (P12). Attenzione a un dettaglio:
l'identificatore della PYNQ-Z1 è **`www.digilentinc.com:PYNQ-Z1:part0:1.0`** —
con il `www.`, che la Zybo non ha. Sbagliarlo significa che Vivado non trova la
board.

## 23.3 Il silicio

| | PYNQ-Z1 | ZedBoard |
|---|---|---|
| device | `xc7z020` | `xc7z020` |
| **package** | **`clg400`** | **`clg484`** |
| speed | `-1` | `-1` |

Stesso die, package diverso. È l'unica differenza che conta per la sintesi, ed è
anche il motivo per cui il plugin ZedBoard non si può riusare così com'è: i
package hanno mappature di pin incompatibili.

Una conseguenza che si perde facilmente: la ZedBoard dichiara
`IOSTANDARD = LVCMOS18` come vincolo di default per le porte esterne. **Sulla
PYNQ-Z1 sarebbe sbagliato**: tutti i 69 pin in `part0_pins.xml` sono `LVCMOS33`,
i banchi di I/O sono alimentati a 3.3 V. Copiare il plugin senza guardare questo
campo produce un design che sintetizza e non funziona.

## 23.4 Cosa è stato scritto

```
hdlplugins/
  hdlcoder_board_customization.m    registra 'PYNQZ1.plugin_board'
  +PYNQZ1/
    plugin_board.m                  la definizione per HDL Coder
    board_pins.m                    i pin — unica fonte, regola R2
```

Per usarla basta una riga:

```matlab
addpath('<...>\HDL_Test\Prova_2\hdlplugins')
```

### Perché i pin stanno in un file a parte

`hdlcoder.Board` **non espone pubblicamente** le interfacce aggiunte con
`addExternalIOInterface`: dall'oggetto costruito i pin non si rileggono. Se il
plugin li avesse scritti inline, l'unico modo di verificarli sarebbe stato
parsare il proprio sorgente — fragile. Con `board_pins.m` il dato ha un posto
solo, e sia il plugin sia il verificatore lo leggono da lì.

### Cosa è stato dichiarato, e cosa no

Dichiarati: **4 LED, 4 pulsanti, 2 switch** — dieci pin, tutti verificati.

Non dichiarati di proposito: RGB LED, Pmod JA/JB, shield Arduino, SPI, I2C. Il
percorso dati del progetto passa tutto per registri AXI4-Lite e **non tocca
alcun pin fisico**; i dieci dichiarati servono solo a rispondere a "il bitstream
è vivo?" durante il bring-up. Sono tutti in `part0_pins.xml` se un giorno
serviranno: ogni pin trascritto è un'occasione di sbagliare, e questi non
servono.

## 23.5 Come si verifica

```matlab
R = check_board_plugin();       % livello 1 + livello 2 se trova i board file
```

**Livello 1 — contratto di registrazione.** Il file di registrazione restituisce
un riferimento, il pacchetto si risolve, l'oggetto si costruisce, silicio e nome
sono quelli attesi. La costruzione avviene **attraverso il riferimento
registrato** (`feval(ref)`), non chiamando la funzione direttamente: così si
esercita la risoluzione del pacchetto, che è ciò che fa HDL Coder.

**Livello 2 — trascrizione dei pin.** Ogni pin di `board_pins.m` viene
riconfrontato con `part0_pins.xml`: sigla **e** standard di I/O. Confronto per
nome, non per posizione. È il livello che conta: un pin sbagliato non lo scopre
nessun altro controllo prima della sintesi.

Il livello 2 gira solo dove i board file esistono. Se mancano, la funzione lo
scrive su stderr e il gate T14 lo ripete: **verifica ridotta, non successo
pieno**. Su una macchina diversa si passa il percorso a mano:

```matlab
R = check_board_plugin('D:\percorso\ai\board_files\pynq-z1\1.0');
```

### Provato in fallimento

| Mutazione | Esito |
|---|---|
| package `clg484` (quello della ZedBoard) | ✅ `checkBoard:wrongPart` |
| due pin LED invertiti (R14 ↔ P14) | ✅ `checkBoard:pinMismatch` |
| `LVCMOS18` al posto di `LVCMOS33` | ✅ `checkBoard:iostdMismatch` |
| riferimento di registrazione sbagliato | ✅ `checkBoard:wrongRef` |

Quattro identificatori distinti: le asserzioni discriminano, non è un unico
`catch` che prende tutto.

## 23.6 Cosa questo NON verifica

**Che la board compaia nel menu del Workflow Advisor.** Il registro delle board
di HDL Coder è p-coded (`toolbox\hdlcoder\ipcore\+hdlcoder\Workflow.p`) e non
espone alcuna API pubblica per elencare le board registrate — verificato
cercandola, non supposto. `hdlcoder.WorkflowConfig` per *IP Core Generation*
restituisce un `hwcli.config.IPCoreConfig` che **non ha** una proprietà
`TargetPlatform`.

Resta quindi una **conferma manuale da fare una volta**:

1. `addpath('<...>\hdlplugins')`
2. aprire l'HDL Workflow Advisor su un modello con DUT
3. verificare che *Digilent PYNQ-Z1* compaia fra le target platform

> Attenzione a una trappola metodologica: avevo costruito una prova che
> sembrava funzionare in entrambe le direzioni — accettava la nostra board e
> rifiutava una inesistente. Entrambi i rami fallivano con lo **stesso** errore
> (`MATLAB:noPublicFieldForClass`, proprietà inesistente). Una controprova che
> fallisce per lo stesso motivo della prova non è una controprova.

## 23.7 Cosa resta aperto, per chi costruirà il reference design (P12)

- **Device tree.** Il plugin non ne dichiara. La ZedBoard aggiunge
  `zynq-zed.dtsi`, che descrive le periferiche del PS di *quella* board (PHY
  ethernet, USB, SD): sulla PYNQ-Z1 sono diverse. Serve solo al flusso Linux.
- **`JTAGChainPosition = 2`.** Preso dal precedente Zynq-7000 (ZedBoard e Trenz
  usano entrambe 2: il DAP dell'ARM è 1, la PL è 2). **Non verificato su questa
  board**: si conferma al primo collegamento.
- **Board file non versionati.** Stanno in Vivado, non nel repository: sono di
  terze parti e il pacchetto scaricato non conteneva una licenza. Chi costruisce
  il bitstream deve averli installati. Se si decidesse di versionarli, va prima
  chiarita la licenza.
- **Preset del PS.** `preset.xml` (73 KB) contiene la configurazione del
  Processing System della PYNQ-Z1 — DDR, clock, MIO. Nel `.tcl` del reference
  design conviene applicarlo con `apply_bd_automation … -config {apply_board_preset "1"}`
  invece di trascrivere i parametri `PCW_*` a mano.
