-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: lfsr.vhd - Configurable Linear Feedback Shift Register
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
--   Variable-width LFSR with configurable polynomial. Data width and feedback
--   taps are set via generics for flexible pseudo-random sequence generation.
--
-- Timing Behavior:
--   This is a sequential state machine, not a pipeline. The shift register
--   updates on each rising clock edge when enable='1'. Output (lfsr_out)
--   reflects the register state with zero combinational delay.
--   reset='1' synchronously loads the seed value.
--   When enable='0' and reset='0', the register holds its current value.
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lfsr is
    generic (
        G_DATA_WIDTH : integer := 10
    );
    port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        enable   : in  std_logic;
        seed     : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        poly     : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        lfsr_out : out std_logic_vector(G_DATA_WIDTH - 1 downto 0)
    );
end entity;

architecture rtl of lfsr is
    signal s_lfsr_reg : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '1');
begin

    process(clk)
        variable v_feedback : std_logic;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                s_lfsr_reg <= seed;
            elsif enable = '1' then
                v_feedback := '0';
                for i in 0 to G_DATA_WIDTH - 1 loop
                    if poly(i) = '1' then
                        v_feedback := v_feedback xor s_lfsr_reg(i);
                    end if;
                end loop;
                s_lfsr_reg <= v_feedback & s_lfsr_reg(G_DATA_WIDTH - 1 downto 1);
            end if;
        end if;
    end process;

    lfsr_out <= s_lfsr_reg;

end architecture;
