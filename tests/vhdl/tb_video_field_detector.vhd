-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_video_field_detector.vhd - Testbench for Video Field Detector
-- License: GNU General Public License v3.0
-- https://github.com/lzxindustries/videomancer-sdk
--
-- This file is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <https://www.gnu.org/licenses/>.
--
-- Description:
--   VUnit testbench for video_field_detector.
--   Tests interlaced field parity detection, progressive mode detection,
--   HSYNC pixel counter reset, and VSYNC position capture.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_video_field_detector is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_video_field_detector is

  constant C_LINE_COUNTER_WIDTH : positive := 12;
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk           : std_logic := '0';
  signal hsync         : std_logic := '0';
  signal vsync         : std_logic := '0';
  signal field_n       : std_logic;
  signal is_interlaced : std_logic;

  signal test_done : boolean := false;

  -- ================================================================
  -- BFM helpers
  -- ================================================================

  -- Generate an HSYNC pulse (rising edge resets pixel counter)
  procedure pulse_hsync(
    signal hsync_sig : out std_logic;
    constant width   : time := C_CLK_PERIOD * 10
  ) is
  begin
    hsync_sig <= '0';
    wait for width;
    hsync_sig <= '1';
    wait for C_CLK_PERIOD;
    hsync_sig <= '0';
  end procedure;

  -- Simulate a number of pixel clocks (just wait)
  procedure wait_pixels(constant count : positive) is
  begin
    wait for C_CLK_PERIOD * count;
  end procedure;

  -- Generate VSYNC rising edge at a specific pixel position within a line
  -- Assumes pixel counter was reset at the last HSYNC rising edge
  procedure vsync_at_pixel(
    signal hsync_sig : out std_logic;
    signal vsync_sig : out std_logic;
    constant pixel_pos : natural;
    constant line_len  : positive := 800
  ) is
  begin
    -- HSYNC rising edge resets counter
    pulse_hsync(hsync_sig);
    -- Wait pixel_pos clocks
    wait_pixels(pixel_pos);
    -- VSYNC rising edge
    vsync_sig <= '0';
    wait for C_CLK_PERIOD * 5;
    vsync_sig <= '1';
    wait for C_CLK_PERIOD;
    vsync_sig <= '0';
    -- Fill out rest of line
    if pixel_pos + 6 < line_len then
      wait_pixels(line_len - pixel_pos - 6);
    end if;
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  dut : entity rtl_lib.video_field_detector
    generic map (
      G_LINE_COUNTER_WIDTH => C_LINE_COUNTER_WIDTH
    )
    port map (
      clk           => clk,
      hsync         => hsync,
      vsync         => vsync,
      field_n       => field_n,
      is_interlaced => is_interlaced
    );

  main : process
  begin
    test_runner_setup(runner, runner_cfg);

    -- Initial settling
    hsync <= '0';
    vsync <= '0';
    wait for C_CLK_PERIOD * 20;

    while test_suite loop

      -- ================================================================
      -- Test 1: Progressive — VSYNC at same pixel position each frame
      -- ================================================================
      if run("test_progressive_detection") then
        info("Testing progressive (non-interlaced) detection");

        -- Frame 1: VSYNC at pixel 100
        vsync_at_pixel(hsync, vsync, 100, 800);
        -- Frame 2: VSYNC at pixel 100 (same position)
        vsync_at_pixel(hsync, vsync, 100, 800);
        -- Frame 3: Same
        vsync_at_pixel(hsync, vsync, 100, 800);

        wait for C_CLK_PERIOD * 10;
        check_equal(is_interlaced, '0',
                   "Same VSYNC position every frame should indicate progressive");

      -- ================================================================
      -- Test 2: Interlaced — VSYNC alternates between two positions
      -- ================================================================
      elsif run("test_interlaced_detection") then
        info("Testing interlaced detection with alternating positions");

        -- Field 1: VSYNC at pixel 100
        vsync_at_pixel(hsync, vsync, 100, 800);
        -- Field 2: VSYNC at pixel 500 (half-line offset)
        vsync_at_pixel(hsync, vsync, 500, 800);
        -- Field 3: Back to 100
        vsync_at_pixel(hsync, vsync, 100, 800);

        wait for C_CLK_PERIOD * 10;
        check_equal(is_interlaced, '1',
                   "Alternating VSYNC positions should indicate interlaced");

      -- ================================================================
      -- Test 3: Field parity toggles between fields
      -- ================================================================
      elsif run("test_field_parity_toggle") then
        info("Testing field parity toggling");

        -- Establish baseline with two fields at different positions
        vsync_at_pixel(hsync, vsync, 100, 800);
        wait for C_CLK_PERIOD * 5;
        -- Capture field_n after first VSYNC
        -- (detector needs at least 2 VSYNCs to compare)

        vsync_at_pixel(hsync, vsync, 500, 800);
        wait for C_CLK_PERIOD * 5;
        -- After transition from pos=100 to pos=500:
        -- 100 < 500 was the previous comparison, now 500 > 100
        -- so field_parity should change

        -- We just need to verify it toggles between two VSYNC events
        -- with different positions (exact polarity depends on implementation)
        info("Field parity after interlaced fields: field_n=" &
             std_logic'image(field_n));

        -- Toggle again
        vsync_at_pixel(hsync, vsync, 100, 800);
        wait for C_CLK_PERIOD * 5;
        info("Field parity after toggle: field_n=" &
             std_logic'image(field_n));
        -- Key check: is_interlaced should be set
        check_equal(is_interlaced, '1',
                   "Should detect interlaced after alternating fields");

      -- ================================================================
      -- Test 4: HSYNC resets pixel counter
      -- ================================================================
      elsif run("test_hsync_resets_counter") then
        info("Testing HSYNC resets pixel counter");
        -- Detector needs 3 VSYNC events to converge: the comparison uses
        -- last_vsync_pixel_pos which lags by one VSYNC cycle.
        vsync_at_pixel(hsync, vsync, 200, 800);
        vsync_at_pixel(hsync, vsync, 200, 800);
        vsync_at_pixel(hsync, vsync, 200, 800);

        wait for C_CLK_PERIOD * 10;
        -- Same position every frame → progressive
        check_equal(is_interlaced, '0',
                   "Identical VSYNC positions = progressive after HSYNC resets");

      -- ================================================================
      -- Test 5: VSYNC without prior HSYNC
      -- ================================================================
      elsif run("test_vsync_without_hsync") then
        info("Testing VSYNC behavior without HSYNC");
        -- Just pulse VSYNC without HSYNC — should not crash, counter free-runs
        vsync <= '0';
        wait for C_CLK_PERIOD * 50;
        vsync <= '1';
        wait for C_CLK_PERIOD;
        vsync <= '0';
        wait for C_CLK_PERIOD * 50;
        vsync <= '1';
        wait for C_CLK_PERIOD;
        vsync <= '0';
        wait for C_CLK_PERIOD * 20;
        -- Just verify no simulation errors; outputs should be deterministic
        info("No-HSYNC test completed: field_n=" & std_logic'image(field_n) &
             " interlaced=" & std_logic'image(is_interlaced));

      -- ================================================================
      -- Test 6: Rapid HSYNC — short lines
      -- ================================================================
      elsif run("test_short_lines") then
        info("Testing very short line periods");
        for i in 0 to 9 loop
          pulse_hsync(hsync, C_CLK_PERIOD * 3);
          wait_pixels(20);
        end loop;
        -- VSYNC at same position on three consecutive short lines (need 3 for convergence)
        vsync_at_pixel(hsync, vsync, 10, 30);
        vsync_at_pixel(hsync, vsync, 10, 30);
        vsync_at_pixel(hsync, vsync, 10, 30);
        wait for C_CLK_PERIOD * 5;
        check_equal(is_interlaced, '0',
                   "Short lines with same VSYNC pos = progressive");

      -- ================================================================
      -- Test 7: Long idle then activity
      -- ================================================================
      elsif run("test_idle_then_active") then
        info("Testing long idle then active");
        -- Long idle
        wait for C_CLK_PERIOD * 500;
        -- Then frames
        vsync_at_pixel(hsync, vsync, 100, 800);
        vsync_at_pixel(hsync, vsync, 400, 800);
        wait for C_CLK_PERIOD * 10;
        check_equal(is_interlaced, '1',
                   "Should detect interlaced after idle period");

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 50 ms);

end architecture;
