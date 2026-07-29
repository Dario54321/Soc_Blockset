function R = check_refdesign(verbose)
%CHECK_REFDESIGN  Verifica il reference design PYNQ-Z1 (P12, gate G12a).
%
%   R = CHECK_REFDESIGN()
%
%   Il reference design e' fatto di quattro file che devono raccontare la
%   STESSA cosa: plugin_rd.m, system_top.tcl, axilite.dtsi e la registrazione.
%   Fra loro non c'e' alcun controllo automatico: si legano per nome e per
%   numero, e quando divergono nessuno protesta — il progetto costruisce e si
%   comporta in modo diverso da come e' documentato.
%
%   Questo verifica i quattro legami che possono rompersi in silenzio:
%
%     1. il nome della board, che lega reference design e board plugin;
%     2. il board part di Vivado, contro board.xml;
%     3. la frequenza di clock, contro soc_params — compare in QUATTRO file;
%     4. i nomi delle istanze che plugin_rd cita e system_top.tcl deve creare.
%
%   Cosa NON verifica: che il block design si costruisca. Serve Vivado 2022.1
%   o 2024.1 — vedi validate_refdesign, e docs\24_REFERENCE_DESIGN §24.5.

    if nargin < 1; verbose = true; end

    here    = fileparts(mfilename('fullpath'));
    root    = fileparts(here);
    plugDir = fullfile(root, 'hdlplugins');
    rdDir   = fullfile(plugDir, '+PYNQZ1', '+vivado_base_2022_1');
    addpath(plugDir);

    fRd   = fullfile(rdDir, 'plugin_rd.m');
    fTcl  = fullfile(rdDir, 'system_top.tcl');
    fDtsi = fullfile(rdDir, 'axilite.dtsi');
    for f = {fRd, fTcl, fDtsi}
        assert(isfile(f{1}), 'checkRd:missingFile', 'File assente: %s', f{1});
    end

    %% ---- 1. il nome della board lega i due plugin ------------------------
    [rd, boardName] = PYNQZ1.hdlcoder_ref_design_customization();
    assert(iscell(rd) && ~isempty(rd), 'checkRd:badRd', ...
        'hdlcoder_ref_design_customization deve restituire un cell array non vuoto.');

    hB = PYNQZ1.plugin_board();
    assert(strcmp(boardName, hB.BoardName), 'checkRd:boardNameMismatch', ...
        ['Il reference design dichiara la board ''%s'', il board plugin si chiama ''%s''.\n' ...
         'Non coincidendo, il reference design non verrebbe associato ad alcuna board.'], ...
        boardName, hB.BoardName);

    hRD = feval(rd{1});
    for pr = {'ReferenceDesignName','BoardName','SupportedToolVersion'}
        assert(isprop(hRD, pr{1}) && ~isempty(hRD.(pr{1})), 'checkRd:emptyProp', ...
            '%s: la proprieta'' %s e'' vuota.', rd{1}, pr{1});
    end
    assert(strcmp(hRD.BoardName, boardName), 'checkRd:rdBoardMismatch', ...
        'plugin_rd dichiara la board ''%s'', la registrazione ''%s''.', hRD.BoardName, boardName);

    assert(~any(strcmp(hRD.SupportedToolVersion, '2026.1')), 'checkRd:vivado2026', ...
        ['Dichiarata la 2026.1 fra le versioni supportate: non lo e''.\n' ...
         '''axi_interconnect'' e'' stato rimosso dopo la 2024.1.']);

    R.boardName    = boardName;
    R.toolVersions = hRD.SupportedToolVersion;

    srcRd  = fileread(fRd);
    srcTcl = fileread(fTcl);
    srcDt  = fileread(fDtsi);

    %% ---- 2. il board part di Vivado, contro board.xml --------------------
    R.boardPart = grab(srcRd, '''VivadoBoardPart''\s*,\s*''([^'']+)''', ...
        'VivadoBoardPart', fRd);

    bxml = locate_board_xml();
    R.boardXml = bxml;
    if isempty(bxml)
        if verbose
            fprintf(2, ['[check_refdesign] board.xml non trovato: il board part ' ...
                        '''%s'' NON e'' stato confrontato con la fonte.\n'], R.boardPart);
        end
    else
        t  = fileread(bxml);
        ven = grab(t, 'vendor\s*=\s*"([^"]+)"',       'vendor in board.xml',       bxml);
        % '\<' e' l'inizio-parola di MATLAB; '\b' NON e' un word boundary e
        % non aggancia nulla (docs\11_NOTE_API §13). Serve a non prendere
        % 'display_name', dove 'name' e' preceduto da '_'.
        nam = grab(t, '\<name\s*=\s*"([^"]+)"',       'name in board.xml',         bxml);
        ver = grab(t, '<file_version>([^<]+)</file_version>', 'file_version',      bxml);
        % Vivado registra il nome in MINUSCOLO: board.xml dice 'PYNQ-Z1', il
        % board part e' 'pynq-z1'. Verificato con get_board_parts.
        want = sprintf('%s:%s:part0:%s', ven, lower(nam), strtrim(ver));
        assert(strcmp(R.boardPart, want), 'checkRd:boardPartMismatch', ...
            ['VivadoBoardPart e'' ''%s'', ma da board.xml risulta ''%s''.\n' ...
             'Attenzione: il nome va in minuscolo.'], R.boardPart, want);
    end

    %% ---- 3. la frequenza di clock, in quattro file -----------------------
    p = soc_params();
    R.clockMHz = p.budget.clockMHz;

    fRdMHz = str2double(grab(srcRd, '''DefaultFrequencyMHz''\s*,\s*([\d.]+)', ...
        'DefaultFrequencyMHz', fRd));
    fCore  = str2double(grab(srcTcl, 'CLKOUT1_REQUESTED_OUT_FREQ\s*\{([\d.]+)\}', ...
        'CLKOUT1_REQUESTED_OUT_FREQ', fTcl));
    fFclk  = str2double(grab(srcTcl, 'PCW_FPGA0_PERIPHERAL_FREQMHZ\s*\{([\d.]+)\}', ...
        'PCW_FPGA0_PERIPHERAL_FREQMHZ', fTcl));
    dtDiv  = str2double(grab(srcDt,  'clock-div\s*=\s*<([\d]+)>', 'clock-div', fDtsi));
    dtMult = str2double(grab(srcDt,  'clock-mult\s*=\s*<([\d]+)>', 'clock-mult', fDtsi));

    assert(fRdMHz == R.clockMHz, 'checkRd:clockRd', ...
        ['plugin_rd offre %g MHz di default, soc_params costruisce il budget su %g.\n' ...
         'Il numero di cicli comunicato all''altro ingegnere sarebbe sbagliato.'], ...
        fRdMHz, R.clockMHz);
    assert(fCore == R.clockMHz, 'checkRd:clockTcl', ...
        'Il clk_wiz in system_top.tcl produce %g MHz, il budget assume %g.', fCore, R.clockMHz);

    % Il device tree descrive a Linux il rapporto fra FCLK_CLK0 e il clock del
    % core. Se sbaglia, i driver calcolano frequenze inesistenti.
    expDiv = fFclk / fCore * dtMult;
    assert(expDiv == round(expDiv) && dtDiv == expDiv, 'checkRd:clockDtsi', ...
        ['axilite.dtsi dichiara clock-div=%g (mult=%g), ma FCLK e'' %g MHz e il core %g:\n' ...
         'il divisore corretto e'' %g.'], dtDiv, dtMult, fFclk, fCore, expDiv);

    R.fclkMHz = fFclk;

    %% ---- 4. i nomi delle istanze -----------------------------------------
    % plugin_rd nomina istanze che system_top.tcl deve creare. Rinominarne una
    % da un lato solo produce un errore in Vivado a meta' build.
    conns = regexp(srcRd, ['''(?:ClockConnection|ResetConnection|InterfaceConnection|' ...
        'ManagerConnection|ManagerClockConnection|ManagerResetConnection|' ...
        'ManagerAddressSpace|ClockModuleInstance)''\s*,\s*''([^'']+)'''], 'tokens');
    assert(~isempty(conns), 'checkRd:noConns', ...
        'Nessuna connessione trovata in %s: il file ha cambiato forma?', fRd);

    inst = unique(cellfun(@(c) firstToken(c{1}), conns, 'UniformOutput', false));
    R.instances = inst;
    for k = 1:numel(inst)
        pat = ['create_bd_cell[^\n]*\s' regexptranslate('escape', inst{k}) '\s*\]'];
        assert(~isempty(regexp(srcTcl, pat, 'once')), 'checkRd:instMissing', ...
            ['plugin_rd cita l''istanza ''%s'', che system_top.tcl non crea.\n' ...
             'I nomi di istanza sono un contratto fra i due file.'], inst{k});
    end

    if verbose
        fprintf(['check_refdesign: %s | board part %s | %g MHz (FCLK %g) | ' ...
                 '%d istanze | Vivado %s\n'], ...
            R.boardName, R.boardPart, R.clockMHz, R.fclkMHz, numel(inst), ...
            strjoin(R.toolVersions, '/'));
    end
end


% =====================================================================
function v = grab(txt, pat, what, file)
%GRAB  Estrae un valore e FALLISCE se il pattern non aggancia nulla.
%   Un'estrazione che restituisce vuoto in silenzio trasformerebbe questo
%   verificatore in un controllo che passa sempre.
    tk = regexp(txt, pat, 'tokens', 'once');
    assert(~isempty(tk), 'checkRd:patternNotFound', ...
        ['Non trovato "%s" in %s.\n' ...
         'Il file e'' cambiato: il controllo va aggiornato, non ignorato.'], what, file);
    v = tk{1};
end


function s = firstToken(str)
    parts = strsplit(str, '/');
    s = parts{1};
end


function f = locate_board_xml()
%LOCATE_BOARD_XML  Cerca board.xml della PYNQ-Z1 dove Vivado lo installa.
    cand = { ...
        'C:\AMDDesignTools\Boards_Drivers\pynq-z1\1.0', ...
        'C:\Xilinx\Vivado\*\data\boards\board_files\pynq-z1\*', ...
        'C:\AMDDesignTools\*\Vivado\data\boards\board_files\pynq-z1\*'};
    f = '';
    for k = 1:numel(cand)
        hits = dir(fullfile(cand{k}, 'board.xml'));
        if ~isempty(hits)
            f = fullfile(hits(1).folder, hits(1).name);
            return
        end
    end
end
