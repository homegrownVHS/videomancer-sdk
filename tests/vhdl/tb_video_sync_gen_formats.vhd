-- Videomancer SDK - VUnit Testbench for video_sync_generator (all formats)
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Parameterized testbench exercising video_sync_generator across all 15
-- video timing formats. Each VUnit config supplies the timing ID and
-- expected per-format properties (clocks_per_line, interlaced, trisync_en).
--
-- Tests per config:
--   1. hsync_and_trisync_active - HSYNC edges appear after fsync; trisync
--      behaviour matches the config flag
--   2. hsync_period_matches_line - the rising-edge period of HSYNC equals
--      clocks_per_line

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.video_timing_pkg.all;
use rtl_lib.video_sync_pkg.all;

entity tb_video_sync_gen_formats is
  generic (
    runner_cfg        : string;
    G_TIMING_ID       : natural := 4;
    G_CLOCKS_PER_LINE : natural := 858;
    G_IS_INTERLACED   : natural := 0;
    G_TRISYNC_EN      : natural := 0
  );
end entity;

architecture tb of tb_video_sync_gen_formats is

  constant C_CLK_PERIOD    : time    := 10 ns;
  constant C_CONFIG_SETTLE : integer := 10;

  signal clk         : std_logic := '0';
  signal ref_hsync   : std_logic := '0';
  signal ref_vsync   : std_logic := '0';
  signal ref_field_n : std_logic := '0';
  signal timing      : std_logic_vector(3 downto 0) := "0100";
  signal trisync_p   : std_logic;
  signal trisync_n   : std_logic;
  signal hsync       : std_logic;
  signal vsync       : std_logic;

  -- ================================================================
  -- Helper: trigger frame sync via appropriate reference signal
  -- ================================================================
  procedure trigger_fsync(
    signal r_vsync   : out std_logic;
    signal r_field_n : out std_logic;
    constant interlaced : natural
  ) is
  begin
    if interlaced = 1 then
      r_field_n <= '1';
      wait until rising_edge(clk);
      r_field_n <= '0';
    else
      r_vsync <= '1';
      wait until rising_edge(clk);
      r_vsync <= '0';
    end if;
    wait until rising_edge(clk);
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2;

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
    variable v_hsync_prev          : std_logic;
    variable v_hsync_edge_count    : integer;
    variable v_trisync_stayed_zero : boolean;
    variable v_trisync_edge_count  : integer;
    variable v_trisync_prev        : std_logic;
    variable v_period_count        : integer;
    variable v_found_first_edge    : boolean;
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- ============================================================
      -- Common per-test setup: load timing config and trigger fsync
      -- ============================================================
      timing      <= std_logic_vector(to_unsigned(G_TIMING_ID, 4));
      ref_hsync   <= '0';
      ref_vsync   <= '0';
      ref_field_n <= '0';

      -- Let config pipeline settle
      for i in 1 to C_CONFIG_SETTLE loop
        wait until rising_edge(clk);
      end loop;

      -- Trigger frame sync
      trigger_fsync(ref_vsync, ref_field_n, G_IS_INTERLACED);

      -- Let fsync propagate into counters
      for i in 1 to C_CONFIG_SETTLE loop
        wait until rising_edge(clk);
      end loop;

      -- ============================================================
      if run("hsync_and_trisync_active") then
      -- ============================================================
        -- Count HSYNC edges over two full line periods
        v_hsync_prev       := hsync;
        v_hsync_edge_count := 0;

        v_trisync_prev        := trisync_p;
        v_trisync_edge_count  := 0;
        v_trisync_stayed_zero := true;

        for i in 1 to 2 * G_CLOCKS_PER_LINE loop
          wait until rising_edge(clk);

          -- Track HSYNC transitions
          if hsync /= v_hsync_prev then
            v_hsync_edge_count := v_hsync_edge_count + 1;
          end if;
          v_hsync_prev := hsync;

          -- Track trisync_p transitions
          if trisync_p /= '0' then
            v_trisync_stayed_zero := false;
          end if;
          if trisync_p /= v_trisync_prev then
            v_trisync_edge_count := v_trisync_edge_count + 1;
          end if;
          v_trisync_prev := trisync_p;
        end loop;

        -- HSYNC must pulse at least twice per line (rising + falling)
        check(v_hsync_edge_count >= 2,
              "HSYNC should have >= 2 edges in 2 lines (got " &
              integer'image(v_hsync_edge_count) & ")");

        -- Trisync correctness
        if G_TRISYNC_EN = 1 then
          check(v_trisync_edge_count >= 2,
                "trisync_p should be active when enabled (got " &
                integer'image(v_trisync_edge_count) & " edges)");
        else
          check(v_trisync_stayed_zero,
                "trisync_p should stay zero when disabled");
        end if;

      -- ============================================================
      elsif run("hsync_period_matches_line") then
      -- ============================================================
        -- Find the first rising edge of HSYNC
        v_hsync_prev      := hsync;
        v_found_first_edge := false;

        for i in 1 to 2 * G_CLOCKS_PER_LINE loop
          wait until rising_edge(clk);
          if hsync = '1' and v_hsync_prev = '0' then
            v_found_first_edge := true;
            exit;
          end if;
          v_hsync_prev := hsync;
        end loop;

        check(v_found_first_edge,
              "Should find an HSYNC rising edge within 2 line periods");

        -- Count clocks until the next rising edge
        v_hsync_prev   := hsync;
        v_period_count := 0;

        for i in 1 to G_CLOCKS_PER_LINE + 10 loop
          wait until rising_edge(clk);
          v_period_count := v_period_count + 1;
          if hsync = '1' and v_hsync_prev = '0' then
            -- Second rising edge found -- distance must equal line length
            check_equal(v_period_count, G_CLOCKS_PER_LINE,
                        "HSYNC period should equal clocks_per_line (" &
                        integer'image(G_CLOCKS_PER_LINE) & ")");
            exit;
          end if;
          v_hsync_prev := hsync;
        end loop;

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 100 ms);

end architecture;
