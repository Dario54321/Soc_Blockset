function S = latency_study(p, latencies, verbose)
%LATENCY_STUDY  Quanta latenza del blocco di calcolo sta dentro il budget.
%
%   S = LATENCY_STUDY()
%
%   Passo P10. Produce il numero da mettere in mano a chi possiede il blocco
%   di calcolo: "avete N cicli". Il numero dipende da tre cose, e questo
%   studio le separa:
%
%     budget totale  =  trasporto(stack PS)  +  overhead del wrapper
%                                            +  latenza del blocco
%
%   Il trasporto viene dal modello di costo in soc_params (costanti di
%   letteratura, da rimisurare al bring-up). L'overhead del wrapper viene
%   invece MISURATO qui, simulando il modello a latenze diverse: non e'
%   assunto costante, si verifica che lo sia.
%
%   Costa qualche minuto: costruisce e simula una variante del wrapper per
%   ogni latenza.

    if nargin < 1 || isempty(p);          p = soc_params(); end
    if nargin < 2 || isempty(latencies);  latencies = [1 2 5 20 100 500]; end
    if nargin < 3;                        verbose = true; end

    here = fileparts(mfilename('fullpath'));
    addpath(here);

    nx = p.mpc.nx;
    x  = (1:nx)';
    td = tempname; mkdir(td);
    cl = onCleanup(@() rmdir(td, 's'));

    S.latencies = latencies(:)';
    S.measured  = nan(size(S.latencies));

    if verbose
        fprintf('\n=== OVERHEAD DEL WRAPPER (misurato sul modello) ===\n');
        fprintf('%12s %12s %10s\n', 'latenza', 'CYCLES', 'overhead');
        fprintf('%s\n', repmat('-', 1, 36));
    end

    for k = 1:numel(S.latencies)
        L  = S.latencies(k);
        pk = p;
        pk.compute.latencyCycles = L;
        pk.compute.timeoutCycles = 10*L + 100;   % largo: non deve scattare

        % Nome distinto per ogni variante: modelli omonimi si ombreggiano a
        % vicenda e i risultati diventano quelli del modello sbagliato
        % (docs/11_NOTE_API §12).
        fk = fullfile(td, sprintf('soc_wrapper_L%d.slx', L));
        evalc('build_wrapper_fpga(pk, fk);');

        T = wrapper_sim_solve(fk, x, pk.compute.timeoutCycles, 1, 2*L + 80);
        assert(T.sawDone, 'latencyStudy:noDone', ...
            'Con latenza %d il solve non termina.', L);
        assert(~T.sawTimeout, 'latencyStudy:timeout', ...
            'Con latenza %d e soglia %d il watchdog e'' scattato.', L, pk.compute.timeoutCycles);

        S.measured(k) = T.cycles;
        if verbose
            fprintf('%12d %12d %10d\n', L, T.cycles, T.cycles - L);
        end
    end

    S.overhead = S.measured - S.latencies;

    % L'overhead DEVE essere costante: se dipendesse dalla latenza, il
    % contatore non sarebbe uno strumento di misura ma una funzione ignota.
    assert(all(S.overhead == S.overhead(1)), 'latencyStudy:overheadVaria', ...
        ['L''overhead del wrapper NON e'' costante: %s cicli sulle latenze %s.\n' ...
         'CYCLES non sarebbe interpretabile come "latenza del blocco + costante".'], ...
        mat2str(S.overhead), mat2str(S.latencies));
    S.overheadCycles = S.overhead(1);

    if verbose
        fprintf('\noverhead del wrapper = %d ciclo/i, costante su %d punti da %d a %d\n', ...
            S.overheadCycles, numel(S.latencies), min(S.latencies), max(S.latencies));
    end

    %% ---- quanto resta al blocco di calcolo, per ogni stack PS -----------
    B = p.budget.analysis;
    S.budget = struct('stack',{},'trasportoUs',{},'maxLatencyCycles',{},'maxLatencyUs',{});
    for k = 1:numel(B.rows)
        r = B.rows(k);
        maxL = r.computeCyclesMax - S.overheadCycles;
        S.budget(end+1) = struct( ...
            'stack',            r.stack, ...
            'trasportoUs',      r.transportSec*1e6, ...
            'maxLatencyCycles', maxL, ...
            'maxLatencyUs',     maxL / p.budget.clockMHz);
    end

    if verbose
        fprintf('\n=== QUANTI CICLI RESTANO AL BLOCCO DI CALCOLO ===\n');
        fprintf('budget %.0f us @ %d MHz = %d cicli | trasporto ''%s'' | overhead wrapper %d\n', ...
            p.budget.TsLoop*1e6, p.budget.clockMHz, p.budget.cyclesTotal, ...
            p.transport.kind, S.overheadCycles);
        fprintf('%-16s %12s %14s %12s\n', 'stack PS', 'trasp[us]', 'max lat[cy]', 'max lat[us]');
        fprintf('%s\n', repmat('-', 1, 58));
        for k = 1:numel(S.budget)
            b = S.budget(k);
            flag = '';
            if b.maxLatencyCycles <= 0; flag = '  <-- budget esaurito'; end
            fprintf('%-16s %12.2f %14d %12.1f%s\n', ...
                b.stack, b.trasportoUs, b.maxLatencyCycles, b.maxLatencyUs, flag);
        end
        fprintf(['\nIl numero da comunicare a chi possiede il blocco di calcolo e'' la\n' ...
                 'colonna "max lat[cy]" della riga corrispondente allo stack scelto.\n' ...
                 'ATTENZIONE: le costanti di trasporto sono ordini di grandezza da\n' ...
                 'letteratura, NON misure su questa board. Il numero definitivo arriva\n' ...
                 'dal bring-up (docs/05_PROCEDURA, P16).\n\n']);
    end
end
