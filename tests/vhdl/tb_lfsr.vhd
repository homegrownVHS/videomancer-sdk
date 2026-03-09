-- Videomancer SDK - VUnit Testbench for lfsr (configurable-width LFSR)
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tests:
--   1. Reset loads seed
--   2. Enable advances state
--   3. Hold (enable=0) freezes state
--   4. Known 10-bit maximal-length polynomial sequence
--   5. Different polynomial produces different sequence
--   6. Seed of all-ones produces non-stuck output
--   7. Reset mid-sequence re-seeds
--   8. Single enable pulse advances exactly once
--   9. Zero polynomial shifts in zeros

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_lfsr is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_lfsr is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_WIDTH      : integer := 10;

  signal clk       : std_logic := '0';
  signal reset     : std_logic := '0';
  signal enable    : std_logic := '0';
  signal seed      : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal poly      : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal lfsr_out  : std_logic_vector(C_WIDTH - 1 downto 0);
  signal test_done : std_logic := '0';

begin

  clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

  dut : entity rtl_lib.lfsr
    generic map (G_DATA_WIDTH => C_WIDTH)
    port map (
      clk      => clk,
      reset    => reset,
      enable   => enable,
      seed     => seed,
      poly     => poly,
      lfsr_out => lfsr_out
    );

  main : process
    variable v_prev : std_logic_vector(C_WIDTH - 1 downto 0);
    variable v_distinct_count : integer;
    variable v_held : std_logic_vector(C_WIDTH - 1 downto 0);
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset between tests
      reset <= '0';
      enable <= '0';
      seed <= (others => '0');
      poly <= (others => '0');
      wait until rising_edge(clk);

      -- ====================================================================
      if run("reset_loads_seed") then
      -- ====================================================================
        seed <= "1010101010";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        wait for 1 ns;
        check_equal(lfsr_out, std_logic_vector'("1010101010"),
                    "output should equal seed after reset");

      -- ====================================================================
      elsif run("enable_advances_state") then
      -- ====================================================================
        -- Load a known seed
        seed <= "1111111111";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        wait for 1 ns;
        v_prev := lfsr_out;

        -- 10-bit maximal-length polynomial: x^10 + x^7 + 1 taps at 9,6
        poly <= "1001000000";
        enable <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check(lfsr_out /= v_prev,
              "output should change after one enable cycle");

      -- ====================================================================
      elsif run("hold_freezes_state") then
      -- ====================================================================
        seed <= "1111111111";
        poly <= "1001000000";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        enable <= '1';
        -- Advance a few cycles
        for i in 0 to 4 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        v_prev := lfsr_out;

        -- Disable and check frozen
        enable <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(lfsr_out, v_prev,
                    "output should not change with enable=0");

      -- ====================================================================
      elsif run("known_sequence_no_repeat_short") then
      -- ====================================================================
        seed <= "1000000000";
        poly <= "1001000000";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        enable <= '1';

        v_distinct_count := 0;
        for i in 0 to 19 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          if lfsr_out /= "0000000000" then
            v_distinct_count := v_distinct_count + 1;
          end if;
        end loop;
        check(v_distinct_count >= 18,
              "should produce mostly non-zero values over 20 cycles");

      -- ====================================================================
      elsif run("different_poly_different_sequence") then
      -- ====================================================================
        seed <= "1000000000";

        -- First polynomial
        poly <= "1001000000";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        enable <= '1';
        for i in 0 to 9 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        v_prev := lfsr_out;

        -- Second polynomial (different taps)
        poly <= "1100000000";
        reset <= '1';
        seed <= "1000000000";
        wait until rising_edge(clk);
        reset <= '0';
        enable <= '1';
        for i in 0 to 9 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check(lfsr_out /= v_prev,
              "different polynomial should yield different sequence");

      -- ====================================================================
      elsif run("all_ones_seed_non_stuck") then
      -- ====================================================================
        seed <= (others => '1');
        poly <= "1001000000";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        enable <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check(lfsr_out /= "1111111111",
              "should advance from all-ones seed");

      -- ====================================================================
      elsif run("reset_mid_sequence") then
      -- ====================================================================
        seed <= "0000000001";
        poly <= "1001000000";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        enable <= '1';

        for i in 0 to 9 loop
          wait until rising_edge(clk);
        end loop;

        seed <= "1100110011";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        wait for 1 ns;
        check_equal(lfsr_out, std_logic_vector'("1100110011"),
                    "should reload seed on reset");

      -- ====================================================================
      elsif run("single_step_enable") then
      -- ====================================================================
        -- One enable pulse advances state exactly once, then holds
        seed <= "1010101010";
        poly <= "1001000000";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        wait for 1 ns;
        v_prev := lfsr_out;

        -- Single enable pulse
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait for 1 ns;
        check(lfsr_out /= v_prev, "should advance on single enable");
        v_held := lfsr_out;

        -- Verify frozen for 5 more cycles
        for i in 0 to 4 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(lfsr_out, v_held,
                      "should stay frozen after single step, cycle "
                      & integer'image(i));
        end loop;

      -- ====================================================================
      elsif run("zero_poly_shifts_zeros") then
      -- ====================================================================
        -- Polynomial = 0 means no feedback taps, so feedback = 0.
        -- Each cycle shifts right and inserts 0 at MSB.
        -- After C_WIDTH cycles, output should be all zeros.
        seed <= "1111111111";
        poly <= "0000000000";
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        enable <= '1';

        for i in 0 to C_WIDTH - 1 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_equal(lfsr_out, std_logic_vector'("0000000000"),
                    "zero poly should shift all bits to zero after "
                    & integer'image(C_WIDTH) & " cycles");

      end if;
    end loop;

    test_done <= '1';
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
