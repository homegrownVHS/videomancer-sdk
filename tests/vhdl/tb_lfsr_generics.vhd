-- Videomancer SDK - VUnit Generic-Parameterized Testbench for lfsr
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Sweeps lfsr across multiple G_DATA_WIDTH configurations to verify
-- LFSR sequence generation, seed loading, polynomial tap behavior,
-- and state machine behavior at each width.
--
-- Tests:
--   1. seed_load_on_reset - reset synchronously loads seed in 1 cycle
--   2. sequence_changes_when_enabled - output changes over 10 cycles
--   3. output_not_stuck - sequences produce varying values
--   4. disabled_holds_state - enable='0' freezes register
--   5. reset_latency_exact - seed appears at output after exactly 1 clock
--   6. enable_single_step - one enable pulse advances state exactly once
--   7. re_seed_mid_sequence - reset mid-run reloads seed value
--   8. all_zero_polynomial_no_advance - poly=0 keeps feedback='0'

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_lfsr_generics is
  generic (
    runner_cfg : string;
    G_WIDTH    : integer := 10
  );
end entity;

architecture tb of tb_lfsr_generics is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk      : std_logic := '0';
  signal reset    : std_logic := '0';
  signal enable   : std_logic := '0';
  signal seed     : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '1');
  signal poly     : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
  signal lfsr_out : std_logic_vector(G_WIDTH - 1 downto 0);
  signal test_done : std_logic := '0';

  -- Common maximal-length polynomials for tested widths
  function get_polynomial(width : integer) return std_logic_vector is
    variable v_poly : std_logic_vector(width - 1 downto 0) := (others => '0');
  begin
    case width is
      when 4  => v_poly := "1100";
      when 8  => v_poly := "10111000";
      when 10 => v_poly := "1001000000";
      when 12 => v_poly := "110010100000";
      when 16 => v_poly := "1011010000000000";
      when others =>
        v_poly(width - 1) := '1';
        v_poly(1)         := '1';
    end case;
    return v_poly;
  end function;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

  dut : entity rtl_lib.lfsr
    generic map (G_DATA_WIDTH => G_WIDTH)
    port map (
      clk      => clk,
      reset    => reset,
      enable   => enable,
      seed     => seed,
      poly     => poly,
      lfsr_out => lfsr_out
    );

  main : process
    variable v_initial  : std_logic_vector(G_WIDTH - 1 downto 0);
    variable v_prev     : std_logic_vector(G_WIDTH - 1 downto 0);
    variable v_step1    : std_logic_vector(G_WIDTH - 1 downto 0);
    variable v_all_same : boolean;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset state
      reset  <= '0';
      enable <= '0';
      seed   <= (others => '1');
      poly   <= get_polynomial(G_WIDTH);
      wait until rising_edge(clk);
      wait until rising_edge(clk);

      -- ==================================================================
      if run("seed_load_on_reset") then
      -- ==================================================================
        seed(0) <= '1';
        for i in 1 to G_WIDTH - 1 loop
          seed(i) <= '0';
        end loop;
        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        wait for 1 ns;

        check_equal(lfsr_out(0), '1',
                    "seed LSB loaded (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("sequence_changes_when_enabled") then
      -- ==================================================================
        seed  <= (others => '1');
        reset <= '1';
        wait until rising_edge(clk);
        reset  <= '0';
        enable <= '1';
        wait for 1 ns;

        v_initial := lfsr_out;

        for i in 1 to 10 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        check(lfsr_out /= v_initial,
              "LFSR output changes after 10 cycles (w=" &
              integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("output_not_stuck") then
      -- ==================================================================
        seed  <= (others => '1');
        reset <= '1';
        wait until rising_edge(clk);
        reset  <= '0';
        enable <= '1';
        for i in 1 to 5 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        v_all_same := true;
        v_prev := lfsr_out;

        for i in 0 to 19 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          if lfsr_out /= v_prev then
            v_all_same := false;
          end if;
          v_prev := lfsr_out;
        end loop;

        check(not v_all_same,
              "LFSR output is not stuck (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("disabled_holds_state") then
      -- ==================================================================
        seed  <= (others => '1');
        reset <= '1';
        wait until rising_edge(clk);
        reset  <= '0';
        enable <= '1';
        for i in 1 to 5 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        v_prev := lfsr_out;

        for i in 1 to 5 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_equal(lfsr_out, v_prev,
                    "disabled LFSR holds state (w=" &
                    integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("reset_latency_exact") then
      -- ==================================================================
        -- Verify seed loads in exactly 1 clock edge
        -- Set a recognizable seed pattern
        for i in 0 to G_WIDTH - 1 loop
          if (i mod 2) = 0 then
            seed(i) <= '1';
          else
            seed(i) <= '0';
          end if;
        end loop;

        reset <= '1';
        -- Before the edge, output should NOT yet have the new seed
        wait for 1 ns;
        -- (output has whatever it had before)

        -- Edge 1: reset latches seed into lfsr_reg
        wait until rising_edge(clk);
        reset <= '0';
        wait for 1 ns;

        -- Verify output matches the seed pattern
        for i in 0 to G_WIDTH - 1 loop
          if (i mod 2) = 0 then
            check_equal(lfsr_out(i), '1',
                        "seed bit " & integer'image(i) & " w=" &
                        integer'image(G_WIDTH));
          else
            check_equal(lfsr_out(i), '0',
                        "seed bit " & integer'image(i) & " w=" &
                        integer'image(G_WIDTH));
          end if;
        end loop;

      -- ==================================================================
      elsif run("enable_single_step") then
      -- ==================================================================
        -- One enable pulse should advance state exactly once
        seed  <= (others => '1');
        reset <= '1';
        wait until rising_edge(clk);
        reset  <= '0';
        wait for 1 ns;
        v_initial := lfsr_out;  -- should be all-ones seed

        -- Single enable pulse
        enable <= '1';
        wait until rising_edge(clk);
        enable <= '0';
        wait for 1 ns;
        v_step1 := lfsr_out;

        -- Verify state changed
        check(v_step1 /= v_initial,
              "state changed after 1 enable (w=" &
              integer'image(G_WIDTH) & ")");

        -- Verify state is frozen now (enable='0')
        for i in 1 to 5 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_equal(lfsr_out, v_step1,
                    "state frozen after enable deasserted (w=" &
                    integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("re_seed_mid_sequence") then
      -- ==================================================================
        -- Run LFSR, then re-seed and verify reload
        seed  <= (others => '1');
        reset <= '1';
        wait until rising_edge(clk);
        reset  <= '0';
        enable <= '1';

        -- Advance several cycles
        for i in 1 to 10 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        -- Re-seed with a different pattern
        enable <= '0';
        for i in 0 to G_WIDTH - 1 loop
          seed(i) <= '1';
        end loop;
        seed(0) <= '0';  -- seed = all-ones except LSB=0

        reset <= '1';
        wait until rising_edge(clk);
        reset <= '0';
        wait for 1 ns;

        check_equal(lfsr_out(0), '0',
                    "re-seeded LSB=0 (w=" & integer'image(G_WIDTH) & ")");
        check_equal(lfsr_out(G_WIDTH - 1), '1',
                    "re-seeded MSB=1 (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("all_zero_polynomial_no_advance") then
      -- ==================================================================
        -- With poly=0, XOR feedback is always '0', so shift register
        -- should shift in zeros from MSB
        seed  <= (others => '1');
        poly  <= (others => '0');  -- no taps
        reset <= '1';
        wait until rising_edge(clk);
        reset  <= '0';
        enable <= '1';

        -- After G_WIDTH cycles, all ones should have shifted out
        for i in 1 to G_WIDTH loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        -- All bits should be '0' (feedback is always '0', shifted in from MSB)
        check_equal(lfsr_out, std_logic_vector(to_unsigned(0, G_WIDTH)),
                    "poly=0 shifts in zeros (w=" &
                    integer'image(G_WIDTH) & ")");

      end if;
    end loop;

    test_done <= '1';
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
