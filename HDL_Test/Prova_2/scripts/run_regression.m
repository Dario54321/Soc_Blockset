function ok = run_regression()
%RUN_REGRESSION  Un comando -> PASS/FAIL. Regola di progetto R4.
%
%   Gate coperti a questo stadio (blocco A/B della procedura):
%     T1  soc_params e' internamente coerente
%     T2  i controlli di soc_params RIFIUTANO una configurazione sbagliata
%         (un gate mai visto fallire non e' un gate)
%     T3  gen_vectors e' deterministico: due esecuzioni -> file identici
%     T4  il reference model coincide con il cross-check indipendente
%         (reshape di MATLAB) su tutta la suite
%     T5  la suite copre le tre famiglie e resta dentro il range dichiarato
%
%   I gate su modelli, HDL e hardware si aggiungono qui a mano a mano.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    results = {};

    fprintf('\n=========== REGRESSIONE Prova_2 ===========\n');

    % ---------------------------------------------------------------- T1
    results(end+1,:) = runTest('T1  soc_params coerente', @() check_params());

    % ---------------------------------------------------------------- T2
    results(end+1,:) = runTest('T2  i controlli rifiutano config errate', @() check_gates_reject());

    % ---------------------------------------------------------------- T3
    results(end+1,:) = runTest('T3  gen_vectors deterministico', @() check_determinism());

    % ---------------------------------------------------------------- T4
    results(end+1,:) = runTest('T4  reference == cross-check', @() check_reference());

    % ---------------------------------------------------------------- T5
    results(end+1,:) = runTest('T5  copertura e range della suite', @() check_suite());

    % ---------------------------------------------------------------- T6
    results(end+1,:) = runTest('T6  soc_fpga compila (rate, tipi, bus)', @() check_fpga_compiles());

    % ---------------------------------------------------------------- T7
    results(end+1,:) = runTest('T7  algoritmo di soc_fpga == reference', @() check_fpga_algorithm());

    % ---------------------------------------------------------------- T8
    results(end+1,:) = runTest('T8  soc_proc compila', @() check_proc_compiles());

    % ---------------------------------------------------------------- T9
    results(end+1,:) = runTest('T9  contratto ARM->FPGA: pack/unpack chiude', @() check_roundtrip());

    % --------------------------------------------------------------- T10
    results(end+1,:) = runTest('T10 soc_top: struttura a 3 modelli (G6)', @() check_top_structure());

    % --------------------------------------------------------------- T11
    % ~2 minuti: e' l'unico gate che simula davvero il sistema completo.
    results(end+1,:) = runTest('T11 catena end-to-end bit-esatta (G7)', @() check_end_to_end());

    % --------------------------------------------------------------- T12
    results(end+1,:) = runTest('T12 wrapper AXI4-Lite: invarianti (G9)', @() check_wrapper());

    % --------------------------------------------------------------- T13
    results(end+1,:) = runTest('T13 overhead del wrapper costante (P10)', @() check_overhead());

    % --------------------------------------------------------------- T14
    results(end+1,:) = runTest('T14 board plugin PYNQ-Z1 (G11)', @() check_board());

    % ------------------------------------------------------------ report
    fprintf('-------------------------------------------\n');
    pass = all([results{:,2}]);
    for k = 1:size(results,1)
        fprintf('  %-4s %s\n', tern(results{k,2},'PASS','FAIL'), results{k,1});
        if ~results{k,2} && ~isempty(results{k,3})
            fprintf('        %s\n', regexprep(results{k,3}, '\s+', ' '));
        end
    end
    fprintf('-------------------------------------------\n');
    fprintf('  ESITO: %s\n\n', tern(pass,'PASS','FAIL'));

    if nargout; ok = pass; end
    if ~pass; error('runRegression:failed', 'Regressione fallita.'); end
end


% =====================================================================
function row = runTest(nm, fcn)
    try
        fcn();
        row = {nm, true, ''};
    catch err
        row = {nm, false, err.message};
    end
end

function s = tern(c, a, b)
    if c; s = a; else; s = b; end
end


% =====================================================================
function check_params()
    p = soc_params();                    % gli assert stanno dentro
    assert(p.payload.nElem == numel([p.matA.idx p.matB.idx]), 'copertura indici');
    assert(p.stream.dataWidth == 32, 'stream non a 32 bit');
end


function check_gates_reject()
%CHECK_GATES_REJECT  Il gate deve fallire quando deve.
%   Si riproduce il difetto reale di Prova_1 - matB che legge U(1:16) invece
%   di U(10:25) - e si verifica che il controllo di partizione lo intercetti.

    p = soc_params();

    % (a) il bug matB: sovrapposizione con matA, 9 elementi scoperti
    bad = p; bad.matB.idx = 1:16;
    caught = false;
    try
        soc_params_probe(bad);
    catch err
        caught = strcmp(err.identifier, 'socParams:partition');
    end
    assert(caught, ...
        'Il controllo di partizione NON ha intercettato matB=U(1:16). Gate inefficace.');

    % (b) stream troppo largo (il vincolo C1)
    bad2 = p; bad2.stream.dataWidth = 64; bad2.payload.wordLength = 64;
    caught2 = false;
    try
        soc_params_probe(bad2);
    catch err
        caught2 = strcmp(err.identifier, 'socParams:streamTooWide');
    end
    assert(caught2, 'Il controllo sui 32 bit dello stream NON ha bloccato una config a 64 bit.');

    % (c) sonda fuori range
    bad3 = p; bad3.probe.fracLength = 14;    % range +/-2, guadagno*maxAbs = 3788
    caught3 = false;
    try
        soc_params_probe(bad3);
    catch err
        caught3 = strcmp(err.identifier, 'socParams:probeRange');
    end
    assert(caught3, 'Il controllo di range della sonda NON ha bloccato un formato insufficiente.');
end


function check_determinism()
    p  = soc_params();
    td = tempname; mkdir(td);
    f1 = fullfile(td, 'v1.mat');
    f2 = fullfile(td, 'v2.mat');

    evalc('gen_vectors(p, f1);');
    evalc('gen_vectors(p, f2);');

    V1 = load(f1); V2 = load(f2);
    assert(V1.count == V2.count, 'conteggio diverso fra due esecuzioni');
    for k = 1:V1.count
        assert(isequal(V1.u{k}, V2.u{k}), ...
            'vettore %d diverso fra due esecuzioni: generatore non deterministico', k);
    end
    rmdir(td, 's');
end


function check_reference()
%CHECK_REFERENCE  Il reference model, scritto nell'ordine dell'hardware,
%   deve coincidere con il cross-check indipendente (reshape di MATLAB).
%   Il cross-check si esegue UNA VOLTA per validare il giudice; poi il
%   giudice e' il reference, non la libreria.

    p = soc_params();
    rs = RandStream('twister','Seed', p.vectors.seed + 1);
    for k = 1:200
        u = (rand(rs, p.payload.nElem, 1)*2 - 1) * p.payload.maxAbs;
        r = ref_model(u, p);

        xA = reshape(u(p.matA.idx), p.matA.size);
        xB = reshape(u(p.matB.idx), p.matB.size);
        xP = xA * p.probe.gain;

        assert(isequal(r.matA, xA), 'matA diverge dal cross-check (iter %d)', k);
        assert(isequal(r.matB, xB), 'matB diverge dal cross-check (iter %d)', k);
        assert(isequal(r.probe, xP), 'probe diverge dal cross-check (iter %d)', k);
    end
end


function check_suite()
    p = soc_params();
    td = tempname; mkdir(td);
    f  = fullfile(td, 'v.mat');
    evalc('gen_vectors(p, f);');
    V = load(f);

    for fam = {'realistic','random','corner'}
        assert(any(strcmp(V.family, fam{1})), 'famiglia %s assente', fam{1});
    end

    q = 2^(-p.payload.fracLength);
    for k = 1:V.count
        u = V.u{k};
        assert(numel(u) == p.payload.nElem, 'vettore %d di lunghezza errata', k);
        assert(max(abs(u)) <= p.payload.maxAbs + eps(p.payload.maxAbs), ...
            'vettore %d (%s) fuori dal range dichiarato: max|u| = %g > %g', ...
            k, V.name{k}, max(abs(u)), p.payload.maxAbs);
        assert(max(abs(u/q - round(u/q))) < 1e-9, ...
            'vettore %d (%s) non rappresentabile esattamente in %s', ...
            k, V.name{k}, p.payload.dtStr);
    end
    rmdir(td, 's');
end


function check_fpga_compiles()
%CHECK_FPGA_COMPILES  Gate G4: il modello FPGA compila, a rate singolo, con
%   i tipi e le dimensioni dichiarati in soc_params. Verifica sull'artefatto
%   salvato, non su quello che il build script credeva di fare.

    p = soc_params();
    f = fpgaModelFile();
    assert(isfile(f), 'soc_fpga.slx assente: eseguire build_soc_fpga.');

    m = 'soc_fpga';
    if bdIsLoaded(m); close_system(m,0); end
    load_system(f);
    c = onCleanup(@() close_system(m,0));

    set_param(m, 'SimulationCommand', 'update');     % errore se non compila

    % Rate SINGOLO: e' il requisito dell'FPGA model per la generazione HDL.
    % Il valore non e' fissato (viene dal flusso dati, non dal clock della
    % PL: vedi build_soc_fpga), ma dev'essere uno solo su tutte le porte.
    rates = [];
    for b = {'tdata','tvalid','streamEnable','tready','matA_out','matB_out','probe_out'}
        ts = get_param([m '/' b{1}], 'CompiledSampleTime');
        if iscell(ts); ts = ts{1}; end
        rates(end+1) = ts(1); %#ok<AGROW>
    end
    assert(numel(unique(rates)) == 1, ...
        'FPGA model multi-rate: rate trovati %s. La generazione HDL richiede rate singolo.', ...
        mat2str(unique(rates)));

    % tdata porta il tipo "sul filo" (intero grezzo); la reinterpretazione a
    % sfix32_En16 avviene dentro, nel DTC_fromwire.
    expect = { 'tdata','Outport',p.stream.wireTypeReader,[1 p.payload.nElem]
               'streamEnable','Outport','boolean',[1 1]
               'tvalid','Outport','StreamM2SBusObj',[1 1]
               'tready','Inport','StreamS2MBusObj',[1 1]
               'matA_out','Inport','sfix32_En16',[2 p.matA.size]
               'matB_out','Inport','sfix32_En16',[2 p.matB.size]
               'probe_out','Inport',fixdtToCompiled(p.probe),[2 p.matA.size] };
    for k = 1:size(expect,1)
        h  = [m '/' expect{k,1}];
        pd = get_param(h,'CompiledPortDataTypes');
        dm = get_param(h,'CompiledPortDimensions');
        got = pd.(expect{k,2}); if iscell(got); got = got{1}; end
        assert(strcmp(got, expect{k,3}), '%s: tipo %s invece di %s', ...
            expect{k,1}, got, expect{k,3});
        assert(isequal(dm.(expect{k,2}), expect{k,4}), '%s: dims %s invece di %s', ...
            expect{k,1}, mat2str(dm.(expect{k,2})), mat2str(expect{k,4}));
    end
end


function check_fpga_algorithm()
%CHECK_FPGA_ALGORITHM  Gate: il codice della MATLAB Function dentro il
%   modello produce gli stessi matA/matB del reference, su tutta la suite.
%
%   Confronta il MODELLO con il GIUDICE, non il build script con se stesso.
%   E' il gate che, se il codice generato perdesse l'offset degli indici
%   (il difetto di Prova_1), fallirebbe.

    p = soc_params();
    f = fpgaModelFile();
    assert(isfile(f), 'soc_fpga.slx assente: eseguire build_soc_fpga.');

    m = 'soc_fpga';
    if bdIsLoaded(m); close_system(m,0); end
    load_system(f);
    c1 = onCleanup(@() close_system(m,0));

    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[m '/unpack']);
    assert(~isempty(ch), 'MATLAB Function unpack non trovata nel modello.');

    % Il codice del modello viene estratto e reso eseguibile come funzione
    % MATLAB: si valuta quello che c'e' DENTRO il modello, non una copia.
    td = tempname; mkdir(td);
    c2 = onCleanup(@() rmdir(td,'s'));
    fid = fopen(fullfile(td,'unpack_from_model.m'),'w');
    fwrite(fid, regexprep(ch.Script, '^function\s+\[([^\]]*)\]\s*=\s*unpack\(', ...
                          'function [$1] = unpack_from_model('), 'char');
    fclose(fid);
    addpath(td); c3 = onCleanup(@() rmpath(td));

    V = loadSuite(p);
    for k = 1:V.count
        u = V.u{k};
        [mA, mB, ~] = unpack_from_model(u, true, true);
        r = V.expected{k};
        assert(isequal(mA, r.matA), ...
            'matA del modello diverge dal reference sul vettore %d (%s)', k, V.name{k});
        assert(isequal(mB, r.matB), ...
            'matB del modello diverge dal reference sul vettore %d (%s)', k, V.name{k});
    end
end


function check_proc_compiles()
%CHECK_PROC_COMPILES  Gate G5: il processor model compila con la sua
%   configurazione (board reale, ARM Cortex-A, Fixed-step).

    p = soc_params();
    f = procModelFile();
    assert(isfile(f), 'soc_proc.slx assente: eseguire build_soc_proc.');

    m = 'soc_proc';
    if bdIsLoaded(m); close_system(m,0); end
    load_system(f);
    c = onCleanup(@() close_system(m,0));

    set_param(m, 'SimulationCommand', 'update');

    chk2('HardwareBoard',    get_param(m,'HardwareBoard'), p.env.simBoard);
    chk2('ProdHWDeviceType', get_param(m,'ProdHWDeviceType'), ...
         'ARM Compatible->ARM Cortex-A (32-bit)');

    % Il payload che esce dal DTC deve essere il formato dichiarato.
    pd = get_param([m '/Writer/DTC_payload'],'CompiledPortDataTypes');
    got = pd.Outport; if iscell(got); got = got{1}; end
    want = sprintf('sfix%d_En%d', p.payload.wordLength, p.payload.fracLength);
    assert(strcmp(got, want), 'payload compilato %s invece di %s', got, want);
end


function check_roundtrip()
%CHECK_ROUNDTRIP  IL gate del contratto software/hardware.
%
%   Prende il codice di packing che sta DENTRO soc_proc, lo esegue, e passa
%   il risultato al reference model (che implementa l'unpack come il modello
%   FPGA). Se pack e unpack non sono operazioni inverse, qui salta fuori.
%
%   E' il controllo che in Prova_1 non esisteva, e infatti il disallineamento
%   di matB e' arrivato fino alla sintesi.

    p = soc_params();
    f = procModelFile();
    assert(isfile(f), 'soc_proc.slx assente: eseguire build_soc_proc.');

    m = 'soc_proc';
    if bdIsLoaded(m); close_system(m,0); end
    load_system(f);
    c1 = onCleanup(@() close_system(m,0));

    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[m '/Writer/compute_payload']);
    assert(~isempty(ch), 'MATLAB Function compute_payload non trovata.');

    td = tempname; mkdir(td);
    c2 = onCleanup(@() rmdir(td,'s'));
    fid = fopen(fullfile(td,'payload_from_model.m'),'w');
    fwrite(fid, regexprep(ch.Script, '^function\s+u\s*=\s*compute_payload\(', ...
                          'function u = payload_from_model('), 'char');
    fclose(fid);
    addpath(td); c3 = onCleanup(@() rmpath(td));

    u = payload_from_model();

    % 1) forma e formato
    assert(numel(u) == p.payload.nElem, ...
        'payload di %d elementi invece di %d', numel(u), p.payload.nElem);
    assert(max(abs(u)) <= p.payload.maxAbs, ...
        'payload fuori dal range dichiarato: max|u| = %g > %g', max(abs(u)), p.payload.maxAbs);
    q = 2^(-p.payload.fracLength);
    assert(max(abs(u/q - round(u/q))) < 1e-9, ...
        'payload non rappresentabile esattamente in %s', p.payload.dtStr);

    % 2) pack e unpack sono inversi: il reference deve ritrovare le matrici
    A = [1 2 3; 4 5 6; 7 8 9];
    B = [9 8 7; 6 5 4; 3 2 1];
    C = [1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16];
    D = eye(4);
    r = ref_model(u, p);
    assert(isequal(r.matA, A*B), ...
        'unpack(pack(A*B)) ~= A*B: pack e unpack non sono inversi');
    assert(isequal(r.matB, C*D), ...
        'unpack(pack(C*D)) ~= C*D: pack e unpack non sono inversi');
end


function check_top_structure()
%CHECK_TOP_STRUCTURE  Gate G6 — quello che bloccava il progetto.
%
%   Verifica la condizione che SoC Builder pretende e la cui assenza produce
%   "FPGA or processor model not detected": il top model referenzia soc_fpga
%   e soc_proc tramite Model block, con solver Variable-step e feature set
%   SoC Blockset. E che l'insieme COMPILI.

    p = soc_params();
    here = fileparts(mfilename('fullpath'));
    modelDir = fullfile(fileparts(here), 'models');
    f = fullfile(modelDir, 'soc_top.slx');
    assert(isfile(f), 'soc_top.slx assente: eseguire build_soc_top.');
    addpath(modelDir);

    m = 'soc_top';
    if bdIsLoaded(m); close_system(m,0); end
    load_system(f);
    c = onCleanup(@() close_system(m,0));

    chk2('SolverType', get_param(m,'SolverType'), 'Variable-step');
    chk2('FeatureSet', get_param(m,'HardwareBoardFeatureSet'), 'SoCBlockset');
    chk2('HardwareBoard', get_param(m,'HardwareBoard'), p.env.simBoard);

    refs  = find_system(m,'LookUnderMasks','all','BlockType','ModelReference');
    names = cellfun(@(b) erase(get_param(b,'ModelNameDialog'),'.slx'), refs, 'UniformOutput', false);
    assert(any(strcmp(names,'soc_fpga')), 'soc_fpga non referenziato. Trovati: %s', strjoin(names,', '));
    assert(any(strcmp(names,'soc_proc')), 'soc_proc non referenziato. Trovati: %s', strjoin(names,', '));

    % Il Task Manager deve esserci e pilotare il processor model.
    tm = find_system(m,'LookUnderMasks','all','RegExp','on','Name','Task Manager');
    assert(~isempty(tm), 'Task Manager assente nel top model.');

    % Compilazione dell'insieme: e' qui che si scoprono i disallineamenti
    % di tipo e dimensione fra i tre modelli.
    set_param(m, 'SimulationCommand', 'update');
end


function check_end_to_end()
%CHECK_END_TO_END  Gate G7 — il risultato principale del test.
%
%   Simula il sistema completo e verifica che le matrici che escono dalla PL
%   coincidano BIT PER BIT con il reference model. Copre in un colpo solo:
%   calcolo lato ARM, impacchettamento, reinterpretazione Stored Integer,
%   trasporto sul canale AXI4-Stream, handshake, spacchettamento lato PL e
%   aritmetica in virgola fissa della sonda.
%
%   Costa ~2 minuti di wall clock: e' il prezzo dell'unico gate che esercita
%   davvero il canale.

    R = run_system_sim();
    assert(R.errA == 0, 'matA dalla PL differisce dal reference (errore max %g)', R.errA);
    assert(R.errB == 0, 'matB dalla PL differisce dal reference (errore max %g)', R.errB);
    assert(R.errP == 0, 'sonda dalla PL differisce dal reference (errore max %g)', R.errP);
end


function check_wrapper()
%CHECK_WRAPPER  Gate G9 — il wrapper AXI4-Lite (Test 2).
%
%   Copre i criteri B1-B4 e gli invarianti I2-I7 di docs/21_SPEC_WRAPPER.md:
%   il modello compila (niente anello algebrico, tipi giusti), un solve
%   nominale produce il dato atteso, CYCLES e' esatto, due solve consecutivi
%   funzionano entrambi, e con il blocco muto scatta il watchdog.
%
%   Quest'ultimo e' l'unico gate che protegge dallo stallo dell'ARM, ed e'
%   provato facendo tacere il blocco di proposito.

    here = fileparts(mfilename('fullpath'));
    f = fullfile(fileparts(here), 'models', 'soc_wrapper_fpga.slx');
    assert(isfile(f), 'soc_wrapper_fpga.slx assente: eseguire build_wrapper_fpga.');
    run_wrapper_unit_sim();     % contiene le proprie assert, parlanti
end


% =====================================================================
function check_board()
%CHECK_BOARD  Gate G11 — il plugin board PYNQ-Z1 (docs\23_BOARD_PYNQZ1).
%
%   Il livello 2 (confronto dei pin con i board file Vivado) gira solo dove
%   i board file esistono. Se mancano, check_board_plugin lo scrive su
%   stderr e il gate resta verde sul solo livello 1: e' una verifica
%   ridotta, non un successo pieno, e deve VEDERSI.

    R = check_board_plugin();
    if ~R.level2
        fprintf(2, ['  [T14] ATTENZIONE: verificata solo la registrazione. ' ...
                    'I pin NON sono stati confrontati (board file assenti).\n']);
    end
end


% =====================================================================
function check_overhead()
%CHECK_OVERHEAD  L'overhead del wrapper e' ancora 1 ciclo (docs\22_STUDIO_LATENZA).
%
%   Tutto il budget in 22_STUDIO_LATENZA poggia su "latenza del blocco =
%   CYCLES - 1". Se una modifica alla FSM aggiunge uno stadio, il numero
%   comunicato all'altro ingegnere diventa sbagliato senza che nulla protesti.
%
%   Due punti bastano a distinguere una costante da una funzione della
%   latenza; latency_study ne usa sei e ha il proprio assert sulla costanza.

    S = latency_study([], [3 40], false);
    assert(S.overheadCycles == 1, 'checkOverhead:cambiato', ...
        ['L''overhead del wrapper e'' %d cicli, non 1.\n' ...
         'docs\\22_STUDIO_LATENZA e il numero dato all''altro ingegnere ' ...
         'vanno rifatti.'], S.overheadCycles);
end


% =====================================================================
function chk2(what, got, want)
    assert(strcmp(got, want), '%s: atteso ''%s'', trovato ''%s''.', what, want, got);
end

function f = procModelFile()
    here = fileparts(mfilename('fullpath'));
    f = fullfile(fileparts(here), 'models', 'soc_proc.slx');
end

% =====================================================================
function f = fpgaModelFile()
    here = fileparts(mfilename('fullpath'));
    f = fullfile(fileparts(here), 'models', 'soc_fpga.slx');
end

function V = loadSuite(p)
    here = fileparts(mfilename('fullpath'));
    f = fullfile(fileparts(here), 'test', p.vectors.file);
    if ~isfile(f); evalc('gen_vectors(p);'); end
    V = load(f);
end

function s = fixdtToCompiled(fmt)
    s = sprintf('sfix%d_En%d', fmt.wordLength, fmt.fracLength);
end


% =====================================================================
function soc_params_probe(p)
%SOC_PARAMS_PROBE  Esegue i controlli di coerenza su una struct gia'
%   costruita, riusando l'unica implementazione che sta in soc_params (R2).
    soc_params(p);
end
