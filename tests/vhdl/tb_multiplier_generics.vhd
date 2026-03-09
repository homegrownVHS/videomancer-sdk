-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_multiplier_generics.vhd - Generic-parameterized multiplier tests
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
--   VUnit testbench for multiplier_s testing across a range of generic
--   parameters. Verifies pipeline latency formulas, enable/valid timing,
--   and functional correctness at widths from 6 to 16 bits.
--
-- Pipeline Latency Formulas (verified by test_valid_latency_exact):
--   C_MULTIPLIER_STAGES = (G_WIDTH + 1) / 2
--   Valid pipeline depth : C_MULTIPLIER_STAGES + 2 clock cycles
--   Data pipeline depth  : C_MULTIPLIER_STAGES + 3 clock cycles
--   Valid leads data by exactly 1 clock cycle.
--
--   Measured as edges after the sampling edge:
--     valid_wait = C_MULTIPLIER_STAGES + 2
--     data_wait  = C_MULTIPLIER_STAGES + 3
--
-- Tested generic configurations (via VUnit add_config in run.py):
--   w6_f5:    G_WIDTH=6,  G_FRAC_BITS=5,  range [-32, 31]
--   w8_f7:    G_WIDTH=8,  G_FRAC_BITS=7,  range [-128, 127]
--   w10_f9:   G_WIDTH=10, G_FRAC_BITS=9,  range [-512, 511]
--   w12_f10:  G_WIDTH=12, G_FRAC_BITS=10, range [-2048, 2047]  (asymmetric)
--   w16_f15:  G_WIDTH=16, G_FRAC_BITS=15, range [-32768, 32767]

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_multiplier_generics is
  generic (
    runner_cfg   : string;
    G_WIDTH      : integer := 8;
    G_FRAC_BITS  : integer := 7;
    G_OUTPUT_MIN : integer := -128;
    G_OUTPUT_MAX : integer := 127
  );
end entity;

architecture tb of tb_multiplier_generics is

  constant C_CLK_PERIOD : time := 10 ns;

  -- ========================================================================
  -- Pipeline latency constants (derived from multiplier_s RTL)
  -- ========================================================================
  -- Radix-4 Booth processes 2 bits per stage
  constant C_MULTIPLIER_STAGES : integer := (G_WIDTH + 1) / 2;
  -- Edges after sampling edge until valid='1'
  -- Formula: 1 (s_enable delay into valid_arr) + CMS (shift through arr) + 1 (output stage)
  constant C_VALID_WAIT : integer := C_MULTIPLIER_STAGES + 2;
  -- Edges after sampling edge until result is correct (valid leads data by 1)
  constant C_DATA_WAIT  : integer := C_MULTIPLIER_STAGES + 3;

  signal clk    : std_logic := '0';
  signal enable : std_logic := '0';
  signal x      : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal y      : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal z      : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal result : signed(G_WIDTH - 1 downto 0);
  signal valid  : std_logic;

  signal test_done : boolean := false;

  -- Helper: wait exactly N rising edges
  procedure wait_edges(signal clk_sig : in std_logic; n : integer) is
  begin
    for i in 1 to n loop
      wait until rising_edge(clk_sig);
    end loop;
  end procedure;

  -- Helper: flush pipeline until valid is guaranteed low
  procedure flush(signal clk_sig : in std_logic) is
  begin
    wait_edges(clk_sig, C_DATA_WAIT + 5);
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.multiplier_s
    generic map (
      G_WIDTH      => G_WIDTH,
      G_FRAC_BITS  => G_FRAC_BITS,
      G_OUTPUT_MIN => G_OUTPUT_MIN,
      G_OUTPUT_MAX => G_OUTPUT_MAX
    )
    port map (
      clk    => clk,
      enable => enable,
      x      => x,
      y      => y,
      z      => z,
      result => result,
      valid  => valid
    );

  main : process
    variable v_count    : integer;
    variable v_expected : integer;
    variable v_half     : integer;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ================================================================
      -- Test 1: Exact valid latency measurement (single-pulse enable)
      -- Verifies: valid asserts exactly C_VALID_WAIT edges after sampling
      -- ================================================================
      if run("test_valid_latency_exact") then
        info("Verifying valid latency = " & integer'image(C_VALID_WAIT) &
             " edges (CMS=" & integer'image(C_MULTIPLIER_STAGES) &
             ") for G_WIDTH=" & integer'image(G_WIDTH));
        enable <= '0';
        x <= (others => '0'); y <= (others => '0'); z <= (others => '0');
        flush(clk);

        -- Pulse enable for exactly 1 cycle
        x <= to_signed(1, G_WIDTH);
        y <= to_signed(1, G_WIDTH);
        enable <= '1';
        wait until rising_edge(clk);  -- Sampling edge
        enable <= '0';

        -- Count edges until valid='1'
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
        x <= (others => '0'); y <= (others => '0'); z <= (others => '0');
        flush(clk);

        x <= to_signed(1, G_WIDTH);
        y <= to_signed(1, G_WIDTH);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        -- Count total valid='1' cycles over the drain period
        v_count := 0;
        for i in 1 to C_DATA_WAIT + 10 loop
          wait until rising_edge(clk);
          if valid = '1' then
            v_count := v_count + 1;
          end if;
        end loop;

        check_equal(v_count, 1, "Exactly 1 valid cycle from 1 enable pulse");

      -- ================================================================
      -- Test 3: Streaming mode — valid sustained while enable is high
      -- ================================================================
      elsif run("test_streaming_valid_sustained") then
        info("Verifying valid stays high in streaming mode");
        enable <= '0';
        flush(clk);

        x <= to_signed(10, G_WIDTH);
        y <= to_signed(10, G_WIDTH);
        z <= to_signed(0, G_WIDTH);
        enable <= '1';

        -- Wait for valid to assert
        wait_edges(clk, C_VALID_WAIT + 2);
        check_equal(valid, '1', "Valid should be high after latency");

        -- Verify valid remains high for 10 more cycles
        for i in 0 to 9 loop
          wait until rising_edge(clk);
          check_equal(valid, '1',
            "Valid should stay high, cycle " & integer'image(i));
        end loop;
        enable <= '0';

      -- ================================================================
      -- Test 4: Valid deassert latency after enable drops
      -- Verifies: deassert latency = assert latency = C_VALID_WAIT
      -- ================================================================
      elsif run("test_valid_deassert_latency") then
        info("Verifying valid deassert latency = " &
             integer'image(C_VALID_WAIT));
        enable <= '0';
        flush(clk);

        -- Prime pipeline
        x <= to_signed(5, G_WIDTH);
        y <= to_signed(5, G_WIDTH);
        z <= to_signed(0, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 5);
        check_equal(valid, '1', "Pipeline should be primed");

        -- Drop enable and wait for the sampling edge
        enable <= '0';
        wait until rising_edge(clk);  -- Sampling edge for enable='0'

        -- Count edges until valid='0'
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
          "Deassert latency should equal assert latency");

      -- ================================================================
      -- Test 5: Enable gap — valid tracks enable with latency offset
      -- ================================================================
      elsif run("test_enable_gap_tracking") then
        info("Verifying valid tracks enable through a gap");
        enable <= '0';
        flush(clk);

        x <= to_signed(7, G_WIDTH);
        y <= to_signed(7, G_WIDTH);
        z <= to_signed(0, G_WIDTH);

        -- Enable long enough to fill pipeline
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid high before gap");

        -- Create a gap
        enable <= '0';
        wait_edges(clk, C_VALID_WAIT + 3);
        check_equal(valid, '0', "Valid low during gap");

        -- Re-enable
        enable <= '1';
        wait_edges(clk, C_VALID_WAIT + 2);
        check_equal(valid, '1', "Valid high after gap");
        enable <= '0';

      -- ================================================================
      -- Test 6: Streaming data correctness
      -- Verifies result is correct after C_DATA_WAIT in streaming mode
      -- ================================================================
      elsif run("test_streaming_data_check") then
        info("Verifying data correctness in streaming mode");
        enable <= '0';
        flush(clk);

        -- Known computation: (half * half) / 2^frac + 0
        v_half := 2 ** (G_FRAC_BITS - 1);
        x <= to_signed(v_half, G_WIDTH);
        y <= to_signed(v_half, G_WIDTH);
        z <= to_signed(0, G_WIDTH);
        enable <= '1';

        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid should be high");
        v_expected := (v_half * v_half) / (2 ** G_FRAC_BITS);
        check(abs(to_integer(result) - v_expected) <= 1,
          "Result should be ~" & integer'image(v_expected) &
          ", got " & integer'image(to_integer(result)));
        enable <= '0';

      -- ================================================================
      -- Test 7: Zero product
      -- ================================================================
      elsif run("test_zero_product") then
        enable <= '0'; flush(clk);
        x <= to_signed(0, G_WIDTH);
        y <= to_signed(0, G_WIDTH);
        z <= to_signed(0, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        check_equal(to_integer(result), 0, "0*0+0 = 0");
        enable <= '0';

      -- ================================================================
      -- Test 8: Accumulator passthrough (z only, x*y=0)
      -- ================================================================
      elsif run("test_accumulator_passthrough") then
        enable <= '0'; flush(clk);
        v_half := 2 ** (G_FRAC_BITS - 2);
        x <= to_signed(0, G_WIDTH);
        y <= to_signed(0, G_WIDTH);
        z <= to_signed(v_half, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        check_equal(to_integer(result), v_half,
          "0*0+" & integer'image(v_half) & " = " & integer'image(v_half));
        enable <= '0';

      -- ================================================================
      -- Test 9: Known positive product
      -- ================================================================
      elsif run("test_known_positive_product") then
        enable <= '0'; flush(clk);
        v_half := 2 ** (G_FRAC_BITS - 1);
        x <= to_signed(v_half, G_WIDTH);
        y <= to_signed(v_half, G_WIDTH);
        z <= to_signed(0, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        v_expected := (v_half * v_half) / (2 ** G_FRAC_BITS);
        check(abs(to_integer(result) - v_expected) <= 1,
          "pos*pos: expected ~" & integer'image(v_expected) &
          ", got " & integer'image(to_integer(result)));
        enable <= '0';

      -- ================================================================
      -- Test 10: Positive overflow clamping
      -- ================================================================
      elsif run("test_clamp_positive") then
        enable <= '0'; flush(clk);
        -- Use half-max for x,y to avoid internal overflow in asymmetric configs
        -- (e.g. G_WIDTH=12, G_FRAC_BITS=10 where scaled product can exceed G_WIDTH+1 bits)
        x <= to_signed(G_OUTPUT_MAX / 2, G_WIDTH);
        y <= to_signed(G_OUTPUT_MAX / 2, G_WIDTH);
        z <= to_signed(G_OUTPUT_MAX, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        check_equal(to_integer(result), G_OUTPUT_MAX,
          "Should clamp to " & integer'image(G_OUTPUT_MAX));
        enable <= '0';

      -- ================================================================
      -- Test 11: Negative overflow clamping
      -- ================================================================
      elsif run("test_clamp_negative") then
        enable <= '0'; flush(clk);
        -- Use half-max for x to avoid internal overflow in asymmetric configs
        x <= to_signed(G_OUTPUT_MAX / 2, G_WIDTH);
        y <= to_signed(G_OUTPUT_MIN, G_WIDTH);
        z <= to_signed(G_OUTPUT_MIN, G_WIDTH);
        enable <= '1';
        wait_edges(clk, C_DATA_WAIT + 3);
        check_equal(valid, '1', "Valid");
        check_equal(to_integer(result), G_OUTPUT_MIN,
          "Should clamp to " & integer'image(G_OUTPUT_MIN));
        enable <= '0';

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 100 ms);

end architecture;
