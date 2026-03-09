-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: frame_phase_accumulator.vhd - Vsync-Driven Phase Accumulator (DDS)
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
--   Frame-rate phase accumulator (DDS).  On each falling edge of vsync_n,
--   if enable='1', the phase register advances by resize(speed, G_PHASE_WIDTH).
--   When enable='0' the phase holds its current value.
--
--   The phase register wraps naturally at 2^G_PHASE_WIDTH, giving a
--   continuous sawtooth ramp whose frequency is:
--
--     f_phase = f_frame * speed / 2^G_PHASE_WIDTH
--
--   Typical use: drive animation offsets, rotation angles, or pattern
--   scrolling in FPGA video programs.
--
-- Latency:
--   1 clock cycle (registered output).
--
-- Resource cost:
--   G_PHASE_WIDTH + 1 flip-flops, no BRAM.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity frame_phase_accumulator is
    generic (
        G_PHASE_WIDTH : natural := 16;
        G_SPEED_WIDTH : natural := 10
    );
    port (
        clk     : in  std_logic;
        vsync_n : in  std_logic;
        enable  : in  std_logic;
        speed   : in  unsigned(G_SPEED_WIDTH - 1 downto 0);
        phase   : out unsigned(G_PHASE_WIDTH - 1 downto 0)
    );
end entity frame_phase_accumulator;

architecture rtl of frame_phase_accumulator is
    signal s_phase      : unsigned(G_PHASE_WIDTH - 1 downto 0) := (others => '0');
    signal s_vsync_prev : std_logic := '1';
begin

    phase <= s_phase;

    p_phase_accum : process(clk)
    begin
        if rising_edge(clk) then
            s_vsync_prev <= vsync_n;

            if vsync_n = '0' and s_vsync_prev = '1' then
                if enable = '1' then
                    s_phase <= s_phase + resize(speed, G_PHASE_WIDTH);
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
