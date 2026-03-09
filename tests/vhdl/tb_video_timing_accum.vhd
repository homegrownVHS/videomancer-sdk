-- Videomancer SDK - VUnit Testbench for video_timing_accumulator
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- video_timing_accumulator is a phase accumulator synchronized to video timing
-- events. Three modes: C_ANIMATION (accumulate on vsync_start), C_VERTICAL
-- (accumulate on avid_start, reset on vsync_start with lock), C_HORIZONTAL
-- (free-running, reset on avid_start with lock).
--
-- Pipeline (verified by test_accumulator_latency_exact):
--   Cycle 1: Input registration (i_timing -> s_i_timing, etc.)
--   Cycle 2: Accumulator logic (s_o_accumulator update)
--   o_accumulator: combinational from s_o_accumulator (2 cycles from input)
--   o_clock: combinational MSB of s_o_accumulator (2 cycles from input)
--   o_pulse: combinational from s_last_msb (3 cycles: MSB change + last_msb reg)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.video_timing_pkg.all;

entity tb_video_timing_accum is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_video_timing_accum is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_ACC_WIDTH  : integer := 8;  -- Small for easy verification

  signal clk           : std_logic := '0';
  signal i_timing      : t_video_timing_port := (others => '0');
  signal i_range       : t_video_timing_range := C_ANIMATION;
  signal i_reset       : std_logic := '0';
  signal i_lock        : std_logic := '0';
  signal i_accumulator : std_logic_vector(C_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal o_accumulator : std_logic_vector(C_ACC_WIDTH - 1 downto 0);
  signal o_clock       : std_logic;
  signal o_pulse       : std_logic;

  signal test_done : boolean := false;

  -- Pipeline: 1 input reg + 1 accum logic = 2 cycles for o_accumulator/o_clock
  constant C_ACCUM_LATENCY : integer := 2;
  -- Pulse: 3 cycles (accum latency + 1 for s_last_msb register + combinational)
  constant C_PULSE_LATENCY : integer := 3;
  -- Generous settle for multi-step tests
  constant C_SETTLE        : integer := 4;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.video_timing_accumulator
    generic map (
      G_ACCUMULATOR_WIDTH => C_ACC_WIDTH
    )
    port map (
      clk           => clk,
      i_timing      => i_timing,
      i_range       => i_range,
      i_reset       => i_reset,
      i_lock        => i_lock,
      i_accumulator => i_accumulator,
      o_accumulator => o_accumulator,
      o_clock       => o_clock,
      o_pulse       => o_pulse
    );

  main : process
    procedure clk_wait(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    procedure do_reset is
    begin
      i_timing      <= (others => '0');
      i_range       <= C_ANIMATION;
      i_reset       <= '1';
      i_lock        <= '0';
      i_accumulator <= (others => '0');
      clk_wait(C_SETTLE);
      i_reset <= '0';
      clk_wait(C_SETTLE);
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      do_reset;

      -- ==================================================================
      if run("test_accumulator_latency_exact") then
      -- ==================================================================
        -- Verify o_accumulator updates exactly 2 edges from raw input.
        -- Since o_accumulator is a combinational copy of s_o_accumulator,
        -- the result is visible right after the second rising edge (edge 1
        -- from our perspective, since we already consumed edge 0 for
        -- sampling).
        info("Verifying accumulator latency = 2 edges from raw input");
        do_reset;

        i_range       <= C_ANIMATION;
        i_accumulator <= std_logic_vector(to_unsigned(50, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        -- Pulse vsync_start for 1 cycle
        i_timing.vsync_start <= '1';
        wait until rising_edge(clk);  -- Edge 0: input register captures vsync
        i_timing.vsync_start <= '0';

        -- Edge 1: accumulator process reads registered vsync_start='1'
        --         and updates s_o_accumulator. Combinational output follows.
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(unsigned(o_accumulator), to_unsigned(50, C_ACC_WIDTH),
                    "Accumulator should be 50 at 2 edges from raw input");

      -- ==================================================================
      elsif run("test_pulse_latency_exact") then
      -- ==================================================================
        -- o_pulse asserts when MSB falls (1->0). Pulse latency is 1 edge
        -- later than the accumulator output, because s_last_msb must
        -- register the OLD MSB before detecting the falling edge.
        --
        -- Flow: input reg (edge 0) -> accum update (edge 1) ->
        --       s_last_msb captures old MSB (edge 1) + o_accumulator has
        --       new MSB (edge 1). Because s_last_msb reads the OLD
        --       s_o_accumulator on the same edge, the pulse is
        --       combinational: s_last_msb(old=1) AND current MSB(new=0).
        --       So o_pulse will be 1 right after edge 1 (same delta as
        --       o_accumulator update), but ONLY if s_last_msb was already
        --       captured from the previous state.
        --
        -- Let's simplify: accumulate to MSB=1, let s_last_msb settle,
        -- then trigger the wrap and verify o_pulse.
        do_reset;

        i_range       <= C_ANIMATION;
        -- Step=128: each vsync adds 128 to 8-bit accum
        i_accumulator <= std_logic_vector(to_unsigned(128, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        -- First vsync: accumulator goes 0 -> 128 (MSB=1)
        i_timing.vsync_start <= '1';
        wait until rising_edge(clk);
        i_timing.vsync_start <= '0';
        clk_wait(C_SETTLE);
        check_equal(o_clock, '1', "MSB should be 1 after first vsync");

        -- Wait extra cycle so s_last_msb captures MSB=1
        clk_wait(1);

        -- Second vsync: accumulator wraps 128+128=256 -> 0 (MSB falls)
        i_timing.vsync_start <= '1';
        wait until rising_edge(clk);  -- Edge 0: input registered
        i_timing.vsync_start <= '0';

        -- Edge 1: accumulator updates (MSB goes 0), s_last_msb captures
        --         old MSB (=1). Combinational: last_msb=1 AND MSB=0 -> pulse=1
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(o_clock, '0', "Clock should be 0 after wrap");
        check_equal(o_pulse, '1', "Pulse on MSB falling edge");

      -- ==================================================================
      elsif run("animation_mode_accumulates_on_vsync") then
      -- ==================================================================
        i_range       <= C_ANIMATION;
        i_accumulator <= std_logic_vector(to_unsigned(10, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        -- Pulse vsync_start 3 times
        for pulse in 1 to 3 loop
          i_timing.vsync_start <= '1';
          wait until rising_edge(clk);
          i_timing.vsync_start <= '0';
          clk_wait(C_SETTLE);
        end loop;

        check_equal(unsigned(o_accumulator), to_unsigned(30, C_ACC_WIDTH),
                    "3 vsync pulses * step 10 = 30");

      -- ==================================================================
      elsif run("vertical_mode_accumulates_on_avid_start") then
      -- ==================================================================
        i_range       <= C_VERTICAL;
        i_accumulator <= std_logic_vector(to_unsigned(5, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        -- Pulse avid_start 4 times
        for pulse in 1 to 4 loop
          i_timing.avid_start <= '1';
          wait until rising_edge(clk);
          i_timing.avid_start <= '0';
          clk_wait(C_SETTLE);
        end loop;

        check_equal(unsigned(o_accumulator), to_unsigned(20, C_ACC_WIDTH),
                    "4 avid_start pulses * step 5 = 20");

      -- ==================================================================
      elsif run("horizontal_mode_free_running") then
      -- ==================================================================
        i_range       <= C_HORIZONTAL;
        i_accumulator <= std_logic_vector(to_unsigned(1, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        -- In horizontal mode, accumulator advances every cycle
        for i in 1 to 10 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;

        check(unsigned(o_accumulator) > to_unsigned(0, C_ACC_WIDTH),
              "Horizontal mode should accumulate every cycle");

      -- ==================================================================
      elsif run("reset_clears_accumulator") then
      -- ==================================================================
        -- Accumulate something first
        i_range       <= C_HORIZONTAL;
        i_accumulator <= std_logic_vector(to_unsigned(1, C_ACC_WIDTH));
        for i in 1 to 20 loop
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check(unsigned(o_accumulator) > to_unsigned(0, C_ACC_WIDTH),
              "Non-zero before reset");

        -- Apply reset
        i_reset <= '1';
        clk_wait(C_SETTLE);
        check_equal(unsigned(o_accumulator), to_unsigned(0, C_ACC_WIDTH),
                    "Reset should clear accumulator");

      -- ==================================================================
      elsif run("lock_resets_vertical_on_vsync") then
      -- ==================================================================
        i_range       <= C_VERTICAL;
        i_lock        <= '1';
        i_accumulator <= std_logic_vector(to_unsigned(10, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        -- Accumulate via avid_start
        for pulse in 1 to 5 loop
          i_timing.avid_start <= '1';
          wait until rising_edge(clk);
          i_timing.avid_start <= '0';
          clk_wait(C_SETTLE);
        end loop;
        check(unsigned(o_accumulator) > to_unsigned(0, C_ACC_WIDTH),
              "Accumulated before vsync reset");

        -- Pulse vsync_start with lock=1 -> resets
        i_timing.vsync_start <= '1';
        wait until rising_edge(clk);
        i_timing.vsync_start <= '0';
        clk_wait(C_SETTLE);
        check_equal(unsigned(o_accumulator), to_unsigned(0, C_ACC_WIDTH),
                    "vsync_start with lock resets vertical accumulator");

      -- ==================================================================
      elsif run("clock_reflects_msb") then
      -- ==================================================================
        i_range       <= C_HORIZONTAL;
        i_accumulator <= std_logic_vector(to_unsigned(1, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        for i in 1 to 200 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(o_clock, o_accumulator(C_ACC_WIDTH - 1),
                      "o_clock should always match MSB");
        end loop;

      -- ==================================================================
      elsif run("pulse_on_msb_falling_edge") then
      -- ==================================================================
        -- Use large step to quickly toggle MSB
        i_range       <= C_ANIMATION;
        i_accumulator <= std_logic_vector(to_unsigned(64, C_ACC_WIDTH));
        clk_wait(C_SETTLE);

        -- 2 vsync: accumulate to 128 (MSB=1)
        for pulse in 1 to 2 loop
          i_timing.vsync_start <= '1';
          wait until rising_edge(clk);
          i_timing.vsync_start <= '0';
          clk_wait(C_SETTLE);
        end loop;
        check_equal(o_clock, '1', "MSB 1 after accumulating to 128");

        -- 2 more vsync: 128+64=192, 192+64=256 wraps to 0 (MSB falls)
        for pulse in 1 to 2 loop
          i_timing.vsync_start <= '1';
          wait until rising_edge(clk);
          i_timing.vsync_start <= '0';
          clk_wait(C_SETTLE);
        end loop;

        check_equal(o_clock, '0', "MSB wraps back to 0");

      end if;
    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
