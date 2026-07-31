function export_r2023b(modelDir)
%EXPORT_R2023B  Riporta tutti i modelli di Prova_2 in formato compatibile R2023b.
%
%   Regola di progetto R1 (docs/04_CONVENZIONI.md): i .slx versionati devono
%   sempre essere apribili con MATLAB R2023b, perche' il repo e' condiviso e
%   l'aggiornamento di formato di un .slx e' irreversibile.
%
%   Uso:
%       export_r2023b()             % opera su <questo_file>/../models
%       export_r2023b(cartella)     % opera sulla cartella indicata
%
%   Comportamento: esporta IN PLACE. Se un modello non e' esportabile a R2023b
%   lo script si ferma con errore e lo dice. Non salta mai in silenzio: un
%   export fallito che passa inosservato e' esattamente il guasto che questa
%   regola esiste per prevenire.

    TARGET = 'R2023B';

    if nargin < 1 || isempty(modelDir)
        modelDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'models');
    end
    assert(isfolder(modelDir), 'export_r2023b:noDir', ...
        'Cartella modelli inesistente: %s', modelDir);

    % I modelli referenziati vanno risolti, altrimenti esportando il top
    % Simulink avvisa "Unable to find model '...' referenced by ..." e si
    % esporta un modello con riferimenti non risolti.
    addpath(modelDir);

    files = dir(fullfile(modelDir, '*.slx'));
    if isempty(files)
        fprintf('Nessun .slx in %s — niente da fare.\n', modelDir);
        return
    end

    fprintf('Export a %s di %d modelli in %s\n', TARGET, numel(files), modelDir);

    failures = {};
    for k = 1:numel(files)
        src  = fullfile(files(k).folder, files(k).name);
        [~, name] = fileparts(files(k).name);
        tmp  = [tempname '.slx'];

        % I *_ref.slx sono copie congelate dei modelli originali di Prova_1,
        % gia' salvate con R2023b. Riesportarle le riscriverebbe passando da
        % una release piu' recente, alterandone il contenuto senza motivo:
        % sono riferimenti, non artefatti di lavoro.
        if endsWith(name, '_ref')
            fprintf('  SKIP  %s  (riferimento congelato R2023b)\n', files(k).name);
            continue
        end

        try
            % exportToVersion non scrive sul file sorgente: si passa da un
            % temporaneo e si sostituisce solo a export riuscito, cosi' un
            % fallimento non lascia il modello in uno stato intermedio.
            load_system(src);
            Simulink.exportToVersion(name, tmp, TARGET);
            close_system(name, 0);

            copyfile(tmp, src, 'f');
            delete(tmp);

            % SI VERIFICA IL FILE, NON IL COMANDO. Che exportToVersion e
            % copyfile non abbiano sollevato errori non dimostra che sul disco
            % ci sia un modello R2023b: lo dimostra rileggerlo.
            % Il 30/07/2026 i modelli committati erano R2026a mentre questo
            % script stampava "tutti compatibili": l'export era stato scartato
            % a valle da un `git checkout` e nulla se n'era accorto.
            got = Simulink.MDLInfo(src).ReleaseName;
            if ~strcmpi(got, TARGET)
                error('export_r2023b:notWritten', ...
                    'dopo l''export il file e'' ancora %s, non %s', got, TARGET);
            end
            fprintf('  OK    %-24s -> %s\n', files(k).name, got);

        catch err
            if bdIsLoaded(name); close_system(name, 0); end
            if isfile(tmp); delete(tmp); end
            failures{end+1} = sprintf('%s : %s', files(k).name, err.message); %#ok<AGROW>
            fprintf('  FAIL  %s\n', files(k).name);
        end
    end

    if ~isempty(failures)
        error('export_r2023b:failed', ...
            ['%d modelli NON esportabili a %s. Il commit non deve partire.\n' ...
             'Vanno risolti scegliendo costrutti disponibili in R2023b:\n  %s'], ...
            numel(failures), TARGET, strjoin(failures, '\n  '));
    end

    fprintf('Tutti i modelli sono compatibili %s.\n', TARGET);
end
