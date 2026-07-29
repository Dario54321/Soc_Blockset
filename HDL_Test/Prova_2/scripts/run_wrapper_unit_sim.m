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
    T = wrapper_sim_solve(f, x, p.compute.timeoutCycles, 1, 2*L + 60);
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
    T2 = wrapper_sim_solve(f, x, p.compute.timeoutCycles, [1, L+20], 3*L + 80);
    R.second = T2;
    assert(T2.donePulses == 2, ...
        ['B4: %d solve completati invece di 2. Se e'' 1, START non si ' ...
         'autoazzera (I2) oppure la FSM non torna a IDLE.'], T2.donePulses);
    assert(all(T2.allCycles == R.expectedCycles), ...
        'B4: cicli dei due solve = %s, attesi entrambi %d.', ...
        mat2str(T2.allCycles), R.expectedCycles);

    %% ---- I4: start_cmd tenuto alto non avvia due solve -------------------
    T3 = wrapper_sim_solve(f, x, p.compute.timeoutCycles, 1:10, 2*L + 60);
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

    T4 = wrapper_sim_solve(fMute, x, muteThr, 1, 4*muteThr + 40);
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
