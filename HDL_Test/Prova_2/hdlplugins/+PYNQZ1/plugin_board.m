function hB = plugin_board()
%PLUGIN_BOARD  Definizione della board Digilent PYNQ-Z1 per HDL Coder.
%
%   Passo P11. La PYNQ-Z1 non e' fra le board fornite da MathWorks: va
%   registrata a mano. Struttura ricalcata su +ZedBoard (stesso silicio
%   xc7z020, package diverso) e sull'esempio Trenz, che e' il precedente
%   spedito nel prodotto per una board di terze parti.
%
%   FONTE DEI DATI — non trascritti da un manuale ne' ricordati:
%   i pin vengono dai board file Vivado che il gruppo ha gia' installato,
%       C:\AMDDesignTools\Boards_Drivers\pynq-z1\1.0\part0_pins.xml
%   che sono la stessa cosa che Vivado legge quando si sceglie la board.
%   `check_board_plugin` rilegge quel file e verifica che questa
%   trascrizione gli corrisponda ancora, pin per pin (gate T14).
%
%   Vedi docs\23_BOARD_PYNQZ1.md.

    hB = hdlcoder.Board;

    hB.BoardName    = 'Digilent PYNQ-Z1';

    % --- silicio -------------------------------------------------------
    % part0_pins.xml: part_name="xc7z020clg400-1"
    % Stesso die della ZedBoard, package diverso: clg400 invece di clg484.
    % E' l'unica differenza che conta per la sintesi, ed e' anche il motivo
    % per cui il plugin ZedBoard non si puo' usare cosi' com'e'.
    hB.FPGAVendor   = 'Xilinx';
    hB.FPGAFamily   = 'Zynq';
    hB.FPGADevice   = 'xc7z020';
    hB.FPGAPackage  = 'clg400';
    hB.FPGASpeed    = '-1';

    % Solo Vivado: ISE non copre questo flusso e non lo useremo.
    hB.SupportedTool = {'Xilinx Vivado'};

    % Posizione nella catena JTAG. Presa dal precedente Zynq-7000
    % (ZedBoard e Trenz usano entrambe 2: il DAP dell'ARM e' 1, la PL e' 2).
    % NON verificata su questa board: si conferma al primo collegamento.
    hB.JTAGChainPosition = 2;

    % --- interfaccia di default per le porte esterne --------------------
    % ATTENZIONE: la ZedBoard dichiara LVCMOS18, qui sarebbe SBAGLIATO.
    % Tutti i 69 pin dichiarati in part0_pins.xml sono LVCMOS33: i banchi
    % di I/O della PYNQ-Z1 sono alimentati a 3.3 V.
    hB.addExternalPortInterface( ...
        'IOPadConstraint', {'IOSTANDARD = LVCMOS33'});

    % --- I/O di bordo ---------------------------------------------------
    % Solo cio' che serve al bring-up. Il percorso dati del progetto passa
    % tutto per registri AXI4-Lite e non tocca alcun pin: questi servono a
    % rispondere alla domanda "il bitstream e' vivo?".
    % Deliberatamente NON dichiarati: RGB LED, Pmod JA/JB, shield Arduino,
    % SPI, I2C. Sono in part0_pins.xml se un giorno serviranno — ogni pin
    % trascritto e' un'occasione di sbagliare, e questi non servono.
    %
    % I pin stanno in PYNQZ1.board_pins, non qui: e' l'unico posto da cui
    % li legge anche il verificatore (regola R2).
    for io = PYNQZ1.board_pins()
        hB.addExternalIOInterface( ...
            'InterfaceID',    io.id, ...
            'InterfaceType',  io.type, ...
            'PortName',       io.port, ...
            'PortWidth',      numel(io.pins), ...
            'FPGAPin',        io.pins, ...
            'IOPadConstraint', {['IOSTANDARD = ' io.iostd]});
    end

    % --- device tree ----------------------------------------------------
    % NON dichiarato di proposito. La ZedBoard aggiunge 'zynq-zed.dtsi', che
    % descrive le periferiche del PS di QUELLA board (PHY ethernet, USB, SD):
    % sulla PYNQ-Z1 sono diverse. Serve solo al flusso Linux del reference
    % design (P12) ed e' un punto aperto per chi lo costruira'.
end
