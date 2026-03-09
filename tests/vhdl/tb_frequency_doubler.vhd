-- Videomancer SDK - VUnit Testbench for frequency_doubler
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Pipeline: 2 stages (input register + processing register)
--   Stage 1: Register inputs (data_in, bypass, data_enable)
--   Stage 2: Compute folded output or bypass
--   Valid latency: 2 clock edges after data_enable
--
-- Tests:
--   1. Zero input → output 0
--   2. Below midpoint → doubled (scaled ×2)
--   3. At midpoint → folds to max
--   4. Above midpoint → mirrored and doubled
--   5. Maximum input → output 0 (or near)
--   6. Bypass mode passes input unchanged
--   7. Valid pipeline is 2 cycles
--   8. Enable gating — valid tracks data_enable

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_frequency_doubler is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_frequency_doubler is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_WIDTH      : integer := 9;
  constant C_PIPE_DELAY : integer := 2;  -- 2-stage pipeline

  signal clk         : std_logic := '0';
  signal bypass      : std_logic := '0';
  signal data_enable : std_logic := '0';
  signal data_in     : unsigned(C_WIDTH - 1 downto 0) := (others => '0');
  signal data_out    : unsigned(C_WIDTH - 1 downto 0);
  signal data_valid  : std_logic;

begin

  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity rtl_lib.frequency_doubler
    generic map (G_WIDTH => C_WIDTH)
    port map (
      clk         => clk,
      bypass      => bypass,
      data_enable => data_enable,
      data_in     => data_in,
      data_out    => data_out,
      data_valid  => data_valid
    );

  main : process
    -- Wait for pipeline to flush
    procedure pipe_wait is
    begin
      for i in 1 to C_PIPE_DELAY loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      bypass <= '0';
      data_enable <= '0';
      data_in <= (others => '0');
      wait until rising_edge(clk);

      -- ====================================================================
      if run("zero_input_output_zero") then
      -- ====================================================================
        data_in <= to_unsigned(0, C_WIDTH);
        data_enable <= '1';
        bypass <= '0';
        pipe_wait;
        check_equal(data_out, to_unsigned(0, C_WIDTH),
                    "zero input should produce zero output");

      -- ====================================================================
      elsif run("below_midpoint_doubled") then
      -- ====================================================================
        -- Input = 64, midpoint = 256. Result = 64*2 = 128
        data_in <= to_unsigned(64, C_WIDTH);
        data_enable <= '1';
        bypass <= '0';
        pipe_wait;
        check_equal(data_out, to_unsigned(128, C_WIDTH),
                    "input 64 below midpoint should produce 128");

      -- ====================================================================
      elsif run("at_midpoint_produces_max") then
      -- ====================================================================
        -- Input = 255 (just below midpoint 256). Result = 255*2 = 510
        data_in <= to_unsigned(255, C_WIDTH);
        data_enable <= '1';
        bypass <= '0';
        pipe_wait;
        check_equal(data_out, to_unsigned(510, C_WIDTH),
                    "input 255 just below midpoint should produce 510");

      -- ====================================================================
      elsif run("above_midpoint_mirrored") then
      -- ====================================================================
        -- Input = 320, midpoint = 256:
        -- Result = 511 - (320-256)*2 = 511 - 128 = 383
        data_in <= to_unsigned(320, C_WIDTH);
        data_enable <= '1';
        bypass <= '0';
        pipe_wait;
        check_equal(data_out, to_unsigned(383, C_WIDTH),
                    "input 320 above midpoint should mirror to 383");

      -- ====================================================================
      elsif run("max_input") then
      -- ====================================================================
        -- Input = 511 (max), midpoint = 256:
        -- Result = 511 - (511-256)*2 = 511 - 510 = 1
        data_in <= to_unsigned(511, C_WIDTH);
        data_enable <= '1';
        bypass <= '0';
        pipe_wait;
        check_equal(data_out, to_unsigned(1, C_WIDTH),
                    "max input should fold to 1");

      -- ====================================================================
      elsif run("bypass_passes_unchanged") then
      -- ====================================================================
        data_in <= to_unsigned(123, C_WIDTH);
        data_enable <= '1';
        bypass <= '1';
        pipe_wait;
        check_equal(data_out, to_unsigned(123, C_WIDTH),
                    "bypass should pass input unchanged");

      -- ====================================================================
      elsif run("valid_pipeline_2_cycles") then
      -- ====================================================================
        data_enable <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(data_valid, '0', "valid should be 0 when disabled");

        data_enable <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(data_valid, '0', "valid should still be 0 after 1 cycle");
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(data_valid, '1', "valid should be 1 after 2 cycles");

      -- ====================================================================
      elsif run("enable_gating") then
      -- ====================================================================
        data_enable <= '1';
        data_in <= to_unsigned(100, C_WIDTH);
        pipe_wait;
        check_equal(data_valid, '1', "valid when enabled");

        data_enable <= '0';
        pipe_wait;
        check_equal(data_valid, '0', "valid deasserts when disabled (after pipeline)");

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;

end architecture;
