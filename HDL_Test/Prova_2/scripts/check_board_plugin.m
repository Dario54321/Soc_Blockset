function R = check_board_plugin(boardFilesDir, verbose)
%CHECK_BOARD_PLUGIN  Verifica il plugin board PYNQ-Z1 (P11, gate G11).
%
%   R = CHECK_BOARD_PLUGIN()
%   R = CHECK_BOARD_PLUGIN(boardFilesDir)
%
%   Due livelli, e il risultato dice sempre QUALE dei due e' stato eseguito.
%
%   Livello 1 — contratto di registrazione (sempre eseguibile)
%     hdlcoder_board_customization restituisce un riferimento; il pacchetto si
%     risolve; l'oggetto hdlcoder.Board si costruisce; silicio e nome sono
%     quelli attesi. E' il contratto documentato nei file di registrazione
%     spediti nel prodotto.
%
%   Livello 2 — trascrizione dei pin (se i board file Vivado si trovano)
%     Ogni pin dichiarato in PYNQZ1.board_pins viene riconfrontato con
%     part0_pins.xml: sigla del pin E standard di I/O. E' il livello che
%     conta davvero, perche' un pin sbagliato non lo scopre nessun altro
%     controllo prima della sintesi.
%
%   Cosa questo NON verifica: che la board compaia nel menu del Workflow
%   Advisor. Il registro di HDL Coder e' p-coded e non espone alcuna API
%   pubblica per elencare le board (verificato, non supposto). Resta una
%   conferma manuale da fare una volta sola — vedi docs\23_BOARD_PYNQZ1.md.

    if nargin < 2; verbose = true; end

    here    = fileparts(mfilename('fullpath'));
    plugDir = fullfile(fileparts(here), 'hdlplugins');
    assert(isfolder(plugDir), 'checkBoard:noPlugDir', ...
        'Cartella dei plugin assente: %s', plugDir);
    addpath(plugDir);

    %% ---- livello 1: il contratto di registrazione -----------------------
    assert(exist('hdlcoder_board_customization','file') == 2, ...
        'checkBoard:noCustomFile', ...
        ['hdlcoder_board_customization non e'' sul path.\n' ...
         'Senza quel file HDL Coder non vede la board: addpath(''%s'').'], plugDir);

    refs = hdlcoder_board_customization();
    assert(iscell(refs) && ~isempty(refs), 'checkBoard:badRefs', ...
        'hdlcoder_board_customization deve restituire un cell array non vuoto.');
    ref = refs{1};
    assert(strcmp(ref, 'PYNQZ1.plugin_board'), 'checkBoard:wrongRef', ...
        'Riferimento registrato ''%s'', atteso ''PYNQZ1.plugin_board''.', ref);

    % Costruzione ATTRAVERSO il riferimento registrato, non chiamando
    % direttamente la funzione: cosi' si esercita la risoluzione del
    % pacchetto, che e' cio' che fa HDL Coder.
    hB = feval(ref);
    % NON si verifica con isa(hB,'hdlcoder.Board'): hdlcoder.Board e' una
    % facciata e l'oggetto costruito e' un hdlturnkey.plugin.BoardIP
    % (docs\11_NOTE_API §14). Si verifica cio' che conta: che l'oggetto
    % esponga e abbia popolato le proprieta' che descrivono la board.
    need = {'BoardName','FPGAVendor','FPGAFamily','FPGADevice','FPGAPackage','FPGASpeed'};
    for k = 1:numel(need)
        assert(isprop(hB, need{k}), 'checkBoard:notABoard', ...
            '%s ha restituito un %s: manca la proprieta'' %s.', ref, class(hB), need{k});
        assert(~isempty(hB.(need{k})), 'checkBoard:emptyProp', ...
            '%s: la proprieta'' %s e'' vuota.', ref, need{k});
    end

    R.boardName = hB.BoardName;
    R.part      = sprintf('%s%s%s', hB.FPGADevice, hB.FPGAPackage, hB.FPGASpeed);

    assert(strcmp(hB.FPGAVendor,'Xilinx') && strcmp(hB.FPGAFamily,'Zynq'), ...
        'checkBoard:wrongFamily', 'Vendor/famiglia: %s / %s', hB.FPGAVendor, hB.FPGAFamily);
    assert(strcmp(R.part, 'xc7z020clg400-1'), 'checkBoard:wrongPart', ...
        ['Part dichiarata ''%s'', attesa ''xc7z020clg400-1''.\n' ...
         'Nota: clg484 e'' la ZedBoard, non questa board.'], R.part);

    R.level1 = true;

    %% ---- livello 2: la trascrizione dei pin -----------------------------
    if nargin < 1 || isempty(boardFilesDir)
        boardFilesDir = find_board_files();
    end

    R.boardFilesDir = boardFilesDir;
    R.level2        = false;
    R.nPinsChecked  = 0;

    if isempty(boardFilesDir)
        if verbose
            fprintf(2, ['[check_board_plugin] board file Vivado NON trovati: ' ...
                'i %d pin NON sono stati verificati.\n' ...
                '  Passare il percorso a mano: check_board_plugin(''<dir con part0_pins.xml>'')\n' ...
                '  Su questa macchina stanno in C:\\AMDDesignTools\\Boards_Drivers\\pynq-z1\\1.0\n'], ...
                total_pins());
        end
        return
    end

    xmlFile = fullfile(boardFilesDir, 'part0_pins.xml');
    assert(isfile(xmlFile), 'checkBoard:noPinFile', ...
        'part0_pins.xml assente in %s', boardFilesDir);
    txt = fileread(xmlFile);

    % La part dichiarata dai board file deve essere la stessa del plugin:
    % se il gruppo aggiorna i board file a una revisione diversa, si scopre qui.
    tk = regexp(txt, 'part_info\s+part_name\s*=\s*"([^"]+)"', 'tokens', 'once');
    assert(~isempty(tk), 'checkBoard:noPartName', ...
        'part_name non trovata in %s', xmlFile);
    assert(strcmp(tk{1}, R.part), 'checkBoard:partMismatch', ...
        'I board file dichiarano part ''%s'', il plugin ''%s''.', tk{1}, R.part);

    % name= ha uno spazio prima dell'uguale nei file Digilent: 'name ="..."'.
    m = regexp(txt, ['name\s*=\s*"([^"]+)"\s+iostandard\s*=\s*"([^"]+)"' ...
                     '\s+loc\s*=\s*"([^"]+)"'], 'tokens');
    assert(~isempty(m), 'checkBoard:noPins', ...
        'Nessun pin estratto da %s: il formato del file e'' cambiato?', xmlFile);
    ref = containers.Map();
    for k = 1:numel(m)
        ref(m{k}{1}) = struct('iostd', m{k}{2}, 'loc', m{k}{3});
    end

    for io = PYNQZ1.board_pins()
        for i = 1:numel(io.pins)
            nm = sprintf(io.xmlName, i-1);      % i nomi nell'XML sono 0-based
            assert(ref.isKey(nm), 'checkBoard:pinNotInXml', ...
                '''%s'' (%s) non esiste in part0_pins.xml: nome sbagliato?', nm, io.id);
            got = ref(nm);
            assert(strcmp(got.loc, io.pins{i}), 'checkBoard:pinMismatch', ...
                '%s pin %d: il plugin dice %s, i board file dicono %s.', ...
                io.id, i, io.pins{i}, got.loc);
            assert(strcmp(got.iostd, io.iostd), 'checkBoard:iostdMismatch', ...
                '%s pin %d (%s): il plugin dice %s, i board file dicono %s.', ...
                io.id, i, io.pins{i}, io.iostd, got.iostd);
            R.nPinsChecked = R.nPinsChecked + 1;
        end
    end

    R.level2 = true;

    if verbose
        fprintf('check_board_plugin: %s | part %s | %d pin verificati su %s\n', ...
            R.boardName, R.part, R.nPinsChecked, xmlFile);
    end
end


% =====================================================================
function n = total_pins()
    n = 0;
    for io = PYNQZ1.board_pins(); n = n + numel(io.pins); end
end


function d = find_board_files()
%FIND_BOARD_FILES  Cerca i board file Vivado della PYNQ-Z1.
%
%   I board file sono di terze parti e non stanno nel repository: vivono
%   dove Vivado li ha installati, e il percorso cambia da macchina a
%   macchina. Si cerca in ordine di specificita'.

    cand = { ...
        'C:\AMDDesignTools\Boards_Drivers\pynq-z1\1.0', ...
        'C:\Xilinx\Vivado\*\data\boards\board_files\pynq-z1\*', ...
        'C:\Xilinx\Vivado\*\data\xhub\boards\XilinxBoardStore\boards\*\pynq*\*', ...
        'C:\AMDDesignTools\*\Vivado\data\boards\board_files\pynq-z1\*'};

    d = '';
    for k = 1:numel(cand)
        hits = dir(fullfile(cand{k}, 'part0_pins.xml'));
        if ~isempty(hits)
            d = hits(1).folder;
            return
        end
    end
end
