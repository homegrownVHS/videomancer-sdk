-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: lfsr16.vhd - 16-bit Maximal-Length LFSR
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
--   16-bit maximal-length LFSR for pseudo-random noise generation.
--   Taps at bits 16, 15, 13, 4 (x^16 + x^15 + x^13 + x^4 + 1).
--   Includes seed loading with all-zeros lockup prevention.
--
-- Timing Behavior:
--   This is a sequential state machine, not a pipeline. The shift register
--   updates on each rising clock edge when enable='1'. Output (q) reflects
--   the register state with zero combinational delay.
--   load='1' synchronously loads the seed value (with all-zeros protection).
--   When enable='0' and load='0', the register holds its current value.
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lfsr16 is
    port (
        clk    : in  std_logic;
        enable : in  std_logic;
        seed   : in  std_logic_vector(15 downto 0);
        load   : in  std_logic;
        q      : out std_logic_vector(15 downto 0)
    );
end entity lfsr16;

architecture rtl of lfsr16 is
    signal s_sr : std_logic_vector(15 downto 0) := x"ACE1";
begin

    process(clk)
        variable v_feedback : std_logic;
    begin
        if rising_edge(clk) then
            if load = '1' then
                if unsigned(seed) = 0 then
                    s_sr <= x"ACE1";  -- prevent all-zeros lockup
                else
                    s_sr <= seed;
                end if;
            elsif enable = '1' then
                v_feedback := s_sr(15) xor s_sr(14) xor s_sr(12) xor s_sr(3);
                s_sr <= s_sr(14 downto 0) & v_feedback;
            end if;
        end if;
    end process;

    q <= s_sr;

end architecture rtl;
