# Misure reali di risorse e tempi (sintesi Vivado 2022.1)

Questo documento raccoglie i risultati **reali**, ottenuti facendo girare davvero Vivado (non stime teoriche), sui pezzi elementari del progetto. Servono da riferimento quando si dovrà stimare quanto costerà in hardware il vero algoritmo MPC.

Target chip usato per tutti i test: **xc7z020clg484-1** (lo stesso della Pynq-Z1 e della ZedBoard).

## Metodo

Per ogni test: si isola il subsystem `FPGA` (o una sua variante) in un file `.slx` separato, si genera il Verilog con `makehdl`, poi si sintetizza/implementa con Vivado tramite uno script Tcl lanciato direttamente da riga di comando (non tramite le API di scripting di MATLAB per l'HDL Workflow Advisor, che in questa installazione non sono risultate disponibili in forma affidabile).

## Risultato 1 — Reshape/riorganizzazione dati (nessun calcolo)

Prendere un flusso di byte e riorganizzarlo in due matrici (3x3 e 4x4) senza fare nessuna operazione aritmetica:

```
Slice LUT:      0 / 53200
Slice Registri: 0 / 106400
DSP:            0 / 220
```

**Zero risorse.** Quando gli indici sono noti a tempo di compilazione, "riorganizzare" un array è pura re-instradazione di fili (wire renaming) — non serve nessuna porta logica reale.

*Limite del metodo di test*: se si prova a fare anche l'Implementation completa (place & route, non solo sintesi) su questo caso, con le porte larghe di questo test (centinaia/migliaia di bit trattati come se fossero pin fisici del chip), il place fallisce per limite fisico di pin del package (il chip ne ha ~200, il test ne richiederebbe migliaia). Questo **non è un problema del progetto reale** — nel sistema vero questi segnali restano internamente nel silicio (interconnessione PS-PL incorporata), non escono mai su pin fisici. È solo un artefatto di come si isola un pezzo per un test rapido.

## Risultato 2 — Moltiplicazione fixed-point (vero calcolo)

Stessa logica di reshape, ma con l'aggiunta di una vera moltiplicazione (per un guadagno non-potenza-di-2, per evitare che il sintetizzatore la trasformi in un semplice shift di bit gratuito):

```
Slice LUT: 0 / 53200
DSP:       9 / 220   (una per ogni elemento della matrice 3x3 moltiplicato)
```

Quindi: **~1 DSP48 dedicato per ogni moltiplicazione fixed-point**, zero LUT — Vivado mappa le moltiplicazioni direttamente sui blocchi hardware dedicati del chip.

### Timing (place & route completo, riuscito su questo test perché le porte sono strette)

```
Ritardo totale misurato: 8.946 ns
  - buffer di ingresso:  0.921 ns
  - DSP48 (il calcolo vero): 3.841 ns
  - buffer di uscita:    2.584 ns
  - resto: instradamento dei fili
```

Il numero rilevante per il vero costo del calcolo è **~3.8 ns** (solo il DSP48) — i buffer di ingresso/uscita sono un artefatto dello stesso motivo spiegato sopra (nel sistema vero questi segnali non attraversano buffer di I/O fisici).

## Regola pratica per dimensionare l'MPC

- Lo Zynq-7020 ha **220 DSP48** in totale. Ogni moltiplicazione fixed-point concorrente ne consuma circa 1. Questo dà un limite superiore diretto: se l'algoritmo MPC richiede più di ~220 moltiplicazioni parallele, bisognerà serializzarne alcune (più cicli di clock, meno parallelismo) oppure ottimizzare l'algoritmo.
- Operazioni di puro "instradamento/riorganizzazione" (selezione di sotto-matrici, trasposizioni, ecc., senza aritmetica) sono sostanzialmente gratuite in hardware — non è necessario preoccuparsi della loro area.
- La virgola mobile reale (floating-point) richiede un supporto IP dedicato più costoso — va evitata se il fixed-point offre precisione sufficiente per l'algoritmo di controllo.

## Risultato 3 — DUT completo del modello SoC Blockset (`ComputeCore`, il reshape lato FPGA), sintesi Vivado reale

Dopo aver risolto il blocco toolchain ARM e scoperto le regole di "IP Core Generation" di SoC Blockset (vedi `docs/socbuilder_notes.md`), il blocco `FPGA_HW` del modello `Prova_1_socbuilder` è stato sintetizzato con Vivado reale (bypassando `socModelBuilder`, stesso metodo TCL diretto usato per i Risultati 1-2), per verificare che il DUT costruito e corretto fosse davvero sintetizzabile, non solo passasse i controlli del validatore.

Metodo: il DUT (blocco MATLAB Function che ricompone lo stream in `matA`/`matB`) è stato incapsulato in un Subsystem (`Simulink.BlockDiagram.createSubsystem`, richiesto da HDL Coder — non genera codice per un MATLAB Function "nudo"), generato VHDL reale con `makehdl` (con `UseFloatingPoint=on` per gestire i segnali `double` senza cambiarne il tipo), poi sintetizzato via script Tcl diretto.

```
Slice LUTs: 0 / 53200
Registri:   0 / 106400
DSP:        0 / 220
```

**Zero risorse**, coerente con il Risultato 1: questo pezzo del modello non fa aritmetica, solo reshape/ricomposizione dello stream (la moltiplicazione vera è lato software/ARM in questo modello didattico). Ogni percorso nel report timing (es. `readFromMem[0][0]→matA[0,0][0]`, `streamEnable→doneOut1/doneOut2`) mostra **0 logic levels, 0.973 ns** di puro routing — stesso valore già misurato per il passthrough enable→done, confermato come riferimento stabile per questo tipo di percorso (buffer I/O, non un vero calcolo).

**Perché conta**: dimostra che il flusso completo — dal modello Simulink SoC Blockset, attraverso le regole di IP Core Generation scoperte oggi, fino a un vero report di sintesi Vivado — funziona end-to-end su questa installazione, senza dipendere dal validatore p-code di `socModelBuilder`. Metodo riusabile quando si sintetizzerà il vero algoritmo MPC.

## Risultato 4 — Moltiplicazione matriciale 3x3 vera, bitstream completo via SoC Builder (`MatMul_Top`/Register Channel)

Diversamente dai Risultati 1-3 (reshape/routing puro, nessun calcolo reale sull'FPGA), questo test costruisce da zero un modello con **calcolo vero sulla FPGA**: due matrici 3x3 (`fixdt(1,16,8)`) entrano via Register Channel/AXI4-Lite, la moltiplicazione matriciale vera (`Y = A*B`, blocco `Product` in modalità `Matrix(*)`) avviene sul DUT, il risultato torna al software ARM. Metodo e regole scoperte in dettaglio: `docs/socbuilder_notes.md`, sezione "ripreso da zero con Register Channel".

**Standalone (solo il DUT, HDL Workflow Advisor diretto su `MatMul_FPGA.slx`, package `clg400` — Pynq-Z1 reale)**:
```
Slice LUTs: 0 / 53200
Slice Registers: 0 / 106400
DSPs: 27 / 220 (12.27%)
Data Path Delay: 9.268 ns (requirement 10 ns @ 100MHz — rispettato)
```
27 = 3 prodotti scalari per elemento di `Y` × 9 elementi, ciascuno mappato su un DSP48E1 (3 DSP incatenati via `PCIN+A*B` per prodotto scalare, accumulo combinatorio, nessun registro di pipeline).

**Sistema completo (`socModelBuilder`/SoC Builder, PS7 Zynq + AXI4-Lite + DUT, package `clg484` — ZedBoard, unica board supportata da questo meccanismo)**, bitstream reale generato (`write_bitstream`, ~957 KB, 0 errori):
```
Slice LUTs: 1375 / 53200 (2.58%)
Slice Registers: 1875 / 106400 (1.76%)
DSPs: 27 / 220 (12.27%)
```
I 27 DSP coincidono esattamente col conteggio standalone — l'integrazione nel sistema completo (Register Channel, wrapper AXI4-Lite, PS7) non altera né duplica la logica di calcolo, aggiunge solo l'infrastruttura di trasporto (i ~1375 LUT/1875 registri extra rispetto allo standalone).

**Perché conta**: primo bitstream reale di tutta la storia di questo progetto (sessione attuale e storico `Prova_1`/`Prova_2`) con un calcolo effettivo sulla FPGA, non solo trasporto/reshape — e primo numero di riferimento diretto per il costo di una vera moltiplicazione matriciale 3x3 in hardware, utile per dimensionare l'MPC (una matrice N×N×N costa circa N³ DSP con questo pattern non ottimizzato).
