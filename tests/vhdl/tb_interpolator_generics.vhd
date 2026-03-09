-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_interpolator_generics.vhd - Generic-parameterized interpolator tests
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
--   VUnit testbench for interpolator_u testing across a range of generic
--   parameters. Verifies pipeline latency, enable/valid timing, and
--   functional correctness at multiple widths, fractional bit depths,
--   and clamping configurations.
--
-- Pipeline Latency (verified by test_valid_latency_exact):
--   The interpolator has a fixed 4-stage pipeline independent of generics.
--   Valid and data are synchronized (arrive on the same clock edge).
--
--   Pipeline depth  : 4 clock cycles (from enable to output)
--   Measured as edges after the sampling edge: 4
--
-- Tested generic configurations (via VUnit add_config in run.py):
--   w8_f8:               G_WIDTH=8,  G_FRAC_BITS=8,  range [0, 255]
--   w10_f10:             G_WIDTH=10, G_FRAC_BITS=10, range [0, 1023]
--   w12_f12:             G_WIDTH=12, G_FRAC_BITS=12, range [0, 4095]
--   w8_f12:              G_WIDTH=8,  G_FRAC_BITS=12, range [0, 255]  (asymmetric)
--   w10_f10_narrowclamp: G_WIDTH=10, G_FRAC_BITS=10, range [100, 900]

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_interpolator_generics is
  generic (
    runner_cfg   : string;
    G_WIDTH      : integer := 8;
    G_FRAC_BITS  : integer := 8;
    G_OUTPUT_MIN : integer := 0;
    G_OUTPUT_MAX : integer := 255
  );
end entity;

architecture tb of tb_interpolator_generics is

  constant C_CLK_PERIOD : time := 10 ns;

  -- ========================================================================
  -- Pipeline latency constants
  -- The interpolator has a fixed 4-stage pipeline. Valid and data arrive
  -- on the same edge (synchronized, unlike multiplier_s).
  -- ========================================================================
  constant C_PIPELINE_STAGES : integer := 4;
  -- Edges after sampling edge until valid='1' AND result is correct
  -- The sampling edge itself is stage 0; stages 1-3 execute on subsequent edges.
  constant C_WAIT : integer := C_PIPELINE_STAGES;  -- = 4

  -- Useful constants
  constant C_DATA_MAX : integer := 2 ** G_WIDTH - 1;
  constant C_T_MAX    : integer := 2 ** G_FRAC_BITS - 1;
  constant C_T_MID    : integer := 2 ** (G_FRAC_BITS - 1);

  signal clk    : std_logic := '0';
  signal enable : std_logic := '0';
  signal a_in   : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal b_in   : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal t_in   : unsigned(G_FRAC_BITS - 1 downto 0) := (others => '0');
  signal result : unsigned(G_WIDTH - 1 downto 0);
  signal valid  : std_logic;

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
    wait_edges(clk_sig, C_WAIT + 5);
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.interpolator_u
    generic map (
      G_WIDTH      => G_WIDTH,
      G_FRAC_BITS  => G_FRAC_BITS,
      G_OUTPUT_MIN => G_OUTPUT_MIN,
      G_OUTPUT_MAX => G_OUTPUT_MAX
    )
    port map (
      clk    => clk,
      enable => enable,
      a      => a_in,
      b      => b_in,
      t      => t_in,
      result => result,
      valid  => valid
    );

  main : process
    variable v_count      : integer;
    variable v_result_int : integer;
    variable v_expected   : integer;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ================================================================
      -- Test 1: Exact valid latency measurement
      -- Verify: valid asserts exactly C_WAIT edges after sampling
      -- This proves pipeline depth = 4 regardless of generics
      -- ================================================================
      if run("test_valid_latency_exact") then
        info("Verifying valid latency = " & integer'image(C_WAIT) &
             " edges (4-stage pipeline) for G_WIDTH=" &
             integer'image(G_WIDTH) & ", G_FRAC_BITS=" &
             integer'image(G_FRAC_BITS));
        enable <= '0';
        a_in <= (others => '0'); b_in <= (others => '0');
        t_in <= (others => '0');
        flush(clk);

        a_in <= to_unsigned(100 mod (C_DATA_MAX + 1), G_WIDTH);
        b_in <= to_unsigned(200 mod (C_DATA_MAX + 1), G_WIDTH);
        t_in <= to_unsigned(C_T_MID mod (C_T_MAX + 1), G_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);  -- Sampling edge
        enable <= '0';

        v_count := 0;
        for i in 1 to C_WAIT + 10 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if valid = '1' then
            exit;
          end if;
        end loop;

        check_equal(valid, '1', "Valid should have asserted");
        check_equal(v_count, C_WAIT,
          "Valid latency should be " & integer'image(C_WAIT) &
          " edges (pipeline depth " & integer'image(C_PIPELINE_STAGES) & ")");

      -- ================================================================
      -- Test 2: Single enable pulse produces exactly 1 valid cycle
      -- ================================================================
      elsif run("test_single_pulse_valid_count") then
        info("Verifying 1 enable pulse -> 1 valid cycle");
        enable <= '0';
        a_in <= (others => '0'); b_in <= (others => '0');
        t_in <= (others => '0');
        flush(clk);

        a_in <= to_unsigned(50 mod (C_DATA_MAX + 1), G_WIDTH);
        b_in <= to_unsigned(200 mod (C_DATA_MAX + 1), G_WIDTH);
        t_in <= to_unsigned(0, G_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        v_count := 0;
        for i in 1 to C_WAIT + 10 loop
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

        a_in <= to_unsigned(100 mod (C_DATA_MAX + 1), G_WIDTH);
        b_in <= to_unsigned(200 mod (C_DATA_MAX + 1), G_WIDTH);
        t_in <= to_unsigned(C_T_MID mod (C_T_MAX + 1), G_FRAC_BITS);
        enable <= '1';

        wait_edges(clk, C_WAIT + 2);
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
             integer'image(C_WAIT));
        enable <= '0';
        flush(clk);

        a_in <= to_unsigned(100 mod (C_DATA_MAX + 1), G_WIDTH);
        b_in <= to_unsigned(200 mod (C_DATA_MAX + 1), G_WIDTH);
        t_in <= to_unsigned(C_T_MID mod (C_T_MAX + 1), G_FRAC_BITS);
        enable <= '1';
        wait_edges(clk, C_WAIT + 5);
        check_equal(valid, '1', "Pipeline should be primed");

        enable <= '0';
        wait until rising_edge(clk);  -- Sampling edge for enable='0'

        v_count := 0;
        for i in 1 to C_WAIT + 10 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if valid = '0' then
            exit;
          end if;
        end loop;

        check_equal(valid, '0', "Valid should have deasserted");
        check_equal(v_count, C_WAIT,
          "Deassert latency should match assert latency");

      -- ================================================================
      -- Test 5: Streaming data correctness (t=0 → a)
      -- Also verifies valid and data are synchronized
      -- ================================================================
      elsif run("test_streaming_data_t_zero") then
        info("Verifying t=0 returns a in streaming mode");
        enable <= '0';
        flush(clk);

        a_in <= to_unsigned(G_OUTPUT_MAX / 2, G_WIDTH);
        b_in <= to_unsigned(G_OUTPUT_MAX, G_WIDTH);
        t_in <= to_unsigned(0, G_FRAC_BITS);
        enable <= '1';
        wait_edges(clk, C_WAIT + 2);
        check_equal(valid, '1', "Valid should be high");
        check_equal(to_integer(result), G_OUTPUT_MAX / 2,
          "t=0 should return a");
        enable <= '0';

      -- ================================================================
      -- Test 6: t=0 returns a
      -- ================================================================
      elsif run("test_t_zero_returns_a") then
        enable <= '0'; flush(clk);
        a_in <= to_unsigned(G_OUTPUT_MIN + (G_OUTPUT_MAX - G_OUTPUT_MIN) / 3,
                            G_WIDTH);
        b_in <= to_unsigned(G_OUTPUT_MAX, G_WIDTH);
        t_in <= to_unsigned(0, G_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        -- Wait for valid; data is synchronized
        wait_edges(clk, C_WAIT);
        check_equal(valid, '1', "Valid");
        v_expected := G_OUTPUT_MIN + (G_OUTPUT_MAX - G_OUTPUT_MIN) / 3;
        check_equal(to_integer(result), v_expected,
          "t=0 should return a=" & integer'image(v_expected));

      -- ================================================================
      -- Test 7: t=max returns approximately b
      -- ================================================================
      elsif run("test_t_max_returns_b") then
        enable <= '0'; flush(clk);
        a_in <= to_unsigned(G_OUTPUT_MIN, G_WIDTH);
        b_in <= to_unsigned(G_OUTPUT_MAX, G_WIDTH);
        t_in <= to_unsigned(C_T_MAX, G_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_edges(clk, C_WAIT);
        check_equal(valid, '1', "Valid");
        v_result_int := to_integer(result);
        -- t=max gives result ≈ b (not exact: t_max = 2^frac - 1, not 2^frac)
        check(abs(v_result_int - G_OUTPUT_MAX) <= 2,
          "t=max should be ~" & integer'image(G_OUTPUT_MAX) &
          ", got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 8: Midpoint interpolation
      -- a + (b - a) * t_mid / 2^frac ≈ (a + b) / 2
      -- ================================================================
      elsif run("test_midpoint") then
        enable <= '0'; flush(clk);
        a_in <= to_unsigned(G_OUTPUT_MIN, G_WIDTH);
        b_in <= to_unsigned(G_OUTPUT_MAX, G_WIDTH);
        t_in <= to_unsigned(C_T_MID, G_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_edges(clk, C_WAIT);
        check_equal(valid, '1', "Valid");
        v_result_int := to_integer(result);
        v_expected := (G_OUTPUT_MIN + G_OUTPUT_MAX) / 2;
        check(abs(v_result_int - v_expected) <= 2,
          "Midpoint should be ~" & integer'image(v_expected) &
          ", got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 9: Reverse direction (b < a)
      -- a=max, b=min, t=mid → result ≈ midpoint
      -- ================================================================
      elsif run("test_reverse_direction") then
        enable <= '0'; flush(clk);
        a_in <= to_unsigned(G_OUTPUT_MAX, G_WIDTH);
        b_in <= to_unsigned(G_OUTPUT_MIN, G_WIDTH);
        t_in <= to_unsigned(C_T_MID, G_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_edges(clk, C_WAIT);
        check_equal(valid, '1', "Valid");
        v_result_int := to_integer(result);
        v_expected := (G_OUTPUT_MIN + G_OUTPUT_MAX) / 2;
        check(abs(v_result_int - v_expected) <= 2,
          "Reverse midpoint should be ~" & integer'image(v_expected) &
          ", got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 10: Output clamping
      -- Tests clamping when G_OUTPUT_MIN > 0 or G_OUTPUT_MAX < C_DATA_MAX
      -- For full-range configs, just verifies boundaries work correctly
      -- ================================================================
      elsif run("test_clamp_output") then
        enable <= '0'; flush(clk);

        if G_OUTPUT_MIN > 0 then
          -- Value below G_OUTPUT_MIN should clamp
          info("Testing clamp to min=" & integer'image(G_OUTPUT_MIN));
          a_in <= to_unsigned(G_OUTPUT_MIN / 2, G_WIDTH);
          b_in <= to_unsigned(G_OUTPUT_MIN / 2, G_WIDTH);
          t_in <= to_unsigned(0, G_FRAC_BITS);
          enable <= '1';
          wait_edges(clk, C_WAIT + 2);
          check_equal(valid, '1', "Valid");
          check_equal(to_integer(result), G_OUTPUT_MIN,
            "Should clamp to min=" & integer'image(G_OUTPUT_MIN));
          enable <= '0';
          wait until rising_edge(clk);
          flush(clk);
        end if;

        if G_OUTPUT_MAX < C_DATA_MAX then
          -- Value above G_OUTPUT_MAX should clamp
          info("Testing clamp to max=" & integer'image(G_OUTPUT_MAX));
          a_in <= to_unsigned(C_DATA_MAX, G_WIDTH);
          b_in <= to_unsigned(C_DATA_MAX, G_WIDTH);
          t_in <= to_unsigned(0, G_FRAC_BITS);
          enable <= '1';
          wait_edges(clk, C_WAIT + 2);
          check_equal(valid, '1', "Valid");
          check_equal(to_integer(result), G_OUTPUT_MAX,
            "Should clamp to max=" & integer'image(G_OUTPUT_MAX));
          enable <= '0';
        else
          -- Full range: verify max endpoints return max
          info("Full range: verifying max endpoints");
          a_in <= to_unsigned(G_OUTPUT_MAX, G_WIDTH);
          b_in <= to_unsigned(G_OUTPUT_MAX, G_WIDTH);
          t_in <= to_unsigned(C_T_MAX, G_FRAC_BITS);
          enable <= '1';
          wait_edges(clk, C_WAIT + 2);
          check_equal(valid, '1', "Valid");
          check_equal(to_integer(result), G_OUTPUT_MAX,
            "Max endpoints should give max=" &
            integer'image(G_OUTPUT_MAX));
          enable <= '0';
        end if;

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 100 ms);

end architecture;
