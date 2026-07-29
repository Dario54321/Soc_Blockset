function hRD = plugin_rd()
%PLUGIN_RD  Reference design AXI4-Lite per la Digilent PYNQ-Z1.
%
%   Passo P12. Dice a HDL Coder dove attaccare l'IP core generato dal
%   wrapper: quale clock, quale reset, quale porta AXI, a quale indirizzo.
%
%   PROVENIENZA: ricalcato su
%   toolbox\hdlcoder\boards\amd\+ZedBoard\+vivado_base_2022_1\plugin_rd.m,
%   il reference design AXI4-Lite validato da MathWorks per lo stesso silicio.
%
%   I nomi citati qui ('core_clkwiz', 'axi_cpu_interconnect', ...) devono
%   coincidere con i nomi di istanza in system_top.tcl: sono un contratto fra
%   i due file, non etichette.
%
%   Vedi docs\24_REFERENCE_DESIGN.md.

    hRD = hdlcoder.ReferenceDesign('SynthesisTool', 'Xilinx Vivado');

    hRD.ReferenceDesignName = 'Default system (AXI4-Lite)';
    hRD.BoardName           = 'Digilent PYNQ-Z1';

    % Non la 2026.1: 'axi_interconnect' e' stato rimosso dopo la 2024.1, e
    % queste sono comunque le uniche versioni supportate da HDL Coder R2026a.
    hRD.SupportedToolVersion = {'2022.1', '2023.1', '2024.1'};

    %% --- block design ---------------------------------------------------
    % Il board part e' 'pynq-z1' MINUSCOLO, non 'PYNQ-Z1' come appare in
    % board.xml: e' il nome con cui Vivado lo registra. Verificato con
    % get_board_parts, non dedotto (docs\24_REFERENCE_DESIGN §24.3).
    hRD.addCustomVivadoDesign( ...
        'CustomBlockDesignTcl', 'system_top.tcl', ...
        'VivadoBoardPart',      'www.digilentinc.com:pynq-z1:part0:1.0');

    hRD.addDeviceTree('axilite.dtsi');

    %% --- clock -----------------------------------------------------------
    % 100 MHz di default: e' il clock su cui e' costruito tutto il budget
    % (soc_params: p.budget.clockMHz). La ZedBoard usa 50.
    % Il valore compare in quattro file diversi; check_refdesign verifica che
    % continuino a dire la stessa cosa.
    % Min/Max sono quelli che MathWorks dichiara per lo STESSO silicio
    % (xc7z020 speed -1) sulla ZedBoard: sono l'intervallo offerto nel
    % Workflow Advisor, non una promessa di chiusura temporale.
    hRD.addClockInterface( ...
        'ClockConnection',     'core_clkwiz/clk_out1', ...
        'ResetConnection',     'sys_core_rstgen/peripheral_aresetn', ...
        'DefaultFrequencyMHz', 100, ...
        'MinFrequencyMHz',     5, ...
        'MaxFrequencyMHz',     500, ...
        'ClockModuleInstance', 'core_clkwiz', ...
        'ClockNumber',         1);

    %% --- registri AXI4-Lite ----------------------------------------------
    % E' il percorso del progetto: l'ARM scrive x e START qui, e rilegge
    % DONE, CYCLES e u (docs\20_CONTRATTO_INTERFACCIA §6).
    hRD.addRegisterInterface( ...
        'InterfaceConnection',    'axi_cpu_interconnect/M00_AXI', ...
        'BaseAddress',            '0x400D0000', ...
        'ManagerAddressSpace',    'sys_cpu/Data', ...
        'HasProcessorConnection', true, ...
        'DeviceTreeBusNode',      '&fpga_axi');

    %% --- data capture -----------------------------------------------------
    % Analizzatore di stati logici on-chip. Non serve al funzionamento, ma il
    % primo bring-up avviene senza alcuna visibilita' interna: e' li' che
    % risponde a "start arriva davvero al blocco?".
    hRD.addFPGADataCaptureInterface( ...
        'AllowedConnectivityTypes', {'JTAG','PS Ethernet','USB Ethernet'}, ...
        'ManagerConnection',        'axi_cpu_interconnect/M01_AXI', ...
        'ManagerAddressSegments',   {'sys_cpu/Data', hex2dec('50000000'), hex2dec('00100000')}, ...
        'ManagerClockConnection',   'core_clkwiz/clk_out1', ...
        'ManagerResetConnection',   'sys_core_rstgen/peripheral_aresetn');

    hRD.GenerateIPCoreDeviceTreeNodes = true;
end
