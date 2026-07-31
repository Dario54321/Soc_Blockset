function run_ipcore_generation(p)
%RUN_IPCORE_GENERATION  Genera RTL + IP core per soc_wrapper_fpga, da script.
%
%   Passi 3-4 di docs/24_REFERENCE_DESIGN.md §24.5, interamente automatizzati:
%   caricamento reference design, assegnazione interfacce AXI4-Lite, workflow
%   HDL Coder "IP Core Generation". Nessuna interazione con l'HDL Workflow
%   Advisor: equivalente scriptato di quanto fatto a mano in GUI, verificato
%   dare lo stesso risultato (stesso identificatore 'AXI4-Lite', stesse
%   porte). Vedi docs/24_REFERENCE_DESIGN.md §24.8 per come è stata trovata
%   questa API (non documentata, ma pubblica e non ristretta).
%
%   Richiede Vivado 2022.1 o 2024.1 sul path (hdlsetuptoolpath) e
%   addpath('hdlplugins') già eseguito nella sessione corrente.
%
%   Non costruisce il progetto Vivado né il bitstream (task successivo,
%   "4. Embedded System Integration" nel Workflow Advisor, P13): qui si ferma
%   a RTL + IP core packaging, lo stesso perimetro del primo run riuscito.
%
%   Uso:  addpath('hdlplugins'); run_ipcore_generation()

    if nargin < 1 || isempty(p); p = soc_params(); end

    mdl = 'soc_wrapper_fpga';
    load_system(fullfile('models', [mdl '.slx']));
    cl = onCleanup(@() closeIfLoaded(mdl));

    hdlset_param(mdl, 'SynthesisTool',   'Xilinx Vivado');
    hdlset_param(mdl, 'TargetPlatform',  'Digilent PYNQ-Z1');
    hdlset_param(mdl, 'ReferenceDesign', 'Default system (AXI4-Lite)');
    hdlset_param(mdl, 'TargetFrequency', p.budget.clockMHz);
    % Deve combaciare con TargetWorkflow della config sotto, altrimenti
    % hdlcoder:workflow:ModelWorkflowMismatchConfig.
    hdlset_param(mdl, 'Workflow', 'IP Core Generation');

    %% --- Set Interfaces: ogni porta -> registro AXI4-Lite -----------------
    % 'AXI4-Lite' e' uno dei valori validi restituiti dall'errore stesso di
    % setTargetInterface quando si passa una stringa sbagliata (non e' stato
    % indovinato). Gli indirizzi (0x100, 0x104, ...) li assegna HDL Coder: si
    % leggono dal report generato, non si trascrivono qui a mano (stessa
    % regola di docs/20_CONTRATTO_INTERFACCIA §6).
    portNames = [{'start_cmd', 'timeout_thr'}, ...
                 arrayfun(@(i) sprintf('x%d', i), 0:p.mpc.nx-1, 'UniformOutput', false), ...
                 {'done', 'busy', 'timeout_flag', 'cycles'}, ...
                 arrayfun(@(j) sprintf('u%d', j), 0:p.mpc.nu-1, 'UniformOutput', false)];

    hDI = downstream.DownstreamIntegrationDriver(mdl);
    hDI.loadTopLevelSettings();
    hDI.loadModelSettings();

    for i = 1:numel(portNames)
        hDI.setTargetInterface(portNames{i}, 'AXI4-Lite');
    end

    problems = hDI.validateTargetInterface();
    errs = problems(cellfun(@(s) strcmp(s.Status, 'Error'), problems));
    assert(isempty(errs), 'runIpcoreGeneration:interfaceNotAssigned', ...
        'Interfacce non assegnate correttamente: %s', strjoin(cellfun(@(s) s.Message, errs, 'UniformOutput', false), '; '));

    %% --- Workflow: solo RTL + IP core, niente progetto/bitstream ----------
    cfg = hdlcoder.WorkflowConfig('TargetWorkflow', 'IP Core Generation', ...
        'SynthesisTool', 'Xilinx Vivado');
    cfg.RunTaskGenerateRTLCodeAndIPCore  = true;
    cfg.RunTaskCreateProject             = false;
    cfg.RunTaskGenerateSoftwareInterface = false;
    cfg.GenerateSoftwareInterfaceModel   = false;
    cfg.GenerateHostInterfaceScript      = false;
    cfg.RunTaskBuildFPGABitstream        = false;
    cfg.RunTaskProgramTargetDevice       = false;
    cfg.GenerateIPCoreReport             = true;

    hdlcoder.runWorkflow(mdl, cfg);
    fprintf('run_ipcore_generation: IP core generato per %s.\n', mdl);
end

function closeIfLoaded(mdl)
    if bdIsLoaded(mdl); close_system(mdl, 0); end
end
