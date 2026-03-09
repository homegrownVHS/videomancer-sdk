-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: variable_delay_u.vhd - BRAM Variable Delay Line (Unsigned)
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
--   BRAM-based variable delay line for unsigned values. Uses a circular buffer
--   with configurable depth. Delay amount is adjustable at runtime.
--
-- Pipeline Architecture:
--   The module has a fixed 2-cycle pipeline overhead on top of the
--   programmed delay amount:
--     Cycle 1: Address generation (register delay input, compute read/write
--              addresses, write data to BRAM, assert valid)
--     Cycle 2: BRAM read (registered output from read address)
--
-- Latency:
--   valid:  1 clock cycle after enable (set in address-gen process)
--   result: 2 clock cycles after enable (BRAM read register follows)
--   Note: valid leads result by 1 clock cycle. When using valid as a
--   data qualifier in streaming mode, sample result 1 cycle after valid.
--
--   Total sample delay = programmed delay + 2 cycles pipeline overhead.
--   When delay=0, read address equals write address (minimum latency).
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity variable_delay_u is
    generic (
        G_WIDTH : integer := 32; -- Bits width of the data input
        G_DEPTH : integer := 11  -- Bits depth of the delay line
    );
    port (
        clk    : in std_logic;
        enable : in std_logic;
        delay  : in unsigned(G_DEPTH - 1 downto 0);
        a      : in unsigned(G_WIDTH - 1 downto 0);
        result : out unsigned(G_WIDTH - 1 downto 0);
        valid  : out std_logic
    );
end entity variable_delay_u;

architecture rtl of variable_delay_u is

    type t_ram is array(0 to ((2 ** G_DEPTH) - 1)) of unsigned(G_WIDTH - 1 downto 0);
    signal s_ram     : t_ram := (others => (others => '0'));  -- Initialize RAM to zero
    signal s_output  : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
    signal s_wr_addr : unsigned(G_DEPTH - 1 downto 0) := (others => '0');
    signal s_rd_addr : unsigned(G_DEPTH - 1 downto 0) := (others => '0');
    signal s_count   : unsigned(G_DEPTH - 1 downto 0) := (others => '0');
    signal s_delay   : unsigned(G_DEPTH - 1 downto 0) := (others => '0');  -- Register delay input
    signal s_valid   : std_logic := '0';

begin

    -- Address generation and control logic
    process (clk)
    begin
        if rising_edge(clk) then
            if enable = '1' then
                -- Register the delay input for stable operation
                s_delay <= delay;

                -- Increment counter
                s_count <= s_count + 1;

                -- Write address is the current counter value
                s_wr_addr <= s_count;

                -- Read address trails write address by (delay - 1) to account for
                -- the RAM read register (1 cycle) plus output register (1 cycle) = 2 cycles
                if s_delay = 0 then
                    -- When delay=0, read the address being written for minimum 1-cycle latency
                    s_rd_addr <= s_count;
                else
                    -- For non-zero delay, read (delay-1) addresses behind write
                    s_rd_addr <= s_count - (s_delay - 1);
                end if;

                s_valid <= '1';
            else
                s_valid <= '0';
            end if;
        end if;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            s_output <= s_ram(to_integer(s_rd_addr));
        end if;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            s_ram(to_integer(s_wr_addr)) <= a;
        end if;
    end process;

    result <= s_output;
    valid  <= s_valid;

end architecture rtl;
