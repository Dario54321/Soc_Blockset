function mdl = build_soc_top(p, outFile)
%BUILD_SOC_TOP  Costruisce models/soc_top.slx da zero, per script.
%
%   Passo P6 della procedura. E' il modello che chiude il gate G6: il top
%   referenzia soc_fpga e soc_proc come Model block, ed e' quello da cui si
%   lancia SoC Builder.
%
%   Struttura replicata da 'soc_swhw_stream_top':
%
%     Processor (SubSystem)
%       WriteTaskEvent -> Task Manager -> Model(soc_proc).write_fcn
%       done ------------------------------> Model(soc_proc).done
%       Model.dataOut -> dataOut ; Model.streamEnable -> streamEnable
%
%     Processor.dataOut ---> Software to AXI4-Stream ---> FPGA.tdata/tvalid
%     FPGA.tready ---------> Software to AXI4-Stream
%     Software to AXI4-Stream ---> Processor.WriteTaskEvent / .done
%     Processor.streamEnable ---> Register Channel ---> FPGA.streamEnable
%     FPGA.matA_out/matB_out/probe_out ---> To Workspace (per la verifica)
%
%   Uso:  build_soc_top()

    if nargin < 1 || isempty(p);  p = soc_params(); end
    here = fileparts(mfilename('fullpath'));
    modelDir = fullfile(fileparts(here), 'models');
    if nargin < 2 || isempty(outFile)
        outFile = fullfile(modelDir, 'soc_top.slx');
    end

    assert(isfile(fullfile(modelDir,'soc_fpga.slx')), 'buildSocTop:noFpga', ...
        'models/soc_fpga.slx assente: eseguire prima build_soc_fpga.');
    assert(isfile(fullfile(modelDir,'soc_proc.slx')), 'buildSocTop:noProc', ...
        'models/soc_proc.slx assente: eseguire prima build_soc_proc.');
    addpath(modelDir);

    mdl = 'soc_top';
    if bdIsLoaded(mdl); close_system(mdl, 0); end
    if isfile(outFile); delete(outFile); end

    load_system('socmemlib'); load_system('proctasklib');
    new_system(mdl);
    cl = onCleanup(@() closeIfLoaded(mdl));

    %% --- configurazione: trapianto dall'esempio -----------------------
    copyTopConfigSet(mdl);
    set_param(mdl, 'HardwareBoard', p.env.simBoard);
    % Il top model e' 'None': non e' ne' FPGA ne' processore, e' il contenitore.
    codertarget.data.setParameterValue(mdl, 'ESB.ProcessingUnit', 'None');
    % 5 attivazioni del task: sufficienti a osservare il regime senza
    % simulazioni interminabili.
    set_param(mdl, 'StopTime', sprintf('%g', p.timing.taskPeriod * 5));

    %% =================== Processor =====================================
    P = [mdl '/Processor'];
    add_block('simulink/Ports & Subsystems/Subsystem', P, 'Position',[180 60 380 220]);
    delete_line(P,'In1/1','Out1/1'); delete_block([P '/In1']); delete_block([P '/Out1']);

    add(P,'simulink/Sources/In1','WriteTaskEvent',[30 50 60 64]);
    set_param([P '/WriteTaskEvent'],'Port','1');
    add(P,'simulink/Sources/In1','done',[30 130 60 144]);
    set_param([P '/done'],'Port','2');

    add_block('proctasklib/Task Manager', [P '/Task Manager'], 'Position',[120 35 220 85]);
    configureTaskManager([P '/Task Manager'], p);

    add_block('simulink/Ports & Subsystems/Model', [P '/Processor Algorithm'], ...
              'Position',[280 40 400 150]);
    set_param([P '/Processor Algorithm'], 'ModelNameDialog', 'soc_proc.slx');

    add(P,'simulink/Sinks/Out1','dataOut',[470 58 500 72]);
    set_param([P '/dataOut'],'Port','1');
    add(P,'simulink/Sinks/Out1','streamEnable',[470 118 500 132]);
    set_param([P '/streamEnable'],'Port','2');

    add_line(P,'WriteTaskEvent/1','Task Manager/1','autorouting','on');
    add_line(P,'Task Manager/1','Processor Algorithm/1','autorouting','on');
    add_line(P,'done/1','Processor Algorithm/2','autorouting','on');
    add_line(P,'Processor Algorithm/1','dataOut/1','autorouting','on');
    add_line(P,'Processor Algorithm/2','streamEnable/1','autorouting','on');

    %% =================== blocchi di primo livello ======================
    add_block('socmemlib/Software to AXI4-Stream', [mdl '/Software to AXI4-Stream'], ...
              'Position',[460 60 620 160]);
    configureSwToStream([mdl '/Software to AXI4-Stream'], p);

    add_block('socmemlib/Register Channel', [mdl '/Register Channel'], ...
              'Position',[460 240 620 300]);
    % La tabella dei registri e' una "Custom Table" a CINQUE colonne in
    % R2026a: nome, R/W, tipo, dimensione, valore di default.
    % (In R2023b — vedi Prova_1_ref — erano quattro: differenza di release.)
    % I parametri di colonna NON si aggiornano da soli quando si scrive la
    % tabella: vanno impostati anche loro, altrimenti restano al default
    % 'reg1'/'Read' e la configurazione diventa incoerente in silenzio.
    set_param([mdl '/Register Channel'], ...
        'RegisterTable',       '{''streamEnable'',''Write'',''boolean'',''1'',''n/a''}', ...
        'RegTableNames',       '{''streamEnable''}', ...
        'RegTableRW',          '{''Write''}', ...
        'RegTableDataTypes',   '{''boolean''}', ...
        'RegTableVectorSizes', '{''1''}', ...
        'NumRegisters',        '1', ...
        'RegTableDirty',       '1', ...
        'SampleTime',          '-1');

    add_block('simulink/Ports & Subsystems/Model', [mdl '/FPGA'], ...
              'Position',[700 60 840 220]);
    set_param([mdl '/FPGA'], 'ModelNameDialog', 'soc_fpga.slx');

    % Uscite dati della PL: registrate per la verifica numerica (P7).
    logNames = {'matA_out','matB_out','probe_out'};
    for k = 1:numel(logNames)
        b = [mdl '/log_' logNames{k}];
        add_block('simulink/Sinks/To Workspace', b, 'Position',[920 40+60*k 1010 70+60*k]);
        set_param(b, 'VariableName', ['fpga_' logNames{k}], 'SaveFormat','Timeseries');
    end

    %% =================== collegamenti ==================================
    add_line(mdl,'Processor/1','Software to AXI4-Stream/1','autorouting','on');
    add_line(mdl,'FPGA/1','Software to AXI4-Stream/2','autorouting','on');   % tready
    add_line(mdl,'Software to AXI4-Stream/1','FPGA/1','autorouting','on');   % tdata
    add_line(mdl,'Software to AXI4-Stream/2','FPGA/2','autorouting','on');   % tvalid
    add_line(mdl,'Software to AXI4-Stream/3','Processor/1','autorouting','on'); % event
    add_line(mdl,'Software to AXI4-Stream/4','Processor/2','autorouting','on'); % done
    add_line(mdl,'Processor/2','Register Channel/1','autorouting','on');
    add_line(mdl,'Register Channel/1','FPGA/3','autorouting','on');          % streamEnable
    for k = 1:numel(logNames)
        add_line(mdl, sprintf('FPGA/%d',k+1), sprintf('log_%s/1',logNames{k}), 'autorouting','on');
    end

    %% -------------------------------------------------------------------
    Simulink.BlockDiagram.arrangeSystem(mdl);
    save_system(mdl, outFile);
    close_system(mdl, 0);

    verify_soc_top(outFile, p);
    fprintf('build_soc_top: %s  [verificato]\n', outFile);
end


% =====================================================================
function configureTaskManager(blk, p)
%CONFIGURETASKMANAGER  Modifica il JSON del Task Manager partendo dallo
%   SCHEMA DEL TOOL (default del blocco), non da uno inventato: si decodifica,
%   si cambiano i campi che ci interessano, si ricodifica.
    raw = get_param(blk, 'AllTaskData');
    td  = jsondecode(raw);
    if iscell(td); td = td{1}; end
    if numel(td) > 1; td = td(1); end

    td.taskName     = p.task.name;
    td.taskType     = 'Event-driven';
    td.taskEvent    = [p.task.name 'Event'];
    td.taskPeriod   = sprintf('%g', p.timing.taskPeriod);
    td.taskPriority = sprintf('%d', p.task.priority);
    td.taskDuration = p.timing.meanTaskDuration;
    if isfield(td,'taskEventSource')
        td.taskEventSource = 'Software to AXI4-Stream';
    end
    set_param(blk, 'AllTaskData', jsonencode(td));
    set_param(blk, 'EnableTaskSimulation', 'on');
    set_param(blk, 'SupportEventPorts', 'on');
end


function configureSwToStream(blk, p)
%CONFIGURESWTOSTREAM  Parametri del canale, tutti da soc_params.
    set_param(blk, ...
        'MemorySimulation',            'Burst accurate', ...
        'MemorySelection',             'PS memory', ...
        'MRNumBuffers',                num2str(p.stream.numBuffers), ...
        'BurstLengthReaderChIf',       num2str(p.stream.burstLen), ...
        'FIFODepthReader',             num2str(p.stream.fifoDepth), ...
        'FIFOAFullDepthReader',        num2str(p.stream.fifoAFull), ...
        'ICClockFrequencyReader',      num2str(p.stream.icClockMHz), ...
        'ICDataWidthReader',           num2str(p.stream.dataWidth), ...
        'ChDimensionsWriterChIf',      num2str(p.stream.frameSize), ...
        'ChTypeWriterChIf',            p.stream.wireTypeWriter, ...
        'ChDimensionsReaderChIf',      num2str(p.stream.frameSize), ...
        'ChTypeReaderChIf',            p.stream.wireTypeReader, ...
        ... % E' QUESTO a fissare il rate di simulazione del modello FPGA.
        'ChFrameSampleTimeReaderChIf', sprintf('%.17g', p.stream.frameSampleTime));
end


function copyTopConfigSet(mdl)
    src = fullfile(matlabroot,'toolbox','soc','socexamples','soc_swhw_stream_top.slx');
    assert(isfile(src), 'buildSocTop:noExample', 'Esempio non trovato: %s', src);
    [~, srcMdl] = fileparts(src);
    wasLoaded = bdIsLoaded(srcMdl);
    if ~wasLoaded; load_system(src); end
    cl = onCleanup(@() closeIfNotPreviouslyLoaded(srcMdl, wasLoaded));
    cs = getActiveConfigSet(srcMdl).copy();
    cs.Name = 'SocTopConfig';
    attachConfigSet(mdl, cs, true);
    setActiveConfigSet(mdl, cs.Name);
end


% =====================================================================
function verify_soc_top(file, p)
    [~, mdl] = fileparts(file);
    load_system(file);
    c = onCleanup(@() close_system(mdl, 0));

    chk('SolverType',   get_param(mdl,'SolverType'), 'Variable-step');
    chk('HardwareBoard',get_param(mdl,'HardwareBoard'), p.env.simBoard);
    chk('FeatureSet',   get_param(mdl,'HardwareBoardFeatureSet'), 'SoCBlockset');

    % Il requisito di SoC Builder: il top DEVE referenziare i due modelli
    % tramite Model block. E' la condizione la cui assenza produce
    % "FPGA or processor model not detected" (docs/00_DIAGNOSI D1).
    refs = find_system(mdl,'LookUnderMasks','all','BlockType','ModelReference');
    names = cellfun(@(b) erase(get_param(b,'ModelNameDialog'),'.slx'), refs, 'UniformOutput', false);
    assert(any(strcmp(names,'soc_fpga')), 'verifySocTop:noFpgaRef', ...
        'Il top non referenzia soc_fpga. Trovati: %s', strjoin(names,', '));
    assert(any(strcmp(names,'soc_proc')), 'verifySocTop:noProcRef', ...
        'Il top non referenzia soc_proc. Trovati: %s', strjoin(names,', '));

    assert(~isempty(find_system(mdl,'LookUnderMasks','all','RegExp','on','Name','Task Manager')), ...
        'verifySocTop:noTaskManager', 'Task Manager assente.');
end

function chk(what, got, want)
    assert(strcmp(got, want), 'verifySocTop:mismatch', ...
        '%s: atteso ''%s'', trovato ''%s''.', what, want, got);
end


% =====================================================================
function add(sys, src, name, pos)
    add_block(src, [sys '/' name], 'Position', pos);
end

function closeIfLoaded(mdl)
    if bdIsLoaded(mdl); close_system(mdl, 0); end
end

function closeIfNotPreviouslyLoaded(mdlName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdlName); close_system(mdlName, 0); end
end

