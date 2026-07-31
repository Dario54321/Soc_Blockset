function V = validate_refdesign(vivadoExe, verbose)
%VALIDATE_REFDESIGN  Esegue system_top.tcl in Vivado e riporta cosa e' successo.
%
%   V = VALIDATE_REFDESIGN()
%   V = VALIDATE_REFDESIGN('C:\...\Vivado\bin\vivado.bat')
%
%   check_refdesign confronta i quattro file fra loro; questo fa l'unica cosa
%   che quel confronto non puo' fare: **costruire davvero il block design**.
%
%   L'esito e' uno di tre, e non vengono confusi fra loro:
%
%     'completa'   il design si costruisce e valida. Serve Vivado 2022.1 o
%                  2024.1 (le versioni dichiarate dal reference design).
%     'parziale'   il PRESET DELLA BOARD si applica (la parte piu' incerta del
%                  design), ma il block design non arriva in fondo. La CAUSA
%                  varia con l'installazione e viene letta dal log, non assunta.
%     'fallita'    nemmeno il Processing System viene costruito.
%     'assente'    nessun Vivado trovato. Niente e' stato verificato.
%
%   Un esito 'parziale' NON e' un successo. La funzione lo restituisce senza
%   sollevare errore, ma V.esito lo dice e vengono stampate le cause osservate.
%
%   Cause viste finora, per riferimento — NON sono le uniche possibili:
%     Vivado 2026.1 : 'axi_interconnect' non esiste piu' (rimosso dopo la 2024.1)
%     Vivado 2022.1 : 'axi_interconnect:2.1' su disco ma non in catalogo
%   Vedi docs\24_REFERENCE_DESIGN §24.7.

    if nargin < 2; verbose = true; end
    if nargin < 1 || isempty(vivadoExe); vivadoExe = find_vivado(); end

    here  = fileparts(mfilename('fullpath'));
    root  = fileparts(here);
    fTcl  = fullfile(root, 'hdlplugins', '+PYNQZ1', '+vivado_base_2022_1', 'system_top.tcl');
    assert(isfile(fTcl), 'validateRd:noTcl', 'system_top.tcl assente: %s', fTcl);

    V = struct('esito','assente', 'vivado','', 'versione','', ...
               'presetApplicato',false, 'designValidato',false, ...
               'celle',{{}}, 'log','');

    if isempty(vivadoExe)
        if verbose
            fprintf(2, ['[validate_refdesign] nessun Vivado trovato: il block design ' ...
                        'NON e'' stato costruito.\n']);
        end
        return
    end
    V.vivado = vivadoExe;

    wd = fullfile(tempdir, ['rdval_' char(java.util.UUID.randomUUID.toString())]);
    mkdir(wd);
    cl = onCleanup(@() rmdirQuiet(wd));

    boardRepo = board_repo_root();
    runTcl = fullfile(wd, 'run.tcl');
    fid = fopen(runTcl, 'w');
    fprintf(fid, 'puts "MWV: version [version -short]"\n');
    if ~isempty(boardRepo)
        fprintf(fid, 'set_param board.repoPaths [list "%s"]\n', strrep(boardRepo,'\','/'));
    end
    fprintf(fid, 'if {[catch {source "%s"} msg]} {\n', strrep(fTcl,'\','/'));
    % L'errore del tcl e' multiriga e la parte utile ("in catalogo c'e' invece
    % X") sta dopo la prima riga: si appiattisce, altrimenti la cattura per riga
    % la perde proprio a chi serve.
    fprintf(fid, '  puts "MWV: sourceFallito [string map [list \\n { | }] $msg]"\n');
    fprintf(fid, '} else {\n');
    fprintf(fid, '  puts "MWV: sourceOk"\n');
    fprintf(fid, '  foreach c [get_bd_cells] { puts "MWV: cella [string trimleft $c /]" }\n');
    fprintf(fid, '  if {[catch {validate_bd_design -quiet} m2]} {\n');
    fprintf(fid, '    puts "MWV: validazioneFallita $m2"\n');
    fprintf(fid, '  } else { puts "MWV: validazioneOk" }\n');
    fprintf(fid, '}\n');
    % Il preset si controlla comunque, anche se il source e' fallito dopo il PS:
    % e' la parte che dipende dai board file ed e' quella che volevamo provare.
    fprintf(fid, 'if {[llength [get_bd_cells -quiet sys_cpu]]} {\n');
    fprintf(fid, '  puts "MWV: ddrPart [get_property CONFIG.PCW_UIPARAM_DDR_PARTNO [get_bd_cells sys_cpu]]"\n');
    fprintf(fid, '  puts "MWV: fclk0 [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells sys_cpu]]"\n');
    fprintf(fid, '  puts "MWV: gp0 [get_property CONFIG.PCW_USE_M_AXI_GP0 [get_bd_cells sys_cpu]]"\n');
    fprintf(fid, '}\n');
    fclose(fid);

    cmd = sprintf('"%s" -mode batch -source "%s" -nojournal -log "%s"', ...
        vivadoExe, runTcl, fullfile(wd,'val.log'));
    old = cd(wd);
    clCd = onCleanup(@() cd(old));
    [~, out] = system(cmd);
    V.log = out;

    % ANCORATI A INIZIO RIGA. Vivado in modo batch rieccheggia il sorgente del
    % tcl (prefissato da '# '), quindi un pattern non ancorato aggancia il
    % TESTO DELLO SCRIPT invece del suo output: 'validazioneOk' matcherebbe la
    % riga «puts "MWV: validazioneOk"» anche quando non viene mai eseguita, e
    % il banco dichiarerebbe riuscita una validazione fallita. Successo qui il
    % 29/07 (docs/24_REFERENCE_DESIGN §24.6).
    V.versione        = firstMatch(out, '^MWV: version (\S+)');
    V.celle           = regexp(out, '^MWV: cella (\S+)', 'tokens', 'lineanchors');
    V.celle           = cellfun(@(c) c{1}, V.celle, 'UniformOutput', false);
    V.designValidato  = ~isempty(regexp(out, '^MWV: validazioneOk', 'once', 'lineanchors'));
    V.sourceOk        = ~isempty(regexp(out, '^MWV: sourceOk',      'once', 'lineanchors'));
    fclk              = firstMatch(out, '^MWV: fclk0 (\S+)');

    % La CAUSA si legge dal log, non si assume. Una versione precedente stampava
    % una spiegazione fissa ("questo Vivado non ha axi_interconnect") che era
    % giusta solo sulla macchina dove era stata scritta: su una 2022.1 reale il
    % motivo era un altro e il messaggio depistava chi lo leggeva.
    V.errore = firstMatch(out, '^MWV: sourceFallito ([^\r\n]+)');
    V.erroriVivado = unique(regexp(out, '^(?:ERROR|CRITICAL WARNING): \[[^\]]+\][^\r\n]*', ...
                                   'match', 'lineanchors'), 'stable');
    % '[^\r\n]+' e non '.+': in MATLAB il punto matcha ANCHE il newline
    % (l'opzione per escluderlo e' 'dotexceptnewline'), quindi '.+' si
    % mangerebbe le righe successive.
    ddr               = firstMatch(out, '^MWV: ddrPart ([^\r\n]+)');
    V.presetApplicato = ~isempty(ddr);
    V.ddrPart         = strtrim(ddr);
    V.fclk0           = fclk;

    if V.designValidato
        V.esito = 'completa';
    elseif V.presetApplicato
        V.esito = 'parziale';
    else
        V.esito = 'fallita';
    end

    if verbose
        fprintf('validate_refdesign: Vivado %s -> esito %s\n', V.versione, V.esito);
        if V.presetApplicato
            fprintf('  preset della board applicato: DDR = %s, FCLK0 = %s MHz\n', V.ddrPart, V.fclk0);
        end
        fprintf('  celle create: %s\n', strjoin(V.celle, ', '));
        switch V.esito
            case 'parziale'
                fprintf(2, ['  VERIFICA PARZIALE: il preset della board si applica, ma il ' ...
                            'block design non e'' stato completato.\n' ...
                            '  Interconnessione, clock del core e reset NON sono stati provati.\n']);
                mostraCause(V);
            case 'fallita'
                fprintf(2, '  FALLITA: il Processing System non e'' stato nemmeno costruito.\n');
                mostraCause(V);
                fprintf(2, '  Log in coda:\n%s\n', tail(V.log, 15));
        end
    end
end


% =====================================================================
function mostraCause(V)
%MOSTRACAUSE  Stampa la causa OSSERVATA, non quella supposta.
%
%   Chi legge questo messaggio sta su una macchina diversa da quella dove il
%   banco e' stato scritto. Una spiegazione preconfezionata la' e' un depistaggio
%   qui: si riportano l'errore del sorgente tcl e le righe ERROR/CRITICAL del log.

    if ~isempty(V.errore)
        fprintf(2, '  Causa riportata dal tcl:\n    %s\n', V.errore);
    end
    if ~isempty(V.erroriVivado)
        fprintf(2, '  Righe ERROR/CRITICAL nel log di Vivado:\n');
        for k = 1:min(numel(V.erroriVivado), 8)
            fprintf(2, '    %s\n', strtrim(V.erroriVivado{k}));
        end
        if numel(V.erroriVivado) > 8
            fprintf(2, '    ... e altre %d\n', numel(V.erroriVivado)-8);
        end
    end
    if isempty(V.errore) && isempty(V.erroriVivado)
        fprintf(2, ['  Nessun ERROR nel log: il tcl non e'' arrivato in fondo senza ' ...
                    'segnalare. Ispezionare V.log.\n']);
    end
end


function s = firstMatch(txt, pat)
    tk = regexp(txt, pat, 'tokens', 'once', 'lineanchors');
    if isempty(tk); s = ''; else; s = tk{1}; end
end

function s = tail(txt, n)
    L = strsplit(txt, newline);
    L = L(max(1,end-n+1):end);
    s = strjoin(L, newline);
end

function v = find_vivado()
    cand = dir('C:\AMDDesignTools\*\Vivado\bin\vivado.bat');
    if isempty(cand); cand = dir('C:\Xilinx\Vivado\*\bin\vivado.bat'); end
    if isempty(cand); v = ''; else; v = fullfile(cand(end).folder, cand(end).name); end
end

function r = board_repo_root()
%BOARD_REPO_ROOT  La cartella che CONTIENE le cartelle-board, non la board.
    cand = {'C:\AMDDesignTools\Boards_Drivers'};
    r = '';
    for k = 1:numel(cand)
        if isfolder(fullfile(cand{k}, 'pynq-z1')); r = cand{k}; return; end
    end
end

function rmdirQuiet(d)
    try rmdir(d, 's'); catch; end
end
