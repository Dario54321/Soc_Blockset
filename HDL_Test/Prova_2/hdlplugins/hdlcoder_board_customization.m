function r = hdlcoder_board_customization
%HDLCODER_BOARD_CUSTOMIZATION  Registra le board custom di questo progetto.
%
%   Meccanismo (confermato sull'esempio Trenz spedito nel prodotto,
%   toolbox\shared\hdlmotorcontrol\socMotorControl\refdesigns\trenzboard):
%     1. un file con QUESTO nome, ovunque sul path MATLAB, viene raccolto;
%     2. restituisce un cell array di riferimenti '<Pacchetto>.plugin_board';
%     3. il pacchetto (+PYNQZ1) deve essere raggiungibile dal path e contenere
%        il file di definizione plugin_board.m.
%
%   Perche' la board serva, basta quindi:
%       addpath('<...>\HDL_Test\Prova_2\hdlplugins')
%
%   Vedi docs\23_BOARD_PYNQZ1.md.

    r = {'PYNQZ1.plugin_board'};
end
