-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: video_field_detector.vhd - Video Field Detector
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
--   Detects field parity (odd/even) and interlace status from raw hsync and
--   vsync signals. Counts hsync edges between vsync events and compares
--   consecutive field lengths to determine interlace vs progressive.
--
-- Timing Behavior:
--   This is an event-driven detector, not a fixed-depth pipeline.
--   field_n and is_interlaced update on vsync rising edges based on the
--   line count observed in the preceding field. Latency is one full
--   field period before outputs are valid (first vsync edge after reset).
--   Internally uses 1-cycle edge detection on hsync and vsync.
--
-- Authors:
--   Lars Larsen

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_field_detector is
    generic (
        G_LINE_COUNTER_WIDTH : positive := 12
    );
    port (
        clk : in std_logic;
        hsync : in std_logic;
        vsync : in std_logic;
        field_n : out std_logic;
        is_interlaced : out std_logic
    );
end entity;

architecture rtl of video_field_detector is
    signal s_hsync_prev : std_logic := '1';
    signal s_vsync_prev : std_logic := '1';
    signal s_pixel_counter : unsigned(G_LINE_COUNTER_WIDTH -1 downto 0) := (others => '0');
    signal s_vsync_pixel_pos : unsigned(G_LINE_COUNTER_WIDTH -1 downto 0) := (others => '0');
    signal s_last_vsync_pixel_pos : unsigned(G_LINE_COUNTER_WIDTH -1 downto 0) := (others => '0');
    signal s_field_parity : std_logic := '0';
    signal s_interlaced : std_logic := '0';
begin

    process (clk)
    begin
        if rising_edge(clk) then
            s_hsync_prev <= hsync;
            s_vsync_prev <= vsync;

            s_pixel_counter <= s_pixel_counter + 1;

            -- HSYNC rising edge: reset pixel counter
            if s_hsync_prev = '0' and hsync = '1' then
                s_pixel_counter <= (others => '0');
            end if;

            -- VSYNC rising edge: capture position and determine field
            if s_vsync_prev = '0' and vsync = '1' then
                s_vsync_pixel_pos <= s_pixel_counter;

                -- Compare current VSYNC position with previous
                -- If positions differ significantly (half-line difference),
                -- fields alternate. Otherwise same field type.
                if s_vsync_pixel_pos < s_last_vsync_pixel_pos then
                    s_field_parity <= '1';  -- Odd field (earlier in line)
                    s_interlaced <= '1';    -- Different positions = interlaced
                else
                    s_field_parity <= '0';  -- Even field (later in line)
                    if s_vsync_pixel_pos = s_last_vsync_pixel_pos then
                        s_interlaced <= '0';  -- Same position = progressive
                    else
                        s_interlaced <= '1';  -- Different positions = interlaced
                    end if;
                end if;

                s_last_vsync_pixel_pos <= s_vsync_pixel_pos;
            end if;
        end if;
    end process;

    field_n <= not s_field_parity;
    is_interlaced <= s_interlaced;

end architecture;