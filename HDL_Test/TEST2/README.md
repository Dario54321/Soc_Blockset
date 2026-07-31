# TEST2 — artefatti reali del primo bring-up hardware di Prova_2 (31/07/2026)

Copia dei risultati reali della sessione che ha chiuso i gate G11b/G12b/G13:
primo IP Core Generation, primo bitstream, primo bitstream **programmato su
Pynq-Z1 vera** via JTAG. Racconto completo, passo per passo, con le cause di
ogni blocco incontrato: [`../Prova_2/docs/24_REFERENCE_DESIGN.md`
§24.8](../Prova_2/docs/24_REFERENCE_DESIGN.md).

**Non è un artefatto rigenerabile a comando come quelli in `Prova_2/models/`**:
è uno scatto dello stato reale in un momento preciso, prodotto da
`D:\SocBuilderBuild\Prova_2_build` (fuori da questo repository, per il bug
whitespace-nel-path documentato in §24.8). Per rigenerarlo da zero servono gli
stessi passaggi, non solo questi file.

## Cosa c'è dentro

| Cartella | Contenuto | Dimensione |
|---|---|---|
| `bitstream/` | `system_top_wrapper.bit` — il bitstream reale, **già programmato con successo** su una Pynq-Z1 vera via JTAG | ~4 MB |
| `reports/` | Report di sintesi/implementazione Vivado: timing (`timing_summary_routed`), utilizzo risorse (`utilization_placed`), potenza (`power_routed`), DRC e stato di routing | ~4.2 MB |
| `devicetree/` | Nodi device tree generati per il flusso Linux/PYNQ (`soc_wrapp_ip.dtsi`) — non ancora usati, il percorso SSH resta bloccato da `dtc` mancante (§24.8) | poche KB |
| `ipcore/` | L'IP core Vivado impacchettato (`soc_wrapp_ip_v1_0`) — **contiene anche il VHDL sorgente** in `hdl/`, la stessa fonte di `hdlsrc/` (confrontato: differiscono solo nel timestamp del commento "Created", nessuna differenza di logica) | 361 KB |

## Cosa NON c'è (e perché)

- Il progetto Vivado completo (`vivado_ip_prj/`) resta **fuori** da git: contiene
  checkpoint binari (`.dcp`), cache e file di journaling per ~60 MB, tutti
  rigenerabili dai sorgenti sopra + `scripts/run_ipcore_generation.m` +
  l'HDL Workflow Advisor. Portarli in git sarebbe peso morto, non informazione.
- La cartella `hdlsrc/` generata da HDL Coder **non è qui**, di proposito: il
  `.gitignore` di root la esclude già ovunque nel repository (riga 21, insieme
  a `*.log`, `*_report.html`, `hdl_prj/` — convenzione esistente per l'output
  intermedio di build, rigenerabile). Il VHDL che conteneva è comunque
  presente, identico, in `ipcore/soc_wrapp_ip_v1_0/hdl/`. I log reali dei task
  del Workflow Advisor (incluso quello di programmazione via JTAG) restano
  citati per esteso in [`24_REFERENCE_DESIGN.md` §24.8](../Prova_2/docs/24_REFERENCE_DESIGN.md),
  non versionati come file separati.

## Tre livelli di verifica, per non confonderli

1. **Modello Simulink** (`scripts/run_wrapper_unit_sim.m`) — verificato, 501
   cicli attesi (`latencyCycles=500` + 1 di registro).
2. **RTL in simulazione** (`Prova_2/sim/tb_soc_wrapper_fpga.vhd`, gira su PC
   con `xsim`, non sulla scheda) — verificato lo stesso giorno, stesso
   risultato: 501 cicli, indipendentemente dal modello.
3. **Hardware reale** — il bitstream in questa cartella è stato **caricato e
   accettato** dalla PL (`DONE` alto, confermato dal log). Il comportamento
   funzionale sul chip vero (scrivere `x`, dare `START`, leggere `DONE`/`u`
   dai registri AXI4-Lite reali) **non è ancora stato verificato**: serve
   `dtc` (percorso SSH) o una licenza HDL Verifier (percorso JTAG AXI
   Manager), nessuno dei due disponibile al momento di questo commit.
