-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: edge_detector.vhd - Rising/Falling Edge Detector
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
--   Single-cycle edge detector. Registers input and generates one-clock-wide
--   pulses on rising and falling transitions.
--
-- Latency:
--   b output:       1 clock cycle (registered copy of input a)
--   rising output:   Combinational (compares current a with registered a_ff).
--                    Asserts in the same cycle as the input rising edge.
--   falling output:  Combinational (compares current a with registered a_ff).
--                    Asserts in the same cycle as the input falling edge.
--   Pulse width is always exactly 1 clock cycle.
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity edge_detector is
  port(
    clk      : in  std_logic;
    a        : in  std_logic;
    b        : out std_logic;
    rising   : out std_logic;
    falling  : out std_logic
  );
end entity edge_detector;

architecture rtl of edge_detector is
  signal s_a_ff  : std_logic := '0';

begin
  process(clk)
  begin
    if rising_edge(clk) then
      s_a_ff  <= a;
    end if;
  end process;

  b <= s_a_ff;
  rising <= '1' when (a = '1' and s_a_ff = '0') else '0';
  falling <= '1' when (a = '0' and s_a_ff = '1') else '0';

end architecture rtl;
