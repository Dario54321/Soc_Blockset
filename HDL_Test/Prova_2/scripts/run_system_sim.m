function R = run_system_sim(p)
%RUN_SYSTEM_SIM  Simula il modello SoC completo e verifica l'uscita della PL
%   contro il reference model. E' il passo P7 e il gate G7.
%
%   R = RUN_SYSTEM_SIM()
%
%   Cosa dimostra: che il payload calcolato sull'ARM, impacchettato,
%   trasportato dal canale AXI4-Stream e spacchettato dalla PL, ritorna le
%   matrici attese. E' la prima verifica NUMERICA end-to-end del progetto.
%
%   Nota sui tempi: la simulazione impiega ~2 minuti. Il rate del modello
%   FPGA non e' il clock della PL ma il tempo di frame del canale
%   (docs/11_NOTE_API): fissarlo a 10 ns renderebbe la simulazione
%   impraticabile (2e8 passi per 2 s simulati).

    if nargin < 1 || isempty(p); p = soc_params(); end

    here     = fileparts(mfilename('fullpath'));
    modelDir = fullfile(fileparts(here), 'models');
    f = fullfile(modelDir, 'soc_top.slx');
    assert(isfile(f), 'runSystemSim:noTop', ...
        'models/soc_top.slx assente: eseguire build_soc_top.');
    addpath(modelDir);

    m = 'soc_top';
    if bdIsLoaded(m); close_system(m, 0); end
    load_system(f);
    cl = onCleanup(@() close_system(m, 0));

    t0 = tic;
    % NON usare sim(m) da dentro una funzione: in modalita' legacy le
    % variabili To Workspace finiscono nel workspace del CHIAMANTE (quindi
    % nella funzione, invisibili), non nel base. Da script sembrava
    % funzionare solo perche' il chiamante era il base workspace.
    % Simulink.SimulationInput con ReturnWorkspaceOutputs='on' restituisce
    % sempre un oggetto popolato, indipendente dal contesto di chiamata.
    in  = Simulink.SimulationInput(m);
    in  = in.setModelParameter('ReturnWorkspaceOutputs','on');
    out = sim(in);
    R.wallClock = toc(t0);

    % --- raccolta uscite -------------------------------------------------
    R.matA  = lastSample(getLogged(out,'fpga_matA_out'),  p.matA.size);
    R.matB  = lastSample(getLogged(out,'fpga_matB_out'),  p.matB.size);
    R.probe = lastSample(getLogged(out,'fpga_probe_out'), p.matA.size);

    % --- attesi ----------------------------------------------------------
    % Il payload atteso e' quello prodotto dal lato ARM; il reference model
    % ne calcola lo spacchettamento e la sonda.
    A = [1 2 3; 4 5 6; 7 8 9];
    B = [9 8 7; 6 5 4; 3 2 1];
    C = [1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16];
    D = eye(4);
    u = [reshape(A*B, [], 1); reshape(C*D, [], 1)];
    ref = ref_model(u, p);

    qProbe = 2^(-p.probe.fracLength);
    R.expected.matA  = ref.matA;
    R.expected.matB  = ref.matB;
    R.expected.probe = probeExpected(ref.matA, p);

    R.errA = max(abs(R.matA(:)  - R.expected.matA(:)));
    R.errB = max(abs(R.matB(:)  - R.expected.matB(:)));
    R.errP = max(abs(R.probe(:) - R.expected.probe(:)));

    fprintf('\nrun_system_sim: %.1f s di wall clock\n', R.wallClock);
    fprintf('  matA : errore max = %g\n', R.errA);
    fprintf('  matB : errore max = %g\n', R.errB);
    fprintf('  sonda: errore max = %g   (LSB del formato = %g)\n', R.errP, qProbe);
end


% =====================================================================
function y = probeExpected(matA, p)
%PROBEEXPECTED  Riproduce l'aritmetica della sonda ESATTAMENTE come la fa il
%   modello, non come la farebbe la matematica reale.
%
%   Catena nel modello:
%     matA (sfix32_En16)
%       -> Data Type Conversion  fixdt(1,16,fl), RndMeth=Floor, Saturate
%       -> Gain K,               fixdt(1,16,fl), RndMeth=Floor, Saturate
%
%   Il punto che avevo sbagliato: **anche il COEFFICIENTE e' quantizzato**.
%   Con uscita a 16 bit, Simulink sceglie per il guadagno un fixdt a 16 bit a
%   massima precisione: per 3.7 servono 2 bit interi + segno, quindi En13, e
%   il valore effettivo e' round(3.7*2^13)/2^13 = 3.699951171875, non 3.7.
%   Usare 3.7 esatto produce un errore di 1 LSB su alcuni elementi e fa
%   sembrare sbagliato il modello quando invece e' sbagliato il riferimento.

    q  = 2^(-p.probe.fracLength);
    lo = -2^(p.probe.wordLength - 1 - p.probe.fracLength);
    hi =  2^(p.probe.wordLength - 1 - p.probe.fracLength) - q;

    % coefficiente quantizzato, regola "best precision" a wordLength bit
    kInt = max(1, ceil(log2(abs(p.probe.gain))));       % bit interi (senza segno)
    kFl  = p.probe.wordLength - 1 - kInt;
    K    = round(p.probe.gain * 2^kFl) / 2^kFl;

    a = min(max(floor(matA / q) * q, lo), hi);          % DTC, Floor + Saturate
    y = min(max(floor(a * K / q) * q, lo), hi);         % Gain, Floor + Saturate
end


function ts = getLogged(out, name)
%GETLOGGED  Estrae una variabile To Workspace, dall'oggetto o dal base.
    avail = {};
    try, avail = out.who; catch, end
    if ~iscell(avail); avail = cellstr(avail); end

    if any(strcmp(avail, name))
        ts = out.(name);
        return
    end
    try
        ts = evalin('base', name);
    catch
        error('runSystemSim:noVar', ...
            ['Variabile ''%s'' non registrata dalla simulazione.\n' ...
             'Disponibili: %s'], name, strjoin(avail, ', '));
    end
end


function v = lastSample(ts, shp)
%LASTSAMPLE  Ultimo campione di una timeseries, rimodellato.
    assert(isa(ts,'timeseries'), 'runSystemSim:notTs', ...
        'Atteso timeseries, ricevuto %s', class(ts));
    assert(~isempty(ts.Data), 'runSystemSim:empty', ...
        'Nessun campione registrato: la PL non ha prodotto uscite.');
    d = ts.Data;
    if ndims(d) == 3
        v = reshape(d(:,:,end), shp);
    else
        v = reshape(d(end,:), shp);
    end
    v = double(v);
end
