# 3. Sintesi Vivado da riga di comando

## Sintesi vs Implementation: due fasi diverse, spesso confuse

Nel flusso di sviluppo FPGA ci sono (almeno) due fasi distinte dopo aver scritto l'RTL (i file `.vhd`/`.v`):

- **Sintesi** (`synth_design`): traduce l'RTL (una descrizione astratta, "voglio un registro che fa questo, un moltiplicatore che fa quest'altro") nei **componenti fisici reali** disponibili su quello specifico chip — LUT (Look-Up Table, le celle logiche generiche), DSP48 (blocchi hardware dedicati per moltiplicazioni/somme, molto più efficienti di implementarle con LUT), blocchi di memoria (BRAM), ecc. Il risultato è una "netlist": un elenco di questi componenti e di come sono collegati tra loro, ma **non ancora** posizionati fisicamente sul chip.
- **Implementation** (place & route, `opt_design`/`place_design`/`route_design`): prende la netlist della sintesi e decide **dove**, fisicamente, sul silicio, va ciascun componente, e come vanno instradati i fili reali che li collegano, rispettando i vincoli fisici del chip (numero di celle disponibili in ogni area, lunghezza massima dei fili per rispettare i tempi, ecc.).

Per sapere "quante risorse consuma il mio design" basta la sola sintesi. Per sapere "il design funzionerà davvero a questa velocità sul chip reale" serve anche l'implementation (la sintesi da sola dà solo stime di area, non un timing definitivo). In questa guida ci si ferma quasi sempre alla sola sintesi (più veloce, sufficiente per dimensionare un algoritmo), con implementation completa solo quando i vincoli lo permettono (vedi sotto, "Il limite dei bus larghi").

## Perché Tcl e non la GUI

Vivado ha una GUI completa, ma **ogni azione della GUI corrisponde a uno o più comandi Tcl** (Tool Command Language — il linguaggio di scripting nativo di Vivado, e di molti altri tool EDA). Usare Tcl invece della GUI permette di:
- Automatizzare il flusso (utile se devi ripetere la sintesi molte volte, es. per confrontare varianti di un algoritmo).
- Eseguire Vivado in **modalità batch** (`vivado -mode batch`), cioè senza aprire nessuna finestra, adatto a essere lanciato da uno script o da un altro programma (in questo progetto, da MATLAB stesso o da un tool di automazione).
- Avere un log testuale preciso e riproducibile di cosa è stato fatto, invece di dover rifare click a mano ogni volta.

## Anatomia di uno script di sintesi minimale

```tcl
set part xc7z020clg484-1
read_vhdl -vhdl2008 percorso/pkg.vhd
read_vhdl -vhdl2008 percorso/sottoblocco.vhd
read_vhdl -vhdl2008 percorso/top.vhd

synth_design -top NomeEntitaTop -part $part -mode out_of_context

report_utilization -file percorso/utilization.txt
```

- `set part ...`: il codice identificativo esatto del chip target. `xc7z020clg484-1` significa: famiglia Zynq-7000, modello `7z020`, package `clg484` (484 pin, un certo tipo di case fisico), grado di velocità `-1`. Questo è il chip montato sia sulla Pynq-Z1 sia sulla ZedBoard usate in questo progetto — se cambi scheda, questo è il primo valore da aggiornare (lo trovi sul datasheet della scheda).
- `read_vhdl`/`read_verilog`: carica i file sorgente, **nell'ordine giusto** (i file che definiscono tipi o sotto-moduli usati da altri file vanno letti per primi — vedi il file `_compile.do` generato da `makehdl`, capitolo 2).
- `synth_design -top NomeEntitaTop`: lancia la sintesi vera, partendo dall'entity/module il cui nome corrisponde al DUT che hai generato.

## `-mode out_of_context`: perché serve, spiegato dal principio

Quando sintetizzi un design **come se fosse l'intero progetto per il chip**, Vivado assume che ogni ingresso/uscita del tuo design corrisponda a un **pin fisico reale** del package del chip — perché normalmente è così: il "top level" di un vero progetto FPGA è collegato direttamente ai pin che poi vanno saldati sulla scheda.

Il problema: un package come `clg484` ha circa 200 pin realmente utilizzabili come I/O generici (il resto sono alimentazione, massa, pin speciali). Se il blocco che stai sintetizzando isolatamente ha, ad esempio, un bus dati di centinaia di bit (comune per canali di streaming o strutture dati intere passate come singolo segnale), Vivado tenta di assegnare **ogni singolo bit** a un pin fisico distinto — e se il conteggio richiesto supera i pin disponibili, il place fallisce con un errore tipo `Bonded IOB 2627/200 (1313%)` o simile.

Nella realtà, però, quel blocco **non è mai il top-level vero** del sistema finale — è un pezzo interno, che nel progetto completo si collega ad altra logica *sullo stesso silicio*, non a pin fisici esterni. Il flag:
```tcl
synth_design -top NomeEntitaTop -part $part -mode out_of_context
```
dice esplicitamente a Vivado: "tratta questo come un blocco che farà parte di un design più grande — non forzare i suoi ingressi/uscite su pin fisici reali, lasciali come segnali interni generici". Questo permette di sintetizzare (ottenere i numeri di LUT/DSP) anche blocchi con bus larghi, senza il limite dei ~200 pin.

### Il limite dei bus larghi per l'Implementation completa

`-mode out_of_context` risolve il problema per la sola **sintesi**. Se provi a spingere fino all'**Implementation completa** (place & route) un blocco con bus larghi in questa modalità, spesso ottieni un risultato "vuoto" (`ERROR: [Place 30-494] The design is empty` — Vivado ottimizza via tutta la logica non avendo un vero contesto a cui collegarla). Se invece lo fai **senza** `out_of_context`, torni al problema dei pin fisici insufficienti. **Conclusione pratica, verificata in questo progetto**: per un'Implementation completa e realistica, il blocco isolato che stai testando deve avere **porte strette** (pochi bit, non bus interi da centinaia di bit) — se il tuo blocco reale ha bus larghi (come un canale dati streaming), limita la sintesi isolata al solo `report_utilization` (stima di area, sempre valida), e rimanda l'Implementation completa al momento in cui il blocco sarà integrato nel design completo con un vero wrapper di sistema.

## Leggere `report_utilization`

Il file di testo prodotto elenca, per categoria, quante risorse del tipo sono state usate rispetto al totale disponibile sul chip:
```
| Slice LUTs | 0 | ... | 53200 | 0.00 |
| DSPs       | 0 | ... |   220 | 0.00 |
```
- **Slice LUTs**: le celle logiche generiche (Look-Up Table) — implementano qualsiasi funzione logica combinatoria semplice. Un chip `xc7z020` ne ha 53.200.
- **DSPs**: blocchi hardware dedicati (DSP48E1 su questa famiglia) specializzati in moltiplicazioni/somme — molto più efficienti (in area e velocità) di implementare la stessa operazione con sole LUT. Un chip `xc7z020` ne ha 220 in totale: questo è il "budget" massimo di moltiplicazioni fixed-point concorrenti che puoi avere in hardware su questo chip, prima di dover serializzare (fare più operazioni in sequenza sullo stesso DSP, su più cicli di clock) o accettare l'uso di LUT (più lento).
- **Slice Registers**: elementi di memoria a 1 bit (flip-flop) — usati per tenere stato tra un ciclo di clock e l'altro (pipeline, contatori, macchine a stati).

Se un blocco mostra **0 su tutte le voci**, significa che non fa nessun vero calcolo/memorizzazione — è puro instradamento di segnali (es. un'operazione di reshape/riorganizzazione dati con indici noti a tempo di compilazione, che Vivado ottimizza a semplice "rinominazione di fili").

## Misurare il tempo quando non c'è un vero clock: la tecnica del clock virtuale

Molti blocchi isolati (specialmente quelli puramente combinatori, senza registri/pipeline) non hanno nessuna porta di clock reale nel VHDL/Verilog generato — sono "logica pura", il cui output cambia istantaneamente (nella teoria digitale) in risposta all'input, senza aspettare un fronte di clock. Il comando standard per l'analisi di temporizzazione, `report_timing`, però ha bisogno di un riferimento di clock per calcolare gli slack (quanto tempo "avanza" rispetto a un requisito) — senza clock reale, non troverebbe nulla da riportare.

La tecnica standard per ottenere comunque un numero di latenza reale è creare un **clock virtuale**: un clock finto, non collegato a nessuna porta reale del design, usato solo come riferimento temporale per l'analisi:
```tcl
create_clock -name virt_clk -period 10
set_input_delay -clock virt_clk 0 [all_inputs]
set_output_delay -clock virt_clk 0 [all_outputs]
report_timing -delay_type max -path_type full -max_paths 5 -file percorso/timing.txt
```
- `create_clock -period 10`: definisce un clock virtuale con periodo 10 ns (100 MHz) — il valore del periodo qui non conta per la misura del ritardo combinatorio puro, è solo un riferimento arbitrario abbastanza largo da non generare violazioni fittizie.
- `set_input_delay`/`set_output_delay ... 0`: dice che i segnali di ingresso/uscita sono già allineati (0 ns di ritardo esterno) rispetto a questo clock virtuale — così il numero di "Data Path Delay" che leggerai nel report è il ritardo **reale e puro** della logica interna del tuo blocco, non un artefatto della configurazione del clock.

Nel report risultante, per ogni percorso critico troverai un blocco simile a:
```
Data Path Delay: 3.841 ns (logic 3.841ns (100.000%) route 0.000ns (0.000%))
Logic Levels: 1
```
`Logic Levels: 0` con delay classificato come "route" (non "logic") significa che quel percorso è puro instradamento (nessun vero calcolo, es. reshape) — un numero `Logic Levels` maggiore di 0, con una parte di delay "logic", indica un vero calcolo (es. attraverso un DSP48).

**Nota**: `report_timing -unconstrained` (un'opzione che sembrerebbe più diretta per "misura senza vincoli") **non è un'opzione valida** in Vivado 2022.1 — usa sempre la tecnica del clock virtuale sopra.
