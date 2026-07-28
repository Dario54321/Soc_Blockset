function mdl = build_soc_proc(p, outFile)
%BUILD_SOC_PROC  Costruisce models/soc_proc.slx da zero, per script.
%
%   Passo P5 della procedura. Come per soc_fpga: artefatto rigenerabile
%   (regola R4), configurazione trapiantata dall'esempio ufficiale
%   'soc_swhw_stream_proc', numeri da soc_params (regola R2).
%
%   Il modello e' il lato ARM del test: calcola le due matrici, le impacchetta
%   in 25 elementi sfix32_En16 e le manda con Stream Write.
%   NIENTE typecast a uint64: il payload nasce a 32 bit (vincolo C1).
%
%   Uso:  build_soc_proc()

    if nargin < 1 || isempty(p);  p = soc_params(); end
    if nargin < 2 || isempty(outFile)
        here = fileparts(mfilename('fullpath'));
        outFile = fullfile(fileparts(here), 'models', 'soc_proc.slx');
    end

    mdl = 'soc_proc';
    if bdIsLoaded(mdl); close_system(mdl, 0); end
    if isfile(outFile); delete(outFile); end

    load_system('prociolib');
    new_system(mdl);
    cl = onCleanup(@() closeIfLoaded(mdl));

    %% --- configurazione: trapianto dall'esempio -----------------------
    copyProcConfigSet(mdl);
    % L'esempio e' su ZC706; noi simuliamo su ZedBoard, che monta lo stesso
    % die della PYNQ-Z1 (xc7z020). Entrambe supportano il feature set SoC.
    set_param(mdl, 'HardwareBoard', p.env.simBoard);
    set_param(mdl, 'StopTime', '10.0');

    % Marca il modello come PROCESSORE (APU). Serve allo scheduler di SoC
    % Blockset per distinguere un modello referenziato da un modello SoC di
    % primo livello: senza, la simulazione del top fallisce con
    % soc:scheduler:SimInProgress ("You cannot simulate two models in the
    % same folder at the same time").
    % Nota: il file dell'esempio shipped memorizza 'None', ma quando viene
    % caricato SOTTO il suo top model la hook di SoC Blockset lo porta a
    % 'APU'. Noi lo scriviamo esplicitamente, come prescrive la doc.
    codertarget.data.setParameterValue(mdl, 'ESB.ProcessingUnit', 'APU');

    %% --- porte di modello --------------------------------------------
    add(mdl,'simulink/Sources/In1','write_fcn',[40 60 70 74]);
    set_param([mdl '/write_fcn'], 'Port','1', 'OutputFunctionCall','on');

    add(mdl,'simulink/Sources/In1','done',[40 140 70 154]);
    set_param([mdl '/done'], 'Port','2', 'OutDataTypeStr','boolean', ...
                             'PortDimensions','1', 'SampleTime','-1');

    % Blocco built-in, non di libreria: nell'esempio non ha ReferenceBlock.
    add(mdl,'built-in/AsynchronousTaskSpecification', ...
        'Asynchronous Task Specification',[40 240 140 280]);
    set_param([mdl '/Asynchronous Task Specification'], ...
        'TaskPriority', num2str(p.task.priority));

    %% --- sottosistema Writer, function-call ---------------------------
    wr = [mdl '/Writer'];
    add_block('simulink/Ports & Subsystems/Function-Call Subsystem', wr, ...
              'Position',[200 50 380 180]);
    % ripulisce il contenuto di default
    delete_line(wr,'In1/1','Out1/1');
    delete_block([wr '/In1']); delete_block([wr '/Out1']);

    add(wr,'simulink/Sources/In1','done',[40 140 70 154]);
    set_param([wr '/done'], 'Port','1', 'OutDataTypeStr','boolean');

    add(wr,'simulink/User-Defined Functions/MATLAB Function','compute_payload',[130 40 250 100]);
    setChartScript(wr, 'compute_payload', payloadCode(p));

    add(wr,'simulink/Signal Attributes/Data Type Conversion','DTC_payload',[300 55 360 85]);
    set_param([wr '/DTC_payload'], 'OutDataTypeStr', p.payload.dtStr, ...
                                   'RndMeth','Floor', ...
                                   'SaturateOnIntegerOverflow','on');

    % Reinterpretazione verso il tipo "sul filo": stesso pattern di bit,
    % nessun riscalamento. E' la sostituzione corretta del typecast a uint64.
    add(wr,'simulink/Signal Attributes/Data Type Conversion','DTC_wire',[370 55 420 85]);
    set_param([wr '/DTC_wire'], 'OutDataTypeStr', p.stream.wireTypeWriter, ...
                                'ConvertRealWorld', 'Stored Integer (SI)');

    add_block('prociolib/Stream Write', [wr '/Stream Write'], 'Position',[460 45 540 105]);
    set_param([wr '/Stream Write'], ...
        'DeviceName',      p.stream.writeDevice, ...
        'NumberOfBuffers', num2str(p.stream.numBuffers), ...
        'EnableEvent',     'on');

    % streamEnable, lato software.
    %
    % Il valore NON va collegato direttamente al Register Channel del top: il
    % canale espone una porta MESSAGGIO e rifiuta un segnale
    % ("Invalid connection between message and signal ports ...
    %   HWSW Message Receive"). Il lato software scrive attraverso il blocco
    % accessore prociolib/Register Write, che e' cio' che produce il
    % messaggio. Stesso pattern dell'esempio shipped, dentro Priming/sendCmd.
    %
    % Il valore costante resta un SEGNAPOSTO: nell'esempio un sottosistema di
    % priming tiene basso streamEnable finche' i buffer non sono pieni. Qui
    % no, quindi il canale non viene primato (docs/10_SPEC_TEST §8).
    add(wr,'simulink/Sources/Constant','streamEnable_placeholder',[280 130 340 160]);
    set_param([wr '/streamEnable_placeholder'], 'Value','true', 'OutDataTypeStr','boolean');

    add_block('prociolib/Register Write', [wr '/Register Write'], 'Position',[380 125 460 165]);
    set_param([wr '/Register Write'], ...
        'RegisterName',  p.regchan.name, ...
        'DeviceName',    p.regchan.deviceName, ...
        'OffsetAddress', p.regchan.offset, ...
        'OutputSink',    'To output port');

    add(wr,'simulink/Sinks/Out1','data',[560 68 590 82]);
    set_param([wr '/data'],'Port','1');
    add(wr,'simulink/Sinks/Out1','streamEnable',[560 138 590 152]);
    set_param([wr '/streamEnable'],'Port','2');

    add_line(wr,'compute_payload/1','DTC_payload/1','autorouting','on');
    add_line(wr,'DTC_payload/1','DTC_wire/1','autorouting','on');
    add_line(wr,'DTC_wire/1','Stream Write/1','autorouting','on');
    add_line(wr,'done/1','Stream Write/2','autorouting','on');
    add_line(wr,'Stream Write/1','data/1','autorouting','on');
    add_line(wr,'streamEnable_placeholder/1','Register Write/1','autorouting','on');
    add_line(wr,'Register Write/1','streamEnable/1','autorouting','on');

    %% --- uscite di modello --------------------------------------------
    add(mdl,'simulink/Sinks/Out1','dataOut',[460 68 490 82]);
    set_param([mdl '/dataOut'],'Port','1');
    add(mdl,'simulink/Sinks/Out1','streamEnable',[460 138 490 152]);
    set_param([mdl '/streamEnable'],'Port','2');

    % L'Asynchronous Task Specification sta IN CASCATA sul segnale
    % function-call, non in parallelo: annota il segnale con le proprieta'
    % del task e lo passa al trigger. Simulink impone entrambi i vincoli:
    %  - dev'essere collegato direttamente all'inport function-call;
    %  - quell'inport non puo' andare a nient'altro.
    add_line(mdl,'write_fcn/1','Asynchronous Task Specification/1','autorouting','on');
    add_line(mdl,'Asynchronous Task Specification/1','Writer/Trigger','autorouting','on');
    add_line(mdl,'done/1','Writer/1','autorouting','on');
    add_line(mdl,'Writer/1','dataOut/1','autorouting','on');
    add_line(mdl,'Writer/2','streamEnable/1','autorouting','on');

    %% -------------------------------------------------------------------
    Simulink.BlockDiagram.arrangeSystem(mdl);
    save_system(mdl, outFile);
    close_system(mdl, 0);

    verify_soc_proc(outFile, p);
    fprintf('build_soc_proc: %s  [verificato]\n', outFile);
end


% =====================================================================
function code = payloadCode(p)
%PAYLOADCODE  Corpo della MATLAB Function che produce il payload.
%   Le due matrici sono lo scenario storico del progetto, dichiarato in
%   docs/10_SPEC_TEST.md come dato di prova dell'infrastruttura.
%   L'impacchettamento e' column-major, inverso esatto dell'unpack lato FPGA.

    code = sprintf([ ...
        'function u = compute_payload()\n' ...
        '%%#codegen\n' ...
        '%% GENERATO DA build_soc_proc.m â€” non modificare a mano.\n' ...
        '%% Lato ARM: calcola le due matrici e le impacchetta in %d elementi.\n' ...
        '%% Column-major, inverso dell''unpack in soc_fpga (regola R2).\n' ...
        '\n' ...
        '    A = [1 2 3; 4 5 6; 7 8 9];\n' ...
        '    B = [9 8 7; 6 5 4; 3 2 1];\n' ...
        '    C = [1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16];\n' ...
        '    D = eye(4);\n' ...
        '\n' ...
        '    Y1 = A * B;   %% %dx%d\n' ...
        '    Y2 = C * D;   %% %dx%d\n' ...
        '\n' ...
        '    u = [reshape(Y1, [], 1); reshape(Y2, [], 1)];   %% %d + %d = %d\n' ...
        'end\n'], ...
        p.payload.nElem, ...
        p.matA.size(1), p.matA.size(2), p.matB.size(1), p.matB.size(2), ...
        prod(p.matA.size), prod(p.matB.size), p.payload.nElem);
end


function copyProcConfigSet(mdl)
%COPYPROCCONFIGSET  Trapianta il config set del processor model d'esempio.
    src = fullfile(matlabroot,'toolbox','soc','socexamples','soc_swhw_stream_proc.slx');
    assert(isfile(src), 'buildSocProc:noExample', ...
        'Esempio SoC Blockset non trovato:\n  %s', src);
    [~, srcMdl] = fileparts(src);
    wasLoaded = bdIsLoaded(srcMdl);
    if ~wasLoaded; load_system(src); end
    cl = onCleanup(@() closeIfNotPreviouslyLoaded(srcMdl, wasLoaded));

    cs = getActiveConfigSet(srcMdl).copy();
    cs.Name = 'SocProcConfig';
    attachConfigSet(mdl, cs, true);
    setActiveConfigSet(mdl, cs.Name);
end


% =====================================================================
function verify_soc_proc(file, p)
%VERIFY_SOC_PROC  Rilegge il file salvato e ne verifica le proprieta'.
    [~, mdl] = fileparts(file);
    load_system(file);
    c = onCleanup(@() close_system(mdl, 0));

    chk('SolverType',    get_param(mdl,'SolverType'), 'Fixed-step');
    chk('Solver',        get_param(mdl,'Solver'),     'FixedStepDiscrete');
    chk('HardwareBoard', get_param(mdl,'HardwareBoard'), p.env.simBoard);
    chk('FeatureSet',    get_param(mdl,'HardwareBoardFeatureSet'), 'SoCBlockset');
    chk('ProdHWDeviceType', get_param(mdl,'ProdHWDeviceType'), ...
        'ARM Compatible->ARM Cortex-A (32-bit)');
    chk('payload dtype', get_param([mdl '/Writer/DTC_payload'],'OutDataTypeStr'), p.payload.dtStr);
    chk('StreamWrite dev', get_param([mdl '/Writer/Stream Write'],'DeviceName'), p.stream.writeDevice);
    chk('StreamWrite buf', get_param([mdl '/Writer/Stream Write'],'NumberOfBuffers'), ...
        num2str(p.stream.numBuffers));
    chk('write_fcn',     get_param([mdl '/write_fcn'],'OutputFunctionCall'), 'on');
end

function chk(what, got, want)
    assert(strcmp(got, want), 'verifySocProc:mismatch', ...
        '%s: atteso ''%s'', trovato ''%s''.', what, want, got);
end


% =====================================================================
function add(sys, src, name, pos)
    add_block(src, [sys '/' name], 'Position', pos);
end

function setChartScript(sys, blkName, code)
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[sys '/' blkName]);
    assert(~isempty(ch), 'buildSocProc:noChart', ...
        'MATLAB Function ''%s'' non trovata.', blkName);
    ch.Script = code;
end

function closeIfLoaded(mdl)
    if bdIsLoaded(mdl); close_system(mdl, 0); end
end

function closeIfNotPreviouslyLoaded(mdlName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdlName); close_system(mdlName, 0); end
end

