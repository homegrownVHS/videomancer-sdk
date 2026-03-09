-- Videomancer SDK - VUnit Testbench for sin_cos_full_lut_10x10
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The LUT is purely combinational (no clock). 1024 entries, 10-bit angle,
-- 10-bit signed output, range -511 to +511.
--
-- Tests:
--   1. sin(0) = 0, cos(0) = 511
--   2. sin(256) = 511 (peak), cos(256) = 0
--   3. sin(512) = 0 (half period), cos(512) = -511
--   4. sin(768) = -511 (trough), cos(768) = 0
--   5. Quadrant symmetry: sin(x) = -sin(x+512)
--   6. cos = sin shifted by 256: cos(x) = sin(x+256)
--   7. Monotonic in first quadrant: sin increases from 0 to 256
--   8. Range boundaries: all outputs within [-511, +511]
--   9. Quarter-period symmetry: sin(x) = sin(512-x) for 0<=x<=256

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_sin_cos_lut is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_sin_cos_lut is

  signal angle_in : std_logic_vector(9 downto 0) := (others => '0');
  signal sin_out  : signed(9 downto 0);
  signal cos_out  : signed(9 downto 0);

begin

  dut : entity rtl_lib.sin_cos_full_lut_10x10
    port map (
      angle_in => angle_in,
      sin_out  => sin_out,
      cos_out  => cos_out
    );

  main : process
    variable v_sin_x     : signed(9 downto 0);
    variable v_sin_x_180 : signed(9 downto 0);
    variable v_cos_x     : signed(9 downto 0);
    variable v_sin_x_90  : signed(9 downto 0);
    variable v_prev_sin  : signed(9 downto 0);
    variable v_sin_mirror : signed(9 downto 0);
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ====================================================================
      if run("angle_0_sin_0_cos_max") then
      -- ====================================================================
        angle_in <= std_logic_vector(to_unsigned(0, 10));
        wait for 1 ns;
        check_equal(sin_out, to_signed(0, 10), "sin(0) should be 0");
        check_equal(cos_out, to_signed(511, 10), "cos(0) should be 511");

      -- ====================================================================
      elsif run("angle_256_sin_max_cos_0") then
      -- ====================================================================
        angle_in <= std_logic_vector(to_unsigned(256, 10));
        wait for 1 ns;
        check_equal(sin_out, to_signed(511, 10), "sin(256) should be 511");
        check_equal(cos_out, to_signed(0, 10), "cos(256) should be 0");

      -- ====================================================================
      elsif run("angle_512_sin_0_cos_neg_max") then
      -- ====================================================================
        angle_in <= std_logic_vector(to_unsigned(512, 10));
        wait for 1 ns;
        check_equal(sin_out, to_signed(0, 10), "sin(512) should be 0");
        check_equal(cos_out, to_signed(-511, 10), "cos(512) should be -511");

      -- ====================================================================
      elsif run("angle_768_sin_neg_max_cos_0") then
      -- ====================================================================
        angle_in <= std_logic_vector(to_unsigned(768, 10));
        wait for 1 ns;
        check_equal(sin_out, to_signed(-511, 10), "sin(768) should be -511");
        check_equal(cos_out, to_signed(0, 10), "cos(768) should be 0");

      -- ====================================================================
      elsif run("half_period_antisymmetry") then
      -- ====================================================================
        -- sin(x) = -sin(x + 512) for several angles
        for x in 0 to 15 loop
          angle_in <= std_logic_vector(to_unsigned(x * 16, 10));
          wait for 1 ns;
          v_sin_x := sin_out;

          angle_in <= std_logic_vector(to_unsigned((x * 16 + 512) mod 1024, 10));
          wait for 1 ns;
          v_sin_x_180 := sin_out;

          check_equal(v_sin_x, -v_sin_x_180,
                      "sin(x) should equal -sin(x+512) at x=" &
                      integer'image(x * 16));
        end loop;

      -- ====================================================================
      elsif run("cos_equals_sin_shifted_256") then
      -- ====================================================================
        -- cos(x) = sin(x + 256) for several angles
        for x in 0 to 15 loop
          angle_in <= std_logic_vector(to_unsigned(x * 64, 10));
          wait for 1 ns;
          v_cos_x := cos_out;

          angle_in <= std_logic_vector(to_unsigned((x * 64 + 256) mod 1024, 10));
          wait for 1 ns;
          v_sin_x_90 := sin_out;

          check_equal(v_cos_x, v_sin_x_90,
                      "cos(x) should equal sin(x+256) at x=" &
                      integer'image(x * 64));
        end loop;

      -- ====================================================================
      elsif run("monotonic_first_quadrant") then
      -- ====================================================================
        -- sin should be non-decreasing from angle 0 to 256 (first quadrant)
        angle_in <= std_logic_vector(to_unsigned(0, 10));
        wait for 1 ns;
        v_prev_sin := sin_out;

        for x in 1 to 256 loop
          angle_in <= std_logic_vector(to_unsigned(x, 10));
          wait for 1 ns;
          check(sin_out >= v_prev_sin,
                "sin should be non-decreasing at angle " &
                integer'image(x) & ": prev=" &
                integer'image(to_integer(v_prev_sin)) &
                " curr=" & integer'image(to_integer(sin_out)));
          v_prev_sin := sin_out;
        end loop;

      -- ====================================================================
      elsif run("range_boundaries") then
      -- ====================================================================
        -- All outputs must be within [-511, +511]
        for x in 0 to 1023 loop
          angle_in <= std_logic_vector(to_unsigned(x, 10));
          wait for 1 ns;
          check(to_integer(sin_out) >= -511 and to_integer(sin_out) <= 511,
                "sin out of range at angle " & integer'image(x) &
                ": " & integer'image(to_integer(sin_out)));
          check(to_integer(cos_out) >= -511 and to_integer(cos_out) <= 511,
                "cos out of range at angle " & integer'image(x) &
                ": " & integer'image(to_integer(cos_out)));
        end loop;

      -- ====================================================================
      elsif run("quarter_period_symmetry") then
      -- ====================================================================
        -- sin(x) = sin(512-x) for x in [0, 256] (mirror symmetry)
        for x in 0 to 15 loop
          angle_in <= std_logic_vector(to_unsigned(x * 16, 10));
          wait for 1 ns;
          v_sin_x := sin_out;

          angle_in <= std_logic_vector(to_unsigned(512 - x * 16, 10));
          wait for 1 ns;
          v_sin_mirror := sin_out;

          check_equal(v_sin_x, v_sin_mirror,
                      "sin(x) = sin(512-x) at x=" &
                      integer'image(x * 16));
        end loop;

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;

end architecture;
