-- Videomancer SDK - VUnit Testbench for frame_phase_accumulator
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tests:
--   1.  Initial state -- phase is 0
--   2.  Single advance -- phase increases by speed on vsync falling edge
--   3.  Multiple advances -- phase accumulates correctly
--   4.  Enable gate -- phase holds when enable='0'
--   5.  Enable toggle -- phase advances only on enabled frames
--   6.  Speed change -- new speed value used on next vsync
--   7.  Phase wrapping -- natural wrap at 2^G_PHASE_WIDTH
--   8.  Zero speed -- phase holds even with enable='1'
--   9.  Max speed -- phase advances by all-ones each frame
--  10.  Speed resize -- narrow speed correctly zero-extended to phase width

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_frame_phase_accumulator is
    generic (runner_cfg : string);
end entity;

architecture tb of tb_frame_phase_accumulator is

    constant C_CLK_PERIOD   : time    := 10 ns;
    constant C_PHASE_WIDTH  : natural := 16;
    constant C_SPEED_WIDTH  : natural := 10;

    signal clk       : std_logic := '0';
    signal vsync_n   : std_logic := '1';
    signal enable    : std_logic := '1';
    signal speed     : unsigned(C_SPEED_WIDTH - 1 downto 0) := (others => '0');
    signal phase     : unsigned(C_PHASE_WIDTH - 1 downto 0);
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

    dut : entity rtl_lib.frame_phase_accumulator
        generic map (
            G_PHASE_WIDTH => C_PHASE_WIDTH,
            G_SPEED_WIDTH => C_SPEED_WIDTH
        )
        port map (
            clk     => clk,
            vsync_n => vsync_n,
            enable  => enable,
            speed   => speed,
            phase   => phase
        );

    test_runner_watchdog(runner, 10 ms);

    main : process
        variable v_expected_phase : unsigned(C_PHASE_WIDTH - 1 downto 0);
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- Reset between tests
            vsync_n <= '1';
            enable  <= '1';
            speed   <= (others => '0');
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            -- ==============================================================
            if run("initial_state") then
            -- ==============================================================
                check_equal(phase, to_unsigned(0, C_PHASE_WIDTH),
                    "phase should be 0 initially");

            -- ==============================================================
            elsif run("single_advance") then
            -- ==============================================================
                speed <= to_unsigned(100, C_SPEED_WIDTH);
                wait until rising_edge(clk);  -- Let speed propagate

                -- Vsync falling edge
                pulse_vsync(vsync_n, clk, 2);
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                check_equal(phase, to_unsigned(100, C_PHASE_WIDTH),
                    "phase should be 100 after one frame with speed=100");

            -- ==============================================================
            elsif run("multiple_advances") then
            -- ==============================================================
                speed <= to_unsigned(50, C_SPEED_WIDTH);
                wait until rising_edge(clk);

                for frame in 1 to 10 loop
                    pulse_vsync(vsync_n, clk, 2);
                    -- Active video gap
                    for i in 0 to 4 loop
                        wait until rising_edge(clk);
                    end loop;
                end loop;

                check_equal(phase, to_unsigned(500, C_PHASE_WIDTH),
                    "phase should be 500 after 10 frames with speed=50");

            -- ==============================================================
            elsif run("enable_gate") then
            -- ==============================================================
                speed  <= to_unsigned(200, C_SPEED_WIDTH);
                enable <= '0';
                wait until rising_edge(clk);

                -- 3 vsync pulses with enable=0
                for frame in 0 to 2 loop
                    pulse_vsync(vsync_n, clk, 2);
                    wait until rising_edge(clk);
                    wait until rising_edge(clk);
                end loop;

                check_equal(phase, to_unsigned(0, C_PHASE_WIDTH),
                    "phase should stay 0 when disabled");

            -- ==============================================================
            elsif run("enable_toggle") then
            -- ==============================================================
                speed <= to_unsigned(100, C_SPEED_WIDTH);
                wait until rising_edge(clk);

                -- Frame 1: enabled
                enable <= '1';
                wait until rising_edge(clk);
                pulse_vsync(vsync_n, clk, 2);
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;

                -- Frame 2: disabled
                enable <= '0';
                wait until rising_edge(clk);
                pulse_vsync(vsync_n, clk, 2);
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;

                -- Frame 3: enabled
                enable <= '1';
                wait until rising_edge(clk);
                pulse_vsync(vsync_n, clk, 2);
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;

                -- Should have advanced for frames 1 and 3 only
                check_equal(phase, to_unsigned(200, C_PHASE_WIDTH),
                    "phase should be 200 (2 enabled frames x 100)");

            -- ==============================================================
            elsif run("speed_change") then
            -- ==============================================================
                -- Frame 1 with speed=100
                speed <= to_unsigned(100, C_SPEED_WIDTH);
                wait until rising_edge(clk);
                pulse_vsync(vsync_n, clk, 2);
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;

                -- Frame 2 with speed=300
                speed <= to_unsigned(300, C_SPEED_WIDTH);
                wait until rising_edge(clk);
                pulse_vsync(vsync_n, clk, 2);
                for i in 0 to 4 loop
                    wait until rising_edge(clk);
                end loop;

                check_equal(phase, to_unsigned(400, C_PHASE_WIDTH),
                    "phase should be 400 (100 + 300)");

            -- ==============================================================
            elsif run("phase_wrapping") then
            -- ==============================================================
                -- Use speed=1023 (max 10-bit), drive enough frames to wrap
                speed <= to_unsigned(1023, C_SPEED_WIDTH);
                wait until rising_edge(clk);

                -- 64 frames x 1023 = 65472 -> phase mod 65536 = 65472
                for frame in 0 to 63 loop
                    pulse_vsync(vsync_n, clk, 2);
                    wait until rising_edge(clk);
                end loop;
                v_expected_phase := to_unsigned(65472, C_PHASE_WIDTH);
                check_equal(phase, v_expected_phase,
                    "phase should be 65472 after 64 frames");

                -- 1 more frame: 65472 + 1023 = 66495 mod 65536 = 959
                pulse_vsync(vsync_n, clk, 2);
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                v_expected_phase := to_unsigned(959, C_PHASE_WIDTH);
                check_equal(phase, v_expected_phase,
                    "phase should wrap to 959");

            -- ==============================================================
            elsif run("zero_speed") then
            -- ==============================================================
                speed  <= to_unsigned(0, C_SPEED_WIDTH);
                enable <= '1';
                wait until rising_edge(clk);

                for frame in 0 to 4 loop
                    pulse_vsync(vsync_n, clk, 2);
                    wait until rising_edge(clk);
                    wait until rising_edge(clk);
                end loop;

                check_equal(phase, to_unsigned(0, C_PHASE_WIDTH),
                    "phase should stay 0 with speed=0");

            -- ==============================================================
            elsif run("max_speed") then
            -- ==============================================================
                speed <= (others => '1');  -- 1023
                wait until rising_edge(clk);

                pulse_vsync(vsync_n, clk, 2);
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                check_equal(phase, to_unsigned(1023, C_PHASE_WIDTH),
                    "phase should be 1023 after one frame with max speed");

            -- ==============================================================
            elsif run("speed_resize") then
            -- ==============================================================
                -- speed is 10-bit, phase is 16-bit
                -- Speed=1 should add 1 to 16-bit phase (zero-extended)
                speed <= to_unsigned(1, C_SPEED_WIDTH);
                wait until rising_edge(clk);

                pulse_vsync(vsync_n, clk, 2);
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                check_equal(phase, to_unsigned(1, C_PHASE_WIDTH),
                    "speed=1 should add 1 to 16-bit phase");

            end if;

        end loop;

        test_done <= '1';
        test_runner_cleanup(runner);
    end process;

end architecture tb;
