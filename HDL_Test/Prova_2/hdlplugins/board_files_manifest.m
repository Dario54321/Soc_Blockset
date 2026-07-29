function m = board_files_manifest()
%BOARD_FILES_MANIFEST  Quali board file Vivado della PYNQ-Z1 sono "quelli giusti".
%
%   I board file NON sono in questo repository. Il pacchetto da cui provengono
%   non dichiara alcuna licenza, quindi non abbiamo il diritto di
%   ridistribuirli. Al loro posto c'e' questo: l'origine e l'impronta.
%
%   L'impronta e' piu' utile del file. Chiunque puo' verificare in un comando
%   di avere ESATTAMENTE la stessa revisione — cosa che avere il file nel repo
%   non garantirebbe comunque, se qualcuno ne installasse un'altra in Vivado.
%
%   Vedi docs\23_BOARD_PYNQZ1.md §23.2.

    m.sorgente = 'https://github.com/cathalmccabe/pynq-z1_board_files';
    m.licenza  = ['nessun file di licenza nel repository (verificato il ' ...
                  '29/07/2026): per questo NON sono versionati qui'];

    % Dove vanno installati: la cartella che CONTIENE 'pynq-z1', cioe'
    % <Vivado>\data\boards\board_files oppure una qualunque cartella
    % dichiarata a Vivado con  set_param board.repoPaths.
    m.installatoQui = 'C:\AMDDesignTools\Boards_Drivers\pynq-z1\1.0';

    % SHA-256 dei file che questo lavoro ha effettivamente usato.
    % Il .png non e' incluso: e' solo l'immagine mostrata nel menu di Vivado.
    m.file = struct( ...
        'nome',  {'board.xml', ...
                  'part0_pins.xml', ...
                  'preset.xml'}, ...
        'bytes', {34472, 5406, 74470}, ...
        'sha256',{'5db0afcd5dbd99bc1d4d72ad586e05c75ffb0ddd9a843582251a696a882f3889', ...
                  '409ee51c096824c8e5ad8ae42379dc79bdadced5c11dbda29b6221c05d9b7de1', ...
                  'f9c063b6e1d47d9ea0137dfd29f756ca2a5d68b9dc415d81afed6b47f9658544'});
end
