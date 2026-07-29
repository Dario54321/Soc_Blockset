function [rd, boardName] = hdlcoder_ref_design_customization
%HDLCODER_REF_DESIGN_CUSTOMIZATION  Reference design della PYNQ-Z1.
%
%   Meccanismo (dai file di registrazione spediti nel prodotto): un file con
%   questo nome DENTRO la cartella del board plugin viene raccolto; restituisce
%   i riferimenti ai reference design e il nome della board a cui si applicano.
%
%   `boardName` deve coincidere esattamente con `hB.BoardName` di
%   plugin_board.m, altrimenti il reference design non viene associato a
%   nessuna board e non compare nel Workflow Advisor. check_refdesign
%   verifica che i due nomi siano ancora uguali.

    rd = { 'PYNQZ1.vivado_base_2022_1.plugin_rd' };

    boardName = 'Digilent PYNQ-Z1';
end
