function R = run_wrapper_unit_sim(p, verbose)
%RUN_WRAPPER_UNIT_SIM  Verifica il wrapper simulando il MODELLO, ciclo per ciclo.
%
%   R = RUN_WRAPPER_UNIT_SIM()
%
%   Copre i criteri B1-B5 e gli invarianti I2-I7 di docs/21_SPEC_WRAPPER.md.
%
%   --- Perche' si simula il modello e non il codice estratto -------------
%   Una versione precedente estraeva le due MATLAB Function dal modello e le
%   faceva girare in un anello MATLAB. Non funziona per le misure di TEMPO:
%   Simulink separa la fase "uscite" dalla fase "aggiornamento di stato",
%   mentre una funzione MATLAB fa entrambe in una chiamata atomica. In un
%   anello a due blocchi l'emulazione introduce percio' un ciclo in piu',
%   ovunque si metta la chiamata, e non e' aggirabile riordinando.
%   Risultato: l'emulazione misurava 502 cicli dove il modello ne fa 501.
%
%   Adattare l'atteso a 502 avrebbe reso verde la suite nascondendo il
%   problema, e avrebbe fatto passare indisturbata una mutazione che sfasa il
%   contatore di uno. Si simula quindi il modello: si verifica l'artefatto,
%   non una sua emulazione.
%
%   Lo stimolo si costruisce con createInputDataset, che genera il dataset
%   gia' con i TIPI CORRETTI di ogni porta (virgola fissa inclusa):
%   https://www.mathworks.com/help/simulink/slref/createinputdataset.html

    if nargin < 1 || isempty(p); p = soc_params(); end
    if nargin < 2; verbose = false; end

    here     = fileparts(mfilename('fullpath'));
    modelDir = fullfile(fileparts(here), 'models');
    f = fullfile(modelDir, 'soc_wrapper_fpga.slx');
    assert(isfile(f), 'wrapperUnit:noModel', ...
        'models/soc_wrapper_fpga.slx assente: eseguire build_wrapper_fpga.');
    addpath(modelDir);

    nx = p.mpc.nx;  nu = p.mpc.nu;
    x  = (1:nx)';                       % stimolo deterministico
    L  = p.compute.latencyCycles;

    % Latenza attesa: L+1. Il segnaposto e' nondirect feedthrough, quindi
    % done_o esce dallo STATO: arriva un ciclo dopo che il contatore ha
    % raggiunto LATENCY. E' il registro che in hardware c'e' comunque
    % sull'uscita done di un IP (docs/21_SPEC_WRAPPER §5, criterio B2).
    R.expectedCycles = L + 1;

    %% ---- B1/B2/I3/I5: un solve nominale --------------------------------
    T = simSolve(f, x, p.compute.timeoutCycles, [1], 2*L + 60);
    R.nominal = T;

    assert(T.sawDone, 'B1: il solve non e'' mai terminato (nessun done).');
    assert(isequal(double(T.u(:)), double(x(1:nu))), ...
        'B1: u = %s invece di %s.', mat2str(double(T.u(:)')), mat2str(double(x(1:nu)')));
    assert(T.cycles == R.expectedCycles, ...
        ['B2: CYCLES = %d invece di %d (latenza %d + 1 di registro). ' ...
         'Il contatore non e'' esatto, quindi non e'' uno strumento di misura.'], ...
        T.cycles, R.expectedCycles, L);
    assert(T.donePulses == 1, 'done alto per %d cicli invece di 1.', T.donePulses);
    assert(~T.sawTimeout, 'Timeout scattato su un solve valido.');

    %% ---- B4/I2: due solve consecutivi ----------------------------------
    % Secondo START molto dopo il primo done. Se START non si autoazzerasse,
    % il secondo solve non partirebbe: e' il guasto classico.
    T2 = simSolve(f, x, p.compute.timeoutCycles, [1, L+20], 3*L + 80);
    R.second = T2;
    assert(T2.donePulses == 2, ...
        ['B4: %d solve completati invece di 2. Se e'' 1, START non si ' ...
         'autoazzera (I2) oppure la FSM non torna a IDLE.'], T2.donePulses);
    assert(all(T2.allCycles == R.expectedCycles), ...
        'B4: cicli dei due solve = %s, attesi entrambi %d.', ...
        mat2str(T2.allCycles), R.expectedCycles);

    %% ---- I4: start_cmd tenuto alto non avvia due solve -------------------
    T3 = simSolve(f, x, p.compute.timeoutCycles, 1:10, 2*L + 60);
    R.holdStart = T3;
    assert(T3.donePulses == 1, ...
        ['I4: tenendo start_cmd alto per 10 cicli sono partiti %d solve. ' ...
         'Un solve alla volta.'], T3.donePulses);

    %% ---- B3/I6: blocco muto -> watchdog ---------------------------------
    % Il segnaposto viene reso muto costruendo una VARIANTE del modello con
    % latenza oltre la soglia. E' il gate provato in fallimento: l'unico che
    % protegge dallo stallo dell'ARM.
    muteThr = 40;
    pm = p;
    pm.compute.latencyCycles = muteThr * 10;      % non rispondera' mai in tempo
    pm.compute.timeoutCycles = muteThr;
    % NOME DIVERSO dal modello vero: con lo stesso nome Simulink caricherebbe
    % quello piu' in alto sul path e il gate passerebbe per il motivo
    % sbagliato ("... is shadowed by a file of the same name higher on the
    % MATLAB path"). Il builder deriva il nome del modello dal file.
    td = tempname; mkdir(td);
    cl = onCleanup(@() rmdir(td,'s'));
    fMute = fullfile(td, 'soc_wrapper_mute.slx');
    evalc('build_wrapper_fpga(pm, fMute);');

    T4 = simSolve(fMute, x, muteThr, [1], 4*muteThr + 40);
    R.mute = T4;
    assert(T4.sawTimeout, ...
        'B3: con blocco muto il watchdog NON e'' scattato. L''ARM resterebbe appeso.');
    assert(~T4.sawDone, 'B3: done alzato pur senza risposta dal blocco.');
    assert(T4.cycles == muteThr, ...
        'B3: CYCLES = %d invece della soglia %d.', T4.cycles, muteThr);
    assert(T4.backToIdle, 'I6: il wrapper non e'' tornato a IDLE dopo il timeout.');

    R.pass = true;
    if verbose
        fprintf('run_wrapper_unit_sim: tutto verde (misurato sul modello)\n');
        fprintf('  solve nominale : cycles=%d  u=%s\n', T.cycles, mat2str(double(T.u(:)')));
        fprintf('  due solve      : cycles=%s\n', mat2str(T2.allCycles));
        fprintf('  start a livello: %d solve (atteso 1)\n', T3.donePulses);
        fprintf('  watchdog       : scattato a %d cicli\n', T4.cycles);
    end
end


% =====================================================================
function T = simSolve(modelFile, x, timeoutThr, startCycles, nCycles)
%SIMSOLVE  Simula il modello e restituisce cosa e' successo.
%
%   startCycles : indici di ciclo (1-based) in cui start_cmd e' alto
%   nCycles     : durata della simulazione, in cicli (FixedStep = 1)

    [~, m] = fileparts(modelFile);
    if bdIsLoaded(m); close_system(m, 0); end
    load_system(modelFile);
    cl = onCleanup(@() close_system(m, 0));

    t = (0:nCycles-1)';

    % Dataset con i TIPI GIA' CORRETTI per ogni porta di root
    % Gli elementi restituiti da createInputDataset sono timeseries (non
    % oggetti con campo .Values): il tipo della porta sta in .Data.
    ds = createInputDataset(m);
    for k = 1:ds.numElements
        e     = ds{k};
        nm    = e.Name;
        proto = e.Data(1);                 % conserva il tipo della porta
        switch nm
            case 'start_cmd'
                v = false(nCycles,1);
                v(startCycles(startCycles <= nCycles)) = true;
            case 'timeout_thr'
                v = repmat(cast(timeoutThr,'like',proto), nCycles, 1);
            otherwise                       % x0..x{nx-1}
                i = sscanf(nm, 'x%d');
                v = repmat(cast(x(i+1),'like',proto), nCycles, 1);
        end
        ds{k} = timeseries(v, t, 'Name', nm);
    end

    in = Simulink.SimulationInput(m);
    in = in.setModelParameter('StopTime', num2str(nCycles-1));
    in = in.setModelParameter('SaveOutput','on','OutputSaveName','yout');
    in = in.setModelParameter('SaveFormat','Dataset');
    in = in.setExternalInput(ds);
    out = sim(in);

    % Gli elementi di yout NON portano il nome del blocco Outport: si accede
    % per INDICE, che corrisponde al numero di porta impostato dal builder
    % (1=done, 2=busy, 3=timeout_flag, 4=cycles, 5..=u0..u{nu-1}).
    y = out.yout;
    assert(y.numElements >= 5, ...
        'yout ha %d elementi, attesi almeno 5: l''ordine delle porte e'' cambiato?', ...
        y.numElements);
    g = @(k) squeeze(elemData(y{k}));

    done = logical(g(1));
    busy = logical(g(2));
    toF  = logical(g(3));
    cyc  = double(g(4));

    uAll = [];
    for k = 5:y.numElements
        uAll = [uAll, double(g(k))]; %#ok<AGROW>
    end

    T.sawDone    = any(done);
    T.sawTimeout = any(toF);
    T.donePulses = sum(done);
    T.allCycles  = cyc(done)';
    idx = find(done | toF, 1);
    if isempty(idx)
        T.cycles = NaN;  T.u = [];
    else
        T.cycles = cyc(idx);
        T.u      = uAll(idx, :)';
    end
    T.backToIdle = ~isempty(idx) && any(~busy(idx:end));
end


function d = elemData(e)
%ELEMDATA  I dati di un elemento di Dataset, sia esso timeseries o Signal.
    if isa(e, 'timeseries')
        d = e.Data;
    else
        d = e.Values.Data;
    end
end
