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

% --- registro del Register Channel di SoC Blockset -------------------
% ATTENZIONE: e' cosa diversa dalla tabella p.regmap.reg qui sotto.
%   * questo e' il registro modellato dal blocco Register Channel, usato in
%     SIMULAZIONE per portare streamEnable dal processore alla PL;
%   * p.regmap.reg e' la mappa AXI4-Lite dell'IP core che verra' GENERATO
%     a P12 (CTRL/STATUS/CYCLES/ID_VER).
% Il lato software NON collega un segnale grezzo al Register Channel: ci
% scrive attraverso un blocco prociolib/Register Write, che e' cio' che
% emette il messaggio atteso dal canale (vedi docs/11_NOTE_API).
p.regchan.name       = 'streamEnable';
p.regchan.rw         = 'Write';
p.regchan.dataType   = 'boolean';
p.regchan.deviceName = '/dev/mwipcore';   % segnaposto: allineare all'IP core a P12
p.regchan.offset     = 'hex2dec(''0100'')';
p.regmap.reg = struct( ...
    'name',   {'CTRL','STATUS','CYCLES','ITERS','ID_VER'}, ...
    'offset', {  '0x00','0x04',  '0x44',  '0x48', '0x4C'}, ...
    'access', {   'RW',   'R',     'R',     'R',    'R'}, ...
    'type',   {'uint32','uint32','uint32','uint32','uint32'}, ...
    'descr',  {'bit0 START(autoclear) bit1 SOFT_RESET bit2 IRQ_EN', ...
               'bit0 DONE bit1 BUSY bit2 ERROR', ...
               'cicli dell''ultimo solve', ...
               'iterazioni eseguite', ...
               'costante magica + versione'});

%% ------------------------------------------------------------------
%  Vettori di test
%  ------------------------------------------------------------------
p.vectors.seed      = 20260728;          % seed FISSO: la suite e' rigenerabile
p.vectors.nRandom   = 500;
p.vectors.file      = 'vectors.mat';

%% ------------------------------------------------------------------
soc_params_check(p);
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

% --- Register map: offset unici ---
offs = {p.regmap.reg.offset};
assert(numel(unique(offs)) == numel(offs), 'socParams:regmapDup', ...
    'Offset duplicati nel register map: %s', strjoin(offs, ' '));
end


% =====================================================================
function [lo, hi] = fixdt_range(wordLength, fracLength)
%FIXDT_RANGE  Estremi rappresentabili di fixdt(1, wordLength, fracLength).
lo = -2^(wordLength - 1 - fracLength);
hi =  2^(wordLength - 1 - fracLength) - 2^(-fracLength);
end
