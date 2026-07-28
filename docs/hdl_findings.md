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
