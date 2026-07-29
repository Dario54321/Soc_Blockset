function mdl = build_wrapper_fpga(p, outFile)
%BUILD_WRAPPER_FPGA  Costruisce models/soc_wrapper_fpga.slx da zero.
%
%   Passo P9. E' il wrapper AXI4-Lite: CSR, macchina a stati start/done,
%   watchdog e contatore di cicli, con il blocco di calcolo di terzi
%   rappresentato da un SEGNAPOSTO a latenza configurabile.
%
%   Specifica: docs/21_SPEC_WRAPPER.md
%   Contratto: docs/20_CONTRATTO_INTERFACCIA.md
%
%   NON sostituisce soc_fpga.slx (Test 1, percorso AXI4-Stream), che resta
%   come seconda implementazione della stessa interfaccia.
%
%   --- Nota importante sulla semantica del tempo -----------------------
%   In questo modello **un passo di simulazione = un ciclo di clock**.
%   E' vero solo nella simulazione UNITARIA (run_wrapper_unit_sim), dove il
%   modello viene pilotato direttamente. A livello di sistema il modello FPGA
%   gira al rate del canale, NON al clock della PL (docs/11_NOTE_API §6):
%   li' il contatore di cicli non e' fedele, e infatti la verifica di CYCLES
%   si fa a livello unitario. E' la ragione per cui esistono due livelli di
%   verifica invece di uno.
%
%   Uso:  build_wrapper_fpga()

    if nargin < 1 || isempty(p);  p = soc_params(); end
    if nargin < 2 || isempty(outFile)
        here = fileparts(mfilename('fullpath'));
        outFile = fullfile(fileparts(here), 'models', 'soc_wrapper_fpga.slx');
    end

    % Il nome del modello si DERIVA dal file, non e' fisso. Altrimenti una
    % variante costruita altrove (per esempio il segnaposto muto del banco di
    % prova) avrebbe lo stesso nome del modello vero, e Simulink caricherebbe
    % quello piu' in alto sul path:
    %   "The file containing block diagram '...' is shadowed by a file of the
    %    same name higher on the MATLAB path."
    % Il test passerebbe per il motivo sbagliato, in silenzio.
    [~, mdl] = fileparts(outFile);
    if bdIsLoaded(mdl); close_system(mdl, 0); end
    if isfile(outFile); delete(outFile); end

    new_system(mdl);
    cl = onCleanup(@() closeIfLoaded(mdl));

    %% --- configurazione: stesso trapianto del modello FPGA del Test 1 ---
    copyFpgaConfigSetFrom(mdl);
    set_param(mdl, 'SolverType', 'Fixed-step');
    set_param(mdl, 'Solver',     'FixedStepDiscrete');
    set_param(mdl, 'FixedStep',  '1');    % 1 passo = 1 ciclo (vedi nota sopra)
    set_param(mdl, 'StartTime',  '0');
    set_param(mdl, 'StopTime',   '1000');

    nx = p.mpc.nx;  nu = p.mpc.nu;

    %% =================== porte verso l'ARM (AXI4-Lite) =================
    % Porte SCALARI, una per registro: e' la forma che la generazione
    % dell'IP core mappa direttamente sulla mappa AXI4-Lite, senza ambiguita'.
    y = 40;
    add(mdl,'simulink/Sources/In1','start_cmd',[30 y 60 y+14]);
    set_param([mdl '/start_cmd'],'Port','1','OutDataTypeStr','boolean','PortDimensions','1');

    y = y + 50;
    add(mdl,'simulink/Sources/In1','timeout_thr',[30 y 60 y+14]);
    set_param([mdl '/timeout_thr'],'Port','2','OutDataTypeStr','uint32','PortDimensions','1');

    for i = 0:nx-1
        y = y + 50;
        nm = sprintf('x%d', i);
        add(mdl,'simulink/Sources/In1',nm,[30 y 60 y+14]);
        set_param([mdl '/' nm],'Port',num2str(3+i), ...
            'OutDataTypeStr',p.payload.dtStr,'PortDimensions','1');
    end

    add(mdl,'simulink/Signal Routing/Mux','Mux_x',[110 120 115 220]);
    set_param([mdl '/Mux_x'],'Inputs',num2str(nx));

    %% =================== logica ========================================
    add(mdl,'simulink/User-Defined Functions/MATLAB Function','wrapper_fsm',[200 40 320 140]);
    setChartScript(mdl,'wrapper_fsm', fsmCode());

    add(mdl,'simulink/User-Defined Functions/MATLAB Function','compute_stub',[200 200 320 280]);
    setChartScript(mdl,'compute_stub', stubCode(p, nx, nu));

    % --- nondirect feedthrough: come si rompe l'anello, per il manuale ----
    % Di default una MATLAB Function e' direct feedthrough su TUTTI gli
    % ingressi, quindi l'anello fsm -> stub -> fsm diventa algebrico e il
    % modello non compila.
    %
    % La soluzione documentata da MathWorks non e' un ritardo aggiunto a mano,
    % ma disattivare il direct feedthrough sul blocco che deve rompere
    % l'anello: "When Allow direct feedthrough is cleared, the output of the
    % block depends on the internal state and properties and does not depend
    % on the input."  In cambio il codice deve rispettare una regola:
    % **leggere lo stato PRIMA di aggiornarlo** (stile Moore).
    %   https://www.mathworks.com/help/hdlcoder/ug/using-persistent-variables-inside-matlab-function-blocks-for-hdl-code-generation.html
    %
    % Solo compute_stub: wrapper_fsm deve restare direct feedthrough, perche'
    % start_o dipende davvero da start_cmd nello stesso ciclo.
    %
    % La regola e' piu' stretta di quanto sembri: NESSUNA uscita del blocco
    % puo' dipendere da un ingresso. Con un'uscita "u_raw = x(1:nu)" Simulink
    % rifiuta con
    %   Stateflow:cdr:CannotDisallowDirectFeedthrough
    %   "Property 'Allow direct feedthrough' is not supported for MATLAB
    %    Function '...', but Simulink is not able to enforce this constraint."
    % Per questo il segnaposto NON produce piu' il dato: e' solo un ritardo
    % con handshake, e il dato va al latch direttamente da x.
    cfg = get_param([mdl '/compute_stub'], 'MATLABFunctionConfiguration');
    cfg.AllowDirectFeedthrough = 0;

    % Percorso dati verso il latch: i primi nu elementi di x.
    add(mdl,'simulink/Signal Routing/Selector','sel_u',[240 200 270 240]);
    set_param([mdl '/sel_u'], 'NumberOfDimensions','1', ...
        'IndexOptionArray',{'Index vector (dialog)'}, ...
        'IndexParamArray',{sprintf('1:%d',nu)}, ...
        'InputPortWidth', num2str(nx));

    % --- latch di u: appartiene al WRAPPER, non al blocco di calcolo ----
    % docs/21_SPEC_WRAPPER §3: "RUNNING -> DONE: u latchato".
    % Realizzato con Switch + Unit Delay invece che dentro una MATLAB
    % Function: il latch resta VISIBILE nel modello, e si evita di dover
    % inizializzare una persistent tipizzata in virgola fissa (vedi
    % docs/11_NOTE_API §12 per il perche' quella strada non funziona).
    add(mdl,'simulink/Signal Routing/Switch','u_latch',[350 200 380 240]);
    set_param([mdl '/u_latch'],'Criteria','u2 > Threshold','Threshold','0.5');

    add(mdl,'simulink/Discrete/Unit Delay','u_hold',[350 300 380 330]);
    set_param([mdl '/u_hold'],'InitialCondition','0');

    % --- tipi DICHIARATI, non inferiti ---------------------------------
    % L'anello fsm -> stub -> fsm rende circolare l'inferenza dei tipi:
    % Simulink non riesce a chiuderla e degrada un segnale a double, con
    %   "Output 'done_o' is a signal of data type 'boolean'. However, it is
    %    driving a signal of data type 'double'."
    % Dichiararli toglie l'ambiguita' ed e' comunque la scelta giusta: sono
    % le porte di un'interfaccia, non un dettaglio interno.
    setDataType(mdl,'wrapper_fsm', 'start_cmd',   'boolean', 1);
    setDataType(mdl,'wrapper_fsm', 'done_i',      'boolean', 1);
    setDataType(mdl,'wrapper_fsm', 'timeout_thr', 'uint32',  1);
    setDataType(mdl,'wrapper_fsm', 'start_o',     'boolean', 1);
    setDataType(mdl,'wrapper_fsm', 'done_o',      'boolean', 1);
    setDataType(mdl,'wrapper_fsm', 'busy_o',      'boolean', 1);
    setDataType(mdl,'wrapper_fsm', 'timeout_o',   'boolean', 1);
    setDataType(mdl,'wrapper_fsm', 'cycles_o',    'uint32',  1);

    setDataType(mdl,'compute_stub','x',       p.payload.dtStr, nx);
    setDataType(mdl,'compute_stub','start_i', 'boolean',       1);
    setDataType(mdl,'compute_stub','done_o',  'boolean',       1);

    %% =================== porte verso l'ARM (uscite) ====================
    outs = {'done','busy','timeout_flag'};
    for k = 1:numel(outs)
        add(mdl,'simulink/Sinks/Out1',outs{k},[430 40+40*k 460 54+40*k]);
        set_param([mdl '/' outs{k}],'Port',num2str(k));
    end
    add(mdl,'simulink/Sinks/Out1','cycles',[430 200 460 214]);
    set_param([mdl '/cycles'],'Port','4');

    if nu > 1
        add(mdl,'simulink/Signal Routing/Demux','Demux_u',[380 250 385 330]);
        set_param([mdl '/Demux_u'],'Outputs',num2str(nu));
    end
    for j = 0:nu-1
        nm = sprintf('u%d', j);
        add(mdl,'simulink/Sinks/Out1',nm,[430 250+40*j 460 264+40*j]);
        set_param([mdl '/' nm],'Port',num2str(5+j));
    end

    %% =================== collegamenti ==================================
    for i = 0:nx-1
        add_line(mdl, sprintf('x%d/1',i), sprintf('Mux_x/%d',i+1), 'autorouting','on');
    end
    add_line(mdl,'Mux_x/1','compute_stub/1','autorouting','on');
    add_line(mdl,'Mux_x/1','sel_u/1','autorouting','on');

    add_line(mdl,'start_cmd/1','wrapper_fsm/1','autorouting','on');
    add_line(mdl,'timeout_thr/1','wrapper_fsm/3','autorouting','on');

    % Anello fsm -> stub -> fsm, chiuso direttamente: e' il nondirect
    % feedthrough di compute_stub a spezzarlo (vedi commento sopra).
    add_line(mdl,'wrapper_fsm/1','compute_stub/2','autorouting','on');   % start_o
    add_line(mdl,'compute_stub/1','wrapper_fsm/2','autorouting','on');   % done_i

    add_line(mdl,'wrapper_fsm/2','done/1','autorouting','on');
    add_line(mdl,'wrapper_fsm/3','busy/1','autorouting','on');
    add_line(mdl,'wrapper_fsm/4','timeout_flag/1','autorouting','on');
    add_line(mdl,'wrapper_fsm/5','cycles/1','autorouting','on');

    % latch: quando done, cattura x(1:nu); altrimenti tiene il valore prec.
    add_line(mdl,'sel_u/1','u_latch/1','autorouting','on');
    add_line(mdl,'wrapper_fsm/2','u_latch/2','autorouting','on');    % done
    add_line(mdl,'u_hold/1','u_latch/3','autorouting','on');
    add_line(mdl,'u_latch/1','u_hold/1','autorouting','on');

    if nu > 1
        add_line(mdl,'u_latch/1','Demux_u/1','autorouting','on');
        for j = 0:nu-1
            add_line(mdl, sprintf('Demux_u/%d',j+1), sprintf('u%d/1',j), 'autorouting','on');
        end
    else
        add_line(mdl,'u_latch/1','u0/1','autorouting','on');
    end

    %% -------------------------------------------------------------------
    Simulink.BlockDiagram.arrangeSystem(mdl);
    save_system(mdl, outFile);
    close_system(mdl, 0);

    verify_wrapper(outFile, p);
    fprintf('build_wrapper_fpga: %s  [verificato]\n', outFile);
end


% =====================================================================
function code = fsmCode()
%FSMCODE  Macchina a stati del wrapper (docs/21_SPEC_WRAPPER §3).
%
%   Invarianti implementate:
%     I2  START si autoazzera: la FSM reagisce al fronte, non al livello
%     I3  start_o e' un impulso di esattamente un ciclo
%     I4  un solo solve alla volta: in RUNNING, start_cmd viene ignorato
%     I5  cycles conta esattamente i cicli fra start_o e done_i
%     I6  da RUNNING si esce sempre: o per done, o per watchdog
%     I7  in timeout NON si latcha nulla (il latch e' nel compute_stub)

    code = sprintf([ ...
        'function [start_o, done_o, busy_o, timeout_o, cycles_o] = wrapper_fsm(start_cmd, done_i, timeout_thr)\n' ...
        '%%#codegen\n' ...
        '%% GENERATO DA build_wrapper_fpga.m — non modificare a mano.\n' ...
        '\n' ...
        '    persistent state cnt cyc doneL toL\n' ...
        '    if isempty(state)\n' ...
        '        state = uint8(0);   %% 0=IDLE 1=RUNNING\n' ...
        '        cnt   = uint32(0);\n' ...
        '        cyc   = uint32(0);\n' ...
        '        doneL = false;\n' ...
        '        toL   = false;\n' ...
        '    end\n' ...
        '\n' ...
        '    start_o   = false;\n' ...
        '    doneL     = false;   %% DONE e TIMEOUT sono impulsi di un ciclo\n' ...
        '    toL       = false;\n' ...
        '\n' ...
        '    if state == uint8(0)\n' ...
        '        %% IDLE: si parte solo su comando. In RUNNING start_cmd e''\n' ...
        '        %% ignorato: un solve alla volta (I4).\n' ...
        '        if start_cmd\n' ...
        '            start_o = true;      %% impulso di UN ciclo (I3)\n' ...
        '            state   = uint8(1);\n' ...
        '            cnt     = uint32(0);\n' ...
        '        end\n' ...
        '    else\n' ...
        '        cnt = cnt + uint32(1);\n' ...
        '        if done_i\n' ...
        '            cyc   = cnt;         %% latenza misurata (I5)\n' ...
        '            doneL = true;\n' ...
        '            state = uint8(0);\n' ...
        '        elseif cnt >= timeout_thr\n' ...
        '            cyc   = cnt;         %% quanto si e'' aspettato prima di mollare\n' ...
        '            toL   = true;\n' ...
        '            state = uint8(0);    %% si esce SEMPRE (I6)\n' ...
        '        end\n' ...
        '    end\n' ...
        '\n' ...
        '    done_o    = doneL;\n' ...
        '    timeout_o = toL;\n' ...
        '    busy_o    = (state == uint8(1));\n' ...
        '    cycles_o  = cyc;\n' ...
        'end\n']);
end


function code = stubCode(p, nx, nu) %#ok<INUSD>
%STUBCODE  Segnaposto del blocco di calcolo di terzi.
%
%   MACCHINA DI MOORE: le uscite dipendono solo dallo stato, mai dagli
%   ingressi del ciclo corrente. E' cio' che interrompe il feedthrough
%   nell'anello fsm->stub->fsm.
%
%   Il "calcolo" e' deliberatamente banale (somma pesata degli ingressi):
%   serve solo a poter verificare che il dato attraversi il wrapper intatto.
%   L'algoritmo vero e' di terzi e non e' nel nostro perimetro.

    code = sprintf([ ...
        'function done_o = compute_stub(x, start_i) %%#ok<INUSL>\n' ...
        '%%#codegen\n' ...
        '%% GENERATO DA build_wrapper_fpga.m — non modificare a mano.\n' ...
        '%%\n' ...
        '%% Segnaposto del blocco di calcolo di terzi. Latenza %d cicli.\n' ...
        '%% NON e'' un algoritmo: e'' un ritardo con un handshake. Il calcolo\n' ...
        '%% vero e'' di terzi e non e'' nel nostro perimetro (docs/21_SPEC_WRAPPER §6).\n' ...
        '%%\n' ...
        '%% Il blocco e'' configurato NONDIRECT FEEDTHROUGH: e'' cio'' che rompe\n' ...
        '%% l''anello fsm -> stub -> fsm senza aggiungere ritardi a mano.\n' ...
        '%% In cambio vale una regola, prescritta dalla documentazione HDL Coder:\n' ...
        '%%   "You must read the persistent variable''s value BEFORE updating it."\n' ...
        '%% Le uscite si calcolano quindi in cima, dallo stato; gli aggiornamenti\n' ...
        '%% di stato stanno tutti dopo. Rompere questa regola non da'' un errore:\n' ...
        '%% da'' risultati sbagliati.\n' ...
        '%%\n' ...
        '%% Il segnaposto NON produce il dato: solo done. Il percorso dati va al\n' ...
        '%% latch del wrapper direttamente da x (docs/21_SPEC_WRAPPER §3). Serve\n' ...
        '%% perche'' col nondirect feedthrough NESSUNA uscita puo'' dipendere da un\n' ...
        '%% ingresso, e "u = x(1:nu)" ne dipenderebbe.\n' ...
        '%% x resta fra gli ingressi per fedelta'' al contratto: il blocco vero lo\n' ...
        '%% legge, e deve poterlo fare in qualunque momento fra start e done.\n' ...
        '\n' ...
        '    persistent cnt running doneReg\n' ...
        '    LATENCY = uint32(%d);\n' ...
        '    if isempty(cnt)\n' ...
        '        cnt     = uint32(0);\n' ...
        '        running = false;\n' ...
        '        doneReg = false;\n' ...
        '    end\n' ...
        '\n' ...
        '    %% --- USCITE: solo dallo stato, prima di ogni aggiornamento ---\n' ...
        '    done_o = doneReg;\n' ...
        '\n' ...
        '    %% --- AGGIORNAMENTI DI STATO ---\n' ...
        '    doneReg = false;\n' ...
        '    if running\n' ...
        '        cnt = cnt + uint32(1);\n' ...
        '        if cnt >= LATENCY\n' ...
        '            running = false;\n' ...
        '            doneReg = true;\n' ...
        '        end\n' ...
        '    elseif start_i\n' ...
        '        running = true;\n' ...
        '        cnt     = uint32(0);\n' ...
        '    end\n' ...
        'end\n'], ...
        p.compute.latencyCycles, p.compute.latencyCycles);
end


% =====================================================================
function copyFpgaConfigSetFrom(mdl)
    src = fullfile(matlabroot,'toolbox','soc','socexamples','soc_swhw_stream_fpga.slx');
    assert(isfile(src), 'buildWrapper:noExample', 'Esempio non trovato: %s', src);
    [~, srcMdl] = fileparts(src);
    wasLoaded = bdIsLoaded(srcMdl);
    if ~wasLoaded; load_system(src); end
    cl = onCleanup(@() closeIfNotPreviouslyLoaded(srcMdl, wasLoaded));
    cs = getActiveConfigSet(srcMdl).copy();
    cs.Name = 'SocWrapperConfig';
    attachConfigSet(mdl, cs, true);
    setActiveConfigSet(mdl, cs.Name);
end


function verify_wrapper(file, p)
%VERIFY_WRAPPER  Rilegge il file salvato e ne verifica le proprieta'.
    [~, mdl] = fileparts(file);
    load_system(file);
    c = onCleanup(@() close_system(mdl, 0));

    chk('SolverType', get_param(mdl,'SolverType'), 'Fixed-step');
    chk('FixedStep',  get_param(mdl,'FixedStep'),  '1');
    chk('ProdHWDeviceType', get_param(mdl,'ProdHWDeviceType'), 'ASIC/FPGA->ASIC/FPGA');

    for i = 0:p.mpc.nx-1
        b = sprintf('%s/x%d', mdl, i);
        chk(sprintf('x%d dtype',i), get_param(b,'OutDataTypeStr'), p.payload.dtStr);
    end
    chk('start_cmd dtype',   get_param([mdl '/start_cmd'],'OutDataTypeStr'),   'boolean');
    chk('timeout_thr dtype', get_param([mdl '/timeout_thr'],'OutDataTypeStr'), 'uint32');

    % La latenza del segnaposto deve essere quella di soc_params: se qualcuno
    % cambia il parametro senza rigenerare, qui salta fuori.
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[mdl '/compute_stub']);
    assert(~isempty(ch), 'buildWrapper:noStub', 'compute_stub assente.');
    need = sprintf('LATENCY = uint32(%d)', p.compute.latencyCycles);
    assert(contains(ch.Script, need), 'buildWrapper:staleLatency', ...
        'Il segnaposto non contiene "%s": modello non rigenerato dopo un cambio di soc_params.', need);
end

function chk(what, got, want)
    assert(strcmp(got, want), 'buildWrapper:mismatch', ...
        '%s: atteso ''%s'', trovato ''%s''.', what, want, got);
end


% =====================================================================
function add(sys, src, name, pos)
    add_block(src, [sys '/' name], 'Position', pos);
end

function setChartScript(sys, blkName, code)
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[sys '/' blkName]);
    assert(~isempty(ch), 'buildWrapper:noChart', ...
        'MATLAB Function ''%s'' non trovata.', blkName);
    ch.Script = code;
end

function setDataType(sys, blkName, dataName, typeStr, nElem)
%SETDATATYPE  Dichiara tipo e dimensione di un ingresso/uscita di una
%   MATLAB Function, invece di lasciarli inferire.
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[sys '/' blkName]);
    assert(~isempty(ch), 'buildWrapper:noChart', ...
        'MATLAB Function ''%s'' non trovata.', blkName);
    all = ch.find('-isa','Stateflow.Data');
    idx = find(arrayfun(@(d) strcmp(d.Name, dataName), all), 1);
    assert(~isempty(idx), 'buildWrapper:noData', ...
        'Dato ''%s'' non trovato in %s. Firma della funzione cambiata?', dataName, blkName);
    d = all(idx);
    d.DataType = typeStr;
    if nElem > 1
        d.Props.Array.Size = num2str(nElem);
    end
end

function closeIfLoaded(mdl)
    if bdIsLoaded(mdl); close_system(mdl, 0); end
end

function closeIfNotPreviouslyLoaded(mdlName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdlName); close_system(mdlName, 0); end
end
