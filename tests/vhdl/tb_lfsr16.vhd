-- Videomancer SDK - VUnit Testbench for lfsr16 (16-bit maximal-length LFSR)
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tests:
--   1. Default output is x"ACE1"
--   2. Load sets seed value
--   3. Zero seed lockup prevention loads x"ACE1"
--   4. Enable advances state
--   5. Hold (enable=0) freezes state
--   6. Non-repeating output over 100 cycles
--   7. Load priority over enable (load takes precedence)
--   8. Resume after hold continues from frozen state

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_lfsr16 is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_lfsr16 is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk       : std_logic := '0';
  signal enable    : std_logic := '0';
  signal seed      : std_logic_vector(15 downto 0) := (others => '0');
  signal load      : std_logic := '0';
  signal q         : std_logic_vector(15 downto 0);
  signal test_done : std_logic := '0';

begin

  clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

  dut : entity rtl_lib.lfsr16
    port map (
      clk    => clk,
      enable => enable,
      seed   => seed,
      load   => load,
      q      => q
    );

  main : process
    variable v_prev     : std_logic_vector(15 downto 0);
    variable v_all_same : boolean;
    variable v_held     : std_logic_vector(15 downto 0);
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      enable <= '0';
      load <= '0';
      seed <= (others => '0');
      wait until rising_edge(clk);

      -- ====================================================================
      if run("default_output") then
      -- ====================================================================
        wait for 1 ns;
        check_equal(q, std_logic_vector'(x"ACE1"),
                    "default output should be x""ACE1""");

      -- ====================================================================
      elsif run("load_sets_seed") then
      -- ====================================================================
        seed <= x"1234";
        load <= '1';
        wait until rising_edge(clk);
        load <= '0';
        wait for 1 ns;
        check_equal(q, std_logic_vector'(x"1234"),
                    "output should equal loaded seed");

      -- ====================================================================
      elsif run("zero_seed_lockup_prevention") then
      -- ====================================================================
        seed <= x"0000";
        load <= '1';
        wait until rising_edge(clk);
        load <= '0';
        wait for 1 ns;
        check_equal(q, std_logic_vector'(x"ACE1"),
                    "zero seed should be replaced by x""ACE1""");

      -- ====================================================================
      elsif run("enable_advances_state") then
      -- ====================================================================
        seed <= x"ACE1";
        load <= '1';
        wait until rising_edge(clk);
        load <= '0';
        wait for 1 ns;
        v_prev := q;

        enable <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check(q /= v_prev, "state should advance after enable");

      -- ====================================================================
      elsif run("hold_freezes_state") then
      -- ====================================================================
        seed <= x"BEEF";
        load <= '1';
        wait until rising_edge(clk);
        load <= '0';
        enable <= '1';
        for i in 0 to 4 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        v_prev := q;

        enable <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(q, v_prev, "should freeze with enable=0");

      -- ====================================================================
      elsif run("non_repeating_over_100_cycles") then
      -- ====================================================================
        seed <= x"ACE1";
        load <= '1';
        wait until rising_edge(clk);
        load <= '0';
        enable <= '1';

        v_prev := q;
        v_all_same := true;
        for i in 0 to 99 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          if q /= v_prev then
            v_all_same := false;
          end if;
          v_prev := q;
        end loop;
        check(not v_all_same,
              "should produce changing values over 100 cycles");

      -- ====================================================================
      elsif run("load_priority_over_enable") then
      -- ====================================================================
        -- When load and enable are both asserted, load takes precedence
        seed <= x"DEAD";
        load <= '1';
        enable <= '1';
        wait until rising_edge(clk);
        load <= '0';
        enable <= '0';
        wait for 1 ns;
        check_equal(q, std_logic_vector'(x"DEAD"),
                    "load should take priority over enable");

      -- ====================================================================
      elsif run("resume_after_hold") then
      -- ====================================================================
        -- Verify that re-enabling continues from the frozen state
        seed <= x"1111";
        load <= '1';
        wait until rising_edge(clk);
        load <= '0';
        enable <= '1';
        -- Advance 5 cycles
        for i in 0 to 4 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        v_held := q;

        -- Freeze for 3 cycles
        enable <= '0';
        for i in 0 to 2 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_equal(q, v_held, "should be frozen");

        -- Resume and verify it advances from the held state
        enable <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check(q /= v_held, "should advance from held state after re-enable");

      end if;
    end loop;

    test_done <= '1';
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
