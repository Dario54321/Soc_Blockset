function mdl = build_soc_fpga(p, outFile)
%BUILD_SOC_FPGA  Costruisce models/soc_fpga.slx da zero, per script.
%
%   Passo P4 della procedura. Il modello e' un ARTEFATTO RIGENERABILE
%   (regola R4): si ricostruisce con un comando, non si modifica a mano.
%   Se serve una modifica, si modifica questo script.
%
%   Struttura e impostazioni replicate dall'esempio ufficiale SoC Blockset
%   'soc_swhw_stream_fpga' (software -> hardware), che e' esattamente la
%   nostra architettura. Tutti i numeri vengono da soc_params (regola R2).
%
%   Uso:  build_soc_fpga()

    if nargin < 1 || isempty(p);  p = soc_params(); end
    if nargin < 2 || isempty(outFile)
        here = fileparts(mfilename('fullpath'));
        outFile = fullfile(fileparts(here), 'models', 'soc_fpga.slx');
    end

    mdl = 'soc_fpga';
    if bdIsLoaded(mdl); close_system(mdl, 0); end
    if isfile(outFile); delete(outFile); end

    load_system('hwlogicconnlib');
    new_system(mdl);
    cl = onCleanup(@() closeIfLoaded(mdl));

    %% ---------------------------------------------------------------
    %  Impostazioni del modello â€” da soc_swhw_stream_fpga
    %  L'ordine conta: target file -> board -> feature set.
    %  ---------------------------------------------------------------
    % --- Configurazione: copiata dall'esempio shipped, non ricostruita ---
    %
    % Un FPGA model di SoC Blockset ha una combinazione che l'API pubblica
    % non permette di raggiungere per gradi: HardwareBoard='None' INSIEME a
    % HardwareBoardFeatureSet='SoCBlockset' e ProdHWDeviceType='ASIC/FPGA'.
    % Impostare la board a 'None' resetta il feature set a EmbeddedCoderHSP;
    % impostare il feature set richiede una board supportata. Verificato
    % sperimentalmente su quattro ordini diversi (docs/11_NOTE_API).
    %
    % Quindi non si ricostruisce: si COPIA il config set di
    % soc_swhw_stream_fpga.slx, che e' l'artefatto validato da MathWorks per
    % questa esatta architettura. La provenienza e' dichiarata, non nascosta.
    copyFpgaConfigSet(mdl);

    % Regola: l'FPGA model e' Fixed-step. Il top sara' Variable-step.
    % Non e' una contraddizione: sono due modelli distinti (docs/00_DIAGNOSI D2).
    set_param(mdl, 'SolverType', 'Fixed-step');
    set_param(mdl, 'Solver',     'FixedStepDiscrete');
    % FixedStep = 'auto', come l'esempio shipped.
    %
    % CORREZIONE di una scelta precedente sbagliata. Era stato fissato a
    % Ts_FPGA = 10 ns "per non lasciare un rate accidentale". Sbagliato: in
    % SoC Blockset il rate di SIMULAZIONE del modello FPGA non e' il clock
    % fisico della PL, e' il rate del flusso dati che gli arriva dal canale.
    % Il clock a 100 MHz e' un PARAMETRO DEL CANALE (ICClockFrequencyReader),
    % usato per calcolare i tempi di burst, non il passo del solutore.
    %
    % Fissarlo a 10 ns rende la simulazione di sistema impraticabile:
    % con StopTime = 2 s servirebbero 2e8 passi. Misurato: la simulazione
    % non termina in 10 minuti.
    set_param(mdl, 'FixedStep',  'auto');
    set_param(mdl, 'StartTime',  '0.0');
    set_param(mdl, 'StopTime',   sprintf('%g', 200*p.timing.TsFpga));

    %% ---------------------------------------------------------------
    %  Blocchi
    %  ---------------------------------------------------------------
    % Il filo porta bit grezzi (tipo intero builtin): la PL li reinterpreta
    % come sfix32_En16 con una conversione 'Stored Integer'. Simmetrico al
    % DTC_wire lato processore.
    add(mdl,'simulink/Sources/In1','tdata',[40 100 70 114]);
    set_param([mdl '/tdata'], 'OutDataTypeStr', p.stream.wireTypeReader, ...
                              'PortDimensions', num2str(p.payload.nElem), ...
                              'SampleTime', '-1');

    add(mdl,'simulink/Signal Attributes/Data Type Conversion','DTC_fromwire',[100 95 150 125]);
    set_param([mdl '/DTC_fromwire'], 'OutDataTypeStr', p.payload.dtStr, ...
                                     'ConvertRealWorld', 'Stored Integer (SI)');

    add(mdl,'simulink/Sources/In1','tvalid',[40 160 70 174]);
    set_param([mdl '/tvalid'], 'Port','2', 'OutDataTypeStr','Bus: StreamM2SBusObj', ...
                               'PortDimensions','1', 'SampleTime','-1');

    add(mdl,'simulink/Sources/In1','streamEnable',[40 240 70 254]);
    set_param([mdl '/streamEnable'], 'Port','3', 'OutDataTypeStr','boolean', ...
                                     'PortDimensions','1', 'SampleTime','-1');

    add(mdl,'hwlogicconnlib/SoC Bus Selector','SoC Bus Selector',[140 150 200 190]);
    set_param([mdl '/SoC Bus Selector'], 'Protocol','Data stream', 'ctrltype','Valid');

    add(mdl,'hwlogicconnlib/SoC Bus Creator','SoC Bus Creator',[560 232 620 268]);
    set_param([mdl '/SoC Bus Creator'], 'Protocol','Data stream', 'ctrltype','Ready');

    add(mdl,'simulink/Sinks/Terminator','Term_tlast',[240 200 260 220]);

    % --- algoritmo: unpack del payload ------------------------------
    add(mdl,'simulink/User-Defined Functions/MATLAB Function','unpack',[280 84 380 136]);
    setChartScript(mdl, 'unpack', unpackCode(p));

    % --- sonda aritmetica -------------------------------------------
    add(mdl,'simulink/Signal Attributes/Data Type Conversion','DTC_probe',[430 60 480 90]);
    set_param([mdl '/DTC_probe'], 'OutDataTypeStr', p.probe.dtStr, ...
                                  'RndMeth', p.probe.rndMethod, ...
                                  'SaturateOnIntegerOverflow', onoff(p.probe.saturate));

    add(mdl,'simulink/Math Operations/Gain','Gain_probe',[520 58 560 92]);
    set_param([mdl '/Gain_probe'], 'Gain', sprintf('%.17g', p.probe.gain), ...
                                   'OutDataTypeStr', p.probe.dtStr, ...
                                   'SaturateOnIntegerOverflow', onoff(p.probe.saturate));

    % --- uscite ------------------------------------------------------
    add(mdl,'simulink/Sinks/Out1','tready',[700 243 730 257]);
    set_param([mdl '/tready'], 'Port','1', 'OutDataTypeStr','Bus: StreamS2MBusObj');

    add(mdl,'simulink/Sinks/Out1','matA_out',[700 93 730 107]);
    set_param([mdl '/matA_out'], 'Port','2');
    add(mdl,'simulink/Sinks/Out1','matB_out',[700 133 730 147]);
    set_param([mdl '/matB_out'], 'Port','3');
    add(mdl,'simulink/Sinks/Out1','probe_out',[700 68 730 82]);
    set_param([mdl '/probe_out'], 'Port','4');

    %% ---------------------------------------------------------------
    %  Collegamenti â€” stessa topologia di soc_swhw_stream_fpga
    %  ---------------------------------------------------------------
    add_line(mdl,'tvalid/1','SoC Bus Selector/1','autorouting','on');
    add_line(mdl,'SoC Bus Selector/1','unpack/2','autorouting','on');   % valid
    add_line(mdl,'SoC Bus Selector/2','Term_tlast/1','autorouting','on'); % tlast: non usato
    add_line(mdl,'tdata/1','DTC_fromwire/1','autorouting','on');
    add_line(mdl,'DTC_fromwire/1','unpack/1','autorouting','on');
    add_line(mdl,'streamEnable/1','unpack/3','autorouting','on');

    add_line(mdl,'unpack/1','DTC_probe/1','autorouting','on');          % matA
    add_line(mdl,'DTC_probe/1','Gain_probe/1','autorouting','on');
    add_line(mdl,'Gain_probe/1','probe_out/1','autorouting','on');

    add_line(mdl,'unpack/1','matA_out/1','autorouting','on');
    add_line(mdl,'unpack/2','matB_out/1','autorouting','on');
    add_line(mdl,'unpack/3','SoC Bus Creator/1','autorouting','on');    % ready
    add_line(mdl,'SoC Bus Creator/1','tready/1','autorouting','on');

    %% ---------------------------------------------------------------
    Simulink.BlockDiagram.arrangeSystem(mdl);
    save_system(mdl, outFile);
    close_system(mdl, 0);

    % Verifica sull'ARTEFATTO, non sull'intenzione: si rilegge il file
    % salvato e si controlla che le impostazioni ci siano davvero.
    verify_soc_fpga(outFile, p);
    fprintf('build_soc_fpga: %s  [verificato]\n', outFile);
end


% =====================================================================
function copyFpgaConfigSet(mdl)
%COPYFPGACONFIGSET  Trapianta il config set dell'FPGA model d'esempio.
%   Sorgente: matlabroot/toolbox/soc/socexamples/soc_swhw_stream_fpga.slx

    src = fullfile(matlabroot,'toolbox','soc','socexamples','soc_swhw_stream_fpga.slx');
    assert(isfile(src), 'buildSocFpga:noExample', ...
        ['Esempio SoC Blockset non trovato:\n  %s\n' ...
         'Serve il support package SoC Blockset (docs/03_AMBIENTE).'], src);

    [~, srcMdl] = fileparts(src);
    wasLoaded = bdIsLoaded(srcMdl);
    if ~wasLoaded; load_system(src); end
    cl = onCleanup(@() closeIfNotPreviouslyLoaded(srcMdl, wasLoaded));

    cs = getActiveConfigSet(srcMdl).copy();
    cs.Name = 'SocFpgaConfig';
    attachConfigSet(mdl, cs, true);
    setActiveConfigSet(mdl, cs.Name);
end

function closeIfNotPreviouslyLoaded(mdlName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdlName); close_system(mdlName, 0); end
end


% =====================================================================
function verify_soc_fpga(file, p)
%VERIFY_SOC_FPGA  Rilegge il modello salvato e ne verifica le proprieta'.
    [~, mdl] = fileparts(file);
    load_system(file);
    c = onCleanup(@() close_system(mdl, 0));

    chk('SolverType',   get_param(mdl,'SolverType'),   'Fixed-step');
    chk('Solver',       get_param(mdl,'Solver'),       'FixedStepDiscrete');
    chk('FixedStep',    get_param(mdl,'FixedStep'),    'auto');
    % La firma di un FPGA model e' ProdHWDeviceType, non un parametro
    % codertarget: e' quello che distingue il modello nel file salvato.
    chk('HardwareBoard',get_param(mdl,'HardwareBoard'), 'None');
    chk('FeatureSet',   get_param(mdl,'HardwareBoardFeatureSet'), 'SoCBlockset');
    chk('ProdHWDeviceType', get_param(mdl,'ProdHWDeviceType'), 'ASIC/FPGA->ASIC/FPGA');
    chk('ProdEqTarget', get_param(mdl,'ProdEqTarget'), 'off');
    chk('tdata dtype',  get_param([mdl '/tdata'],'OutDataTypeStr'), p.stream.wireTypeReader);
    chk('tdata dims',   get_param([mdl '/tdata'],'PortDimensions'), num2str(p.payload.nElem));
    chk('fromwire dt',  get_param([mdl '/DTC_fromwire'],'OutDataTypeStr'), p.payload.dtStr);
    chk('fromwire mode',get_param([mdl '/DTC_fromwire'],'ConvertRealWorld'), 'Stored Integer (SI)');
    chk('probe dtype',  get_param([mdl '/Gain_probe'],'OutDataTypeStr'), p.probe.dtStr);
    chk('probe satura', get_param([mdl '/Gain_probe'],'SaturateOnIntegerOverflow'), 'on');

    % Il codice della MATLAB Function deve contenere gli indici di soc_params:
    % se qualcuno cambia la partizione senza rigenerare, qui salta fuori.
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[mdl '/unpack']);
    assert(~isempty(ch), 'verifySocFpga:noChart', 'MATLAB Function unpack assente.');
    needA = sprintf('u(%d:%d)', p.matA.idx(1), p.matA.idx(end));
    needB = sprintf('u(%d:%d)', p.matB.idx(1), p.matB.idx(end));
    assert(contains(ch.Script, needA), 'verifySocFpga:idxA', ...
        'Il codice di unpack non contiene %s.', needA);
    assert(contains(ch.Script, needB), 'verifySocFpga:idxB', ...
        'Il codice di unpack non contiene %s (il bug matB di Prova_1 era esattamente questo).', needB);
end

function chk(what, got, want)
    assert(strcmp(got, want), 'verifySocFpga:mismatch', ...
        '%s: atteso ''%s'', trovato ''%s''.', what, want, got);
end


% =====================================================================
function code = unpackCode(p)
%UNPACKCODE  Genera il corpo della MATLAB Function DA soc_params (regola R2).
%   Gli indici non sono scritti a mano da nessuna parte: se la partizione
%   cambia in soc_params, il codice generato cambia con essa. E' il rimedio
%   strutturale al disallineamento .slx/HDL di Prova_1.

    a0 = p.matA.idx(1);  a1 = p.matA.idx(end);
    b0 = p.matB.idx(1);  b1 = p.matB.idx(end);

    code = sprintf([ ...
        'function [matA, matB, ready] = unpack(u, valid, streamEnable)\n' ...
        '%%#codegen\n' ...
        '%% GENERATO DA build_soc_fpga.m â€” non modificare a mano.\n' ...
        '%% Indici e forme provengono da soc_params (regola R2).\n' ...
        '%% Srotolamento column-major, coerente con ref_model.m.\n' ...
        '\n' ...
        '    matA = reshape(u(%d:%d), [%d %d]);\n' ...
        '    matB = reshape(u(%d:%d), [%d %d]);\n' ...
        '\n' ...
        '    %% Handshake.\n' ...
        '    %% ready NON deve dipendere da valid: e'' la regola AXI4-Stream\n' ...
        '    %% (VALID non aspetta READY, READY non e'' funzione di VALID).\n' ...
        '    %% Violarla produce uno stallo: il canale non alza valid finche''\n' ...
        '    %% non vede ready, e ready non sale perche'' aspetta valid.\n' ...
        '    %% Misurato: tvalid.valid e tready.ready costantemente 0, uscite\n' ...
        '    %% della PL sempre nulle.\n' ...
        '    %% Resta un SEGNAPOSTO: sempre pronto = nessuna contropressione.\n' ...
        '    ready = streamEnable;\n' ...
        '    %%#ok<INUSD> valid non usato di proposito\n' ...
        'end\n'], ...
        a0, a1, p.matA.size(1), p.matA.size(2), ...
        b0, b1, p.matB.size(1), p.matB.size(2));
end


function add(mdl, src, name, pos)
    add_block(src, [mdl '/' name], 'Position', pos);
end

function setChartScript(mdl, blkName, code)
    sf  = sfroot;
    ch  = sf.find('-isa','Stateflow.EMChart','Path',[mdl '/' blkName]);
    assert(~isempty(ch), 'buildSocFpga:noChart', ...
        'MATLAB Function ''%s'' non trovata.', blkName);
    ch.Script = code;
end

function s = onoff(tf)
    if tf; s = 'on'; else; s = 'off'; end
end

function closeIfLoaded(mdl)
    if bdIsLoaded(mdl); close_system(mdl, 0); end
end

