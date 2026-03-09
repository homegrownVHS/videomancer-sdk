-- Videomancer SDK - VUnit Generic-Parameterized Testbench for frequency_doubler
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Sweeps frequency_doubler across multiple G_WIDTH configurations to verify
-- midpoint folding, bypass mode, valid pipeline, and exact pipeline latency.
--
-- frequency_doubler folds input at midpoint (2^(W-1)):
--   input < midpoint: output = input * 2
--   input >= midpoint: output = (max - input) * 2
--
-- Pipeline Latency (verified by test_valid_latency_exact):
--   data_out and data_valid: 2 clock cycles from data_in/data_enable
--   Constant depth independent of G_WIDTH.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_freq_doubler_generics is
  generic (
    runner_cfg : string;
    G_WIDTH    : integer := 9
  );
end entity;

architecture tb of tb_freq_doubler_generics is
  constant C_CLK_PERIOD : time := 10 ns;
  -- Exact pipeline depth: 1 input reg + 1 compute = 2 cycles
  constant C_PIPE_DEPTH : integer := 2;

  signal clk         : std_logic := '0';
  signal bypass      : std_logic := '0';
  signal data_enable : std_logic := '0';
  signal data_in     : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal data_out    : unsigned(G_WIDTH - 1 downto 0);
  signal data_valid  : std_logic;

  signal test_done : boolean := false;

  constant C_MIDPOINT : integer := 2 ** (G_WIDTH - 1);
  constant C_MAXIMUM  : integer := 2 ** G_WIDTH - 1;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.frequency_doubler
    generic map (G_WIDTH => G_WIDTH)
    port map (
      clk         => clk,
      bypass      => bypass,
      data_enable => data_enable,
      data_in     => data_in,
      data_out    => data_out,
      data_valid  => data_valid
    );

  main : process
    procedure clk_wait(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    -- Flush pipeline until valid is guaranteed low
    procedure flush is
    begin
      data_enable <= '0';
      bypass      <= '0';
      data_in     <= (others => '0');
      clk_wait(C_PIPE_DEPTH + 4);
    end procedure;

    -- Apply input and wait for exact pipeline latency
    procedure apply(val : integer; byp : std_logic := '0') is
    begin
      bypass      <= byp;
      data_enable <= '1';
      data_in     <= to_unsigned(val, G_WIDTH);
      clk_wait(C_PIPE_DEPTH + 1);
    end procedure;

    variable v_count : integer;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset
      flush;

      -- ==================================================================
      if run("test_valid_latency_exact") then
      -- ==================================================================
        -- Measure exact cycle count from enable to valid
        info("Verifying valid latency = " & integer'image(C_PIPE_DEPTH) &
             " cycles for G_WIDTH=" & integer'image(G_WIDTH));
        flush;

        data_enable <= '1';
        data_in     <= to_unsigned(1, G_WIDTH);
        wait until rising_edge(clk);  -- Sampling edge
        data_enable <= '0';

        v_count := 0;
        for i in 1 to C_PIPE_DEPTH + 10 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if data_valid = '1' then
            exit;
          end if;
        end loop;

        check_equal(data_valid, '1', "Valid should have asserted");
        check_equal(v_count, C_PIPE_DEPTH,
          "Valid latency should be exactly " & integer'image(C_PIPE_DEPTH) &
          " cycles (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_single_pulse_valid_count") then
      -- ==================================================================
        -- 1 enable pulse produces exactly 1 valid cycle
        flush;

        data_enable <= '1';
        data_in     <= to_unsigned(1, G_WIDTH);
        wait until rising_edge(clk);
        data_enable <= '0';

        v_count := 0;
        for i in 1 to C_PIPE_DEPTH + 10 loop
          wait until rising_edge(clk);
          if data_valid = '1' then
            v_count := v_count + 1;
          end if;
        end loop;

        check_equal(v_count, 1,
          "Exactly 1 valid cycle from 1 enable pulse (w=" &
          integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_streaming_valid_sustained") then
      -- ==================================================================
        -- Valid stays high while enable is continuously high
        flush;

        data_enable <= '1';
        data_in     <= to_unsigned(42, G_WIDTH);
        clk_wait(C_PIPE_DEPTH + 1);
        check_equal(data_valid, '1', "Valid after latency");

        -- Verify sustained for 10 more cycles
        for i in 0 to 9 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(data_valid, '1',
            "Valid sustained, cycle " & integer'image(i));
        end loop;
        data_enable <= '0';

      -- ==================================================================
      elsif run("zero_input_doubles_to_zero") then
      -- ==================================================================
        apply(0);
        check_equal(data_valid, '1',
                    "valid asserted (w=" & integer'image(G_WIDTH) & ")");
        check_equal(data_out, to_unsigned(0, G_WIDTH),
                    "zero doubles to zero (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("quarter_doubles_to_half") then
      -- ==================================================================
        apply(C_MIDPOINT / 2);
        check_equal(data_valid, '1', "valid");
        check(abs(to_integer(data_out) - C_MIDPOINT) <= 1,
              "quarter doubles to midpoint (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("midpoint_folds_to_max") then
      -- ==================================================================
        apply(C_MIDPOINT);
        check_equal(data_valid, '1', "valid");
        check(to_integer(data_out) >= C_MIDPOINT,
              "midpoint folds to high value (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("max_input_folds_to_zero") then
      -- ==================================================================
        apply(C_MAXIMUM);
        check_equal(data_valid, '1', "valid");
        check(to_integer(data_out) <= 2,
              "max folds back to ~zero (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("bypass_passes_through") then
      -- ==================================================================
        apply(C_MIDPOINT / 2, '1');
        check_equal(data_valid, '1', "valid in bypass");
        check_equal(data_out, to_unsigned(C_MIDPOINT / 2, G_WIDTH),
                    "bypass passes input (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_back_to_back_streaming") then
      -- ==================================================================
        -- Stream different values and verify continuous valid output
        flush;

        data_enable <= '1';
        -- Wait for pipeline to fill
        clk_wait(C_PIPE_DEPTH + 1);

        -- Stream 20 different values
        for i in 0 to 19 loop
          data_in <= to_unsigned((i * 17) mod (C_MAXIMUM + 1), G_WIDTH);
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(data_valid, '1',
            "Valid sustained during streaming, cycle " & integer'image(i));
        end loop;
        data_enable <= '0';

      -- ==================================================================
      elsif run("test_enable_gap_recovery") then
      -- ==================================================================
        -- Enable, disable, re-enable and verify valid tracks correctly
        flush;

        -- Fill pipeline
        data_enable <= '1';
        data_in     <= to_unsigned(42, G_WIDTH);
        clk_wait(C_PIPE_DEPTH + 1);
        check_equal(data_valid, '1', "Valid before gap");

        -- Create gap
        data_enable <= '0';
        clk_wait(C_PIPE_DEPTH + 1);
        check_equal(data_valid, '0', "Valid low during gap");

        -- Re-enable
        data_enable <= '1';
        clk_wait(C_PIPE_DEPTH + 1);
        check_equal(data_valid, '1', "Valid restored after gap");
        data_enable <= '0';

      end if;
    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
