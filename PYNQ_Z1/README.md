# Pynq-Z1 come board custom per SoC Blockset / SoC Builder

Registrazione `soc.sdk.BoardSupport` della Pynq-Z1 per SoC Blockset — non solo
per HDL Coder IP Core Generation (già presente in `HDL_Test/Prova_2/hdlplugins/`),
ma per il **workflow SoC Builder completo** (co-design hardware/software,
partizionamento FPGA+Processore, generazione IP core + software ARM).

**Aggiorna quanto detto nel README principale** ("*La Pynq-Z1 non è fra le
board supportate da SoC Blockset*"): con questa registrazione **lo è**,
verificato fino alla cross-compilazione ARM reale (non solo `validate()` o
selezione da GUI) — vedi [`STORIA_TECNICA.md`](STORIA_TECNICA.md) per il
percorso completo e i problemi risolti.

---

## Cosa scaricare

Ti serve solo questa cartella:

```
custom_board_pynqz1_v2/
```

Contiene tutta la definizione della board — nessun altro file di questo
repository è necessario per usarla.

## Setup (MATLAB R2023b)

La registrazione **non è permanente**: va rifatta a ogni nuova sessione
MATLAB. Prima di aprire qualunque modello, nella Command Window:

```matlab
addpath('<percorso>\custom_board_pynqz1_v2')
sl_refresh_customizations
RTW.TargetRegistry.getInstance('reset')
```

Il terzo comando è importante: senza, MATLAB può tenere in cache una
versione vecchia della registrazione (es. il menu "Processing Unit" in
Hardware Implementation potrebbe non comparire). Se anche questo non
basta, riavvia MATLAB — la causa è quasi sempre cache, non un problema
della board.

Dopo questi tre comandi, **`Pynq-Z1` compare come `HardwareBoard`
selezionabile** in qualunque modello Simulink (Model Settings → Hardware
Implementation, oppure via `set_param(model,'HardwareBoard','Pynq-Z1')`).

## Verifica rapida

```matlab
bsObj = soc.sdk.loadBoardSupport('Board Support for Pynq-Z1');
validate(bsObj)   % deve restituire 1
```

## Test end-to-end (facoltativo, per confermare che tutto funzioni)

Usa un esempio SoC Blockset **nativo per R2023b** — non uno scaricato o
convertito da altre versioni (vedi "Errori incontrati" sotto, punto 1):

```matlab
openExample('soc/StreamingDataFromHardwareToSoftwareExample')
```

Poi, su ciascuno dei tre modelli generati (top / fpga / proc):
1. `HardwareBoard = Pynq-Z1`
2. Model Settings → Hardware Implementation → **Processing Unit**:
   `None` sul top, `FPGA` sul modello FPGA (+ Solver → Type = `Fixed-step`),
   `APU` sul modello processore
3. System on Chip → **Configure, Build & Deploy** → segui il wizard
   (Prepare → Validate → Build)

Con questo esempio la build si ferma all'ultimo passo (link finale) per
librerie di terze parti mancanti (`libiio` e affini, per dispositivi
RF/SDR — non necessarie per la Pynq-Z1 base): la generazione del codice C
e la **compilazione con il vero cross-compilatore ARM
(`arm-linux-gnueabihf-gcc`) riescono comunque**, ed è quello il punto che
conta per verificare che la board sia a posto.

## Dati hardware reali usati per costruire la board

| Periferica | Pin | Note |
|---|---|---|
| Chip | `xc7z020clg400-1` | — |
| Clock di sistema | `H16`, 125 MHz, LVCMOS33 | — |
| LED (4) | `R14, P14, N16, M14` | — |
| DIP switch (2) | `M20, M19` | — |
| Pulsanti (3 di 4) | `D20, L20, L19` | `D19` (btn0) **escluso di proposito** |

**Perché solo 3 pulsanti su 4**: la Pynq-Z1 non ha un pin di reset di
sistema dedicato (verificato: nessun componente/interfaccia di tipo reset
in tutto `board.xml`). `D19` (il primo pulsante) è usato come reset — se
venisse esposto *anche* come pulsante GPIO normale, lo stesso pin
finirebbe con due vincoli fisici (`LOC`) diversi nel file di constraint
generato, un conflitto che Vivado rifiuterebbe in fase di
place/route. **Non aggiungere mai un `PushButton` su `D19`.**

Fonte dei dati: `Vivado\2022.1\data\boards\board_files\pynq-z1\1.0\
{board.xml, part0_pins.xml}` (non ridistribuiti in questo repository —
stesso motivo di licenza già spiegato nel README principale).

## Errori incontrati, in breve (dettaglio completo in STORIA_TECNICA.md)

1. **Esempi SoC Blockset scaricati/esportati da una versione MATLAB
   diversa da quella in uso possono contenere riferimenti rotti** (es.
   `FixedStep` puntato a una variabile mai definita) che impediscono a
   SoC Builder di rilevare il modello FPGA — sintomo fuorviante, sembra
   un problema della board e invece è del file. Usa sempre un esempio
   nativo per la tua versione MATLAB (`openExample(...)`).
2. Se il menu "Processing Unit" non compare in Hardware Implementation:
   quasi sempre cache MATLAB non aggiornata — vedi
   `RTW.TargetRegistry.getInstance('reset')` sopra, o riavvia MATLAB.
3. Se SoC Builder da errore "Unrecognized field name" su LED/DIPSwitch/
   PushButton: la board a cui ti stai riferendo (se ne crei una tua copia)
   deve avere quei periferici effettivamente registrati con
   `addNewLED`/`addNewDIPSwitch`/`addNewPushButton` — non basta che il
   modello li usi.
