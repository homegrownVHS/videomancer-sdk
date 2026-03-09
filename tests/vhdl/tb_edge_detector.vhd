-- Videomancer SDK - VUnit Testbench for edge_detector
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tests:
--   1.  Initial state -- outputs are 0 after reset
--   2.  Rising edge detection -- single-cycle pulse on 0->1 transition
--   3.  Falling edge detection -- single-cycle pulse on 1->0 transition
--   4.  No edge (stable high) -- no pulses
--   5.  No edge (stable low) -- no pulses
--   6.  Registered output b tracks input with 1-cycle delay
--   7.  Rapid toggle -- alternating 0/1 produces alternating rise/fall pulses
--   8.  b latency exact -- b follows a in exactly 1 clock cycle (edge-counted)
--   9.  Mutual exclusion -- rising and falling never both '1' simultaneously
--  10.  Long idle then edge -- edge detected after 50 idle cycles
--  11.  Consecutive same-direction edges -- two rising edges separated by gap

library ieee;
use ieee.std_logic_1164.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_edge_detector is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_edge_detector is
  constant C_CLK_PERIOD : time := 10 ns;
  signal clk       : std_logic := '0';
  signal a         : std_logic := '0';
  signal b         : std_logic;
  signal rising    : std_logic;
  signal falling   : std_logic;
  signal test_done : std_logic := '0';

begin

  clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

  dut : entity rtl_lib.edge_detector
    port map (
      clk     => clk,
      a       => a,
      b       => b,
      rising  => rising,
      falling => falling
    );

  main : process
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset inputs between tests
      a <= '0';
      wait until rising_edge(clk);
      wait until rising_edge(clk);

      -- ====================================================================
      if run("initial_state") then
      -- ====================================================================
        -- After two clocks with a=0, a_ff=0 -> no edges
        wait for 1 ns;
        check_equal(rising, '0', "rising should be 0 initially");
        check_equal(falling, '0', "falling should be 0 initially");
        check_equal(b, '0', "b should be 0 initially");

      -- ====================================================================
      elsif run("rising_edge_detection") then
      -- ====================================================================
        a <= '1';
        -- Combinational: a='1', a_ff='0' -> rising='1'
        wait for 1 ns;
        check_equal(rising, '1', "rising pulse expected on 0->1");
        check_equal(falling, '0', "no falling on 0->1");
        -- After the next clock edge, a_ff='1', a='1' -> no edge
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(rising, '0', "rising should clear after one cycle");

      -- ====================================================================
      elsif run("falling_edge_detection") then
      -- ====================================================================
        a <= '1';
        wait until rising_edge(clk);  -- a_ff = '1'
        wait until rising_edge(clk);  -- a_ff definitely '1'
        a <= '0';
        wait for 1 ns;
        check_equal(falling, '1', "falling pulse expected on 1->0");
        check_equal(rising, '0', "no rising on 1->0");
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(falling, '0', "falling should clear after one cycle");

      -- ====================================================================
      elsif run("no_edge_stable_high") then
      -- ====================================================================
        a <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);  -- a_ff = '1', a = '1'
        wait until rising_edge(clk);  -- still '1'
        wait for 1 ns;
        check_equal(rising, '0', "no rising on stable high");
        check_equal(falling, '0', "no falling on stable high");

      -- ====================================================================
      elsif run("no_edge_stable_low") then
      -- ====================================================================
        -- a already '0' from reset
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(rising, '0', "no rising on stable low");
        check_equal(falling, '0', "no falling on stable low");

      -- ====================================================================
      elsif run("registered_output_b_delay") then
      -- ====================================================================
        -- b should be a delayed copy of a by 1 clock
        wait for 1 ns;
        check_equal(b, '0', "b=0 when a was 0");
        a <= '1';
        wait for 1 ns;
        check_equal(b, '0', "b still 0 before clock");
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(b, '1', "b=1 one cycle after a=1");
        a <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(b, '0', "b=0 one cycle after a=0");

      -- ====================================================================
      elsif run("rapid_toggle") then
      -- ====================================================================
        -- Toggle 0 -> 1: combinational rising before clock captures
        a <= '1';
        wait for 1 ns;
        check_equal(rising, '1', "rising on toggle 0->1");
        check_equal(falling, '0', "no falling on 0->1");

        -- Clock captures a='1' into a_ff
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(rising, '0', "rising cleared after capture");

        -- Toggle 1 -> 0: combinational falling before clock captures
        a <= '0';
        wait for 1 ns;
        check_equal(falling, '1', "falling on toggle 1->0");
        check_equal(rising, '0', "no rising on 1->0");

        -- Clock captures a='0' into a_ff
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(falling, '0', "falling cleared after capture");

      -- ====================================================================
      elsif run("test_b_latency_exact") then
      -- ====================================================================
        -- Verify b follows a with exactly 1 clock cycle latency using
        -- precise edge counting. Drive a='1', then count rising edges
        -- until b='1'.
        a <= '1';
        -- Edge 1: a_ff latches '1' -> b='1' after this edge
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(b, '1', "b should be '1' after exactly 1 clock edge");

        -- Now drive a='0', verify b takes exactly 1 more edge
        a <= '0';
        wait for 1 ns;
        check_equal(b, '1', "b still '1' before next edge");
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(b, '0', "b should be '0' after exactly 1 clock edge");

      -- ====================================================================
      elsif run("test_mutual_exclusion") then
      -- ====================================================================
        -- Verify rising and falling can never both be '1' simultaneously
        -- across a stream of transitions
        for i in 0 to 19 loop
          -- Toggle a
          if (i mod 2) = 0 then
            a <= '1';
          else
            a <= '0';
          end if;
          wait for 1 ns;
          check(not (rising = '1' and falling = '1'),
                "rising/falling mutual exclusion at step " &
                integer'image(i));
          wait until rising_edge(clk);
          wait for 1 ns;
          check(not (rising = '1' and falling = '1'),
                "rising/falling mutual exclusion after edge at step " &
                integer'image(i));
        end loop;

      -- ====================================================================
      elsif run("test_long_idle_then_edge") then
      -- ====================================================================
        -- Hold a stable for 50 cycles, then verify edge detection still works
        a <= '0';
        for i in 1 to 50 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_equal(rising, '0', "no spurious rising after long idle");
        check_equal(falling, '0', "no spurious falling after long idle");

        -- Now trigger a rising edge
        a <= '1';
        wait for 1 ns;
        check_equal(rising, '1', "rising detected after long idle");
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(rising, '0', "rising clears normally after long idle");

      -- ====================================================================
      elsif run("test_consecutive_same_direction") then
      -- ====================================================================
        -- Two rising edges separated by a falling edge in between
        -- First rising: 0->1
        a <= '1';
        wait for 1 ns;
        check_equal(rising, '1', "first rising pulse");
        wait until rising_edge(clk);  -- a_ff='1'
        wait for 1 ns;
        check_equal(rising, '0', "first rising cleared");

        -- Fall back to 0
        a <= '0';
        wait for 1 ns;
        check_equal(falling, '1', "intermediate falling");
        wait until rising_edge(clk);  -- a_ff='0'

        -- Second rising: 0->1
        a <= '1';
        wait for 1 ns;
        check_equal(rising, '1', "second rising pulse");
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(rising, '0', "second rising cleared");

      end if;
    end loop;

    test_done <= '1';
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
