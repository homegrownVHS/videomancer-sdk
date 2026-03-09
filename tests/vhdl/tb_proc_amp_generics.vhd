-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_proc_amp_generics.vhd - Generic-parameterized proc amp tests
-- License: GNU General Public License v3.0
-- https://github.com/lzxindustries/videomancer-sdk
--
-- This file is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <https://www.gnu.org/licenses/>.
--
-- Description:
--   VUnit testbench for proc_amp_u testing across a range of G_WIDTH values.
--   Verifies pipeline latency formulas, enable/valid timing, and functional
--   correctness at widths 8, 10, and 12.
--
-- Pipeline Latency Formulas (verified by test_valid_latency_exact):
--   proc_amp_u wraps multiplier_s with internal width = G_WIDTH + 2.
--   C_INTERNAL_MULT_STAGES = (G_WIDTH + 3) / 2
--
--   Valid pipeline depth : C_INTERNAL_MULT_STAGES + 3 clock cycles
--   Data pipeline depth  : C_INTERNAL_MULT_STAGES + 4 clock cycles
--   Valid leads data by 1 clock cycle (inherited from multiplier_s).
--
--   Measured as edges after the sampling edge:
--     valid_wait = C_INTERNAL_MULT_STAGES + 3
--     data_wait  = C_INTERNAL_MULT_STAGES + 4
--
--   Example latencies (edges after sampling):
--     G_WIDTH=8:  CMS_int=5, valid_wait=8,  data_wait=9
--     G_WIDTH=10: CMS_int=6, valid_wait=9,  data_wait=10
--     G_WIDTH=12: CMS_int=7, valid_wait=10, data_wait=11
--
-- Tested generic configurations (via VUnit add_config in run.py):
--   w8:  G_WIDTH=8
--   w10: G_WIDTH=10
--   w12: G_WIDTH=12

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_proc_amp_generics is
  generic (
    runner_cfg : string;
    G_WIDTH    : integer := 10
  );
end entity;

architecture tb of tb_proc_amp_generics is

  constant C_CLK_PERIOD : time := 10 ns;

  -- ========================================================================
  -- Pipeline latency constants (derived from proc_amp_u + multiplier_s RTL)
  -- ========================================================================
  constant C_PROC_WIDTH          : integer := G_WIDTH + 2;
  constant C_INTERNAL_MULT_STAGES : integer := (C_PROC_WIDTH + 1) / 2;
  -- Edges after sampling edge until valid='1'
  -- Formula: 1 (proc input) + 1 (mult input reg) + CMS_int (valid shift) + 1 (mult output)
  constant C_VALID_WAIT : integer := C_INTERNAL_MULT_STAGES + 3;
  -- Edges after sampling edge until result is correct (valid leads data by 1)
  constant C_DATA_WAIT  : integer := C_INTERNAL_MULT_STAGES + 4;

  -- Useful constants for test values
  constant C_MIDPOINT : integer := 2 ** (G_WIDTH - 1);
  constant C_MAX_VAL  : integer := 2 ** G_WIDTH - 1;
  constant C_TOLERANCE : integer := C_MAX_VAL / 20 + 1;  -- ~5% of full scale

  signal clk        : std_logic := '0';
  signal enable     : std_logic := '0';
  signal a          : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal contrast   : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal brightness : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal result     : unsigned(G_WIDTH - 1 downto 0);
  signal valid      : std_logic;

  signal test_done : boolean := false;

  -- Helper: wait exactly N rising edges
  procedure wait_edges(signal clk_sig : in std_logic; n : integer) is
  begin
    for i in 1 to n loop
      wait until rising_edge(clk_sig);
    end loop;
  end procedure;

  -- Helper: flush pipeline
  procedure flush(signal clk_sig : in std_logic) is
  begin
    wait_edges(clk_sig, C_DATA_WAIT + 5);
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.proc_amp_u
    generic map (
      G_WIDTH => G_WIDTH
    )
    port map (
      clk        => clk,
      enable     => enable,
      a          => a,
      contrast   => contrast,
      brightness => brightness,
      result     => result,
      valid      => valid
    );

  main : process
    variable v_count      : integer;
    variable v_result_int : integer;
    variable v_first      : integer;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ================================================================
      -- Test 1: Exact valid latency measurement
      -- ================================================================
      if run("test_valid_latency_exact") then
        info("Verifying valid latency = " & integer'image(C_VALID_WAIT) &
             " edges (CMS_int=" & integer'image(C_INTERNAL_MULT_STAGES) &
             ") for G_WIDTH=" & integer'image(G_WIDTH));
        enable <= '0';
        a <= (others => '0'); contrast <= (others => '0');
        brightness <= (others => '0');
        flush(clk);

        a          <= to_unsigned(C_MIDPOINT, G_WIDTH);
        contrast   <= to_unsigned(C_MIDPOINT, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait until rising_edge(clk);  -- Sampling edge
        enable <= '0';

        v_count := 0;
        for i in 1 to C_DATA_WAIT + 10 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if valid = '1' then
            exit;
          end if;
        end loop;

        check_equal(valid, '1', "Valid should have asserted");
        check_equal(v_count, C_VALID_WAIT,
          "Valid latency should be " & integer'image(C_VALID_WAIT) & " edges");

      -- ================================================================
      -- Test 2: Single enable pulse produces exactly 1 valid cycle
      -- ================================================================
      elsif run("test_single_pulse_valid_count") then
        info("Verifying 1 enable pulse -> 1 valid cycle");
        enable <= '0';
        a <= (others => '0'); contrast <= (others => '0');
        brightness <= (others => '0');
        flush(clk);

        a          <= to_unsigned(C_MIDPOINT, G_WIDTH);
        contrast   <= to_unsigned(C_MIDPOINT, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        v_count := 0;
        for i in 1 to C_DATA_WAIT + 10 loop
          wait until rising_edge(clk);
          if valid = '1' then
            v_count := v_count + 1;
          end if;
        end loop;

        check_equal(v_count, 1, "Exactly 1 valid cycle from 1 enable pulse");

      -- ================================================================
      -- Test 3: Streaming mode — valid sustained
      -- ================================================================
      elsif run("test_streaming_valid_sustained") then
        info("Verifying valid stays high in streaming mode");
        enable <= '0';
        flush(clk);

        a          <= to_unsigned(C_MIDPOINT, G_WIDTH);
        contrast   <= to_unsigned(C_MIDPOINT, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';

        wait_edges(clk, C_VALID_WAIT + 2);
        check_equal(valid, '1', "Valid should be high after latency");

        for i in 0 to 9 loop
          wait until rising_edge(clk);
          check_equal(valid, '1',
            "Valid should stay high, cycle " & integer'image(i));
        end loop;
        enable <= '0';

      -- ================================================================
      -- Test 4: Valid deassert latency
      -- ================================================================
      elsif run("test_valid_deassert_latency") then
        info("Verifying valid deassert latency = " &
             integer'image(C_VALID_WAIT));
        enable <= '0';
        flush(clk);

        a          <= to_unsigned(C_MIDPOINT, G_WIDTH);
        contrast   <= to_unsigned(C_MIDPOINT, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 5);
        check_equal(valid, '1', "Pipeline should be primed");

        enable <= '0';
        wait until rising_edge(clk);  -- Sampling edge for enable='0'

        v_count := 0;
        for i in 1 to C_DATA_WAIT + 10 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if valid = '0' then
            exit;
          end if;
        end loop;

        check_equal(valid, '0', "Valid should have deasserted");
        check_equal(v_count, C_VALID_WAIT,
          "Deassert latency should match assert latency");

      -- ================================================================
      -- Test 5: Streaming data correctness (unity at midgray)
      -- Formula: (midpoint - 0.5) * 1.0 + 0.0 = 0.0 -> output = midpoint
      -- ================================================================
      elsif run("test_streaming_data_check") then
        info("Verifying unity at midgray in streaming mode");
        enable <= '0';
        flush(clk);

        a          <= to_unsigned(C_MIDPOINT, G_WIDTH);
        contrast   <= to_unsigned(C_MIDPOINT, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid should be high");
        v_result_int := to_integer(result);
        check(abs(v_result_int - C_MIDPOINT) <= C_TOLERANCE,
          "Unity midgray: expected ~" & integer'image(C_MIDPOINT) &
          ", got " & integer'image(v_result_int));
        enable <= '0';

      -- ================================================================
      -- Test 6: Unity gain at different input levels
      -- Black (a=0) -> result near 0
      -- White (a=max) -> result near max
      -- ================================================================
      elsif run("test_unity_extremes") then
        info("Verifying unity gain at black and white");
        enable <= '0';
        flush(clk);

        -- Black
        a          <= to_unsigned(0, G_WIDTH);
        contrast   <= to_unsigned(C_MIDPOINT, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        v_result_int := to_integer(result);
        check(v_result_int <= C_TOLERANCE,
          "Unity at black should be near 0, got " &
          integer'image(v_result_int));
        enable <= '0';
        wait until rising_edge(clk);

        -- White
        flush(clk);
        a          <= to_unsigned(C_MAX_VAL, G_WIDTH);
        contrast   <= to_unsigned(C_MIDPOINT, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        v_result_int := to_integer(result);
        check(v_result_int >= C_MAX_VAL - C_TOLERANCE,
          "Unity at white should be near max, got " &
          integer'image(v_result_int));
        enable <= '0';

      -- ================================================================
      -- Test 7: Zero contrast — different inputs produce same output
      -- ================================================================
      elsif run("test_zero_contrast_collapse") then
        info("Verifying zero contrast collapses all inputs");
        enable <= '0';
        flush(clk);

        -- First input: near black
        a          <= to_unsigned(C_MAX_VAL / 4, G_WIDTH);
        contrast   <= to_unsigned(0, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        v_first := to_integer(result);
        enable <= '0';
        wait until rising_edge(clk);

        -- Second input: near white
        flush(clk);
        a          <= to_unsigned(3 * C_MAX_VAL / 4, G_WIDTH);
        contrast   <= to_unsigned(0, G_WIDTH);
        brightness <= to_unsigned(C_MIDPOINT, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        check(abs(to_integer(result) - v_first) <= 2,
          "Zero contrast: different inputs should give same result. " &
          "First=" & integer'image(v_first) &
          ", Second=" & integer'image(to_integer(result)));
        enable <= '0';

      -- ================================================================
      -- Test 8: Clamp to maximum
      -- ================================================================
      elsif run("test_clamp_max") then
        enable <= '0'; flush(clk);
        a          <= to_unsigned(C_MAX_VAL, G_WIDTH);
        contrast   <= to_unsigned(C_MAX_VAL, G_WIDTH);
        brightness <= to_unsigned(C_MAX_VAL, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        check_equal(to_integer(result), C_MAX_VAL,
          "Should clamp to " & integer'image(C_MAX_VAL));
        enable <= '0';

      -- ================================================================
      -- Test 9: Clamp to minimum
      -- ================================================================
      elsif run("test_clamp_min") then
        enable <= '0'; flush(clk);
        a          <= to_unsigned(0, G_WIDTH);
        contrast   <= to_unsigned(C_MAX_VAL, G_WIDTH);
        brightness <= to_unsigned(0, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        check_equal(to_integer(result), 0,
          "Should clamp to 0");
        enable <= '0';

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 100 ms);

end architecture;
