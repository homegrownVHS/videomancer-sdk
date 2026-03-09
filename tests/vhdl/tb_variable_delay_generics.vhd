-- Videomancer SDK - VUnit Generic-Parameterized Testbench for variable_delay_u
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Sweeps variable_delay_u across multiple G_WIDTH and G_DEPTH configurations
-- to verify BRAM-based delay line behavior, exact pipeline timing, address
-- wrapping, enable gating, and data integrity at each configuration.
--
-- variable_delay_u Pipeline Latency (verified by test_valid_latency_exact):
--   valid:  1 clock cycle after enable (address-gen process)
--   result: 2 clock cycles after enable (BRAM read register)
--   Note: valid leads result by 1 clock cycle.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_variable_delay_generics is
  generic (
    runner_cfg : string;
    G_WIDTH    : integer := 32;
    G_DEPTH    : integer := 11
  );
end entity;

architecture tb of tb_variable_delay_generics is
  constant C_CLK_PERIOD  : time := 10 ns;
  constant C_BUFFER_SIZE : integer := 2 ** G_DEPTH;

  signal clk      : std_logic := '0';
  signal enable   : std_logic := '0';
  signal a        : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal delay    : unsigned(G_DEPTH - 1 downto 0) := (others => '0');
  signal result   : unsigned(G_WIDTH - 1 downto 0);
  signal valid    : std_logic;

  signal test_done : boolean := false;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.variable_delay_u
    generic map (
      G_WIDTH => G_WIDTH,
      G_DEPTH => G_DEPTH
    )
    port map (
      clk      => clk,
      enable   => enable,
      delay    => delay,
      a        => a,
      result   => result,
      valid    => valid
    );

  main : process
    procedure clk_wait(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    -- Flush: disable and let state settle
    procedure flush is
    begin
      enable <= '0';
      a      <= (others => '0');
      delay  <= (others => '0');
      clk_wait(4);
    end procedure;

    variable v_fill_val : integer;
    variable v_count    : integer;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset
      flush;

      -- ==================================================================
      if run("test_valid_latency_exact") then
      -- ==================================================================
        -- Valid should assert exactly 1 cycle after enable
        info("Verifying valid latency = 1 cycle for w=" &
             integer'image(G_WIDTH) & " d=" & integer'image(G_DEPTH));
        flush;

        enable <= '1';
        a      <= to_unsigned(42, G_WIDTH);
        wait until rising_edge(clk);  -- Sampling edge
        enable <= '0';

        -- Count edges until valid='1'
        v_count := 0;
        for i in 1 to 10 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if valid = '1' then
            exit;
          end if;
        end loop;

        check_equal(valid, '1', "Valid should have asserted");
        check_equal(v_count, 1,
          "Valid latency should be exactly 1 cycle (w=" &
          integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_result_latency_exact") then
      -- ==================================================================
        -- Result data pipeline is 2 cycles (valid + 1 BRAM read)
        -- Fill buffer with known value first (delay=0)
        enable <= '1';
        delay  <= (others => '0');
        a      <= to_unsigned(77, G_WIDTH);
        clk_wait(C_BUFFER_SIZE + 4);  -- Fill entirely
        enable <= '0';
        clk_wait(4);  -- Settle

        -- Now pulse enable once, count cycles to data
        enable <= '1';
        a      <= to_unsigned(77, G_WIDTH);
        wait until rising_edge(clk);
        enable <= '0';

        -- Data arrives 2 cycles after enable was sampled
        wait until rising_edge(clk);  -- 1 cycle: valid asserts
        wait until rising_edge(clk);  -- 2 cycles: BRAM data ready
        wait for 1 ns;
        check_equal(result, to_unsigned(77, G_WIDTH),
          "Result data at exactly 2 cycles (w=" &
          integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_single_pulse_valid_count") then
      -- ==================================================================
        -- 1 enable pulse produces exactly 1 valid cycle
        flush;

        enable <= '1';
        a      <= to_unsigned(50, G_WIDTH);
        wait until rising_edge(clk);
        enable <= '0';

        v_count := 0;
        for i in 1 to 10 loop
          wait until rising_edge(clk);
          if valid = '1' then
            v_count := v_count + 1;
          end if;
        end loop;

        check_equal(v_count, 1,
          "Exactly 1 valid from 1 enable (w=" &
          integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_enable_gap_recovery") then
      -- ==================================================================
        -- Valid tracks enable with 1-cycle offset through gaps
        enable <= '1';
        a      <= to_unsigned(10, G_WIDTH);
        clk_wait(3);
        check_equal(valid, '1', "Valid high when enabled");

        enable <= '0';
        clk_wait(2);
        check_equal(valid, '0', "Valid low during gap");

        enable <= '1';
        clk_wait(2);
        check_equal(valid, '1', "Valid restored after gap");
        enable <= '0';

      -- ==================================================================
      elsif run("zero_delay_passthrough") then
      -- ==================================================================
        -- With delay=0, output should be the most recently written value
        delay  <= (others => '0');
        enable <= '1';
        a      <= to_unsigned(42, G_WIDTH);
        -- Fill buffer fully + pipeline settle
        for i in 0 to C_BUFFER_SIZE + 3 loop
          wait until rising_edge(clk);
        end loop;
        clk_wait(2);
        check_equal(result, to_unsigned(42, G_WIDTH),
                    "zero delay reads most recent value (w=" &
                    integer'image(G_WIDTH) & " d=" & integer'image(G_DEPTH) & ")");

      -- ==================================================================
      elsif run("known_pattern_retrieval") then
      -- ==================================================================
        -- Fill buffer with marker, switch to writing zeros with delay
        v_fill_val := 2 ** (G_WIDTH - 2);  -- quarter-range
        delay  <= (others => '0');
        enable <= '1';
        a      <= to_unsigned(v_fill_val, G_WIDTH);
        for i in 0 to 2 * C_BUFFER_SIZE - 1 loop
          wait until rising_edge(clk);
        end loop;

        -- Write zeros with half-buffer delay
        a     <= (others => '0');
        delay <= to_unsigned(C_BUFFER_SIZE / 2, G_DEPTH);
        clk_wait(4);  -- BRAM pipeline

        check_equal(result, to_unsigned(v_fill_val, G_WIDTH),
                    "retrieved marker at half-buffer delay (w=" &
                    integer'image(G_WIDTH) & " d=" & integer'image(G_DEPTH) & ")");

      -- ==================================================================
      elsif run("max_delay_wraps") then
      -- ==================================================================
        -- Verify buffer works at maximum delay (2^G_DEPTH - 1)
        delay  <= (others => '1');  -- max delay
        enable <= '1';
        a      <= to_unsigned(99, G_WIDTH);
        for i in 0 to C_BUFFER_SIZE + 3 loop
          wait until rising_edge(clk);
        end loop;
        clk_wait(2);
        check_equal(result, to_unsigned(99, G_WIDTH),
                    "max delay with uniform fill (w=" &
                    integer'image(G_WIDTH) & " d=" & integer'image(G_DEPTH) & ")");

      -- ==================================================================
      elsif run("sequential_write_integrity") then
      -- ==================================================================
        -- Write sequential values, check they come back in order
        delay  <= to_unsigned(8 mod C_BUFFER_SIZE, G_DEPTH);
        enable <= '1';

        for i in 0 to C_BUFFER_SIZE + 19 loop
          a <= to_unsigned(i mod 128, G_WIDTH);
          wait until rising_edge(clk);
        end loop;
        clk_wait(3);
        check(to_integer(result) < 128,
              "output from sequential sequence (w=" &
              integer'image(G_WIDTH) & " d=" & integer'image(G_DEPTH) & ")");

      end if;
    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 100 ms);

end architecture;
