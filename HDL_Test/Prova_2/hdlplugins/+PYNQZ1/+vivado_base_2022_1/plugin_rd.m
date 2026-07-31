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

    % Queste sono le versioni supportate da HDL Coder R2026a (elenco verificato
    % nel prodotto). La 2026.1 e' esclusa per quel motivo, NON perche' il block
    % design non ci si costruisca: ci si costruisce (11_NOTE_API §16).
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
    %
    % ADATTAMENTO R2023b (Dario, 30-31/07/2026, vedi docs\24_REFERENCE_DESIGN.md):
    % addRegisterInterface non esiste in hdlturnkey.plugin.ReferenceDesignVivado
    % su R2023b (verificato con methods() sull'oggetto reale: assente dalla lista).
    % L'equivalente documentato in toolbox\hdlcoder\hdlcommon\+hdlcoder\ReferenceDesign.m
    % (esempio ufficiale MathWorks, non dedotto) e' addAXI4SlaveInterface, con
    % 'MasterAddressSpace' al posto di 'ManagerAddressSpace'. HasProcessorConnection
    % e DeviceTreeBusNode non compaiono in quell'esempio ma sono stati accettati senza
    % errore da addAXI4SlaveInterface in esecuzione reale su R2023b (hdlcoder.runWorkflow
    % ha superato il caricamento del reference design e la compilazione HDL del modello).
    % Su R2026a (dove il file era stato scritto) restava addRegisterInterface: se questo
    % plugin deve tornare a girare anche li', va verificato che addAXI4SlaveInterface
    % esista ancora in quella release con lo stesso significato.
    hRD.addAXI4SlaveInterface( ...
        'InterfaceConnection', 'axi_cpu_interconnect/M00_AXI', ...
        'BaseAddress',         '0x400D0000', ...
        'MasterAddressSpace',  'sys_cpu/Data', ...
        'HasProcessorConnection', true, ...
        'DeviceTreeBusNode',      '&fpga_axi');

    %% --- data capture -----------------------------------------------------
    % Analizzatore di stati logici on-chip. Non serve al funzionamento, ma il
    % primo bring-up avviene senza alcuna visibilita' interna: e' li' che
    % risponde a "start arriva davvero al blocco?".
    %
    % ADATTAMENTO R2023b (Dario, 30-31/07/2026): addFPGADataCaptureInterface non
    % esiste in nessuna forma su R2023b — non e' un rinomino come per il registro
    % sopra, e' una funzionalita' assente in questa release (nessun metodo simile
    % in methods(), nessuna occorrenza di "DataCapture" in tutto il toolbox hdlcoder
    % R2023b). Commentato qui, non rimosso: da confermare con Carmine se serve
    % un'alternativa (es. ILA aggiunto a mano nel block design Vivado) o se questa
    % capability va riservata alla build su R2026a.
    % hRD.addFPGADataCaptureInterface( ...
    %     'AllowedConnectivityTypes', {'JTAG','PS Ethernet','USB Ethernet'}, ...
    %     'ManagerConnection',        'axi_cpu_interconnect/M01_AXI', ...
    %     'ManagerAddressSegments',   {'sys_cpu/Data', hex2dec('50000000'), hex2dec('00100000')}, ...
    %     'ManagerClockConnection',   'core_clkwiz/clk_out1', ...
    %     'ManagerResetConnection',   'sys_core_rstgen/peripheral_aresetn');

    hRD.GenerateIPCoreDeviceTreeNodes = true;
end
