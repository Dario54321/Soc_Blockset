function p = soc_params(pToValidate)
%SOC_PARAMS  Fonte unica di verita' del test di interfacciamento ARM<->FPGA.
%
%   Regola di progetto R2 (docs/04_CONVENZIONI.md): dimensioni, formati
%   numerici, sample time e offset dei registri sono definiti SOLO qui.
%   Modelli e script leggono da questa funzione; nessuno ridefinisce nulla.
%
%   Due modi d'uso, una sola implementazione dei controlli:
%     p = soc_params()          costruisce la configurazione e la valida
%     soc_params(pIn)           valida SOLO la struct passata
%
%   Il secondo modo serve alla regressione per verificare che i controlli
%   rifiutino davvero una configurazione sbagliata: un gate mai visto
%   fallire non e' un gate. Uno di essi e' esattamente il controllo che
%   avrebbe intercettato in simulazione il disallineamento di matB trovato
%   nel Verilog di Prova_1 (offset +9 mancante).

if nargin == 1
    soc_params_check(pToValidate);
    if nargout; p = pToValidate; end
    return
end

%% ------------------------------------------------------------------
%  Ambiente dichiarato
%  ------------------------------------------------------------------
p.env.matlabRelease        = 'R2026a';
p.env.modelCompatRelease   = 'R2023B';   % regola R1: export prima di ogni commit
p.env.vivadoForWorkflows   = '2022.1';   % supportata dai workflow integrati R2026a
p.env.vivadoInstalledLocal = '2026.1';   % presente su questa macchina, NON supportata
p.env.targetBoard          = 'PYNQ-Z1';   % bersaglio reale del deploy (via HDL Coder)
p.env.fpgaDevice           = 'xc7z020';
p.env.fpgaPackage          = 'clg400';
p.env.fpgaSpeed            = '-1';

% Board usata SOLO per la simulazione SoC Blockset.
% La PYNQ-Z1 non e' fra le board registrate in SoC Blockset; la ZedBoard e'
% registrata e monta lo STESSO die (xc7z020), quindi e' il sostituto piu'
% fedele per il modello di sistema. Il deploy resta sulla PYNQ-Z1 via HDL
% Coder (decisione A3): la board di simulazione e quella di deploy sono due
% cose distinte e vanno tenute distinte.
% Alternativa scartata: 'Custom Hardware Board' - non espone tutte le
% feature SoC Blockset e allontana la simulazione dal bersaglio reale.
p.env.simBoard             = 'ZedBoard';

%% ==================================================================
%  PROBLEMA DI CONTROLLO — ipotesi dichiarate, non confermate
%  ==================================================================
%  Il file dell'MPC non e' ancora disponibile. Questi valori sono IPOTESI
%  e il progetto e' parametrico su di essi proprio per questo.
%  Quando l'MPC arriva, si cambiano qui e basta (regola R2).
%  Osservato: attraversano il confine ARM->PL DUE vettori 3x1. Cosa siano
%  non e' ancora noto (domanda 5 del contratto, docs/20_CONTRATTO_INTERFACCIA
%  §8). Si modella come nVec vettori di vecLen elementi, cosi' "3 o 6?" non
%  puo' piu' essere ambiguo: nx e' il TOTALE che attraversa.
p.mpc.nVec     = 2;        % quanti vettori attraversano il confine
p.mpc.vecLen   = 3;        % lunghezza di ciascun vettore
p.mpc.nx       = p.mpc.nVec * p.mpc.vecLen;   % = 6 elementi totali ARM -> PL
p.mpc.nu       = 1;        % dimensione del risultato PL -> ARM
p.mpc.confirmed = false;   % <- diventa true quando l'MPC e' stato letto

%% ==================================================================
%  BUDGET D'ANELLO
%  ==================================================================
%  33 us viene da un paper, NON e' stato misurato da noi. Target di
%  riferimento dichiarato, da sostituire con il numero vero al bring-up.
p.budget.TsLoop   = 33e-6;      % [s]
p.budget.source   = 'paper, non misurato';
p.budget.clockMHz = 100;        % clock della PL
p.budget.cyclesTotal = round(p.budget.TsLoop * p.budget.clockMHz * 1e6);

%% ==================================================================
%  STACK SOFTWARE DEL PS
%  ==================================================================
%  Le costanti sono ORDINI DI GRANDEZZA da letteratura (soc-expert ch06),
%  NON misure sulla nostra board. Vanno rimisurate al bring-up: e' la
%  prima cosa che il driver deve produrre.
%    tAccessLite = costo di un accesso a registro a 32 bit
%    tFixedDMA   = costo fisso per trasferimento DMA (setup + notifica)
p.psStack.kind = 'baremetal_poll';
p.psStack.catalog = struct( ...
    'name',        {'baremetal_poll','baremetal_irq','linux_mmap','linux_driver'}, ...
    'tAccessLite', {         0.15e-6,        0.15e-6,       1e-6,        5e-6}, ...
    'tFixedDMA',   {            2e-6,           4e-6,      32e-6,       32e-6}, ...
    'note',        {'polling, nessun SO','interrupt','mmap user-space, polling','driver kernel + interrupt'});
p.psStack.nPollAvg = 2;   % letture di STATUS attese prima di vedere DONE

%% ==================================================================
%  BLOCCO DI CALCOLO DI TERZI — segnaposto a latenza configurabile
%  ==================================================================
%  Vedi docs/20_CONTRATTO_INTERFACCIA.md. Il blocco e' una scatola nera:
%  qui se ne modella solo la LATENZA, per rispondere alla domanda
%  "quanta ne possiamo tollerare restando nei 33 us?".
p.compute.latencyCycles = 500;    % IPOTESI: da sostituire con la lettura di CYCLES
p.compute.latencyKnown  = false;
p.compute.timeoutCycles = 3000;   % soglia del watchdog, programmabile a runtime

%% ==================================================================
%  TRASPORTO — sostituibile per costruzione
%  ==================================================================
%  'axi4lite'   : registri. Corretto per payload piccoli (< ~130 B).
%  'axi4stream' : DMA. Corretto oltre i ~4 kB. E' quello implementato dai
%                 modelli attuali, costruiti quando il payload ipotizzato
%                 era di 25 elementi.
%  La scelta e' una DECISIONE ARCHITETTURALE, motivata in
%  docs/01_PIANO.md e ricalcolata da transport_budget() qui sotto.
%  Dal 28/07/2026 e' 'axi4lite': il wrapper (models/soc_wrapper_fpga.slx)
%  esiste, compila ed e' verificato. I modelli del Test 1 (soc_fpga/proc/top)
%  restano come implementazione AXI4-Stream della stessa interfaccia, e
%  tornano in gioco se il payload superera' i ~10-12 elementi.
p.transport.kind = 'axi4lite';

%% ------------------------------------------------------------------
%  Payload dello stream
%  Vincolo C1: il reference design AXI4-Stream shipped e' a 32 bit.
%  ------------------------------------------------------------------
p.payload.nElem      = 25;
p.payload.wordLength = 32;
p.payload.fracLength = 16;              % sfix32_En16
p.payload.dtStr      = 'fixdt(1,32,16)';

% Range operativo DICHIARATO del payload (passo P1 della procedura).
% Non e' una stima: e' un impegno. Il caso di prova attuale (A*B con
% A=[1 2 3;4 5 6;7 8 9], B=[9 8 7;6 5 4;3 2 1]) arriva a 138; 1024 lascia
% margine e resta ampiamente dentro sfix32_En16 (+/-32768).
p.payload.maxAbs = 1024;

%% ------------------------------------------------------------------
%  Partizione del payload nelle due matrici
%  ------------------------------------------------------------------
p.matA.size = [3 3];
p.matA.idx  = 1:9;      % 1-based, MATLAB
p.matB.size = [4 4];
p.matB.idx  = 10:25;

% Ordine di srotolamento: column-major, come il reshape MATLAB e come il
% Verilog generato -> mat(r,c) = u( base + (c-1)*nRows + (r-1) )
p.layout = 'column-major';

%% ------------------------------------------------------------------
%  Sonda aritmetica
%  Esiste per un motivo solo: garantire che il flusso generi hardware vero
%  (DSP) e non solo cablaggio. Senza, un reshape sintetizza a zero risorse
%  e il gate sul timing non significa niente.
%  ------------------------------------------------------------------
p.probe.gain      = 3.7;
p.probe.appliesTo = 'matA';
p.probe.wordLength = 16;                 % riduzione di parola, voluta

% Fraction length DERIVATA dal range, non scelta a mano.
% Range di uscita = maxAbs * gain; servono ceil(log2(.)) bit interi + segno.
probeMax  = p.payload.maxAbs * p.probe.gain;
intBits   = ceil(log2(probeMax));
p.probe.fracLength = p.probe.wordLength - 1 - intBits;
p.probe.dtStr      = sprintf('fixdt(1,%d,%d)', p.probe.wordLength, p.probe.fracLength);
p.probe.rndMethod  = 'Floor';
p.probe.saturate   = true;               % NON wrap: l'overflow deve saturare, non avvolgere

%% ------------------------------------------------------------------
%  Canale AXI4-Stream (Software to AXI4-Stream, lato top model)
%  ------------------------------------------------------------------
p.stream.dataWidth    = 32;              % deve coincidere con payload.wordLength
p.stream.frameSize    = p.payload.nElem; % 25 campioni per frame
p.stream.burstLen     = p.payload.nElem;
p.stream.numBuffers   = 8;
p.stream.fifoDepth    = 8;
p.stream.fifoAFull    = 6;
p.stream.icClockMHz   = 100;   % clock dell'IP: parametro del MODELLO DI CANALE
                               % (tempi di burst), NON il passo del solutore

% Tempo di frame lato lettore (PL): e' questo a fissare il rate di
% simulazione del modello FPGA. Un frame per attivazione del task.
p.stream.frameSampleTime = 0.1;   % s  (== p.timing.taskPeriod, vedi check)

% Tipo "sul filo". Il canale AXI4-Stream trasporta bit grezzi: i blocchi
% Software to AXI4-Stream accettano solo tipi interi builtin, non fixdt
% (errore UdtEvalsToUnsupportedFixdtSignMode). L'interpretazione fixed-point
% sta agli ESTREMI, con conversioni in modalita' 'Stored Integer' che
% preservano il pattern di bit. E' anche la semantica hardware corretta, e
% rende superfluo il vecchio typecast a uint64.
% I due lati del canale hanno tipi diversi perche' il blocco lo impone:
% ChTypeWriterChIf accetta solo tipi UNSIGNED ('int32' -> "Invalid data type
% specification"), ChTypeReaderChIf accetta anche signed. Stessa asimmetria
% dell'esempio shipped (writer uint32, reader int32). La larghezza e' la
% stessa, quindi la reinterpretazione Stored Integer preserva i bit.
p.stream.wireTypeWriter = 'uint32';
p.stream.wireTypeReader = 'int32';

% Nome del device visto dal blocco Stream Write lato processore.
% SEGNAPOSTO: la forma reale e' '<nome_ip_core>:mm2s0' e si conosce solo dopo
% la generazione dell'IP core (P12). Va riallineato allora, non prima.
p.stream.writeDevice  = 'ip:mm2s';

%% ------------------------------------------------------------------
%  Task software
%  ------------------------------------------------------------------
p.task.name     = 'ComputeTask';
p.task.priority = 50;

%% ------------------------------------------------------------------
%  Tempi
%  ------------------------------------------------------------------
p.timing.TsFpga    = 1/(p.stream.icClockMHz*1e6);   % 10 ns @100 MHz
p.timing.taskPeriod = 0.1;                          % periodo del ComputeTask [s]
p.timing.meanTaskDuration = 1e-6;                   % durata simulata del task [s]
p.timing.maxLatency = 1.0;                          % budget di latenza end-to-end [s]

%% ------------------------------------------------------------------
%  Register map (piano di controllo, AXI4-Lite) - contratto unico
%  Il formato numerico di ogni campo sta nella stessa tabella del campo.
%  ------------------------------------------------------------------
p.regmap.baseAddress = '0x400D0000';     % come il reference design shipped
p.regmap.idVerMagic  = uint32(hex2dec('50325A31'));   % "P2Z1"

% --- mappa AXI4-Lite del wrapper: UNICA fonte degli offset --------------
% docs/20_CONTRATTO_INTERFACCIA.md §6. DERIVATA da nx/nu: nessun offset si
% trascrive a mano, ne' in HDL ne' in C.
%
% Qui esisteva anche una seconda tabella (p.regmap.reg) scritta a mano, con
% offset INCOMPATIBILI con questi (CYCLES a 0x44 invece che a 0x80). E'
% stata rimossa: due mappe per la stessa cosa violano la regola R2 ed erano
% gia' divergenti. Segnalata da un audit della documentazione.
p.regmap.wrapper = build_wrapper_regmap(p.mpc.nx, p.mpc.nu, p.payload.dtStr);

% --- registro del Register Channel di SoC Blockset ----------------------
% Cosa diversa dalla mappa qui sopra: questo e' il registro MODELLATO dal
% blocco Register Channel, usato in SIMULAZIONE per portare streamEnable dal
% processore alla PL nel Test 1. La mappa del wrapper e' invece quella che
% l'IP core esporra' davvero sull'AXI4-Lite.
%
% Il lato software NON collega un segnale grezzo al Register Channel: ci
% scrive attraverso un blocco prociolib/Register Write, che e' cio' che
% emette il messaggio atteso dal canale (docs/11_NOTE_API §3).
p.regchan.name       = 'streamEnable';
p.regchan.rw         = 'Write';
p.regchan.dataType   = 'boolean';
p.regchan.deviceName = '/dev/mwipcore';   % segnaposto: allineare all'IP core a P12
p.regchan.offset     = 'hex2dec(''0100'')';

%% ------------------------------------------------------------------
%  Vettori di test
%  ------------------------------------------------------------------
p.vectors.seed      = 20260728;          % seed FISSO: la suite e' rigenerabile
p.vectors.nRandom   = 500;
p.vectors.file      = 'vectors.mat';

%% ------------------------------------------------------------------
%  Analisi di budget: quanto resta al calcolo dopo il trasporto
%  ------------------------------------------------------------------
p.budget.analysis = transport_budget(p);

soc_params_check(p);
end


% =====================================================================
function B = transport_budget(p)
%TRANSPORT_BUDGET  Quanto costa il trasporto e quanto resta al calcolo.
%
%   E' l'equazione di progetto del sistema. Restituisce una riga per ogni
%   stack software del PS, cosi' la scelta si fa su una curva e non su
%   un'impressione.
%
%   Attenzione: le costanti di p.psStack.catalog sono ordini di grandezza
%   da letteratura, NON misure. Il numero definitivo arriva dal bring-up.

    nAcc = p.mpc.nx ...            % scritture dello stato
         + 1 ...                   % scrittura di CTRL (START)
         + p.psStack.nPollAvg ...  % letture di STATUS
         + p.mpc.nu;               % letture del risultato
    nBytes = (p.mpc.nx + p.mpc.nu) * p.payload.wordLength / 8;

    cat = p.psStack.catalog;
    B.rows = struct('stack',{},'transportSec',{},'transportCycles',{}, ...
                    'computeCyclesMax',{},'fits',{});
    for k = 1:numel(cat)
        switch p.transport.kind
            case 'axi4lite'
                tT = nAcc * cat(k).tAccessLite;
            case 'axi4stream'
                % costo fisso dominante a questa taglia: il termine per byte
                % e' trascurabile (nBytes molto sotto il break-even)
                tT = cat(k).tFixedDMA;
            otherwise
                error('socParams:transportKind', ...
                    'Trasporto sconosciuto: ''%s''', p.transport.kind);
        end
        cT   = ceil(tT * p.budget.clockMHz * 1e6);
        cMax = p.budget.cyclesTotal - cT;
        B.rows(end+1) = struct( ...
            'stack',            cat(k).name, ...
            'transportSec',     tT, ...
            'transportCycles',  cT, ...
            'computeCyclesMax', cMax, ...
            'fits',             cMax > 0); %#ok<AGROW>
    end

    B.nAccesses = nAcc;
    B.nBytes    = nBytes;

    % riga corrispondente allo stack attualmente scelto
    idx = find(strcmp({B.rows.stack}, p.psStack.kind), 1);
    assert(~isempty(idx), 'socParams:psStack', ...
        'Stack ''%s'' non presente nel catalogo.', p.psStack.kind);
    B.active = B.rows(idx);
end


% =====================================================================
function R = build_wrapper_regmap(nx, nu, dtStr)
%BUILD_WRAPPER_REGMAP  Mappa AXI4-Lite derivata da nx/nu.
%   Nessun offset scritto a mano: cambiando nx/nu la mappa segue, e con
%   essa l'header C e la decodifica HDL che si generano da qui.

    R = struct('name',{},'offset',{},'access',{},'type',{},'descr',{});
    add = @(n,o,a,t,d) struct('name',n,'offset',o,'access',a,'type',t,'descr',d);

    R(end+1) = add('CTRL',  '0x00','RW','uint32', ...
        'bit0 START(autoazzerante) bit1 SOFT_RESET bit2 IRQ_EN');
    R(end+1) = add('STATUS','0x04','R', 'uint32', ...
        'bit0 DONE bit1 BUSY bit2 ERROR bit3 TIMEOUT');

    for i = 0:nx-1
        R(end+1) = add(sprintf('X%d',i), sprintf('0x%02X', 8 + 4*i), ...
            'W', dtStr, sprintf('stato[%d]', i)); %#ok<AGROW>
    end
    for j = 0:nu-1
        R(end+1) = add(sprintf('U%d',j), sprintf('0x%02X', 64 + 4*j), ...
            'R', dtStr, sprintf('uscita[%d]', j)); %#ok<AGROW>
    end

    R(end+1) = add('CYCLES', '0x80','R', 'uint32','cicli dell''ultimo solve');
    R(end+1) = add('TIMEOUT','0x84','RW','uint32','soglia del watchdog, in cicli');
    R(end+1) = add('ID_VER', '0x8C','R', 'uint32','costante magica + versione');
end


% =====================================================================
function soc_params_check(p)
%SOC_PARAMS_CHECK  Coerenza interna. Fallisce rumorosamente, mai in silenzio.

% --- C1: lo stream e' a 32 bit ---
assert(p.stream.dataWidth == p.payload.wordLength, 'socParams:streamWidth', ...
    ['Larghezza stream (%d bit) diversa dal word length del payload (%d bit). ' ...
     'Il reference design AXI4-Stream shipped accetta al massimo 32 bit.'], ...
    p.stream.dataWidth, p.payload.wordLength);
assert(p.stream.dataWidth <= 32, 'socParams:streamTooWide', ...
    'Lo stream a %d bit supera il limite di 32 bit del reference design.', p.stream.dataWidth);

% --- Le due matrici hanno tanti elementi quanti indici ---
assert(numel(p.matA.idx) == prod(p.matA.size), 'socParams:matA', ...
    'matA: %d indici per %d elementi.', numel(p.matA.idx), prod(p.matA.size));
assert(numel(p.matB.idx) == prod(p.matB.size), 'socParams:matB', ...
    'matB: %d indici per %d elementi.', numel(p.matB.idx), prod(p.matB.size));

% --- IL controllo: gli indici partizionano ESATTAMENTE il payload ---
% Nessuna sovrapposizione, nessun buco. E' la condizione violata dal Verilog
% di Prova_1, dove matB leggeva U(1:16) invece di U(10:25): sovrapposizione
% con matA su 9 elementi e 9 ingressi del payload scollegati.
allIdx = sort([p.matA.idx(:); p.matB.idx(:)]');
assert(isequal(allIdx, 1:p.payload.nElem), 'socParams:partition', ...
    ['Gli indici di matA e matB non partizionano 1:%d.\n' ...
     '  attesi   : %s\n  ottenuti : %s\n' ...
     'Sovrapposizioni o buchi qui diventano ingressi scollegati in hardware.'], ...
    p.payload.nElem, mat2str(1:p.payload.nElem), mat2str(allIdx));

% --- Il formato del payload copre il range dichiarato ---
[loP, hiP] = fixdt_range(p.payload.wordLength, p.payload.fracLength);
assert(p.payload.maxAbs <= hiP && -p.payload.maxAbs >= loP, 'socParams:payloadRange', ...
    'Range dichiarato +/-%g fuori da %s ([%g, %g]).', ...
    p.payload.maxAbs, p.payload.dtStr, loP, hiP);

% --- Il formato della sonda copre la sua uscita ---
probeMax = p.payload.maxAbs * p.probe.gain;
[loQ, hiQ] = fixdt_range(p.probe.wordLength, p.probe.fracLength);
assert(probeMax <= hiQ && -probeMax >= loQ, 'socParams:probeRange', ...
    ['Uscita della sonda (+/-%g) fuori da %s ([%g, %g]).\n' ...
     'Ridurre il guadagno, allargare la parola, o abbassare maxAbs.'], ...
    probeMax, p.probe.dtStr, loQ, hiQ);
assert(p.probe.fracLength >= 0, 'socParams:probeFrac', ...
    'Fraction length della sonda negativa (%d): parola troppo stretta per il range.', ...
    p.probe.fracLength);

% --- Dimensionamento del canale (formule della doc SoC Blockset) ---
framePeriod = p.stream.frameSize * p.timing.TsFpga;
assert((p.stream.numBuffers + 1) * framePeriod <= p.timing.maxLatency, ...
    'socParams:latency', ...
    '(NumFrameBuffers+1)*FramePeriod = %g s supera MaxLatency = %g s.', ...
    (p.stream.numBuffers+1)*framePeriod, p.timing.maxLatency);
assert(p.timing.taskPeriod > p.timing.meanTaskDuration, 'socParams:throughput', ...
    'Periodo del task (%g s) non superiore alla durata media (%g s).', ...
    p.timing.taskPeriod, p.timing.meanTaskDuration);
assert(abs(p.stream.frameSampleTime - p.timing.taskPeriod) < eps(p.timing.taskPeriod)*8, ...
    'socParams:frameRate', ...
    ['Tempo di frame lato PL (%g s) diverso dal periodo del task (%g s): ' ...
     'un frame per attivazione e'' l''ipotesi su cui poggia il dimensionamento.'], ...
    p.stream.frameSampleTime, p.timing.taskPeriod);

% --- Register map del wrapper: offset unici e allineati a 4 byte ---
w = p.regmap.wrapper;
woffs = {w.offset};
assert(numel(unique(woffs)) == numel(woffs), 'socParams:wrapperRegmapDup', ...
    'Offset duplicati nella mappa del wrapper: %s', strjoin(woffs, ' '));
for k = 1:numel(w)
    v = sscanf(w(k).offset, '0x%x');
    assert(mod(v,4) == 0, 'socParams:wrapperAlign', ...
        'Offset %s (%s) non allineato a 4 byte.', w(k).offset, w(k).name);
end

% --- Watchdog: la soglia deve superare la latenza attesa ---
assert(p.compute.timeoutCycles > p.compute.latencyCycles, 'socParams:watchdog', ...
    ['Soglia di watchdog (%d cicli) non superiore alla latenza attesa del ' ...
     'calcolo (%d cicli): scatterebbe su ogni solve valido.'], ...
    p.compute.timeoutCycles, p.compute.latencyCycles);

% --- IL vincolo di progetto: trasporto + calcolo devono stare nel budget ---
B = p.budget.analysis;
assert(B.active.fits, 'socParams:budgetTransport', ...
    ['Con lo stack ''%s'' e il trasporto ''%s'' il solo TRASPORTO costa %.1f us ' ...
     'su un budget di %.1f us: non resta nulla al calcolo.\n' ...
     'Cambiare stack software o trasporto (vedi p.budget.analysis.rows).'], ...
    p.psStack.kind, p.transport.kind, B.active.transportSec*1e6, p.budget.TsLoop*1e6);

assert(p.compute.latencyCycles <= B.active.computeCyclesMax, 'socParams:budgetCompute', ...
    ['La latenza ipotizzata del blocco di calcolo (%d cicli) supera il massimo ' ...
     'compatibile con il budget (%d cicli) per lo stack ''%s'' con trasporto ''%s''.\n' ...
     'Budget totale %d cicli, trasporto %d cicli.'], ...
    p.compute.latencyCycles, B.active.computeCyclesMax, p.psStack.kind, ...
    p.transport.kind, p.budget.cyclesTotal, B.active.transportCycles);

% --- Avviso esplicito quando si progetta su ipotesi ---
% Non e' un errore: e' lecito progettare l'infrastruttura contro un
% contratto parametrico. Ma dev'essere VISIBILE, non implicito.
persistent assumptionsAnnounced
if isempty(assumptionsAnnounced); assumptionsAnnounced = false; end
if (~p.mpc.confirmed || ~p.compute.latencyKnown) && ~assumptionsAnnounced
    assumptionsAnnounced = true;   % una volta per sessione: visibile, non rumoroso
    warning('socParams:assumptions', ...
        ['Si sta progettando su IPOTESI: nx=%d nu=%d confermati=%d, ' ...
         'latenza calcolo=%d cicli nota=%d. Vedi docs/20_CONTRATTO_INTERFACCIA.md §8.'], ...
        p.mpc.nx, p.mpc.nu, p.mpc.confirmed, ...
        p.compute.latencyCycles, p.compute.latencyKnown);
end
end


% =====================================================================
function [lo, hi] = fixdt_range(wordLength, fracLength)
%FIXDT_RANGE  Estremi rappresentabili di fixdt(1, wordLength, fracLength).
lo = -2^(wordLength - 1 - fracLength);
hi =  2^(wordLength - 1 - fracLength) - 2^(-fracLength);
end
