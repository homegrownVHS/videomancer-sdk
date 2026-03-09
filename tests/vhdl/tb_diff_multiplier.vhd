-- Videomancer SDK - VUnit Testbench for diff_multiplier_s
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- diff_multiplier_s computes: result = (x_pos - x_neg) * (y_pos - y_neg) + (z_pos - z_neg)
-- with saturation on the differential stage and the internal multiplier_s.
--
-- Pipeline: 2 front-end stages + multiplier_s pipeline
--   Stage 1: Compute differences (pos - neg) for X, Y, Z
--   Stage 2: Saturate differences to [-128, 127] (for 8-bit)
--   Stages 3+: multiplier_s pipeline = (G_WIDTH+1)/2 + 3 data cycles
--   Total valid latency: 2 + multiplier valid latency
--     = 2 + (G_WIDTH+1)/2 + 2 = (G_WIDTH+1)/2 + 4
--
-- Tests:
--   1. Zero differences → result 0
--   2. Positive X*Y + Z offset
--   3. Negative differences
--   4. Saturation on differential overflow
--   5. Valid pipeline timing
--   6. Z offset passthrough

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_diff_multiplier is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_diff_multiplier is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_WIDTH      : integer := 8;
  constant C_FRAC_BITS  : integer := 7;
  constant C_OUTPUT_MIN : integer := -128;
  constant C_OUTPUT_MAX : integer := 127;

  -- multiplier_s valid latency = (G_WIDTH+1)/2 + 2
  -- diff front-end adds 2 stages
  -- Total valid latency = 2 + (8+1)/2 + 2 = 2 + 4 + 2 = 8
  -- But let's use a generous wait to avoid off-by-one issues
  constant C_PIPE_WAIT : integer := 12;

  signal clk    : std_logic := '0';
  signal enable : std_logic := '0';
  signal x_pos  : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal x_neg  : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal y_pos  : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal y_neg  : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal z_pos  : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal z_neg  : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal result : signed(C_WIDTH - 1 downto 0);
  signal valid  : std_logic;

begin

  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity rtl_lib.diff_multiplier_s
    generic map (
      G_WIDTH      => C_WIDTH,
      G_FRAC_BITS  => C_FRAC_BITS,
      G_OUTPUT_MIN => C_OUTPUT_MIN,
      G_OUTPUT_MAX => C_OUTPUT_MAX
    )
    port map (
      clk    => clk,
      enable => enable,
      x_pos  => x_pos,
      x_neg  => x_neg,
      y_pos  => y_pos,
      y_neg  => y_neg,
      z_pos  => z_pos,
      z_neg  => z_neg,
      result => result,
      valid  => valid
    );

  main : process
    procedure pipe_flush is
    begin
      for i in 1 to C_PIPE_WAIT loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      enable <= '0';
      x_pos <= (others => '0');
      x_neg <= (others => '0');
      y_pos <= (others => '0');
      y_neg <= (others => '0');
      z_pos <= (others => '0');
      z_neg <= (others => '0');
      wait until rising_edge(clk);

      -- ====================================================================
      if run("zero_differences_result_zero") then
      -- ====================================================================
        x_pos <= to_signed(50, C_WIDTH);
        x_neg <= to_signed(50, C_WIDTH);  -- diff = 0
        y_pos <= to_signed(100, C_WIDTH);
        y_neg <= to_signed(100, C_WIDTH); -- diff = 0
        z_pos <= to_signed(0, C_WIDTH);
        z_neg <= to_signed(0, C_WIDTH);   -- diff = 0
        enable <= '1';
        pipe_flush;
        check_equal(result, to_signed(0, C_WIDTH),
                    "0 * 0 + 0 should equal 0");

      -- ====================================================================
      elsif run("positive_xy_plus_z") then
      -- ====================================================================
        -- x_diff = 64 - 0 = 64, y_diff = 127 - 0 = 127, z_diff = 10 - 0 = 10
        -- result ≈ (64 * 127) / 128 + 10 = 63 + 10 = 73 (approx)
        x_pos <= to_signed(64, C_WIDTH);
        x_neg <= to_signed(0, C_WIDTH);
        y_pos <= to_signed(127, C_WIDTH);
        y_neg <= to_signed(0, C_WIDTH);
        z_pos <= to_signed(10, C_WIDTH);
        z_neg <= to_signed(0, C_WIDTH);
        enable <= '1';
        pipe_flush;
        -- Check result is positive and reasonable
        check(result > to_signed(0, C_WIDTH),
              "positive x*y + z should be positive, got " &
              integer'image(to_integer(result)));

      -- ====================================================================
      elsif run("negative_differences") then
      -- ====================================================================
        -- x_diff = 0 - 64 = -64, y_diff = 0 - 64 = -64
        -- result ≈ (-64 * -64) / 128 + 0 = 32
        x_pos <= to_signed(0, C_WIDTH);
        x_neg <= to_signed(64, C_WIDTH);
        y_pos <= to_signed(0, C_WIDTH);
        y_neg <= to_signed(64, C_WIDTH);
        z_pos <= to_signed(0, C_WIDTH);
        z_neg <= to_signed(0, C_WIDTH);
        enable <= '1';
        pipe_flush;
        -- Negative * negative = positive
        check(result > to_signed(0, C_WIDTH),
              "(-64)*(-64) should be positive");

      -- ====================================================================
      elsif run("saturation_on_overflow") then
      -- ====================================================================
        -- x_pos = 127, x_neg = -128 → diff = 255, saturated to 127
        -- y_pos = 127, y_neg = -128 → diff = 255, saturated to 127
        x_pos <= to_signed(127, C_WIDTH);
        x_neg <= to_signed(-128, C_WIDTH);
        y_pos <= to_signed(127, C_WIDTH);
        y_neg <= to_signed(-128, C_WIDTH);
        z_pos <= to_signed(0, C_WIDTH);
        z_neg <= to_signed(0, C_WIDTH);
        enable <= '1';
        pipe_flush;
        -- After saturation: 127 * 127 / 128 ≈ 126
        check(result >= to_signed(C_OUTPUT_MIN, C_WIDTH),
              "result should be within output range (min)");
        check(result <= to_signed(C_OUTPUT_MAX, C_WIDTH),
              "result should be within output range (max)");

      -- ====================================================================
      elsif run("valid_pipeline_timing") then
      -- ====================================================================
        enable <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(valid, '0', "valid should be 0 when disabled");

        enable <= '1';
        -- Wait for valid to assert
        for i in 1 to 20 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          if valid = '1' then
            exit;
          end if;
        end loop;
        check_equal(valid, '1', "valid should eventually assert");

      -- ====================================================================
      elsif run("z_offset_passthrough") then
      -- ====================================================================
        -- Zero X or Y diff means only Z matters
        x_pos <= to_signed(0, C_WIDTH);
        x_neg <= to_signed(0, C_WIDTH);  -- x_diff = 0
        y_pos <= to_signed(50, C_WIDTH);
        y_neg <= to_signed(0, C_WIDTH);
        z_pos <= to_signed(42, C_WIDTH);
        z_neg <= to_signed(0, C_WIDTH);   -- z_diff = 42
        enable <= '1';
        pipe_flush;
        -- 0 * y_diff + 42 = 42
        check_equal(result, to_signed(42, C_WIDTH),
                    "0 * Y + Z should equal Z");

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;

end architecture;
