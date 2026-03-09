-- Videomancer SDK - VUnit Generic-Parameterized Testbench for diff_multiplier_s
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Sweeps diff_multiplier_s across multiple G_WIDTH/G_FRAC_BITS configurations
-- to verify exact pipeline latency and functional correctness at each width.
--
-- diff_multiplier_s computes: result = (x_pos - x_neg) * (y_pos - y_neg) + (z_pos - z_neg)
--
-- Pipeline latency formula (verified by test_valid_latency_exact):
--   valid_latency = (G_WIDTH+1)/2 + 4
--   data_latency  = valid_latency + 1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_diff_multiplier_generics is
  generic (
    runner_cfg   : string;
    G_WIDTH      : integer := 8;
    G_FRAC_BITS  : integer := 7;
    G_OUTPUT_MIN : integer := -128;
    G_OUTPUT_MAX : integer := 127
  );
end entity;

architecture tb of tb_diff_multiplier_generics is
  constant C_CLK_PERIOD : time := 10 ns;

  -- Exact valid latency: (G_WIDTH+1)/2 + 4
  constant C_VALID_LATENCY : integer := (G_WIDTH + 1) / 2 + 4;
  -- Data follows valid by 1 cycle
  constant C_DATA_LATENCY  : integer := C_VALID_LATENCY + 1;
  constant C_PIPE_WAIT     : integer := C_DATA_LATENCY + 2;

  signal clk    : std_logic := '0';
  signal enable : std_logic := '0';
  signal x_pos  : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal x_neg  : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal y_pos  : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal y_neg  : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal z_pos  : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal z_neg  : signed(G_WIDTH - 1 downto 0) := (others => '0');
  signal result : signed(G_WIDTH - 1 downto 0);
  signal valid  : std_logic;

  signal test_done : boolean := false;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.diff_multiplier_s
    generic map (
      G_WIDTH      => G_WIDTH,
      G_FRAC_BITS  => G_FRAC_BITS,
      G_OUTPUT_MIN => G_OUTPUT_MIN,
      G_OUTPUT_MAX => G_OUTPUT_MAX
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
    procedure clk_wait(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    -- Flush state
    procedure flush is
    begin
      enable <= '0';
      x_pos  <= (others => '0');
      x_neg  <= (others => '0');
      y_pos  <= (others => '0');
      y_neg  <= (others => '0');
      z_pos  <= (others => '0');
      z_neg  <= (others => '0');
      clk_wait(C_PIPE_WAIT);
    end procedure;

    -- Stream enable for 1 cycle with given inputs, then wait C_PIPE_WAIT
    procedure pulse_and_wait(
      xp, xn, yp, yn, zp, zn : integer
    ) is
    begin
      x_pos  <= to_signed(xp, G_WIDTH);
      x_neg  <= to_signed(xn, G_WIDTH);
      y_pos  <= to_signed(yp, G_WIDTH);
      y_neg  <= to_signed(yn, G_WIDTH);
      z_pos  <= to_signed(zp, G_WIDTH);
      z_neg  <= to_signed(zn, G_WIDTH);
      enable <= '1';
      clk_wait(C_PIPE_WAIT);
    end procedure;

    variable v_quarter : integer;
    variable v_count   : integer;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      flush;

      -- ==================================================================
      if run("test_valid_latency_exact") then
      -- ==================================================================
        -- Valid must assert at exactly C_VALID_LATENCY cycles
        info("Verifying valid latency = " &
             integer'image(C_VALID_LATENCY) &
             " for G_WIDTH=" & integer'image(G_WIDTH));
        flush;

        enable <= '1';
        x_pos  <= to_signed(1, G_WIDTH);
        wait until rising_edge(clk);  -- Sampling edge
        enable <= '0';
        x_pos  <= (others => '0');

        v_count := 0;
        for i in 1 to C_VALID_LATENCY + 6 loop
          wait until rising_edge(clk);
          v_count := v_count + 1;
          if valid = '1' then
            exit;
          end if;
        end loop;

        check_equal(valid, '1', "Valid should have asserted");
        check_equal(v_count, C_VALID_LATENCY,
          "Valid latency should be exactly " &
          integer'image(C_VALID_LATENCY) &
          " (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_single_pulse_valid_count") then
      -- ==================================================================
        -- 1 enable cycle produces exactly 1 valid cycle
        flush;

        enable <= '1';
        x_pos  <= to_signed(1, G_WIDTH);
        wait until rising_edge(clk);
        enable <= '0';
        x_pos  <= (others => '0');

        v_count := 0;
        for i in 1 to C_VALID_LATENCY + 6 loop
          wait until rising_edge(clk);
          if valid = '1' then
            v_count := v_count + 1;
          end if;
        end loop;

        check_equal(v_count, 1,
          "Exactly 1 valid from 1 enable (w=" &
          integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("test_streaming_valid_sustained") then
      -- ==================================================================
        -- Continuous enable produces continuous valid after pipeline fills
        flush;

        enable <= '1';
        x_pos  <= to_signed(1, G_WIDTH);
        y_pos  <= to_signed(1, G_WIDTH);

        -- Wait for pipeline to fill
        clk_wait(C_VALID_LATENCY);

        -- Valid should now be sustained
        for i in 1 to 8 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(valid, '1',
            "Valid sustained at cycle " & integer'image(i) &
            " (w=" & integer'image(G_WIDTH) & ")");
        end loop;
        enable <= '0';

      -- ==================================================================
      elsif run("test_enable_gap_tracking") then
      -- ==================================================================
        -- Valid deasserts correctly during enable gap
        flush;

        enable <= '1';
        x_pos  <= to_signed(1, G_WIDTH);
        y_pos  <= to_signed(1, G_WIDTH);
        clk_wait(C_DATA_LATENCY + 2);
        check_equal(valid, '1', "Valid while enabled");

        -- Gap
        enable <= '0';
        clk_wait(C_VALID_LATENCY + 2);
        check_equal(valid, '0', "Valid low during gap");

        -- Re-enable
        enable <= '1';
        clk_wait(C_VALID_LATENCY + 1);
        check_equal(valid, '1', "Valid restored after gap");
        enable <= '0';

      -- ==================================================================
      elsif run("zero_input_zero_output") then
      -- ==================================================================
        pulse_and_wait(0, 0, 0, 0, 0, 0);
        check_equal(valid, '1',
          "valid asserted (w=" & integer'image(G_WIDTH) & ")");
        check_equal(result, to_signed(0, G_WIDTH),
          "zero input gives zero output (w=" & integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("symmetric_positive") then
      -- ==================================================================
        v_quarter := 2 ** (G_WIDTH - 3);
        pulse_and_wait(v_quarter, 0, 1, 0, 0, 0);
        check_equal(valid, '1', "valid");
        check(to_integer(result) >= 0,
              "positive * positive = positive (w=" &
              integer'image(G_WIDTH) & ")");

      -- ==================================================================
      elsif run("z_offset_only") then
      -- ==================================================================
        v_quarter := 2 ** (G_WIDTH - 3);
        pulse_and_wait(0, 0, 0, 0, v_quarter, 0);
        check_equal(valid, '1', "valid");

      -- ==================================================================
      elsif run("negative_difference") then
      -- ==================================================================
        v_quarter := 2 ** (G_WIDTH - 3);
        pulse_and_wait(0, v_quarter, 1, 0, 0, 0);
        check_equal(valid, '1', "valid");
        check(to_integer(result) <= 0,
              "negative * positive = negative (w=" &
              integer'image(G_WIDTH) & ")");

      end if;
    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
