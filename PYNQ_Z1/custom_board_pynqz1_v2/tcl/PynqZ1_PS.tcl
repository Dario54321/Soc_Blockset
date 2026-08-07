################################################################
# PynqZ1_PS.tcl — Processing System per la board custom "Pynq-Z1"
# (SoC Blockset / SoC Builder, ProcessingSystem.TCLFile)
#
# Estratto e adattato da system_top.tcl (reference design HDL Coder,
# gia' validato fisicamente), sezione "Processing System" (righe
# ~136-160). A differenza del file sorgente, qui c'e' SOLO la cella
# processing_system7 con la sua configurazione: interconnessione,
# clock wizard e reset li genera SoC Builder da solo, dalle proprieta'
# gia' dichiarate in create_PynqZ1_BoardSupport.m.
#
# Nome dell'istanza: "processing_system7_0" (non "sys_cpu" come nel
# file sorgente) perche' create_PynqZ1_BoardSupport.m dichiara le
# porte (ClockOutputPort, MasterInterfacePort, InterruptInterfacePort)
# con quel prefisso — deve combaciare esattamente.
#
# Preset applicato dai board file Vivado reali della Pynq-Z1
# (apply_board_preset), non trascritto a mano — stessa scelta
# deliberata del file sorgente, per evitare di introdurre errori
# copiando ~400 parametri CONFIG.PCW_* di una board diversa.
################################################################

if { [get_projects -quiet] ne "" } {
    catch { set_property BOARD_PART www.digilentinc.com:pynq-z1:part0:1.0 [current_project] }
}

set processing_system7_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { make_external "FIXED_IO, DDR" apply_board_preset "1" \
              Master "Disable" Slave "Disable" } \
    [get_bd_cells processing_system7_0]

# M_AXI_GP0: master su cui l'ARM raggiunge i registri dell'IP core.
# FCLK_CLK0: 100 MHz (procSysObj.ClockOutputFrequency = 100 in
#            create_PynqZ1_BoardSupport.m — deve combaciare).
# IRQ_F2P: interruzioni dalla PL verso il PS.
set_property -dict [ list \
    CONFIG.PCW_USE_M_AXI_GP0             {1} \
    CONFIG.PCW_EN_CLK0_PORT              {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ  {100} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT      {1} \
    CONFIG.PCW_IRQ_F2P_INTR              {1} \
] $processing_system7_0
