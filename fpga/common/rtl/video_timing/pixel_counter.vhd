-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: pixel_counter.vhd - Active-Region Pixel Coordinate Counter
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
--   Counts active-region pixel coordinates from a video_timing_generator
--   output port.  h_count increments once per active pixel (avid='1') and
--   resets on hsync_start.  v_count increments once per active line
--   (avid_start='1') and resets on vsync_start.
--
--   Replaces the identical 15-line p_counters process duplicated across
--   ~192 FPGA programs.
--
-- Latency:
--   1 clock cycle (registered outputs).
--
-- Resource cost:
--   2 x G_WIDTH flip-flops, no BRAM.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.video_timing_pkg.all;

entity pixel_counter is
    generic (
        G_WIDTH : natural := 12
    );
    port (
        clk     : in  std_logic;
        timing  : in  t_video_timing_port;
        h_count : out unsigned(G_WIDTH - 1 downto 0);
        v_count : out unsigned(G_WIDTH - 1 downto 0)
    );
end entity pixel_counter;

architecture rtl of pixel_counter is
    signal s_h_count : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
    signal s_v_count : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
begin

    h_count <= s_h_count;
    v_count <= s_v_count;

    p_counters : process(clk)
    begin
        if rising_edge(clk) then
            if timing.hsync_start = '1' then
                s_h_count <= (others => '0');
            elsif timing.avid = '1' then
                s_h_count <= s_h_count + 1;
            end if;

            if timing.vsync_start = '1' then
                s_v_count <= (others => '0');
            elsif timing.avid_start = '1' then
                s_v_count <= s_v_count + 1;
            end if;
        end if;
    end process;

end architecture rtl;
