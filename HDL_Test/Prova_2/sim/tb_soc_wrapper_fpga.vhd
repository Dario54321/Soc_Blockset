-------------------------------------------------------------------------------
-- tb_soc_wrapper_fpga.vhd
--
-- Testbench RTL per il DUT generato (soc_wrapp_ip_src_soc_wrapper_fpga), non
-- per l'IP incapsulato in AXI4-Lite: stessi segnali del modello Simulink
-- (start_cmd/x0..x5/done/cycles/u0), stesso stimolo di
-- scripts/run_wrapper_unit_sim.m (x = 1:nx, un solve nominale, poi un secondo
-- solve consecutivo). Lo scopo e' un confronto RTL-vs-modello indipendente:
-- CYCLES deve valere 501 (latencyCycles=500 + 1 di registro su done, vedi
-- soc_params.m e il commento in run_wrapper_unit_sim.m) tanto in simulazione
-- Simulink quanto qui, sul codice VHDL davvero generato da HDL Coder.
--
-- Non e' sintetizzabile e non deve esserlo: usa 'real' per la conversione in
-- virgola fissa e 'report' per l'output leggibile in console.
--
-- Uso in Vivado: aggiungere questo file come simulation source (non ne fa
-- parte l'anno IP core), assieme a tutti i .vhd in hdlsrc\soc_wrapper_fpga,
-- impostare tb_soc_wrapper_fpga come top di simulazione, Run Behavioral
-- Simulation. I risultati si leggono nella Tcl Console (i 'report') e nelle
-- forme d'onda (segnali start_cmd, done, cycles, u0).
-------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE STD.textio.ALL;

ENTITY tb_soc_wrapper_fpga IS
END tb_soc_wrapper_fpga;

ARCHITECTURE sim OF tb_soc_wrapper_fpga IS

  -- Parametri reali del progetto (scripts/soc_params.m) — non inventati:
  -- p.budget.clockMHz = 100, p.compute.latencyCycles = 500,
  -- p.compute.timeoutCycles = 3000, p.payload.dtStr = fixdt(1,32,16).
  CONSTANT CLK_PERIOD_NS   : time    := 10 ns;   -- 100 MHz
  CONSTANT LATENCY_CYCLES  : integer := 500;
  CONSTANT EXPECTED_CYCLES : integer := LATENCY_CYCLES + 1;  -- +1: registro su done (B2)
  CONSTANT TIMEOUT_CYCLES  : integer := 3000;
  CONSTANT WATCHDOG_TB     : integer := TIMEOUT_CYCLES + 10; -- guardia della TB stessa

  COMPONENT soc_wrapp_ip_src_soc_wrapper_fpga
    PORT( clk           :   IN    std_logic;
          reset         :   IN    std_logic;
          clk_enable    :   IN    std_logic;
          start_cmd     :   IN    std_logic;
          timeout_thr   :   IN    std_logic_vector(31 DOWNTO 0);
          x0            :   IN    std_logic_vector(31 DOWNTO 0);
          x1            :   IN    std_logic_vector(31 DOWNTO 0);
          x2            :   IN    std_logic_vector(31 DOWNTO 0);
          x3            :   IN    std_logic_vector(31 DOWNTO 0);
          x4            :   IN    std_logic_vector(31 DOWNTO 0);
          x5            :   IN    std_logic_vector(31 DOWNTO 0);
          ce_out        :   OUT   std_logic;
          done          :   OUT   std_logic;
          busy          :   OUT   std_logic;
          timeout_flag  :   OUT   std_logic;
          cycles        :   OUT   std_logic_vector(31 DOWNTO 0);
          u0            :   OUT   std_logic_vector(31 DOWNTO 0)
          );
  END COMPONENT;

  SIGNAL clk          : std_logic := '0';
  SIGNAL reset        : std_logic := '1';
  SIGNAL clk_enable    : std_logic := '1';
  SIGNAL start_cmd     : std_logic := '0';
  SIGNAL timeout_thr   : std_logic_vector(31 DOWNTO 0);
  SIGNAL x0, x1, x2, x3, x4, x5 : std_logic_vector(31 DOWNTO 0);
  SIGNAL ce_out, done, busy, timeout_flag : std_logic;
  SIGNAL cycles        : std_logic_vector(31 DOWNTO 0);
  SIGNAL u0             : std_logic_vector(31 DOWNTO 0);

  SIGNAL sim_done      : boolean := false;

  -- Q16.16 con segno: stesso formato di p.payload.dtStr = fixdt(1,32,16).
  FUNCTION to_q16_16(v : real) RETURN std_logic_vector IS
  BEGIN
    RETURN std_logic_vector(to_signed(integer(v * 65536.0), 32));
  END FUNCTION;

  -- Legge un uint32 di ritorno come intero, per i 'report'.
  FUNCTION u32(s : std_logic_vector) RETURN integer IS
  BEGIN
    RETURN to_integer(unsigned(s));
  END FUNCTION;

  -- Binding esplicito: non affidarsi al default binding implicito, che con
  -- xelab non e' scattato (il DUT restava una black box senza questo).
  FOR DUT : soc_wrapp_ip_src_soc_wrapper_fpga
    USE ENTITY work.soc_wrapp_ip_src_soc_wrapper_fpga(rtl);

BEGIN

  DUT : soc_wrapp_ip_src_soc_wrapper_fpga
    PORT MAP( clk          => clk,
              reset        => reset,
              clk_enable   => clk_enable,
              start_cmd    => start_cmd,
              timeout_thr  => timeout_thr,
              x0 => x0, x1 => x1, x2 => x2, x3 => x3, x4 => x4, x5 => x5,
              ce_out       => ce_out,
              done         => done,
              busy         => busy,
              timeout_flag => timeout_flag,
              cycles       => cycles,
              u0           => u0
              );

  -- Clock: libero finche' lo stimolo non dichiara finita la simulazione.
  clk_process : PROCESS
  BEGIN
    WHILE NOT sim_done LOOP
      clk <= '0'; WAIT FOR CLK_PERIOD_NS / 2;
      clk <= '1'; WAIT FOR CLK_PERIOD_NS / 2;
    END LOOP;
    WAIT;
  END PROCESS;

  -----------------------------------------------------------------------
  -- Procedura di un solve: alza start_cmd un ciclo, poi conta i cicli fino
  -- a 'done'. Il conteggio parte dallo stesso ciclo in cui la TB alza
  -- start_cmd: il wrapper_fsm genera start_o nello stesso ciclo in cui
  -- campiona start_cmd (I3), quindi il numero misurato qui e quello scritto
  -- nel registro CYCLES devono combaciare — e' proprio il confronto che
  -- serve.
  -----------------------------------------------------------------------
  stimulus : PROCESS
    VARIABLE measured : integer;
    VARIABLE l         : line;

    PROCEDURE run_one_solve(label_txt : string) IS
    BEGIN
      -- impulso di un solo ciclo (I2/I3: start_cmd si autoazzera e va
      -- interpretato a fronte, non a livello)
      WAIT UNTIL rising_edge(clk);
      start_cmd <= '1';
      WAIT UNTIL rising_edge(clk);
      start_cmd <= '0';

      measured := 0;
      WHILE done /= '1' LOOP
        WAIT UNTIL rising_edge(clk);
        measured := measured + 1;
        ASSERT measured <= WATCHDOG_TB
          REPORT label_txt & ": nessun done entro " & integer'image(WATCHDOG_TB) &
                 " cicli - la TB si e' fermata da sola, non e' il watchdog del wrapper."
          SEVERITY failure;
      END LOOP;

      write(l, label_txt & ": done a " & integer'image(measured) &
               " cicli (misurato in TB), CYCLES=" & integer'image(u32(cycles)) &
               ", u0=" & integer'image(u32(u0)));
      writeline(output, l);

      ASSERT measured = EXPECTED_CYCLES
        REPORT label_txt & ": misurato " & integer'image(measured) &
               " cicli in TB, attesi " & integer'image(EXPECTED_CYCLES)
        SEVERITY error;

      ASSERT u32(cycles) = EXPECTED_CYCLES
        REPORT label_txt & ": registro CYCLES = " & integer'image(u32(cycles)) &
               ", atteso " & integer'image(EXPECTED_CYCLES) &
               " - se questo diverge dal valore misurato in TB sopra, il " &
               "contatore del wrapper_fsm non e' esatto (vedi B2 in " &
               "docs/21_SPEC_WRAPPER.md)."
        SEVERITY error;

      -- il solve resta visibile un ciclo in piu' per una forma d'onda leggibile
      WAIT UNTIL rising_edge(clk);
    END PROCEDURE;

  BEGIN
    -- Reset asincrono attivo alto, rilasciato sincrono (stesso stile del
    -- DUT generato: 'PROCESS(clk, reset) IF reset=''1'' THEN ... ELSIF
    -- rising_edge(clk) THEN').
    reset      <= '1';
    clk_enable <= '1';
    timeout_thr <= std_logic_vector(to_unsigned(TIMEOUT_CYCLES, 32));
    x0 <= to_q16_16(1.0); x1 <= to_q16_16(2.0); x2 <= to_q16_16(3.0);
    x3 <= to_q16_16(4.0); x4 <= to_q16_16(5.0); x5 <= to_q16_16(6.0);
    WAIT FOR CLK_PERIOD_NS * 3;
    WAIT UNTIL rising_edge(clk);
    reset <= '0';
    WAIT UNTIL rising_edge(clk);

    -- Solve 1: nominale. u0 atteso = x0 = 1.0 -> 65536, perche' nu=1 e il
    -- segnaposto latcha x(1:nu) (docs/21_SPEC_WRAPPER §3).
    run_one_solve("Solve 1 (nominale)");
    ASSERT u32(u0) = integer(1.0 * 65536.0)
      REPORT "Solve 1: u0 = " & integer'image(u32(u0)) & ", atteso " &
             integer'image(integer(1.0 * 65536.0)) & " (x0)."
      SEVERITY error;

    -- Solve 2: stimolo diverso, per verificare B4 (un secondo solve parte e
    -- da' lo stesso numero di cicli — non e' un caso isolato del primo giro).
    x0 <= to_q16_16(10.0); x1 <= to_q16_16(20.0); x2 <= to_q16_16(30.0);
    x3 <= to_q16_16(40.0); x4 <= to_q16_16(50.0); x5 <= to_q16_16(60.0);
    WAIT UNTIL rising_edge(clk);
    run_one_solve("Solve 2 (back-to-back)");
    ASSERT u32(u0) = integer(10.0 * 65536.0)
      REPORT "Solve 2: u0 = " & integer'image(u32(u0)) & ", atteso " &
             integer'image(integer(10.0 * 65536.0)) & " (x0)."
      SEVERITY error;

    REPORT "tb_soc_wrapper_fpga: FINITO. Se non sono comparsi 'Error', i cicli RTL combaciano con il modello."
      SEVERITY note;

    sim_done <= true;
    WAIT;
  END PROCESS;

END sim;
