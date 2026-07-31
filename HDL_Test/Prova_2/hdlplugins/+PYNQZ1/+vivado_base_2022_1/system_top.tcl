################################################################
# system_top.tcl — block design del reference design PYNQ-Z1 (AXI4-Lite)
#
# Passo P12. Costruisce il sistema attorno al quale HDL Coder inserisce
# l'IP core generato dal wrapper.
#
# PROVENIENZA
#   Topologia ricalcata su quella della ZedBoard
#   (toolbox\hdlcoder\boards\amd\+ZedBoard\+vivado_base_2022_1\system_top.tcl),
#   che e' il reference design AXI4-Lite validato da MathWorks. Stessi IP,
#   stesse connessioni, stessi nomi di istanza: i nomi sono un CONTRATTO,
#   plugin_rd.m li cita per indicare dove attaccare clock, reset e registri.
#
# DUE DIFFERENZE DELIBERATE
#
#   1. Il Processing System NON e' configurato a mano. Quello della ZedBoard
#      contiene 399 righe di CONFIG.PCW_*: DDR, MIO, PLL, tutto trascritto.
#      Qui si applica il preset che sta nei board file Vivado della PYNQ-Z1,
#      che e' la stessa fonte che Vivado userebbe scegliendo la board dal
#      menu. Trascrivere 399 parametri di una board diversa e' il modo piu'
#      efficiente di introdurre un errore che si manifesta solo a runtime.
#
#   2. Le versioni degli IP stanno in una tabella unica in cima (MW_IP_VER) e
#      vengono stampate quando si risolvono. Sono le stesse del file ZedBoard;
#      quel che cambia e' che una versione mancante produce un messaggio che
#      dice COSA c'e' in catalogo, invece di un "IP not found" opaco a meta'
#      costruzione.
#
# VERSIONE DI VIVADO
#   Serve la 2022.1 o la 2024.1 — le uniche supportate da HDL Coder R2026a.
#   Non e' una preferenza: 'axi_interconnect' e' stato RIMOSSO dopo la 2024.1
#   (nella 2026.1 esiste solo 'smartconnect'), e tutti i reference design
#   MathWorks, incluso quello per la 2024.1, lo usano ancora.
#
# Vedi docs\24_REFERENCE_DESIGN.md.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   return [file dirname $script_path]
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

# ---------------------------------------------------------------------------
# Versioni degli IP — FISSATE, non dedotte.
#
# Sono esattamente quelle usate da tutti i reference design MathWorks e dagli
# esempi SoC Blockset (385 occorrenze nell'installazione, nessuna divergenza).
# E' la combinazione che MathWorks valida sulle versioni di Vivado dichiarate in
# plugin_rd.m.
#
# PERCHE' FISSATE. Una versione precedente di questo file le RISOLVEVA a runtime
# prendendo la piu' alta in catalogo. Su una installazione 2022.1 reale il
# catalogo esponeva solo 'axi_interconnect:1.7' (la 2.1 c'era su disco ma non in
# catalogo), lo script ha istanziato la 1.7 senza dire nulla, e il progetto e'
# morto duecento righe dopo con un opaco:
#     ERROR: [BD 5-313] Found unsupported IP 'xilinx.com:ip:axi_interconnect:1.7'
# Scegliere una versione e' una CONFIGURAZIONE: se non c'e' quella giusta si
# deve fermare dicendo cosa manca, non ripiegare in silenzio su un'altra.
# Vedi docs\24_REFERENCE_DESIGN §24.7.
# ---------------------------------------------------------------------------
array set MW_IP_VER {
    processing_system7  5.5
    axi_interconnect    2.1
    clk_wiz             6.0
    proc_sys_reset      5.0
    xlconcat            2.1
    xlconstant          1.1
}

proc mw_ip {name} {
    global MW_IP_VER
    if {![info exists MW_IP_VER($name)]} {
        error "MW_PYNQ: nessuna versione fissata per l'IP '$name'. Aggiungerla a MW_IP_VER."
    }
    set want "xilinx.com:ip:${name}:$MW_IP_VER($name)"

    if {[llength [get_ipdefs -quiet $want]] == 1} {
        puts "  \[mw_ip\] ${name} -> ${want}"
        return $want
    }

    # Non c'e'. Si dice cosa c'e' invece, perche' e' l'informazione che serve.
    set avail [get_ipdefs -quiet xilinx.com:ip:${name}:*]
    set msg "MW_PYNQ: l'IP '$want' non e' nel catalogo di Vivado [version -short]."
    if {[llength $avail] == 0} {
        append msg "\n  Nessuna versione di '$name' e' in catalogo."
    } else {
        append msg "\n  In catalogo c'e' invece: $avail"
        append msg "\n  NON viene sostituita automaticamente: la versione e' una scelta di progetto."
    }
    if {$name eq "axi_interconnect"} {
        append msg "\n  Note: 'axi_interconnect' e' stato RIMOSSO dopo la 2024.1 (resta 'smartconnect'),"
        append msg "\n  e su alcune installazioni 2022.1 la 2.1 e' su disco ma non in catalogo."
        append msg "\n  In quel caso provare 'update_ip_catalog -rebuild' e verificare la licenza."
    }
    append msg "\n  Versioni di Vivado supportate da questo reference design: vedi plugin_rd.m."
    error $msg
}

variable design_name
set design_name system_top

# Se HDL Coder ha gia' creato progetto e block design, si lavora su quelli;
# altrimenti li si crea (e' il caso quando il file si esegue da solo per
# validarlo — vedi scripts\validate_refdesign.m).
if { [get_projects -quiet] eq "" } {
    create_project -force project_1 myproj -part xc7z020clg400-1
    set_property BOARD_PART www.digilentinc.com:pynq-z1:part0:1.0 [current_project]
}
if { [current_bd_design -quiet] eq "" } {
    create_bd_design $design_name
}


proc create_root_design { parentCell } {

  variable design_name

  if { $parentCell eq "" } { set parentCell [get_bd_cells /] }
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "MW_PYNQ-100" "ERROR" "Cella padre <$parentCell> non trovata."}
     return
  }
  set oldCurInst [current_bd_instance .]
  current_bd_instance $parentObj

  ##########################################################################
  # Processing System
  ##########################################################################
  set sys_cpu [ create_bd_cell -type ip -vlnv [mw_ip processing_system7] sys_cpu ]

  # Il preset arriva dai board file della PYNQ-Z1: DDR, MIO, PLL, periferiche.
  # make_external porta fuori DDR e FIXED_IO, che vanno ai pin fisici.
  apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
      -config { make_external "FIXED_IO, DDR" apply_board_preset "1" \
                Master "Disable" Slave "Disable" } \
      [get_bd_cells sys_cpu]

  # Il preset descrive la BOARD, non l'uso che ne facciamo: quello che segue
  # riguarda il confine verso la PL e va impostato comunque.
  #   M_AXI_GP0     : il master su cui l'ARM raggiunge i nostri registri
  #   FCLK_CLK0     : 100 MHz, lo stesso su cui e' costruito il budget
  #                   (soc_params: p.budget.clockMHz)
  #   IRQ_F2P       : le interruzioni dalla PL, usate da HDL Coder
  set_property -dict [ list \
      CONFIG.PCW_USE_M_AXI_GP0        {1} \
      CONFIG.PCW_EN_CLK0_PORT         {1} \
      CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
      CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
      CONFIG.PCW_IRQ_F2P_INTR         {1} \
  ] $sys_cpu

  ##########################################################################
  # Interconnessione, clock e reset
  ##########################################################################
  # Due master: M00 per l'IP core generato, M01 per FPGA Data Capture.
  set axi_cpu_interconnect [ create_bd_cell -type ip -vlnv [mw_ip axi_interconnect] axi_cpu_interconnect ]
  set_property -dict [ list \
      CONFIG.NUM_MI           {2} \
      CONFIG.S00_HAS_REGSLICE {4} \
  ] $axi_cpu_interconnect

  # Clock del core. 100 MHz: e' il clock su cui e' scritto tutto il budget
  # (docs\22_STUDIO_LATENZA). La ZedBoard usa 50 MHz.
  set core_clkwiz [ create_bd_cell -type ip -vlnv [mw_ip clk_wiz] core_clkwiz ]
  set_property -dict [ list \
      CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.0} \
      CONFIG.PRIM_SOURCE                {Global_buffer} \
      CONFIG.RESET_TYPE                 {ACTIVE_LOW} \
  ] $core_clkwiz

  set sys_100m_rstgen [ create_bd_cell -type ip -vlnv [mw_ip proc_sys_reset] sys_100m_rstgen ]
  set_property -dict [ list CONFIG.C_EXT_RST_WIDTH {1} ] $sys_100m_rstgen

  set sys_core_rstgen [ create_bd_cell -type ip -vlnv [mw_ip proc_sys_reset] sys_core_rstgen ]
  set_property -dict [ list CONFIG.C_EXT_RST_WIDTH {1} ] $sys_core_rstgen

  ##########################################################################
  # Interruzioni
  ##########################################################################
  # 16 ingressi tenuti a zero: HDL Coder ne rimpiazza uno se l'IP core
  # genera un'interruzione. Senza il concat, IRQ_F2P resterebbe scollegato.
  set intr_concat [ create_bd_cell -type ip -vlnv [mw_ip xlconcat] intr_concat ]
  set_property -dict [ list CONFIG.NUM_PORTS {16} ] $intr_concat

  set const_intr_concat_gnd [ create_bd_cell -type ip -vlnv [mw_ip xlconstant] const_intr_concat_gnd ]
  set_property -dict [ list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1} ] $const_intr_concat_gnd

  ##########################################################################
  # Connessioni
  ##########################################################################
  connect_bd_intf_net -intf_net axi_cpu_interconnect_s00_axi \
      [get_bd_intf_pins axi_cpu_interconnect/S00_AXI] [get_bd_intf_pins sys_cpu/M_AXI_GP0]

  set gndPins {}
  for {set i 0} {$i < 16} {incr i} { lappend gndPins [get_bd_pins intr_concat/In$i] }
  connect_bd_net -net const_intr_concat_gnd \
      [get_bd_pins const_intr_concat_gnd/dout] {*}$gndPins

  connect_bd_net -net core_clkwiz_locked_net \
      [get_bd_pins core_clkwiz/locked] [get_bd_pins sys_core_rstgen/dcm_locked]

  connect_bd_net -net intr_concat_dout \
      [get_bd_pins intr_concat/dout] [get_bd_pins sys_cpu/IRQ_F2P]

  # Reset di sistema: dal PS a tutto il resto.
  connect_bd_net -net proc_100m_resetn \
      [get_bd_pins core_clkwiz/resetn] \
      [get_bd_pins sys_100m_rstgen/ext_reset_in] \
      [get_bd_pins sys_core_rstgen/ext_reset_in] \
      [get_bd_pins sys_cpu/FCLK_RESET0_N]

  # Dominio a 100 MHz che arriva dal PS: lato slave dell'interconnessione.
  connect_bd_net -net sys_100m_clk \
      [get_bd_pins axi_cpu_interconnect/ACLK] \
      [get_bd_pins axi_cpu_interconnect/S00_ACLK] \
      [get_bd_pins core_clkwiz/clk_in1] \
      [get_bd_pins sys_100m_rstgen/slowest_sync_clk] \
      [get_bd_pins sys_cpu/FCLK_CLK0] \
      [get_bd_pins sys_cpu/M_AXI_GP0_ACLK]

  connect_bd_net -net sys_100m_resetn \
      [get_bd_pins axi_cpu_interconnect/ARESETN] \
      [get_bd_pins axi_cpu_interconnect/S00_ARESETN] \
      [get_bd_pins sys_100m_rstgen/peripheral_aresetn]

  # Dominio del core, generato dal clk_wiz: lato master, dove va il nostro IP.
  connect_bd_net -net sys_core_clk \
      [get_bd_pins axi_cpu_interconnect/M00_ACLK] \
      [get_bd_pins axi_cpu_interconnect/M01_ACLK] \
      [get_bd_pins core_clkwiz/clk_out1] \
      [get_bd_pins sys_core_rstgen/slowest_sync_clk]

  connect_bd_net -net sys_core_resetn \
      [get_bd_pins axi_cpu_interconnect/M00_ARESETN] \
      [get_bd_pins axi_cpu_interconnect/M01_ARESETN] \
      [get_bd_pins sys_core_rstgen/peripheral_aresetn]

  # Nessun segmento di indirizzi qui: li assegna HDL Coder quando inserisce
  # l'IP core, dagli indirizzi dichiarati in plugin_rd.m.

  current_bd_instance $oldCurInst
  save_bd_design
}

create_root_design ""
