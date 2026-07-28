function V = gen_vectors(p, outFile)
%GEN_VECTORS  Genera la suite di vettori di test. Seed fisso, rigenerabile.
%
%   V = GEN_VECTORS()            usa soc_params() e salva in ../test/vectors.mat
%   V = GEN_VECTORS(p, outFile)  esplicito
%
%   Tre famiglie (soc-expert ch22): scenari realistici, campioni casuali
%   uniformi sul range dichiarato, corner case. Il volume conta meno della
%   copertura delle tre famiglie.
%
%   La suite e' un ARTEFATTO RIGENERABILE, non una cartella di dati opachi:
%   due esecuzioni devono produrre lo stesso file. Verificato da
%   run_regression.

    if nargin < 1 || isempty(p);       p = soc_params(); end
    if nargin < 2 || isempty(outFile)
        here    = fileparts(mfilename('fullpath'));
        outDir  = fullfile(fileparts(here), 'test');
        if ~isfolder(outDir); mkdir(outDir); end
        outFile = fullfile(outDir, p.vectors.file);
    end

    n = p.payload.nElem;
    M = p.payload.maxAbs;
    q = 2^(-p.payload.fracLength);          % LSB del formato del payload

    % Il generatore usa il proprio stream: non tocca lo stato globale del
    % chiamante e non dipende da esso.
    rs = RandStream('twister', 'Seed', p.vectors.seed);

    U = {};  fam = {};  name = {};

    % --- Famiglia 1: scenari realistici -------------------------------
    % Il caso storico del progetto: due prodotti matriciali impacchettati.
    A = [1 2 3; 4 5 6; 7 8 9];
    B = [9 8 7; 6 5 4; 3 2 1];
    C = [1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16];
    D = eye(4);
    U{end+1} = [reshape(A*B, [], 1); reshape(C*D, [], 1)];
    fam{end+1} = 'realistic'; name{end+1} = 'AB_CD_storico';

    U{end+1} = [reshape(A*A, [], 1); reshape(C*C/16, [], 1)];
    fam{end+1} = 'realistic'; name{end+1} = 'AA_CC';

    U{end+1} = [reshape(eye(3), [], 1); reshape(eye(4), [], 1)];
    fam{end+1} = 'realistic'; name{end+1} = 'identita';

    % --- Famiglia 2: casuali uniformi sul range dichiarato ------------
    for k = 1:p.vectors.nRandom
        U{end+1} = quantize_to_grid((rand(rs, n, 1)*2 - 1) * M, q); %#ok<AGROW>
        fam{end+1} = 'random'; name{end+1} = sprintf('rand_%04d', k); %#ok<AGROW>
    end

    % --- Famiglia 3: corner case --------------------------------------
    corners = { ...
        zeros(n,1),                          'zeri'; ...
        ones(n,1)*M,                         'max_positivo'; ...
        ones(n,1)*(-M),                      'max_negativo'; ...
        ones(n,1)*q,                         'un_LSB'; ...
        ones(n,1)*(-q),                      'meno_un_LSB'; ...
        repmat([M; -M], ceil(n/2), 1),       'alternato_estremi'; ...
        (1:n)',                              'rampa_indici'; ...
        };
    for k = 1:size(corners,1)
        v = corners{k,1};
        U{end+1} = quantize_to_grid(v(1:n), q);   %#ok<AGROW>
        fam{end+1} = 'corner'; name{end+1} = corners{k,2}; %#ok<AGROW>
    end

    % --- Attesi dal reference model ------------------------------------
    N = numel(U);
    expected = cell(N,1);
    for k = 1:N
        expected{k} = ref_model(U{k}, p);
    end

    V.params   = p;
    V.u        = U(:);
    V.family   = fam(:);
    V.name     = name(:);
    V.expected = expected;
    V.count    = N;

    save(outFile, '-struct', 'V');
    fprintf('gen_vectors: %d vettori (%d realistic, %d random, %d corner) -> %s\n', ...
        N, sum(strcmp(fam,'realistic')), sum(strcmp(fam,'random')), ...
        sum(strcmp(fam,'corner')), outFile);
end


% =====================================================================
function y = quantize_to_grid(x, q)
%QUANTIZE_TO_GRID  Porta x sulla griglia del formato del payload.
%   I vettori devono essere rappresentabili esattamente in sfix32_En16,
%   altrimenti il confronto bit-true misurerebbe l'errore del generatore
%   invece di quello del datapath.
y = round(x / q) * q;
end
