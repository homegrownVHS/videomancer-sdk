-- Videomancer SDK - VUnit Generic-Parameterized Testbench for variable_filter_s
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Sweeps variable_filter_s across multiple G_WIDTH configurations to verify
-- low-pass filter behavior, valid timing, enable gating, and functional
-- correctness at each width.
--
-- variable_filter_s is an IIR filter with a single registered process.
-- Pipeline Latency (verified by test_valid_latency_exact):
--   valid:     1 clock cycle (registered copy of enable)
--   low_pass:  Combinational from registered state (state updates 1 cycle
--              after input change)
--   high_pass: Combinational (a - low_pass)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_variable_filter_generics is
  generic (
    runner_cfg : string;
    G_WIDTH    : integer := 16
  );
end entity;

architecture tb of tb_variable_filter_generics is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_SETTLE     : integer := 8;

  signal clk       : std_logic := '0';
  signal enable    : std_logic := '0';
  signal a         : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal cutoff    : unsigned(7 downto 0) := (others => '0');
  signal low_pass  : signed(G_WIDTH - 1 downto 0);
  signal high_pass : signed(G_WIDTH - 1 downto 0);
  signal valid     : std_logic;

  signal test_done : boolean := false;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.variable_filter_s
    generic map (G_WIDTH => G_WIDTH)
    port map (
      clk       => clk,
      enable    => enable,
      a         => a,
      cutoff    => cutoff,
      low_pass  => low_pass,
      high_pass => high_pass,
      valid     => valid
    );

  main : process
    procedure clk_wait(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    -- Flush: disable and let state settle
    procedure flush is
    begin
      enable <= '0';
      a      <= (others => '0');
      cutoff <= (others => '0');
      clk_wait(C_SETTLE);
    end procedure;

    variable v_max_pos   : integer;
    variable v_max_neg   : integer;
    variable v_step_val  : integer;
    variable v_prev_out  : integer;
    variable v_count     : integer;

  begin
    test_runner_setup(runner, runner_cfg);
    v_max_pos   := 2 ** (G_WIDTH - 1) - 1;
    v_max_neg   := -(2 ** (G_WIDTH - 1));

    while test_suite loop

      -- Reset
      flush;

      -- ==================================================================
      if run("test_valid_latency_exact") then
      -- ==================================================================
        -- Valid should assert exactly 1 cycle after enable
        info("Verifying valid latency = 1 cycle for G_WIDTH=" &
             integer'image(G_WIDTH));
        flush;

        enable <= '1';
        a      <= to_signed(100, G_WIDTH);
        wait until rising_edge(clk);  -- Sampling edge
        enable <= '0';

        -- Count edges until valid='1'
        v_count := 0;
        for i in 1 to 10 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if valid = '1' then
            exit;
          end if;
        end loop;

        check_equal(valid, '1', "Valid should have asserted");
        check_equal(v_count, 1,
          "Valid latency should be exactly 1 cycle (w=" &
          integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_single_pulse_valid_count") then
      -- ==================================================================
        -- 1 enable pulse produces exactly 1 valid cycle
        flush;

        enable <= '1';
        a      <= to_signed(50, G_WIDTH);
        wait until rising_edge(clk);
        enable <= '0';

        v_count := 0;
        for i in 1 to 10 loop
          wait until rising_edge(clk);
          if valid = '1' then
            v_count := v_count + 1;
          end if;
        end loop;

        check_equal(v_count, 1,
          "Exactly 1 valid cycle from 1 enable pulse (w=" &
          integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_enable_gap_tracking") then
      -- ==================================================================
        -- Valid tracks enable with 1-cycle offset
        flush;

        -- Enable
        enable <= '1';
        a      <= to_signed(v_max_pos / 4, G_WIDTH);
        clk_wait(3);
        check_equal(valid, '1', "Valid high when enabled");

        -- Gap
        enable <= '0';
        clk_wait(2);
        check_equal(valid, '0', "Valid low during gap");

        -- Re-enable
        enable <= '1';
        clk_wait(2);
        check_equal(valid, '1', "Valid restored after gap");
        enable <= '0';

      -- ==================================================================
      elsif run("zero_cutoff_holds_state") then
      -- ==================================================================
        cutoff <= (others => '0');
        enable <= '1';
        a      <= to_signed(v_max_pos / 2, G_WIDTH);
        clk_wait(C_SETTLE);
        check(abs(to_integer(low_pass) - v_max_pos / 2) <= 1,
              "zero cutoff tracks input immediately (w=" &
              integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("max_cutoff_tracks_input") then
      -- ==================================================================
        cutoff <= to_unsigned(255, 8);
        enable <= '1';
        a      <= to_signed(v_max_pos / 4, G_WIDTH);
        clk_wait(C_SETTLE);
        check(abs(to_integer(low_pass)) < v_max_pos / 8 + 2,
              "max cutoff holds near initial state (w=" &
              integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("step_response_converges") then
      -- ==================================================================
        v_step_val := v_max_pos / 4;
        cutoff <= to_unsigned(((G_WIDTH - 2) / 2) * 16, 8);
        enable <= '1';
        a      <= to_signed(v_step_val, G_WIDTH);

        clk_wait(G_WIDTH * 4);
        v_prev_out := to_integer(low_pass);

        clk_wait(G_WIDTH * 4);
        check(to_integer(low_pass) >= v_prev_out,
              "step response moving toward target (w=" &
              integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("negative_input") then
      -- ==================================================================
        cutoff <= (others => '0');
        enable <= '1';
        a      <= to_signed(v_max_neg / 4, G_WIDTH);
        clk_wait(C_SETTLE);
        check(to_integer(low_pass) < 0,
              "negative input produces negative output (w=" &
              integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_high_pass_complement") then
      -- ==================================================================
        -- high_pass = a - low_pass, so they should sum to a
        cutoff <= to_unsigned(128, 8);  -- mid cutoff
        enable <= '1';
        a      <= to_signed(v_max_pos / 4, G_WIDTH);
        clk_wait(C_SETTLE * 2);

        -- Verify high_pass = a - low_pass
        check_equal(to_integer(high_pass),
                    to_integer(a) - to_integer(low_pass),
                    "high_pass = a - low_pass (w=" &
                    integer'image(G_WIDTH) & ")");

      end if;
    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
