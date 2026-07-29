# Contratto di interfaccia — wrapper SoC ↔ blocco di calcolo

**Versione 0.1 — 28/07/2026 — BOZZA DA CONCORDARE**

> **A chi serve.** Definisce il confine fra l'infrastruttura di trasporto ARM↔FPGA
> (nostra) e il blocco di calcolo che implementa la parte MPC (di un altro
> ingegnere). È il documento che permette a **ciascuno dei due lati di cambiare
> senza rompere l'altro**.
>
> **Cosa NON fa.** Non prescrive nulla su *come* il calcolo è implementato: né
> algoritmo, né numero di cicli, né linguaggio, né strumenti. Il blocco resta una
> scatola nera.

---

## 0. Perché un contratto e non un'integrazione diretta

Il blocco di calcolo è di proprietà di un altro ingegnere e cambierà. Se il
trasporto assume qualcosa sul suo comportamento interno — quanti cicli impiega,
quando i dati sono pronti — allora ogni sua modifica rompe il nostro lato, e
viceversa.

Le tre proprietà che questo contratto garantisce:

1. **Insensibilità alla latenza.** Nessun numero di cicli è cablato da nessuna
   parte. Il blocco può diventare 3× più veloce o 2× più lento senza che si tocchi
   una riga dall'altro lato.
2. **Sostituibilità simmetrica.** Il blocco di calcolo può essere riscritto,
   sostituito o simulato; il trasporto può passare da AXI4-Lite ad AXI4-Stream.
   Nessuna delle due cose richiede il consenso dell'altra parte.
3. **Nessuno stallo possibile.** L'ARM non può restare appeso su un blocco che non
   risponde.

---

## 1. Segnali

Confine fra i due IP, lato PL. Tutti i segnali sono sincroni al medesimo `clk`,
attivi alto, con `rst_n` asincrono in asserzione e **sincrono in rilascio**.

### Dal wrapper al blocco di calcolo

| Segnale | Larghezza | Descrizione |
|---|---|---|
| `clk` | 1 | clock di sistema, `p.budget.clockMHz` (100 MHz) |
| `rst_n` | 1 | reset attivo basso |
| `x[i]` | `n_x` × `W` | vettore di stato, formato in §3 |
| `start` | 1 | **impulso di un ciclo**: i dati su `x` sono validi e stabili |

### Dal blocco di calcolo al wrapper

| Segnale | Larghezza | Descrizione |
|---|---|---|
| `u[j]` | `n_u` × `W` | risultato, formato in §3 |
| `done` | 1 | **impulso di un ciclo**: `u` è valido |
| `busy` | 1 | *opzionale* — alto fra `start` e `done` |
| `error` | 1 | *opzionale* — il calcolo è fallito; `u` non è valido |

`n_x = 3` e `n_u = 1` sono **ipotesi correnti**, non confermate: manca il file
dell'MPC. Il wrapper è parametrico su entrambi.

---

## 2. Protocollo

```
clk     ‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾
x       ══╳═══ valido e stabile ══════════╳══════
start   ___|‾|____________________________________
busy    _____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|__________
u       ═════════════════════════╳═ valido ═╳════
done    _________________________|‾|______________
```

**Regole, in ordine di importanza.**

1. `start` è **un impulso di un ciclo**, non un livello. Non va tenuto alto.
2. `x` è **stabile da `start` fino a `done`**. Il blocco può leggerlo quando vuole
   in quella finestra; non serve che lo campioni subito.
3. `done` è **un impulso di un ciclo**. `u` è valido nel ciclo di `done` e resta
   stabile fino allo `start` successivo.
4. **Il blocco non deve mai fare assunzioni su quando arriverà il prossimo `start`.**
   Può arrivare il ciclo dopo `done`, o mai più.
5. **Il wrapper non fa assunzioni sul numero di cicli fra `start` e `done`.** Può
   essere costante, variabile, o dipendente dai dati.
6. Se il blocco espone `busy`, deve essere alto per tutta la finestra e basso a
   riposo. Se non lo espone, il wrapper si regola solo su `start`/`done`.

### Su `enable` invece di `start`/`done`

Il blocco attuale usa un `enable` per far attendere il resto del percorso. **Va
bene**, e non chiediamo di cambiarlo: è un contratto equivalente purché sia
possibile derivarne un impulso `done`. Due adattamenti accettabili:

- se `enable` è alto mentre il calcolo è in corso → `done = fronte di discesa di enable`;
- se esiste un segnale di validità del risultato → `done = fronte di salita di quel segnale`.

L'adattamento sta **nel nostro wrapper**, non nel loro blocco. Serve solo sapere
quale dei due casi è.

---

## 3. Formato numerico — la parte che si sbaglia più spesso

I formati numerici interpretati diversamente ai due capi sono uno dei tre guasti
classici di bring-up, e sono silenziosi: producono risultati plausibili e sbagliati.
Per questo il formato sta **nella stessa tabella del segnale**.

| Segnale | Tipo | Note |
|---|---|---|
| `x[i]` | `sfix32_En16` | ±32768, LSB 1.526·10⁻⁵ |
| `u[j]` | `sfix32_En16` | idem |

**Da concordare esplicitamente**, perché nessuno dei due lati può deciderlo da solo:

- [ ] il formato è davvero `sfix32_En16`, o il blocco lavora in un altro Q-format?
- [ ] range operativo dichiarato di `x` e `u` (serve a dimensionare e a verificare
      le saturazioni);
- [ ] comportamento in overflow: **saturazione** o wrap? *(la nostra
      raccomandazione è saturazione: il wrap produce numeri credibili e sbagliati)*
- [ ] arrotondamento: `Floor` o `Nearest`?

Finché queste quattro caselle non sono spuntate, **qualunque confronto numerico
fra i due lati misura la cosa sbagliata**.

---

## 4. Gestione degli errori e watchdog

Il blocco è di terzi e può bloccarsi. Il wrapper implementa un **watchdog**:

- se `done` non arriva entro `TIMEOUT` cicli dallo `start`, il wrapper alza
  `STATUS.TIMEOUT`, torna a riposo e **non** attende oltre;
- `TIMEOUT` è programmabile da software (registro `0x84`), così la soglia si
  adatta al blocco senza risintetizzare;
- se il blocco espone `error`, viene propagato in `STATUS.ERROR`.

**In nessun caso l'ARM può restare bloccato in attesa.** È un requisito, non una
comodità: un anello di controllo che si pianta è peggio di uno lento.

---

## 5. Misura della latenza — a costo zero per il blocco di calcolo

Il wrapper contiene un contatore che conta i cicli fra `start` e `done` e li
espone nel registro `CYCLES` (`0x80`).

Costa circa **30 flip-flop** e **non richiede alcuna modifica al blocco di
calcolo**. Serve a trasformare "il blocco è lento" da impressione a numero, che è
la sola base su cui si possa poi decidere qualcosa.

### Quanti cicli ha a disposizione il blocco di calcolo

Il conto è in [`22_STUDIO_LATENZA`](22_STUDIO_LATENZA.md), qui il risultato:

```
33 µs @ 100 MHz            =  3300 cicli
   − trasporto ARM ↔ FPGA  =  dipende dallo stack software del PS
   − overhead del wrapper  =  1 ciclo (misurato)
   ────────────────────────────────────────────────────────────────
```

| stack software del PS | cicli per il calcolo |
|---|---:|
| bare-metal | **~3150** |
| Linux con registri mappati (UIO/`mmap`) | **~2300** |

**La cifra da usare oggi è l'ordine dei 3000 cicli**, cioè ~30 µs a 100 MHz.
Le due righe differiscono per una scelta che sta dalla nostra parte del confine,
non dalla vostra: appena è presa vi diamo il numero singolo.

Due avvertenze, entrambe nostre e non vostre:

> I 33 µs vengono da un paper, **non sono stati misurati da noi**. Sono un target
> di riferimento dichiarato finché il bring-up non produce il numero vero.

> I costi di trasporto sono **ordini di grandezza da letteratura**, non misure su
> questa board. Bastano a scartare un'alternativa che costa trenta volte più di
> un'altra; non bastano a garantire la terza cifra.

### `CYCLES` conta un ciclo in più del vostro blocco

Il valore letto è **latenza del vostro blocco + 1**. Quel ciclo è il registro
sull'uscita `done`, che in hardware c'è comunque, e sta dal lato del confine —
non ve lo stiamo addebitando. Se vi serve confrontarlo con una vostra misura
interna, il termine di paragone è `CYCLES − 1`.

---

## 6. Mappa dei registri (lato AXI4-Lite, verso l'ARM)

Generata da `scripts/soc_params.m`: **non trascrivere questi offset a mano da
nessuna parte**, né in HDL né in C. Si generano entrambi i lati dalla stessa fonte.

```
0x00  CTRL      R/W   bit0 START (autoazzerante) · bit1 SOFT_RESET · bit2 IRQ_EN
0x04  STATUS    R     bit0 DONE · bit1 BUSY · bit2 ERROR · bit3 TIMEOUT
0x08  X0                W    stato[0]        sfix32_En16
0x0C  X1                W    stato[1]        sfix32_En16
0x10  X2                W    stato[2]        sfix32_En16
0x40  U0                R    uscita[0]       sfix32_En16
0x80  CYCLES    R     cicli dell'ultimo solve
0x84  TIMEOUT   R/W   soglia del watchdog, in cicli
0x8C  ID_VER    R     0x50325A31 ("P2Z1") + versione
```

Protocollo software: `scrivi X → START → attendi DONE → leggi U`.
`START` si autoazzera; senza questo, il primo solve funziona e il secondo non parte
mai — è un guasto classico.

`ID_VER` esiste per un solo motivo: **la prima lettura del bring-up**. Una lettura
prova bus, decodifica indirizzi, clock e reset tutti insieme, e distingue un
problema di infrastruttura da un problema di algoritmo.

---

## 7. Chi possiede cosa

| | Proprietario | Può cambiare senza consultare l'altro? |
|---|---|---|
| Blocco di calcolo (algoritmo, cicli, pipeline) | altro ingegnere | ✅ sì, purché rispetti §2 |
| Wrapper, CSR, watchdog, contatore | noi | ✅ sì, purché rispetti §1–2 |
| Driver PS, stack software | noi | ✅ sì |
| Trasporto (AXI4-Lite ↔ AXI4-Stream) | noi | ✅ sì, è dietro un'astrazione |
| **Segnali e protocollo (§1–2)** | **entrambi** | ❌ **modifica concordata** |
| **Formato numerico (§3)** | **entrambi** | ❌ **modifica concordata** |

Integrazione consigliata: **due IP separati** collegati nel block design Vivado,
non il blocco di terzi inglobato nel nostro DUT. Ciascuno resta padrone dei propri
strumenti e sostituire un lato non obbliga a rigenerare l'altro.

---

## 8. Cosa serve dall'altro lato per chiudere questa bozza

### Sul protocollo
1. `enable` è a livello durante il calcolo, oppure esiste un segnale di validità
   del risultato? *(determina come deriviamo `done`)*
2. La latenza è costante o dipende dai dati? *(non cambia il contratto, cambia la
   soglia del watchdog e il modello di simulazione)*
3. Il blocco ha stato interno fra un solve e il successivo, o è puro?
   *(se ha stato, `SOFT_RESET` deve raggiungerlo)*

### Sul formato numerico
4. Le quattro caselle del §3. Finché non sono spuntate, ogni confronto numerico
   fra i due lati misura la cosa sbagliata.

### Sul payload — le più urgenti
5. **Cosa sono i due vettori 3×1** che già attraversano il confine? *(stato e
   riferimento? stato e disturbo? due colonne della 3×3?)*
6. **La 3×3 da invertire è assemblata da quei vettori?** Se sì è **tempo-variante**
   e l'inversa non è precalcolabile offline. E allora: dove viene la **terza**
   colonna — un terzo vettore che non abbiamo ancora visto, una costante, o il
   campione precedente?
7. **Tutti i vettori devono essere presenti prima che il calcolo parta?**
   *(quasi certamente sì: determina quando il wrapper emette `start`)*
8. **Oltre allo stato, cos'altro attraversa il confine ARM↔FPGA, adesso o in
   prospettiva?** In particolare: i dati grezzi di radar/lidar restano sull'ARM o
   prima o poi passano alla PL? *(cambia la taglia del progetto, vedi §9)*

---

## 9. Perché la taglia del payload decide l'architettura

`scripts/budget_report.m` calcola la curva. Con budget 33 µs a 100 MHz
(3300 cicli), cicli che restano al calcolo:

| elementi che attraversano | AXI4-Lite bare-metal | AXI4-Stream bare-metal | AXI4-Lite Linux mmap | AXI4-Stream Linux |
|---:|---:|---:|---:|---:|
| 3 (una 3×1) | **3195** | 3100 | 2600 | 100 |
| **6 (due 3×1 — caso attuale)** | **3150** | 3100 | 2300 | 100 |
| 9 (tre 3×1) | 3105 | 3100 | 2000 | 100 |
| 12 | 3060 | 3100 | 1700 | 100 |
| 30 | 2790 | 3100 | esaurito | 100 |
| 60 | 2340 | 3100 | esaurito | 100 |

Tre letture, in ordine di importanza:

1. **Il vero discrimine è lo stack software del PS, non il bus.** Con 33 µs di
   budget, qualunque percorso che passi per un driver kernel con interrupt è fuori.
   Su Linux+mmap i registri reggono fino a ~25–30 elementi. **Bare-metal regge
   tutto.** Questo va deciso presto: condiziona se PYNQ/Python può essere usato per
   l'anello a regime (per il bring-up va benissimo).
2. **La soglia registri↔stream sta intorno a 10–12 elementi** (~50 byte) su
   bare-metal. Sotto, i registri vincono; sopra, lo stream. Con due 3×1 siamo
   **sotto**, ma non di molto: se i vettori diventano quattro, si riapre.
3. **Il costo dello stream non dipende dalla taglia** — è dominato dal costo fisso
   di setup. Per questo la sua riga è piatta: è il motivo per cui vince sui payload
   grandi e perde su quelli piccoli.

### Un argomento a favore dei registri che non è la latenza

Con più vettori d'ingresso, la PL deve avere **l'insieme completo** prima di
partire. Con i registri questo è esplicito e gratuito: si scrivono tutti i
registri, poi si alza `START`. Con uno stream bisogna dedurre la completezza da
`TLAST` o da un contatore — logica in più, e un modo di fallire in più (insieme
parziale → risultato plausibile e sbagliato, senza che nessuno se ne accorga).

Finché mancano, il wrapper resta parametrico e il blocco di calcolo è simulato da
un segnaposto a latenza configurabile — il che permette comunque di rispondere a
*"qual è la latenza massima del calcolo che sta dentro i 33 µs?"*.
