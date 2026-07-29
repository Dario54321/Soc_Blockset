function p = board_pins()
%BOARD_PINS  I pin di bordo della PYNQ-Z1 dichiarati al plugin HDL Coder.
%
%   UNICA FONTE del dato di pin (regola R2). Due consumatori:
%     - PYNQZ1.plugin_board  li dichiara a HDL Coder;
%     - check_board_plugin   li riverifica contro i board file Vivado.
%
%   Senza questo file il confronto sarebbe impossibile: hdlcoder.Board non
%   espone pubblicamente le interfacce aggiunte con addExternalIOInterface,
%   quindi dall'oggetto costruito i pin non si rileggono. L'alternativa
%   sarebbe stata parsare il sorgente del plugin, che e' fragile.
%
%   ORIGINE DEI VALORI: part0_pins.xml dei board file Vivado della PYNQ-Z1,
%   quelli che il gruppo ha gia' installato. `xmlName` e' il nome del pin in
%   quel file: e' la chiave che rende il confronto esatto invece che
%   posizionale.

    p = struct( ...
        'id',      {'LEDs General Purpose', 'Push Buttons',      'DIP Switches'}, ...
        'type',    {'OUT',                  'IN',                'IN'}, ...
        'port',    {'GPLEDs',               'PushButtons',       'DIPSwitches'}, ...
        'xmlName', {'leds_4bits_tri_o_%d',  'btns_4bits_tri_i_%d','sws_2bits_tri_i_%d'}, ...
        'pins',    {{'R14','P14','N16','M14'}, ...
                    {'D19','D20','L20','L19'}, ...
                    {'M20','M19'}}, ...
        'iostd',   {'LVCMOS33',             'LVCMOS33',          'LVCMOS33'});
end
