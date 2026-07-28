function out = ref_model(u, p)
%REF_MODEL  Modello di riferimento in doppia precisione. E' il giudice.
%
%   out = REF_MODEL(u, p)  con u vettore di p.payload.nElem elementi.
%
%   Due regole che sembrano pedanti e non lo sono (soc-expert ch22):
%
%   1) E' scritto NELL'ORDINE DI OPERAZIONI DELL'HARDWARE - gli stessi loop,
%      lo stesso srotolamento column-major del Verilog generato. Un
%      riferimento scritto in stile matematico idiomatico (reshape) darebbe
%      una sequenza di arrotondamenti diversa, e il confronto con il modello
%      a precisione finita misurerebbe la differenza fra due algoritmi invece
%      dell'effetto della quantizzazione.
%
%   2) Non usa librerie di alto livello. Il reshape di MATLAB e' il
%      CROSS-CHECK esterno (vedi ref_model_selftest), non il giudice.
%
%   Uscita:
%     out.matA   3x3  double
%     out.matB   4x4  double
%     out.probe  3x3  double   matA * gain, elemento per elemento

    if nargin < 2 || isempty(p); p = soc_params(); end

    u = double(u(:));
    assert(numel(u) == p.payload.nElem, 'refModel:size', ...
        'Attesi %d elementi, ricevuti %d.', p.payload.nElem, numel(u));

    % --- matA: srotolamento column-major esplicito -------------------
    nR = p.matA.size(1); nC = p.matA.size(2); base = p.matA.idx(1);
    matA = zeros(nR, nC);
    for c = 1:nC
        for r = 1:nR
            matA(r,c) = u( base + (c-1)*nR + (r-1) );
        end
    end

    % --- matB: idem, con la propria base --------------------------------
    mR = p.matB.size(1); mC = p.matB.size(2); baseB = p.matB.idx(1);
    matB = zeros(mR, mC);
    for c = 1:mC
        for r = 1:mR
            matB(r,c) = u( baseB + (c-1)*mR + (r-1) );
        end
    end

    % --- sonda aritmetica: guadagno scalare, elemento per elemento -------
    probe = zeros(nR, nC);
    for c = 1:nC
        for r = 1:nR
            probe(r,c) = matA(r,c) * p.probe.gain;
        end
    end

    out.matA  = matA;
    out.matB  = matB;
    out.probe = probe;
end
