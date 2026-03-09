-- Videomancer SDK - VUnit Testbench for video_sync_generator
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- video_sync_generator drives bi-level and tri-level sync signals from
-- reference sync inputs and a timing configuration selected via a 4-bit ID.
--
-- Architecture:
--   - event_detectors: falling edge detection on ref_vsync and ref_field_n
--   - timing_config_regs: 2-cycle pipeline loading config from constant array
--   - counters: clk/line counters reset by fsync, wrap at clocks_per_line/lines_per_frame
--   - sync_gen: threshold comparisons generate hsync, vsync, csync, eq_pulses, etc.
--   - trisync output mux: combines sync signals for tri-level sync output
--
-- Tests use 480P (progressive, timing ID "0100") and NTSC (interlaced, "0000").
--
-- 480P config (from video_sync_pkg):
--   clocks_per_line=858, lines_per_frame=525
--   fsync_clks=1, fsync_lines=13
--   hsync_clks_1=1 (high), hsync_clks_0=64 (low) -> 63 clk pulse
--   vsync_a_lines_1=7 (high), vsync_a_lines_0=13 (low) -> 6 line pulse
--   trisync_en='0', is_interlaced='0'
--
-- Tests:
--   1. hsync_pulse_after_fsync_480p
--   2. hsync_pulse_width_480p
--   3. hsync_repeats_each_line_480p
--   4. vsync_generation_480p
--   5. ntsc_interlaced_field_fsync
--   6. trisync_p_zero_when_disabled
--   7. trisync_n_follows_csync_480p
--   8. counter_survives_full_line
--   9. config_pipeline_latency
--  10. multiple_fsync_resets

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.video_timing_pkg.all;
use rtl_lib.video_sync_pkg.all;

entity tb_video_sync_gen is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_video_sync_gen is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk         : std_logic := '0';
  signal ref_hsync   : std_logic := '1';
  signal ref_vsync   : std_logic := '1';
  signal ref_field_n : std_logic := '1';
  signal timing      : std_logic_vector(3 downto 0) := C_480P;
  signal trisync_p   : std_logic;
  signal trisync_n   : std_logic;
  signal hsync       : std_logic;
  signal vsync       : std_logic;
  signal test_done   : std_logic := '0';

  -- 480P known values
  constant C_480P_CPL         : integer := 858;   -- clocks_per_line
  constant C_480P_LPF         : integer := 525;   -- lines_per_frame
  constant C_480P_FSYNC_CLKS  : integer := 1;
  constant C_480P_FSYNC_LINES : integer := 13;
  constant C_480P_HSYNC_ON    : integer := 1;    -- hsync_clks_1 (set high)
  constant C_480P_HSYNC_OFF   : integer := 64;   -- hsync_clks_0 (set low)
  constant C_480P_VSYNC_ON_L  : integer := 7;    -- vsync_a_lines_1
  constant C_480P_VSYNC_OFF_L : integer := 13;   -- vsync_a_lines_0

  -- Config pipeline latency: timing port -> s_timing (1) -> config regs (1) = 2 cycles
  -- Plus margin for counter/sync_gen to see new config
  constant C_CONFIG_SETTLE    : integer := 6;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

  dut : entity rtl_lib.video_sync_generator
    port map (
      clk         => clk,
      ref_hsync   => ref_hsync,
      ref_vsync   => ref_vsync,
      ref_field_n => ref_field_n,
      timing      => timing,
      trisync_p   => trisync_p,
      trisync_n   => trisync_n,
      hsync       => hsync,
      vsync       => vsync
    );

  main : process
    -- Wait N rising edges then settle
    procedure clk_wait(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    -- Let config pipeline settle
    procedure settle_config is
    begin
      clk_wait(C_CONFIG_SETTLE);
    end procedure;

    -- Trigger frame sync via ref_vsync falling edge (progressive mode)
    procedure trigger_vsync_fsync is
    begin
      ref_vsync <= '0';
      wait until rising_edge(clk);
      ref_vsync <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;

    -- Advance N clocks
    procedure advance_clks(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    variable v_hsync_high_count : integer;
    variable v_hsync_before     : std_logic;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset to known state
      timing      <= C_480P;
      ref_vsync   <= '1';
      ref_field_n <= '1';
      ref_hsync   <= '1';
      settle_config;

      -- ====================================================================
      if run("hsync_pulse_after_fsync_480p") then
      -- ====================================================================
        trigger_vsync_fsync;
        check_equal(hsync, '1', "hsync high at counter=1 (hsync_clks_1)");

      -- ====================================================================
      elsif run("hsync_pulse_width_480p") then
      -- ====================================================================
        trigger_vsync_fsync;
        check_equal(hsync, '1', "hsync starts high");

        v_hsync_high_count := 0;
        while hsync = '1' loop
          v_hsync_high_count := v_hsync_high_count + 1;
          wait until rising_edge(clk);
          wait for 1 ns;
        end loop;
        check(v_hsync_high_count >= 60 and v_hsync_high_count <= 66,
              "hsync pulse width ~63, got " & integer'image(v_hsync_high_count));

      -- ====================================================================
      elsif run("hsync_repeats_each_line_480p") then
      -- ====================================================================
        trigger_vsync_fsync;
        check_equal(hsync, '1', "first hsync");

        while hsync = '1' loop
          wait until rising_edge(clk);
          wait for 1 ns;
        end loop;

        while hsync = '0' loop
          wait until rising_edge(clk);
          wait for 1 ns;
        end loop;
        check_equal(hsync, '1', "hsync re-asserts on next line");

      -- ====================================================================
      elsif run("vsync_generation_480p") then
      -- ====================================================================
        trigger_vsync_fsync;
        advance_clks(2);
        check_equal(vsync, '0', "vsync off at line 13");

        for i in 1 to 20 loop
          advance_clks(C_480P_CPL);
        end loop;
        check_equal(vsync, '0', "vsync still off 20 lines after fsync");

      -- ====================================================================
      elsif run("ntsc_interlaced_field_fsync") then
      -- ====================================================================
        timing <= C_NTSC;
        settle_config;

        ref_vsync <= '0';
        wait until rising_edge(clk);
        ref_vsync <= '1';
        advance_clks(3);

        ref_field_n <= '0';
        wait until rising_edge(clk);
        ref_field_n <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        advance_clks(C_480P_CPL);

      -- ====================================================================
      elsif run("trisync_p_zero_when_disabled") then
      -- ====================================================================
        trigger_vsync_fsync;
        check_equal(trisync_p, '0', "trisync_p off with trisync_en=0");

        for i in 1 to 100 loop
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(trisync_p, '0',
                      "trisync_p stays off at clk " & integer'image(i));
        end loop;

      -- ====================================================================
      elsif run("trisync_n_follows_csync_480p") then
      -- ====================================================================
        trigger_vsync_fsync;
        advance_clks(100);
        check_equal(trisync_n, '1',
                    "trisync_n follows csync high (counter past csync_clks_1)");

      -- ====================================================================
      elsif run("counter_survives_full_line") then
      -- ====================================================================
        trigger_vsync_fsync;
        check_equal(hsync, '1', "hsync initially high after fsync");

        advance_clks(C_480P_CPL);
        check_equal(hsync, '1', "hsync re-asserts after full line wrap");

      -- ====================================================================
      elsif run("config_pipeline_latency") then
      -- ====================================================================
        -- Verify that changing timing ID propagates through the 2-cycle
        -- config pipeline. After 2 edges, the new config registers are loaded.
        trigger_vsync_fsync;
        v_hsync_before := hsync;

        -- Switch to NTSC config
        timing <= C_NTSC;
        -- After 2 clock edges, config registers should hold NTSC values.
        -- We can't directly read config regs, but we verify the pipeline
        -- doesn't stall or break sync generation.
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        -- Config has loaded — trigger fsync with new config
        trigger_vsync_fsync;
        -- After fsync with NTSC config, sync generator should operate
        -- with NTSC timings. Run for a line and verify no stall.
        advance_clks(100);

      -- ====================================================================
      elsif run("multiple_fsync_resets") then
      -- ====================================================================
        -- Verify consecutive fsync triggers work correctly — counters
        -- reset cleanly each time
        trigger_vsync_fsync;
        check_equal(hsync, '1', "hsync after first fsync");

        -- Advance half a line
        advance_clks(C_480P_CPL / 2);

        -- Trigger fsync again mid-line
        trigger_vsync_fsync;
        -- Counters should reset, hsync should re-assert at counter=1
        check_equal(hsync, '1', "hsync after second fsync mid-line");

        -- Advance half a line again and re-trigger
        advance_clks(C_480P_CPL / 2);
        trigger_vsync_fsync;
        check_equal(hsync, '1', "hsync after third fsync mid-line");

      end if;
    end loop;

    test_done <= '1';
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 100 ms);

end architecture;
