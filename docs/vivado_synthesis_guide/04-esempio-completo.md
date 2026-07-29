# 4. Esempio completo eseguito in questo progetto

Tutti i comandi qui sono quelli **realmente eseguiti** (non teorici) per sintetizzare il blocco `FPGA` del modello `Prova_1_socbuilder.slx`, il giorno in cui si è deciso di verificare con Vivado reale il lavoro fatto per sbloccare "IP Core Generation" di SoC Builder (vedi [`../socbuilder_notes.md`](../socbuilder_notes.md)). Segue esattamente l'ordine dei capitoli precedenti.

## Prerequisiti dell'ambiente usato

- MATLAB R2023b con Simulink, HDL Coder, support package Zynq/Xilinx.
- Xilinx Vivado 2022.1, installato in `D:\Xilinx\Vivado\2022.1\`.
- Percorso di lavoro **senza spazi**: `D:\SocBuilderBuild\` (il nome utente Windows di questa macchina contiene uno spazio — `lenovo GAME` — che rompe sia Vivado sia alcuni strumenti MATLAB se usato nel percorso di lavoro; da qui la scelta di lavorare su `D:\`).

## Passo 1 — Model Reference (capitolo 1)

```matlab
cd('D:\SocBuilderBuild');
load_system('D:\SocBuilderBuild\Prova_1_socbuilder.slx');

Simulink.SubSystem.convertToModelReference( ...
    'Prova_1_socbuilder/FPGA', 'FPGA_HW', ...
    'ReplaceSubsystem', true, 'AutoFix', true, 'Force', true);

save_system('Prova_1_socbuilder');
save_system('FPGA_HW', 'D:\SocBuilderBuild\FPGA_HW.slx');
```
Output reale: `### Successfully converted Subsystem block to Model block.` — `FPGA_HW.slx` creato, il blocco `FPGA` nel modello principale ora ha `BlockType = ModelReference`.

## Passo 2 — Incapsulare il DUT (capitolo 2)

Il blocco che fa il vero lavoro dentro `FPGA_HW` era un `MATLAB Function` a livello root, chiamato semplicemente `MATLAB Function`:
```matlab
load_system('D:\SocBuilderBuild\FPGA_HW.slx');
h = get_param('FPGA_HW/MATLAB Function', 'Handle');
Simulink.BlockDiagram.createSubsystem(h, 'Name', 'ComputeCore');
save_system('FPGA_HW');
```
Risultato: `FPGA_HW/ComputeCore` è il nuovo Subsystem, con dentro il vecchio blocco MATLAB Function — è `ComputeCore` il DUT da qui in avanti.

## Passo 3 — `checkhdl` e il fix "Double type signals" (capitolo 2)

```matlab
checkhdl('FPGA_HW/ComputeCore');
```
Primo esito: `HDL check for 'FPGA_HW' complete with 1 errors` — nel report: `"Double" type signals... select the "Use Floating Point" check box`.

Fix applicato (il segnale in ingresso `tdata`/`U` è `double`, e si è scelto di non cambiarne il tipo per restare fedeli al canale dati bit-esatto già usato nel resto del progetto):
```matlab
hdlset_param('FPGA_HW', 'UseFloatingPoint', 'on');
checkhdl('FPGA_HW/ComputeCore');
```
Secondo esito: `HDL check for 'FPGA_HW' complete with 0 errors, 1 warnings` — pronto per la generazione.

## Passo 4 — `makehdl` (capitolo 2)

```matlab
makehdl('FPGA_HW/ComputeCore', 'TargetDirectory', 'D:\SocBuilderBuild\hdlsrc_computecore');
```
Output reale (estratto):
```
### Begin VHDL Code Generation for 'FPGA_HW'.
### Working on FPGA_HW/ComputeCore/MATLAB Function as D:\SocBuilderBuild\hdlsrc_computecore\FPGA_HW\MATLAB_Function.vhd.
### Working on FPGA_HW/ComputeCore as D:\SocBuilderBuild\hdlsrc_computecore\FPGA_HW\ComputeCore.vhd.
### Generating package file D:\SocBuilderBuild\hdlsrc_computecore\FPGA_HW\ComputeCore_pkg.vhd.
### Code Generation for 'FPGA_HW' completed.
```
File prodotti in `D:\SocBuilderBuild\hdlsrc_computecore\FPGA_HW\`: `ComputeCore_pkg.vhd`, `MATLAB_Function.vhd`, `ComputeCore.vhd`, più `ComputeCore_compile.do` (ordine di compilazione: pkg → MATLAB_Function → ComputeCore).

## Passo 5 — Script Tcl (capitolo 3)

File `D:\SocBuilderBuild\vivado_synth_computecore\synth.tcl`:
```tcl
set part xc7z020clg484-1
read_vhdl -vhdl2008 D:/SocBuilderBuild/hdlsrc_computecore/FPGA_HW/ComputeCore_pkg.vhd
read_vhdl -vhdl2008 D:/SocBuilderBuild/hdlsrc_computecore/FPGA_HW/MATLAB_Function.vhd
read_vhdl -vhdl2008 D:/SocBuilderBuild/hdlsrc_computecore/FPGA_HW/ComputeCore.vhd

synth_design -top ComputeCore -part $part -mode out_of_context

report_utilization -file D:/SocBuilderBuild/vivado_synth_computecore/utilization.txt

create_clock -name virt_clk -period 10
set_input_delay -clock virt_clk 0 [all_inputs]
set_output_delay -clock virt_clk 0 [all_outputs]
report_timing -delay_type max -path_type full -max_paths 5 -file D:/SocBuilderBuild/vivado_synth_computecore/timing.txt

write_checkpoint -force D:/SocBuilderBuild/vivado_synth_computecore/post_synth.dcp
```

## Passo 6 — Lanciare Vivado in batch (capitolo 3)

```bash
cd D:/SocBuilderBuild/vivado_synth_computecore
"D:\Xilinx\Vivado\2022.1\bin\vivado.bat" -mode batch -source synth.tcl -log vivado_run.log -journal vivado_run.jou
```
Completato senza errori (verificato leggendo `vivado_run.log` fino in fondo).

## Passo 7 — Risultato reale ottenuto

`utilization.txt`:
```
| Slice LUTs      |    0 |     0 |          0 |     53200 |  0.00 |
| Slice Registers |    0 |     0 |          0 |    106400 |  0.00 |
| DSPs            |    0 |     0 |          0 |       220 |  0.00 |
```

`timing.txt` (uno dei percorsi riportati):
```
Slack (MET) :             9.002ns
  Source:    readFromMem[0][0]
  Destination: matA[0,0][0]
  Data Path Delay:        0.973ns  (logic 0.000ns (0.000%)  route 0.973ns (100.000%))
  Logic Levels:           0
```

## Interpretazione (perché questo risultato ha senso)

Il blocco `ComputeCore` di questo modello **non fa nessuna moltiplicazione** — riceve lo stream di 25 numeri e li ricompone in due matrici (`matA` 3×3, `matB` 4×4) tramite `reshape`, un'operazione di puro rimappaggio di indici, nota già a tempo di compilazione. Per questo il risultato è **zero risorse hardware** su ogni categoria: non c'è nessun calcolo, solo instradamento di fili — esattamente coerente con la misura indipendente ottenuta mesi prima su un blocco di solo reshape isolato (vedi [`../hdl_findings.md`](../hdl_findings.md), Risultato 1). La vera moltiplicazione delle due matrici, in questo modello didattico, avviene lato software (ARM), non lato FPGA — per questo qui non compare nessun DSP48 usato.

**Quando applicherai questo stesso identico procedimento a un blocco che fa un vero calcolo aritmetico** (come l'algoritmo MPC finale dovrà fare), aspettati numeri diversi da zero — coerenti con la regola pratica già misurata: ~1 DSP48 per ogni moltiplicazione fixed-point concorrente, su un totale di 220 disponibili sul chip xc7z020 (vedi Risultato 2 in `../hdl_findings.md`).
