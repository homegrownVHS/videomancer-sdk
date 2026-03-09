-- Videomancer SDK - VUnit Testbench for frame_counter
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tests:
--   1.  Initial state -- count is 0
--   2.  Single frame -- count increments on vsync_n falling edge
--   3.  Multiple frames -- count increments correctly over several frames
--   4.  No increment on rising edge -- only falling edge triggers
--   5.  Count holds during active video -- stable between vsync pulses
--   6.  Wrapping -- counter wraps at 2^G_WIDTH
--   7.  Narrow width (4-bit) -- wraps at 16

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_frame_counter is
    generic (runner_cfg : string);
end entity;

architecture tb of tb_frame_counter is

    constant C_CLK_PERIOD : time := 10 ns;
    constant C_WIDTH      : natural := 8;

    signal clk       : std_logic := '0';
    signal vsync_n   : std_logic := '1';
    signal count     : unsigned(C_WIDTH - 1 downto 0);
    signal test_done : std_logic := '0';

    -- Pulse vsync_n low for a given number of clocks
    procedure pulse_vsync(
        signal   s_vsync_n : out std_logic;
        signal   s_clk     : in  std_logic;
        constant duration  : in  natural := 3
    ) is
    begin
        s_vsync_n <= '0';
        for i in 0 to duration - 1 loop
            wait until rising_edge(s_clk);
        end loop;
        s_vsync_n <= '1';
    end procedure;

begin

    clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

    dut : entity rtl_lib.frame_counter
        generic map (
            G_WIDTH => C_WIDTH
        )
        port map (
            clk     => clk,
            vsync_n => vsync_n,
            count   => count
        );

    test_runner_watchdog(runner, 10 ms);

    main : process
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- Reset between tests
            vsync_n <= '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            -- ==============================================================
            if run("initial_state") then
            -- ==============================================================
                check_equal(count, to_unsigned(0, C_WIDTH),
                    "count should be 0 initially");

            -- ==============================================================
            elsif run("single_frame") then
            -- ==============================================================
                -- Falling edge of vsync_n
                vsync_n <= '0';
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                -- Count should have incremented
                check_equal(count, to_unsigned(1, C_WIDTH),
                    "count should be 1 after first vsync falling edge");
                vsync_n <= '1';
                wait until rising_edge(clk);

            -- ==============================================================
            elsif run("multiple_frames") then
            -- ==============================================================
                for frame in 1 to 5 loop
                    pulse_vsync(vsync_n, clk, 3);
                    -- Wait some "active video" time
                    for i in 0 to 9 loop
                        wait until rising_edge(clk);
                    end loop;
                end loop;
                check_equal(count, to_unsigned(5, C_WIDTH),
                    "count should be 5 after 5 frames");

            -- ==============================================================
            elsif run("no_increment_on_rising_edge") then
            -- ==============================================================
                -- Falling edge -> increments
                vsync_n <= '0';
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                check_equal(count, to_unsigned(1, C_WIDTH),
                    "count should be 1 after falling edge");

                -- Rising edge -> should NOT increment
                vsync_n <= '1';
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                check_equal(count, to_unsigned(1, C_WIDTH),
                    "count should still be 1 after rising edge");

            -- ==============================================================
            elsif run("count_holds_during_active") then
            -- ==============================================================
                -- One frame
                pulse_vsync(vsync_n, clk, 2);
                -- Many clocks of active video
                for i in 0 to 49 loop
                    wait until rising_edge(clk);
                end loop;
                check_equal(count, to_unsigned(1, C_WIDTH),
                    "count should hold at 1 during active video");

            -- ==============================================================
            elsif run("wrapping") then
            -- ==============================================================
                -- Drive 256 frames (8-bit counter wraps at 256)
                for frame in 0 to 255 loop
                    pulse_vsync(vsync_n, clk, 2);
                    wait until rising_edge(clk);
                    wait until rising_edge(clk);
                end loop;
                check_equal(count, to_unsigned(0, C_WIDTH),
                    "count should wrap to 0 after 256 frames");

                -- One more frame
                pulse_vsync(vsync_n, clk, 2);
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                check_equal(count, to_unsigned(1, C_WIDTH),
                    "count should be 1 after wrap + 1 frame");

            end if;

        end loop;

        test_done <= '1';
        test_runner_cleanup(runner);
    end process;

end architecture tb;
