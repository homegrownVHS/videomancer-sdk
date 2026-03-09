-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: frequency_doubler.vhd - Frequency Doubler / Ramp to Triangle Converter
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
--   Folds the input signal at its midpoint, effectively doubling the spatial
--   frequency of ramp-like patterns. Values below midpoint are scaled up by 2,
--   values above are mirrored and scaled. Cascading multiple instances creates
--   geometric harmonic multiplication (2x, 4x, 8x, 16x, etc.).
--
-- Pipeline Architecture (2 stages, 2 clock cycles latency):
--   Stage 0: Register inputs (data_in, data_enable, bypass)
--   Stage 1: Compute fold/bypass and register output
--
-- Latency:
--   data_out:   2 clock cycles from data_in
--   data_valid: 2 clock cycles from data_enable
--   Data and valid are synchronized (arrive on the same clock edge).
--   Pipeline depth is constant and independent of G_WIDTH.
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity frequency_doubler is
  generic (
    G_WIDTH : integer := 9
  );
  port (
    clk         : in  std_logic;
    bypass      : in  std_logic;
    data_enable : in  std_logic;
    data_in     : in  unsigned(G_WIDTH - 1 downto 0);
    data_out    : out unsigned(G_WIDTH - 1 downto 0);
    data_valid  : out std_logic
  );
end frequency_doubler;

architecture rtl of frequency_doubler is
  constant C_MIDPOINT  : unsigned(G_WIDTH - 1 downto 0) := to_unsigned( 2 ** (G_WIDTH - 1), G_WIDTH);
  constant C_MAXIMUM   : unsigned(G_WIDTH - 1 downto 0) := to_unsigned((2 ** G_WIDTH) - 1, G_WIDTH);
  signal s_bypass      : std_logic := '0';
  signal s_data_enable : std_logic := '0';
  signal s_data_in     : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal s_data_out    : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
  signal s_data_valid  : std_logic := '0';
begin

  -- Input register process
  process(clk)
  begin
    if rising_edge(clk) then
      s_bypass      <= bypass;
      s_data_enable <= data_enable;
      s_data_in     <= data_in;
    end if;
  end process;

  -- Rectification/Inversion logic process
  process(clk)
  begin
    if rising_edge(clk) then
        if s_bypass = '1' then
          s_data_out <= s_data_in;  -- Bypass mode
        else
            if s_data_in < C_MIDPOINT then
                s_data_out <= resize(s_data_in * 2, G_WIDTH);
            else
                s_data_out <= resize(C_MAXIMUM - ((s_data_in - C_MIDPOINT) * 2), G_WIDTH);
            end if;
        end if;
        s_data_valid <= s_data_enable;
    end if;
  end process;

  -- Output assignments
  data_out   <= s_data_out;
  data_valid <= s_data_valid;

end rtl;
