function T = budget_report(p)
%BUDGET_REPORT  Quanta latenza di calcolo sta dentro il budget d'anello.
%
%   T = BUDGET_REPORT()
%
%   Risponde alla domanda che serve per parlare con chi possiede il blocco
%   di calcolo: "quanti cicli avete a disposizione?".
%   La risposta dipende da DUE scelte che sono nostre — il trasporto e lo
%   stack software del PS — quindi il risultato e' una tabella, non un numero.
%
%   Le costanti di latenza vengono da letteratura (soc-expert ch06), NON da
%   misure sulla vostra board: servono a ordinare le alternative, non a
%   promettere prestazioni. Il numero vero arriva dal bring-up leggendo
%   CYCLES e cronometrando il round-trip lato software.

    if nargin < 1 || isempty(p)
        w = warning('off','socParams:assumptions');
        c = onCleanup(@() warning(w));
        p = soc_params();
    end

    fprintf('\n=== BUDGET D''ANELLO ===\n');
    fprintf('  target        : %.1f us  (%s)\n', p.budget.TsLoop*1e6, p.budget.source);
    fprintf('  clock PL      : %d MHz  -> %d cicli disponibili in totale\n', ...
        p.budget.clockMHz, p.budget.cyclesTotal);
    fprintf('  payload       : nx=%d nu=%d  ->  %d accessi a registro, %d byte\n', ...
        p.mpc.nx, p.mpc.nu, p.budget.analysis.nAccesses, p.budget.analysis.nBytes);
    fprintf('  ipotesi       : nx/nu confermati=%d, latenza calcolo nota=%d\n', ...
        p.mpc.confirmed, p.compute.latencyKnown);

    kinds = {'axi4lite','axi4stream'};
    rows  = {};
    for t = 1:numel(kinds)
        q = p; q.transport.kind = kinds{t};
        B = localBudget(q);
        for k = 1:numel(B.rows)
            r = B.rows(k);
            rows(end+1,:) = { kinds{t}, r.stack, r.transportSec*1e6, ...
                              r.transportCycles, r.computeCyclesMax, ...
                              r.computeCyclesMax/p.budget.clockMHz }; %#ok<AGROW>
        end
    end

    fprintf('\n%-12s %-16s %10s %10s %12s %10s\n', ...
        'trasporto','stack PS','trasp[us]','trasp[cy]','calcolo[cy]','calcolo[us]');
    fprintf('%s\n', repmat('-',1,76));
    for k = 1:size(rows,1)
        maxCy = rows{k,5};
        if maxCy <= 0
            verdict = '  <-- budget esaurito dal solo trasporto';
        else
            verdict = '';
        end
        fprintf('%-12s %-16s %10.2f %10d %12d %10.1f%s\n', ...
            rows{k,1}, rows{k,2}, rows{k,3}, rows{k,4}, maxCy, rows{k,6}, verdict);
    end

    fprintf('\nLettura: la colonna "calcolo[cy]" e'' il numero da comunicare a chi\n');
    fprintf('possiede il blocco di calcolo. Se la loro latenza sta sotto, il target\n');
    fprintf('e'' raggiungibile con quella combinazione; altrimenti no, e nessuna\n');
    fprintf('scelta di trasporto lo salva.\n\n');

    if nargout
        T = cell2table(rows, 'VariableNames', ...
            {'trasporto','stackPS','trasporto_us','trasporto_cy','calcolo_max_cy','calcolo_max_us'});
    end
end


% =====================================================================
function B = localBudget(p)
%LOCALBUDGET  Ricalcola l'analisi per una variante di p.
%   Passa da soc_params in modalita' validazione? No: soc_params(p) esegue
%   solo i CONTROLLI, e uno di essi fallirebbe proprio sulle combinazioni
%   che qui vogliamo mostrare (quelle fuori budget). Si ricalcola quindi il
%   solo modello, senza i gate.
    nAcc = p.mpc.nx + 1 + p.psStack.nPollAvg + p.mpc.nu;
    cat  = p.psStack.catalog;
    B.rows = struct('stack',{},'transportSec',{},'transportCycles',{}, ...
                    'computeCyclesMax',{});
    for k = 1:numel(cat)
        if strcmp(p.transport.kind,'axi4lite')
            tT = nAcc * cat(k).tAccessLite;
        else
            tT = cat(k).tFixedDMA;
        end
        cT = ceil(tT * p.budget.clockMHz * 1e6);
        B.rows(end+1) = struct('stack', cat(k).name, 'transportSec', tT, ...
            'transportCycles', cT, ...
            'computeCyclesMax', p.budget.cyclesTotal - cT); %#ok<AGROW>
    end
end
