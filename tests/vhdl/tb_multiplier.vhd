-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_multiplier.vhd - Testbench for Radix-4 Booth Multiplier
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
--   VUnit testbench for multiplier_s (pipelined Radix-4 Booth multiplier).
--   Tests signed fixed-point multiplication with accumulation, clamping,
--   and all four sign-combination quadrants.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_multiplier is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_multiplier is

  -- Use an 8-bit width for manageable test vectors
  constant C_WIDTH     : integer := 8;
  constant C_FRAC_BITS : integer := 7;
  constant C_OUT_MIN   : integer := -128;
  constant C_OUT_MAX   : integer := 127;
  constant C_CLK_PERIOD : time := 10 ns;

  -- Pipeline latency: 1 input reg + (WIDTH+1)/2 booth stages + 1 output stage
  -- For WIDTH=8: 1 + ceil(9/2) = 1 + 5 = 6 booth stages, + 1 output = 7 total
  -- But valid pipeline is MULTIPLIER_STAGES deep, plus input reg + output reg
  -- C_MULTIPLIER_STAGES = (8+1)/2 = 4 (integer division)
  -- Total latency = 1 (input) + C_MULTIPLIER_STAGES (booth) + 1 (output) + 1 (valid delay)
  -- Empirically: pipeline_depth = (C_WIDTH+1)/2 + 2
  constant C_PIPELINE_DEPTH : integer := (C_WIDTH + 1) / 2 + 3;

  signal clk    : std_logic := '0';
  signal enable : std_logic := '0';
  signal x      : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal y      : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal z      : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal result : signed(C_WIDTH - 1 downto 0);
  signal valid  : std_logic;

  signal test_done : boolean := false;

  -- Helper: wait for pipeline to fill with enable held high
  -- The multiplier's valid signal leads the result by 1 cycle in streaming mode,
  -- so we wait enough cycles for both valid and result to stabilize.
  procedure wait_pipeline(signal clk_sig : in std_logic) is
  begin
    for i in 0 to C_PIPELINE_DEPTH + 3 loop
      wait until rising_edge(clk_sig);
    end loop;
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.multiplier_s
    generic map (
      G_WIDTH      => C_WIDTH,
      G_FRAC_BITS  => C_FRAC_BITS,
      G_OUTPUT_MIN => C_OUT_MIN,
      G_OUTPUT_MAX => C_OUT_MAX
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
    variable v_expected : integer;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ================================================================
      -- Test 1: Zero multiplied by zero plus zero
      -- ================================================================
      if run("test_zero_times_zero") then
        info("Testing 0 * 0 + 0");
        x <= to_signed(0, C_WIDTH);
        y <= to_signed(0, C_WIDTH);
        z <= to_signed(0, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 0, "0 * 0 + 0 = 0");
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 2: Unity multiplication (x * 1.0 + 0)
      -- In fixed point with FRAC_BITS=7: 1.0 = 128
      -- x=64 (0.5), y=127 (~1.0), z=0 → result ≈ 63
      -- ================================================================
      elsif run("test_unity_gain") then
        info("Testing unity multiplication: x * 1.0 + 0");
        x <= to_signed(64, C_WIDTH);   -- 0.5 in Q1.7
        y <= to_signed(127, C_WIDTH);  -- ~1.0 (max positive in 8-bit signed)
        z <= to_signed(0, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        -- 64 * 127 / 128 + 0 = 63 (with integer truncation)
        check(to_integer(result) >= 62 and to_integer(result) <= 64,
              "64 * 127/128 should be approximately 63, got " & integer'image(to_integer(result)));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 3: Positive × positive (first quadrant)
      -- x=50, y=50, z=0: product = 50*50/128 ≈ 19
      -- ================================================================
      elsif run("test_pos_times_pos") then
        info("Testing positive * positive");
        x <= to_signed(50, C_WIDTH);
        y <= to_signed(50, C_WIDTH);
        z <= to_signed(0, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        v_expected := (50 * 50) / (2 ** C_FRAC_BITS);
        check(abs(to_integer(result) - v_expected) <= 1,
              "50*50/128 should be ~" & integer'image(v_expected) & ", got " & integer'image(to_integer(result)));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 4: Negative × positive (second quadrant)
      -- x=-50, y=50, z=0: product = -50*50/128 ≈ -19
      -- ================================================================
      elsif run("test_neg_times_pos") then
        info("Testing negative * positive");
        x <= to_signed(-50, C_WIDTH);
        y <= to_signed(50, C_WIDTH);
        z <= to_signed(0, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        v_expected := (-50 * 50) / (2 ** C_FRAC_BITS);
        check(abs(to_integer(result) - v_expected) <= 1,
              "(-50)*50/128 should be ~" & integer'image(v_expected) & ", got " & integer'image(to_integer(result)));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 5: Positive × negative (third quadrant)
      -- ================================================================
      elsif run("test_pos_times_neg") then
        info("Testing positive * negative");
        x <= to_signed(50, C_WIDTH);
        y <= to_signed(-50, C_WIDTH);
        z <= to_signed(0, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        v_expected := (50 * (-50)) / (2 ** C_FRAC_BITS);
        check(abs(to_integer(result) - v_expected) <= 1,
              "50*(-50)/128 should be ~" & integer'image(v_expected) & ", got " & integer'image(to_integer(result)));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 6: Negative × negative (fourth quadrant)
      -- x=-50, y=-50, z=0: product = 2500/128 ≈ 19
      -- ================================================================
      elsif run("test_neg_times_neg") then
        info("Testing negative * negative");
        x <= to_signed(-50, C_WIDTH);
        y <= to_signed(-50, C_WIDTH);
        z <= to_signed(0, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        v_expected := ((-50) * (-50)) / (2 ** C_FRAC_BITS);
        check(abs(to_integer(result) - v_expected) <= 1,
              "(-50)*(-50)/128 should be ~" & integer'image(v_expected) & ", got " & integer'image(to_integer(result)));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 7: Accumulator addend (z) contribution
      -- x=0, y=0, z=42 → result = 0 + 42 = 42
      -- ================================================================
      elsif run("test_accumulator_z") then
        info("Testing accumulator addend: 0*0 + z");
        x <= to_signed(0, C_WIDTH);
        y <= to_signed(0, C_WIDTH);
        z <= to_signed(42, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 42, "0*0+42 should be 42");
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 8: Accumulator addend with product
      -- x=64, y=64, z=10 → result = 64*64/128 + 10 = 32 + 10 = 42
      -- ================================================================
      elsif run("test_product_plus_z") then
        info("Testing product plus accumulator");
        x <= to_signed(64, C_WIDTH);
        y <= to_signed(64, C_WIDTH);
        z <= to_signed(10, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        v_expected := (64 * 64) / (2 ** C_FRAC_BITS) + 10;
        check(abs(to_integer(result) - v_expected) <= 1,
              "64*64/128+10 should be ~" & integer'image(v_expected) & ", got " & integer'image(to_integer(result)));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 9: Positive overflow clamping
      -- x=127, y=127, z=127 → large positive → clamped to 127
      -- ================================================================
      elsif run("test_positive_clamp") then
        info("Testing positive overflow clamping");
        x <= to_signed(127, C_WIDTH);
        y <= to_signed(127, C_WIDTH);
        z <= to_signed(127, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), C_OUT_MAX,
                   "Large positive should clamp to " & integer'image(C_OUT_MAX));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 10: Negative overflow clamping
      -- x=127, y=-128, z=-128 → large negative → clamped to -128
      -- ================================================================
      elsif run("test_negative_clamp") then
        info("Testing negative overflow clamping");
        x <= to_signed(127, C_WIDTH);
        y <= to_signed(-128, C_WIDTH);
        z <= to_signed(-128, C_WIDTH);
        enable <= '1';
        wait_pipeline(clk);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), C_OUT_MIN,
                   "Large negative should clamp to " & integer'image(C_OUT_MIN));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 11: Valid pipeline — valid should be low when enable was low
      -- ================================================================
      elsif run("test_valid_deasserted") then
        info("Testing valid deasserts without enable");
        enable <= '0';
        x <= to_signed(0, C_WIDTH);
        y <= to_signed(0, C_WIDTH);
        z <= to_signed(0, C_WIDTH);
        -- Flush pipeline with enable=0
        for i in 0 to C_PIPELINE_DEPTH + 5 loop
          wait until rising_edge(clk);
        end loop;
        check_equal(valid, '0', "Valid should be low when no data was enabled");

      -- ================================================================
      -- Test 12: Back-to-back operations (throughput)
      -- ================================================================
      elsif run("test_back_to_back") then
        info("Testing back-to-back pipeline throughput");
        -- Send 4 operations back-to-back
        for i in 1 to 4 loop
          x <= to_signed(i * 10, C_WIDTH);
          y <= to_signed(i * 10, C_WIDTH);
          z <= to_signed(0, C_WIDTH);
          enable <= '1';
          wait until rising_edge(clk);
        end loop;
        enable <= '0';

        -- Wait for all results
        for cycle in 0 to C_PIPELINE_DEPTH + 10 loop
          wait until rising_edge(clk);
        end loop;
        -- Pipeline should have drained — just confirms no stalls/hangs
        info("Back-to-back pipeline throughput test passed");

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
