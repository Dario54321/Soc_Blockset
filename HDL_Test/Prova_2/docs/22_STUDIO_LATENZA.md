# 22 — Studio di sensibilità alla latenza (P10)

> Passo P10 del piano. Riproducibile con `latency_study` dalla cartella `scripts`.
> Ultima esecuzione: 2026-07-29, MATLAB R2026a.

## 22.1 La domanda

L'altro ingegnere possiede il blocco che fa il calcolo. Prima o poi ci chiederà,
o gli chiederemo, **quanto tempo ha a disposizione**. Questo documento produce
quel numero e, soprattutto, dice da cosa dipende.

L'anello si scompone in tre addendi:

```
budget d'anello  =  trasporto (ARM <-> FPGA)  +  overhead del wrapper  +  latenza del calcolo
     33 us                dipende dallo             MISURATO qui              incognita da
                          stack software del PS                               riempire
```

I primi due li conosciamo. Il terzo è quello che resta.

## 22.2 Metodo: l'overhead si misura, non si assume

Il wrapper ha un contatore che espone `CYCLES` a fine solve. La tentazione è
dire "il contatore misura la latenza del blocco" e fermarsi lì. Non è vero:
misura la latenza **più l'overhead della macchina a stati**. E finché non si
verifica, non si sa nemmeno se quell'overhead sia una costante o una funzione
della latenza — nel secondo caso `CYCLES` non sarebbe interpretabile.

`latency_study.m` costruisce una variante del wrapper per ogni latenza,
la **simula** (non emula il codice estratto: cfr. `11_NOTE_API` §12) e legge
`CYCLES`:

| latenza imposta al segnaposto | `CYCLES` letto | differenza |
|---:|---:|---:|
| 1 | 2 | 1 |
| 2 | 3 | 1 |
| 5 | 6 | 1 |
| 20 | 21 | 1 |
| 100 | 101 | 1 |
| 500 | 501 | 1 |

**Overhead del wrapper = 1 ciclo, costante su tre ordini di grandezza.**

Lo script non si limita a stampare la tabella: contiene un `assert` che fallisce
se l'overhead non è costante. Se un domani la FSM guadagna uno stadio di
pipeline, il test lo dice invece di lasciare che i numeri slittino in silenzio.

Il singolo ciclo non è un residuo inspiegato: è il registro sull'uscita `done`
del blocco, conseguenza del nondirect feedthrough che rompe l'anello algebrico
(`21_SPEC_WRAPPER` §5, riquadro *Perché `+1` in B2*). In hardware quel registro
c'è comunque sull'uscita di un IP. Quello che questo studio aggiunge è la
**prova che sia uno solo e sempre lo stesso**, invece della ragionevolezza
dell'argomento.

Conseguenza operativa: **latenza del blocco = `CYCLES` − 1**. E quando si
comunica il numero all'altro ingegnere va detto, altrimenti gli si addebita un
ciclo che è del confine, non suo.

## 22.3 Quanti cicli restano al calcolo

Budget 33 µs a 100 MHz = 3300 cicli. Trasporto AXI4-Lite, costo per stack
software del PS dal modello in `soc_params`:

| stack PS | trasporto [µs] | max latenza [cicli] | max latenza [µs] |
|---|---:|---:|---:|
| `baremetal_poll` | 1.5 | **3149** | 31.5 |
| `baremetal_irq` | 1.5 | **3149** | 31.5 |
| `linux_mmap` | 10.0 | **2299** | 23.0 |
| `linux_driver` | 50.0 | **−1701** | −17.0 |

## 22.4 Che cosa questo dice sulla decisione D3

`01_PIANO` D3 diceva già, qualitativamente, che un driver di kernel è fuori
gioco. Questo studio non lo scopre: lo **quantifica**, e il numero è più brutale
dell'aspettativa. La riga `linux_driver` non è un margine stretto, è
**negativa di 1701 cicli**: il trasporto da solo costa 50 µs contro un budget di
33 µs. Il blocco di calcolo potrebbe avere latenza zero e l'anello mancherebbe
comunque il bersaglio.

La causa è aritmetica, non implementativa. AXI4-Lite muove **un registro per
accesso**: con 6 elementi di stato più i registri di controllo sono ~10 accessi
per iterazione. A ~5 µs di syscall per accesso — che è il costo del passaggio
user/kernel, non del bus — fa 50 µs. Il bus non c'entra.

Ne segue una cosa che in `01_PIANO` non era esplicita: **trasporto e stack
software non sono due decisioni indipendenti.** La tabella di D3 elencava le
opzioni di stack come se il protocollo fosse un'altra colonna; sono invece
accoppiate, perché il costo per-accesso si moltiplica per il numero di accessi
che è il protocollo a fissare.

Stato di D3 dopo questo studio:

- `linux_driver` — **eliminato**, non per preferenza ma per aritmetica;
- `baremetal` (poll o irq) — 3149 cicli al calcolo, ~95 % del budget;
- `linux_mmap` — 2299 cicli, ~70 % del budget. Costa un terzo del budget ma
  porta in dote un sistema operativo.

La scelta fra gli ultimi due **resta aperta** e non è tecnica in senso stretto:
dipende da cosa deve fare il PS oltre a questo anello. Il costo di prendere
Linux è ora noto: 850 cicli.

Il rovescio vale nell'altro verso ed è già in D3: se il payload cresce oltre
~10-12 elementi il costo per-accesso di AXI4-Lite cresce linearmente e il DMA
torna in vantaggio, perché lì il costo è quasi tutto fisso. I modelli del Test 1
restano in repository per quello.

## 22.5 Che cosa questi numeri non sono

Le costanti di trasporto in `soc_params` (`tAccessLite`, `tFixedDMA`) sono
**ordini di grandezza da letteratura**, non misure su questa board. Servono a
decidere fra alternative che differiscono di un fattore 5-30 — e per quello sono
sufficienti, perché lo scarto fra `baremetal` e `linux_driver` è di trentatré
volte. Non sono sufficienti per dire a qualcuno "hai 3149 cicli" con quel
numero di cifre.

Il numero definitivo arriva dal bring-up su hardware (P16). Fino ad allora la
formulazione corretta verso l'altro ingegnere è:

> **ordine dei 3000 cicli a 100 MHz** con stack bare-metal, da confermare a
> misura; **~2300** se il PS gira Linux con accesso mappato.

L'unica cifra qui che sia una misura vera, e non una stima, è l'overhead del
wrapper: 1 ciclo.

## 22.6 Rifare lo studio

```matlab
cd HDL_Test\Prova_2\scripts
S = latency_study();                       % 6 punti di default
S = latency_study([], [1 10 1000 5000]);   % altre latenze
```

Costa qualche minuto: ogni punto è una costruzione del modello più una
simulazione. La versione ridotta a due punti gira dentro la regressione (gate
T13) per accorgersi se l'overhead cambia dopo una modifica alla FSM.

### Il gate T13 provato in fallimento

| Mutazione | Esito |
|---|---|
| uno stadio di registro in più sul percorso `done` (`compute_stub → wrapper_fsm`) | ✅ *overhead misurato = 2, atteso 1 → T13 scatta* |

È la mutazione che conta: è esattamente ciò che succederebbe se qualcuno
aggiungesse pipeline alla FSM senza rifare i conti del budget.

Nota d'implementazione: ogni variante viene generata in una cartella temporanea
**con un nome distinto** (`soc_wrapper_L500.slx`). Modelli omonimi si ombreggiano
a vicenda sul path e i risultati diventano quelli del modello sbagliato — è già
successo, `11_NOTE_API` §12.
