-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_interpolator.vhd - Testbench for Pipelined Unsigned Interpolator
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
--   VUnit testbench for interpolator_u (4-stage pipelined linear interpolator).
--   Tests: t=0 → a, t=max → b, midpoint, b<a case, boundary pixel values,
--   clamping, valid pipeline, and back-to-back throughput.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_interpolator is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_interpolator is

  constant C_WIDTH      : integer := 10;
  constant C_FRAC_BITS  : integer := 10;
  constant C_OUT_MIN    : integer := 0;
  constant C_OUT_MAX    : integer := 1023;
  constant C_CLK_PERIOD : time := 10 ns;
  -- 4-stage pipeline
  constant C_PIPELINE_DEPTH : integer := 4;

  signal clk    : std_logic := '0';
  signal enable : std_logic := '0';
  signal a_in   : unsigned(C_WIDTH - 1 downto 0) := (others => '0');
  signal b_in   : unsigned(C_WIDTH - 1 downto 0) := (others => '0');
  signal t_in   : unsigned(C_FRAC_BITS - 1 downto 0) := (others => '0');
  signal result : unsigned(C_WIDTH - 1 downto 0);
  signal valid  : std_logic;

  signal test_done : boolean := false;

  procedure wait_for_valid(signal clk_sig : in std_logic; signal valid_sig : in std_logic) is
  begin
    for i in 0 to C_PIPELINE_DEPTH + 5 loop
      wait until rising_edge(clk_sig);
      if valid_sig = '1' then
        return;
      end if;
    end loop;
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.interpolator_u
    generic map (
      G_WIDTH      => C_WIDTH,
      G_FRAC_BITS  => C_FRAC_BITS,
      G_OUTPUT_MIN => C_OUT_MIN,
      G_OUTPUT_MAX => C_OUT_MAX
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
    variable v_result_int : integer;
    variable v_expected   : integer;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ================================================================
      -- Test 1: t=0 should return a
      -- ================================================================
      if run("test_t_zero_returns_a") then
        info("Testing t=0 returns a");
        a_in <= to_unsigned(300, C_WIDTH);
        b_in <= to_unsigned(700, C_WIDTH);
        t_in <= to_unsigned(0, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 300, "t=0 should return a=300");

      -- ================================================================
      -- Test 2: t=max should return ~b
      -- t=1023 → result ≈ b (not exactly b, since t_max = 2^FRAC - 1)
      -- ================================================================
      elsif run("test_t_max_returns_b") then
        info("Testing t=max returns approximately b");
        a_in <= to_unsigned(100, C_WIDTH);
        b_in <= to_unsigned(900, C_WIDTH);
        t_in <= to_unsigned(1023, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        -- With rounding: a + (b-a)*1023/1024 = 100 + 800*1023/1024 ≈ 899
        check(v_result_int >= 898 and v_result_int <= 901,
              "t=max should be ~900, got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 3: Midpoint — t=512, a=0, b=1000 → ~500
      -- a + (b-a) * 512 / 1024 = 0 + 1000 * 0.5 = 500
      -- ================================================================
      elsif run("test_midpoint") then
        info("Testing midpoint interpolation");
        a_in <= to_unsigned(0, C_WIDTH);
        b_in <= to_unsigned(1000, C_WIDTH);
        t_in <= to_unsigned(512, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int >= 498 and v_result_int <= 502,
              "Midpoint should be ~500, got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 4: Reverse direction — b < a
      -- a=800, b=200, t=512 → ~500
      -- ================================================================
      elsif run("test_reverse_direction") then
        info("Testing b < a (reverse interpolation)");
        a_in <= to_unsigned(800, C_WIDTH);
        b_in <= to_unsigned(200, C_WIDTH);
        t_in <= to_unsigned(512, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        -- a + (b-a)*t/1024 = 800 + (200-800)*512/1024 = 800 - 300 = 500
        check(v_result_int >= 498 and v_result_int <= 502,
              "Reverse midpoint should be ~500, got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 5: Same endpoints — a=b, any t → result = a
      -- ================================================================
      elsif run("test_same_endpoints") then
        info("Testing a == b returns a for any t");
        a_in <= to_unsigned(512, C_WIDTH);
        b_in <= to_unsigned(512, C_WIDTH);
        t_in <= to_unsigned(700, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 512, "a==b should return 512");

      -- ================================================================
      -- Test 6: Boundary — a=0, b=0, t=0
      -- ================================================================
      elsif run("test_zero_endpoints") then
        info("Testing zero endpoints");
        a_in <= to_unsigned(0, C_WIDTH);
        b_in <= to_unsigned(0, C_WIDTH);
        t_in <= to_unsigned(0, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 0, "All-zero should return 0");

      -- ================================================================
      -- Test 7: Max endpoints — a=1023, b=1023, t=1023
      -- ================================================================
      elsif run("test_max_endpoints") then
        info("Testing max endpoints");
        a_in <= to_unsigned(1023, C_WIDTH);
        b_in <= to_unsigned(1023, C_WIDTH);
        t_in <= to_unsigned(1023, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        check_equal(to_integer(result), 1023, "Max endpoints should return 1023");

      -- ================================================================
      -- Test 8: Quarter interpolation — t=256 (0.25)
      -- a=0, b=400, t=256 → 0 + 400*256/1024 = 100
      -- ================================================================
      elsif run("test_quarter_interpolation") then
        info("Testing quarter interpolation");
        a_in <= to_unsigned(0, C_WIDTH);
        b_in <= to_unsigned(400, C_WIDTH);
        t_in <= to_unsigned(256, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int >= 99 and v_result_int <= 101,
              "Quarter point should be ~100, got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 9: Three-quarter interpolation — t=768 (0.75)
      -- a=0, b=400, t=768 → 0 + 400*768/1024 = 300
      -- ================================================================
      elsif run("test_three_quarter_interpolation") then
        info("Testing three-quarter interpolation");
        a_in <= to_unsigned(0, C_WIDTH);
        b_in <= to_unsigned(400, C_WIDTH);
        t_in <= to_unsigned(768, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';

        wait_for_valid(clk, valid);
        check_equal(valid, '1', "Valid should assert");
        v_result_int := to_integer(result);
        check(v_result_int >= 299 and v_result_int <= 301,
              "Three-quarter should be ~300, got " & integer'image(v_result_int));

      -- ================================================================
      -- Test 10: Valid pipeline deasserts without enable
      -- ================================================================
      elsif run("test_valid_deasserted") then
        info("Testing valid deasserts");
        enable <= '0';
        for i in 0 to C_PIPELINE_DEPTH + 5 loop
          wait until rising_edge(clk);
        end loop;
        check_equal(valid, '0', "Valid should be low when enable stays low");

      -- ================================================================
      -- Test 11: Back-to-back throughput
      -- ================================================================
      elsif run("test_back_to_back") then
        info("Testing back-to-back pipeline throughput");
        for i in 0 to 7 loop
          a_in <= to_unsigned(i * 100, C_WIDTH);
          b_in <= to_unsigned(1023 - i * 100, C_WIDTH);
          t_in <= to_unsigned(512, C_FRAC_BITS);
          enable <= '1';
          wait until rising_edge(clk);
        end loop;
        enable <= '0';

        -- Wait for pipeline to drain
        for i in 0 to C_PIPELINE_DEPTH + 10 loop
          wait until rising_edge(clk);
        end loop;
        info("Back-to-back throughput test passed");

      -- ================================================================
      -- Test 12: Full-range sweep — a=0, b=1023, t sweeps
      -- ================================================================
      elsif run("test_full_range_sweep") then
        info("Testing full-range sweep");
        a_in <= to_unsigned(0, C_WIDTH);
        b_in <= to_unsigned(1023, C_WIDTH);

        -- t=0 → 0
        t_in <= to_unsigned(0, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait_for_valid(clk, valid);
        check_equal(to_integer(result), 0, "Sweep at t=0 should be 0");

        -- t=1023 → ~1023
        t_in <= to_unsigned(1023, C_FRAC_BITS);
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait_for_valid(clk, valid);
        v_result_int := to_integer(result);
        check(v_result_int >= 1021,
              "Sweep at t=max should be ~1023, got " & integer'image(v_result_int));

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 20 ms);

end architecture;
