-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: frame_counter.vhd - Vsync-Driven Frame Counter
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
--   Free-running frame counter that increments on each falling edge of
--   vsync_n (start of vertical sync = start of a new frame).  The counter
--   wraps naturally at 2^G_WIDTH.
--
--   Uses internal edge detection (1 flip-flop) so the caller does not
--   need to instantiate a separate edge_detector.
--
-- Latency:
--   1 clock cycle (registered output).
--
-- Resource cost:
--   G_WIDTH + 1 flip-flops, no BRAM.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity frame_counter is
    generic (
        G_WIDTH : natural := 16
    );
    port (
        clk     : in  std_logic;
        vsync_n : in  std_logic;
        count   : out unsigned(G_WIDTH - 1 downto 0)
    );
end entity frame_counter;

architecture rtl of frame_counter is
    signal s_count      : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
    signal s_vsync_prev : std_logic := '1';
begin

    count <= s_count;

    p_frame_count : process(clk)
    begin
        if rising_edge(clk) then
            s_vsync_prev <= vsync_n;

            if vsync_n = '0' and s_vsync_prev = '1' then
                s_count <= s_count + 1;
            end if;
        end if;
    end process;

end architecture rtl;
