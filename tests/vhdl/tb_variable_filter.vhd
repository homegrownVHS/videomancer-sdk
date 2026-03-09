-- Videomancer SDK - VUnit Testbench for variable_filter_s
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- variable_filter_s is an IIR LPF/HPF with 8-bit cutoff control.
-- Upper 4 bits of cutoff = coarse shift (exponential decay rate).
-- Lower 4 bits = sigma-delta fine interpolation between adjacent shifts.
--
-- Pipeline latency: 1 cycle (valid <= enable)
-- Outputs: low_pass = s_y_reg (registered), high_pass = a - s_y_reg (combinational)
--
-- Tests:
--   1. LPF step response convergence
--   2. HPF equals input minus LPF
--   3. Cutoff 0 (fastest tracking)
--   4. High cutoff (slowest tracking)
--   5. Valid follows enable
--   6. Signed negative input tracking

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_variable_filter is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_variable_filter is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_WIDTH      : integer := 16;

  signal clk       : std_logic := '0';
  signal enable    : std_logic := '0';
  signal a         : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal cutoff    : unsigned(7 downto 0) := (others => '0');
  signal low_pass  : signed(C_WIDTH - 1 downto 0);
  signal high_pass : signed(C_WIDTH - 1 downto 0);
  signal valid     : std_logic;

begin

  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity rtl_lib.variable_filter_s
    generic map (
      G_WIDTH => C_WIDTH
    )
    port map (
      clk       => clk,
      enable    => enable,
      a         => a,
      cutoff    => cutoff,
      low_pass  => low_pass,
      high_pass => high_pass,
      valid     => valid
    );

  main : process
    variable v_prev_lp : signed(C_WIDTH - 1 downto 0);
    variable v_converging : boolean;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      enable <= '0';
      a      <= (others => '0');
      cutoff <= (others => '0');
      -- Reset the filter state by running with input=0 for a while
      enable <= '1';
      for i in 1 to 50 loop
        wait until rising_edge(clk);
      end loop;
      enable <= '0';
      wait until rising_edge(clk);

      -- ====================================================================
      if run("lpf_step_response_convergence") then
      -- ====================================================================
        -- Apply a step input and verify the LPF converges toward it
        a      <= to_signed(1000, C_WIDTH);
        cutoff <= to_unsigned(16, 8);  -- coarse=1, fine=0: moderate filtering
        enable <= '1';

        -- Run for enough cycles to see convergence
        for i in 1 to 200 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        -- After 200 cycles with coarse=1, should be close to input
        check(low_pass > to_signed(900, C_WIDTH),
              "LPF should converge toward step input (1000), got " &
              integer'image(to_integer(low_pass)));

      -- ====================================================================
      elsif run("hpf_equals_input_minus_lpf") then
      -- ====================================================================
        a      <= to_signed(500, C_WIDTH);
        cutoff <= to_unsigned(32, 8);  -- coarse=2
        enable <= '1';

        for i in 1 to 50 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          -- Check identity: high_pass = a - low_pass
          check_equal(high_pass, a - low_pass,
                      "HPF should equal input minus LPF at cycle " &
                      integer'image(i));
        end loop;

      -- ====================================================================
      elsif run("cutoff_zero_fast_tracking") then
      -- ====================================================================
        -- cutoff=0: coarse=0 (shift by 0), fine=0 → tracks input most quickly
        a      <= to_signed(2000, C_WIDTH);
        cutoff <= to_unsigned(0, 8);
        enable <= '1';

        -- With shift=0, error fully feeds back each cycle
        -- After 1 cycle: y_new = 0 + (2000-0) >> 0 = 2000
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(low_pass, to_signed(2000, C_WIDTH),
                    "cutoff=0 should track input in 1 cycle");

      -- ====================================================================
      elsif run("high_cutoff_slow_tracking") then
      -- ====================================================================
        -- cutoff=0xF0: coarse=15 (shift by 15), fine=0 → very slow tracking
        a      <= to_signed(10000, C_WIDTH);
        cutoff <= to_unsigned(240, 8);  -- 0xF0
        enable <= '1';

        for i in 1 to 100 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        -- With shift=15, very little correction per cycle
        -- Should be far from target after only 100 cycles
        check(low_pass < to_signed(5000, C_WIDTH),
              "High cutoff should track very slowly, got " &
              integer'image(to_integer(low_pass)));

      -- ====================================================================
      elsif run("valid_follows_enable") then
      -- ====================================================================
        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(valid, '0', "valid should be 0 when disabled");

        enable <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(valid, '1', "valid should be 1 when enabled");

        enable <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(valid, '0', "valid should drop when disabled");

      -- ====================================================================
      elsif run("signed_negative_input_tracking") then
      -- ====================================================================
        -- Verify the filter tracks negative values correctly
        a      <= to_signed(-3000, C_WIDTH);
        cutoff <= to_unsigned(0, 8);  -- fast tracking
        enable <= '1';

        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(low_pass, to_signed(-3000, C_WIDTH),
                    "Should track negative input with cutoff=0");

        -- Now apply moderate cutoff and check convergence from -3000 to 0
        a      <= to_signed(0, C_WIDTH);
        cutoff <= to_unsigned(16, 8);  -- coarse=1

        for i in 1 to 100 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        check(low_pass > to_signed(-100, C_WIDTH),
              "LPF should have converged close to 0, got " &
              integer'image(to_integer(low_pass)));
        check(low_pass <= to_signed(0, C_WIDTH),
              "LPF should not overshoot past 0");

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;

end architecture;
