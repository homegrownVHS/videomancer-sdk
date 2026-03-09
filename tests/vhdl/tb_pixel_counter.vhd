-- Videomancer SDK - VUnit Testbench for pixel_counter
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tests:
--   1.  Initial state -- h_count and v_count are 0
--   2.  H increments during avid -- h_count advances each avid='1' clock
--   3.  H resets on hsync_start -- h_count returns to 0
--   4.  H holds during blanking -- h_count frozen when avid='0'
--   5.  V increments on avid_start -- v_count advances once per line
--   6.  V resets on vsync_start -- v_count returns to 0
--   7.  Multi-line counting -- multiple lines produce correct v_count
--   8.  Full frame sequence -- complete frame with correct h/v at end
--   9.  Hsync_start priority -- hsync_start overrides avid for h_count

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.video_timing_pkg.all;

entity tb_pixel_counter is
    generic (runner_cfg : string);
end entity;

architecture tb of tb_pixel_counter is

    constant C_CLK_PERIOD : time := 10 ns;
    constant C_WIDTH      : natural := 12;

    signal clk       : std_logic := '0';
    signal timing    : t_video_timing_port;
    signal h_count   : unsigned(C_WIDTH - 1 downto 0);
    signal v_count   : unsigned(C_WIDTH - 1 downto 0);
    signal test_done : std_logic := '0';

    -- Helper: drive a simplified line of video timing
    -- active_pixels active clocks with avid='1', then blanking
    procedure drive_line(
        signal   s_timing   : out t_video_timing_port;
        signal   s_clk      : in  std_logic;
        constant active_px  : in  natural;
        constant is_first   : in  boolean := false
    ) is
    begin
        -- hsync_start pulse (1 clock)
        s_timing.hsync_start <= '1';
        s_timing.avid        <= '0';
        s_timing.avid_start  <= '0';
        s_timing.avid_end    <= '0';
        wait until rising_edge(s_clk);

        -- Blanking before active (2 clocks)
        s_timing.hsync_start <= '0';
        wait until rising_edge(s_clk);
        wait until rising_edge(s_clk);

        -- Active video starts
        s_timing.avid       <= '1';
        s_timing.avid_start <= '1';
        wait until rising_edge(s_clk);

        s_timing.avid_start <= '0';
        for i in 1 to active_px - 1 loop
            wait until rising_edge(s_clk);
        end loop;

        -- Active video ends
        s_timing.avid     <= '0';
        s_timing.avid_end <= '1';
        wait until rising_edge(s_clk);

        -- Blanking after active (2 clocks)
        s_timing.avid_end <= '0';
        wait until rising_edge(s_clk);
        wait until rising_edge(s_clk);
    end procedure;

begin

    clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

    -- Initialize timing port fields
    timing.hsync_n       <= '1';
    timing.vsync_n       <= '1';
    timing.field_n       <= '1';
    timing.vavid         <= '0';
    timing.is_interlaced <= '0';

    dut : entity rtl_lib.pixel_counter
        generic map (
            G_WIDTH => C_WIDTH
        )
        port map (
            clk     => clk,
            timing  => timing,
            h_count => h_count,
            v_count => v_count
        );

    test_runner_watchdog(runner, 10 ms);

    main : process
    begin
        test_runner_setup(runner, runner_cfg);

        -- Default: all timing signals inactive
        timing.hsync_start <= '0';
        timing.vsync_start <= '0';
        timing.avid        <= '0';
        timing.avid_start  <= '0';
        timing.avid_end    <= '0';

        while test_suite loop

            -- Reset timing between tests
            timing.hsync_start <= '0';
            timing.vsync_start <= '0';
            timing.avid        <= '0';
            timing.avid_start  <= '0';
            timing.avid_end    <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            -- ==============================================================
            if run("initial_state") then
            -- ==============================================================
                -- Send vsync_start to reset counters
                timing.vsync_start <= '1';
                wait until rising_edge(clk);
                timing.vsync_start <= '0';
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';
                wait until rising_edge(clk);
                check_equal(h_count, to_unsigned(0, C_WIDTH),
                    "h_count should be 0 after reset");
                check_equal(v_count, to_unsigned(0, C_WIDTH),
                    "v_count should be 0 after reset");

            -- ==============================================================
            elsif run("h_increments_during_avid") then
            -- ==============================================================
                -- Reset
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';
                wait until rising_edge(clk);

                -- 5 active pixels
                timing.avid <= '1';
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;
                timing.avid <= '0';
                wait until rising_edge(clk);
                -- After 5 avid clocks, h_count should be 5
                check_equal(h_count, to_unsigned(5, C_WIDTH),
                    "h_count should be 5 after 5 avid clocks");

            -- ==============================================================
            elsif run("h_resets_on_hsync_start") then
            -- ==============================================================
                -- Generate some active pixels
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';
                timing.avid <= '1';
                for i in 0 to 9 loop
                    wait until rising_edge(clk);
                end loop;
                timing.avid <= '0';
                wait until rising_edge(clk);
                -- h_count should be 10
                check_equal(h_count, to_unsigned(10, C_WIDTH),
                    "h_count should be 10 before reset");

                -- hsync_start resets
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';
                wait until rising_edge(clk);
                check_equal(h_count, to_unsigned(0, C_WIDTH),
                    "h_count should be 0 after hsync_start");

            -- ==============================================================
            elsif run("h_holds_during_blanking") then
            -- ==============================================================
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';

                -- 3 active pixels
                timing.avid <= '1';
                for i in 0 to 2 loop
                    wait until rising_edge(clk);
                end loop;
                timing.avid <= '0';

                -- 5 blanking clocks
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;

                -- h_count should still be 3
                check_equal(h_count, to_unsigned(3, C_WIDTH),
                    "h_count should hold at 3 during blanking");

            -- ==============================================================
            elsif run("v_increments_on_avid_start") then
            -- ==============================================================
                -- Reset v
                timing.vsync_start <= '1';
                wait until rising_edge(clk);
                timing.vsync_start <= '0';
                wait until rising_edge(clk);
                check_equal(v_count, to_unsigned(0, C_WIDTH),
                    "v_count should be 0 after vsync_start");

                -- First avid_start
                timing.avid_start <= '1';
                timing.avid <= '1';
                wait until rising_edge(clk);
                timing.avid_start <= '0';
                wait until rising_edge(clk);
                check_equal(v_count, to_unsigned(1, C_WIDTH),
                    "v_count should be 1 after first avid_start");

                -- Second avid_start
                timing.avid <= '0';
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';
                wait until rising_edge(clk);
                timing.avid_start <= '1';
                timing.avid <= '1';
                wait until rising_edge(clk);
                timing.avid_start <= '0';
                wait until rising_edge(clk);
                check_equal(v_count, to_unsigned(2, C_WIDTH),
                    "v_count should be 2 after second avid_start");

            -- ==============================================================
            elsif run("v_resets_on_vsync_start") then
            -- ==============================================================
                -- Drive a few avid_start pulses
                for line_num in 0 to 2 loop
                    timing.avid_start <= '1';
                    wait until rising_edge(clk);
                    timing.avid_start <= '0';
                    wait until rising_edge(clk);
                    wait until rising_edge(clk);
                end loop;
                -- v_count should be 3
                wait until rising_edge(clk);
                check_equal(v_count, to_unsigned(3, C_WIDTH),
                    "v_count should be 3 before vsync_start");

                -- vsync_start resets
                timing.vsync_start <= '1';
                wait until rising_edge(clk);
                timing.vsync_start <= '0';
                wait until rising_edge(clk);
                check_equal(v_count, to_unsigned(0, C_WIDTH),
                    "v_count should be 0 after vsync_start");

            -- ==============================================================
            elsif run("multi_line_counting") then
            -- ==============================================================
                -- Reset
                timing.vsync_start <= '1';
                wait until rising_edge(clk);
                timing.vsync_start <= '0';

                -- Drive 5 complete lines (8 active pixels each)
                for line_num in 0 to 4 loop
                    drive_line(timing, clk, 8);
                end loop;

                wait until rising_edge(clk);
                check_equal(v_count, to_unsigned(5, C_WIDTH),
                    "v_count should be 5 after 5 lines");

            -- ==============================================================
            elsif run("full_frame_sequence") then
            -- ==============================================================
                -- vsync_start -> 4 lines of 6 active pixels -> check
                timing.vsync_start <= '1';
                wait until rising_edge(clk);
                timing.vsync_start <= '0';

                for line_num in 0 to 3 loop
                    drive_line(timing, clk, 6);
                end loop;

                wait until rising_edge(clk);
                check_equal(v_count, to_unsigned(4, C_WIDTH),
                    "v_count should be 4 after full frame");
                -- h_count retains last active value (6) during blanking
                check_equal(h_count, to_unsigned(6, C_WIDTH),
                    "h_count should hold at 6 in blanking");

            -- ==============================================================
            elsif run("hsync_start_priority_over_avid") then
            -- ==============================================================
                -- hsync_start should reset h_count even if avid is also high
                -- (uses if/elsif: hsync_start wins)
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';

                timing.avid <= '1';
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;

                -- Now assert hsync_start while avid is high
                timing.hsync_start <= '1';
                wait until rising_edge(clk);
                timing.hsync_start <= '0';
                timing.avid <= '0';
                wait until rising_edge(clk);
                check_equal(h_count, to_unsigned(0, C_WIDTH),
                    "hsync_start should reset h_count even during avid");

            end if;

        end loop;

        test_done <= '1';
        test_runner_cleanup(runner);
    end process;

end architecture tb;
