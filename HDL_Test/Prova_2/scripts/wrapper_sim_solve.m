function T = wrapper_sim_solve(modelFile, x, timeoutThr, startCycles, nCycles)
%WRAPPER_SIM_SOLVE  Simula il wrapper e restituisce cosa e' successo.
%
%   T = WRAPPER_SIM_SOLVE(modelFile, x, timeoutThr, startCycles, nCycles)
%
%   modelFile   : percorso di un .slx prodotto da build_wrapper_fpga
%   x           : vettore di stato (nx elementi)
%   timeoutThr  : soglia del watchdog, in cicli
%   startCycles : indici di ciclo (1-based) in cui start_cmd e' alto
%   nCycles     : durata della simulazione, in cicli (il modello ha FixedStep = 1)
%
%   Restituisce: sawDone, sawTimeout, donePulses, allCycles, cycles, u, backToIdle.
%
%   Sta in un file suo perche' lo usano sia run_wrapper_unit_sim (verifica)
%   sia latency_study (misura): due copie andrebbero tenute allineate a mano,
%   ed e' esattamente cio' che la regola R2 vieta.
%
%   Note operative, con le trappole gia' pagate (docs/11_NOTE_API §12):
%     - lo stimolo si costruisce con createInputDataset, che genera il dataset
%       con i TIPI COMPILATI di ogni porta (virgola fissa inclusa);
%     - gli elementi di yout NON portano il nome del blocco Outport: si accede
%       per indice, che corrisponde al numero di porta;
%     - il nome del modello viene dal FILE: varianti con lo stesso nome si
%       ombreggiano a vicenda e i test passano per il motivo sbagliato.

    [~, m] = fileparts(modelFile);
    if bdIsLoaded(m); close_system(m, 0); end
    load_system(modelFile);
    cl = onCleanup(@() close_system(m, 0));

    t = (0:nCycles-1)';

    % Gli elementi restituiti da createInputDataset sono timeseries (non
    % oggetti con campo .Values): il tipo della porta sta in .Data.
    ds = createInputDataset(m);
    for k = 1:ds.numElements
        e     = ds{k};
        nm    = e.Name;
        proto = e.Data(1);
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

    % Accesso per INDICE = numero di porta impostato dal builder:
    % 1=done, 2=busy, 3=timeout_flag, 4=cycles, 5..=u0..u{nu-1}
    y = out.yout;
    assert(y.numElements >= 5, 'wrapperSim:ports', ...
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
