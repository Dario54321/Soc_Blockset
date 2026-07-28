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

Il budget di riferimento:

```
33 µs @ 100 MHz  =  3300 cicli
   − trasporto AXI4-Lite (~100 cicli)
   ─────────────────────────────────
   ≈ 3200 cicli disponibili per il calcolo
```

> I 33 µs vengono da un paper, **non sono stati misurati da noi**. Vanno trattati
> come target di riferimento dichiarato finché il bring-up non produce il numero
> vero.

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

1. `enable` è a livello durante il calcolo, oppure esiste un segnale di validità
   del risultato? *(determina come deriviamo `done`)*
2. La latenza è costante o dipende dai dati? *(non cambia il contratto, cambia la
   soglia del watchdog e il modello di simulazione)*
3. Le quattro caselle del §3 sul formato numerico.
4. `n_x` e `n_u` reali. *(oggi assumiamo 3 e 1)*
5. Il blocco ha stato interno fra un solve e il successivo, o è puro?
   *(se ha stato, `SOFT_RESET` deve raggiungerlo)*

Finché mancano, il wrapper resta parametrico e il blocco di calcolo è simulato da
un segnaposto a latenza configurabile — il che permette comunque di rispondere a
*"qual è la latenza massima del calcolo che sta dentro i 33 µs?"*.
