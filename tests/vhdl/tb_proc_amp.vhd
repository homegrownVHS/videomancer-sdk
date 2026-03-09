-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_proc_amp.vhd - Testbench for Processing Amplifier
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
--   VUnit testbench for proc_amp_u (unsigned processing amplifier).
--   Tests contrast and brightness adjustments including unity gain,
--   zero contrast, saturation/clamping, and symmetry.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_proc_amp is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_proc_amp is

  constant C_WIDTH      : integer := 10;
  constant C_CLK_PERIOD : time := 10 ns;
  -- proc_amp_u latency: 1 input stage + multiplier_s latency
  -- multiplier_s with G_WIDTH = C_WIDTH+2 = 12:
  --   C_MULTIPLIER_STAGES = (12+1)/2 = 6
  --   total multiplier latency = 1(input) + 6(booth) + 1(output) = 8
  -- proc_amp total = 1(proc input) + 8(multiplier) = 9
  -- Add margin for valid pipeline
  constant C_PIPELINE_DEPTH : integer := 15;

  signal clk        : std_logic := '0';
  signal enable     : std_logic := '0';
  signal a          : unsigned(C_WIDTH - 1 downto 0) := (others => '0');
  signal contrast   : unsigned(C_WIDTH - 1 downto 0) := (others => '0');
  signal brightness : unsigned(C_WIDTH - 1 downto 0) := (others => '0');
  signal result     : unsigned(C_WIDTH - 1 downto 0);
  signal valid      : std_logic;

  signal test_done : boolean := false;

  -- Helper: hold enable high and wait for pipeline to fill.
  -- The proc_amp wraps multiplier_s whose valid leads result by 1 cycle,
  -- so we keep enable high (streaming mode) and wait enough cycles.
  procedure stimulate_and_wait(
    signal clk_sig : in std_logic;
    signal valid_sig : in std_logic;
    signal en_sig : out std_logic
  ) is
  begin
    en_sig <= '1';
    for i in 0 to C_PIPELINE_DEPTH + 3 loop
      wait until rising_edge(clk_sig);
    end loop;
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.proc_amp_u
    generic map (
      G_WIDTH => C_WIDTH
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
    variable v_result_int : integer;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ================================================================
      -- Test 1: Unity gain — contrast=512 (1.0x), brightness=512 (0.0)
      -- Input 512 (midgray) → output should be ~512
      -- Formula: (512 - 512) * 1.0 + 0 + 512 = 512
      -- ================================================================
      if run("test_unity_midgray") then
        info("Testing unity gain at midgray");
        a          <= to_unsigned(512, C_WIDTH);
        contrast   <= to_unsigned(512, C_WIDTH);
        brightness <= to_unsigned(512, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int >= 500 and v_result_int <= 524,
              "Unity at midgray should be ~512, got " & integer'image(v_result_int));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 2: Unity gain at black (input=0)
      -- Formula: (0 - 512) * 1.0 + 0 + 512 = 0 → clamped to 0
      -- ================================================================
      elsif run("test_unity_black") then
        info("Testing unity gain at black");
        a          <= to_unsigned(0, C_WIDTH);
        contrast   <= to_unsigned(512, C_WIDTH);
        brightness <= to_unsigned(512, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int <= 10,
              "Unity at black should be ~0, got " & integer'image(v_result_int));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 3: Unity gain at white (input=1023)
      -- Formula: (1023 - 512) * 1.0 + 0 + 512 = 1023
      -- ================================================================
      elsif run("test_unity_white") then
        info("Testing unity gain at white");
        a          <= to_unsigned(1023, C_WIDTH);
        contrast   <= to_unsigned(512, C_WIDTH);
        brightness <= to_unsigned(512, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int >= 1010,
              "Unity at white should be ~1023, got " & integer'image(v_result_int));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 4: Zero contrast — all inputs should collapse to brightness
      -- contrast=0, brightness=512 → result ≈ 0 (brightness 0.0 maps to 0 shift)
      -- Formula: (input - 512) * 0.0 + 0 + 512 = 512? No:
      --   centered = input - 0.5; * 0 = 0; + (brightness - 0.5) = 0.0; + 0.5 implicit?
      -- Actually: result = 0 * 0 + brightness_offset → clamped
      -- With brightness=512 (0.0 offset), result = 0 → maps near 0 or 512
      -- ================================================================
      elsif run("test_zero_contrast") then
        info("Testing zero contrast collapses output");
        a          <= to_unsigned(800, C_WIDTH);
        contrast   <= to_unsigned(0, C_WIDTH);
        brightness <= to_unsigned(512, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        -- With zero contrast, (input-0.5)*0 = 0, brightness=512 means 0 offset
        -- So result should be near midscale or 0 depending on implementation
        v_result_int := to_integer(result);
        info("Zero contrast result: " & integer'image(v_result_int));
        -- All inputs should produce the same output at zero contrast
        -- Let's test another input to verify they match
        enable <= '0';
        wait until rising_edge(clk);
        a <= to_unsigned(200, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert for second sample");
        check(abs(to_integer(result) - v_result_int) <= 2,
              "Zero contrast: different inputs should yield same output");
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 5: Full brightness (brightness=1023, +0.5 shift)
      -- contrast=512 (unity), brightness=1023 (max positive shift)
      -- Input=0: (0 - 512) * 1.0 + ~511 → ~-1 → clamped 0?
      -- Input=512: (0) * 1.0 + ~511 → ~511 → ~1023
      -- ================================================================
      elsif run("test_max_brightness") then
        info("Testing max brightness offset");
        a          <= to_unsigned(512, C_WIDTH);
        contrast   <= to_unsigned(512, C_WIDTH);
        brightness <= to_unsigned(1023, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int >= 900,
              "Max brightness at midgray should shift high, got " & integer'image(v_result_int));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 6: Min brightness (brightness=0, -0.5 shift)
      -- contrast=512, brightness=0, input=512
      -- (0) * 1.0 + (-0.5) → -0.5 → clamped to 0
      -- ================================================================
      elsif run("test_min_brightness") then
        info("Testing min brightness offset");
        a          <= to_unsigned(512, C_WIDTH);
        contrast   <= to_unsigned(512, C_WIDTH);
        brightness <= to_unsigned(0, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int <= 100,
              "Min brightness at midgray should shift low, got " & integer'image(v_result_int));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 7: Double contrast (contrast=1023 ≈ 2.0x)
      -- input=768 (0.75), contrast=2.0, brightness=0.0
      -- (0.75-0.5)*2.0 + 0.0 = 0.5 → 512
      -- ================================================================
      elsif run("test_double_contrast") then
        info("Testing double contrast");
        a          <= to_unsigned(768, C_WIDTH);
        contrast   <= to_unsigned(1023, C_WIDTH);
        brightness <= to_unsigned(512, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        -- (768-512) * ~2.0 + 0 = 512 → absolute = 512 + 512 shifted internally...
        -- Result should be around 1023 (double contrast pushes 0.75 toward 1.0)
        check(v_result_int >= 900,
              "Double contrast on 768 should push toward max, got " & integer'image(v_result_int));
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 8: Clamping at maximum — large input + high contrast + high brightness
      -- ================================================================
      elsif run("test_clamp_max") then
        info("Testing output clamping at maximum");
        a          <= to_unsigned(1023, C_WIDTH);
        contrast   <= to_unsigned(1023, C_WIDTH);
        brightness <= to_unsigned(1023, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 1023,
                   "Output should clamp to 1023");
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 9: Clamping at minimum — ensure output never goes below 0
      -- ================================================================
      elsif run("test_clamp_min") then
        info("Testing output clamping at minimum");
        a          <= to_unsigned(0, C_WIDTH);
        contrast   <= to_unsigned(1023, C_WIDTH);
        brightness <= to_unsigned(0, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 0,
                   "Output should clamp to 0");
        enable <= '0';
        wait until rising_edge(clk);

      -- ================================================================
      -- Test 10: Valid signal pipeline
      -- ================================================================
      elsif run("test_valid_pipeline") then
        info("Testing valid signal tracks enable");
        enable <= '0';
        for i in 0 to C_PIPELINE_DEPTH + 5 loop
          wait until rising_edge(clk);
        end loop;
        check_equal(valid, '0', "Valid should be low when enable stays low");

      -- ================================================================
      -- Test 11: Symmetry — midgray with contrast=512 and equal offsets
      -- input=256 and input=768 should be equidistant from 512
      -- ================================================================
      elsif run("test_symmetry") then
        info("Testing contrast symmetry around midpoint");
        -- First: input below midpoint
        a          <= to_unsigned(256, C_WIDTH);
        contrast   <= to_unsigned(512, C_WIDTH);
        brightness <= to_unsigned(512, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);

        -- Second: input above midpoint by same amount
        a          <= to_unsigned(768, C_WIDTH);
        stimulate_and_wait(clk, valid, enable);
        check_equal(valid, '1', "Valid should assert");
        -- Both results should be equidistant from 512
        -- |result_low - 512| ≈ |result_high - 512|
        check(abs((512 - v_result_int) - (to_integer(result) - 512)) <= 5,
              "Contrast should be symmetric: low=" & integer'image(v_result_int) &
              " high=" & integer'image(to_integer(result)));
        enable <= '0';
        wait until rising_edge(clk);

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 20 ms);

end architecture;
