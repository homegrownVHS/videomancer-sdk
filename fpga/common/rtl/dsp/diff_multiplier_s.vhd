-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: diff_multiplier_s.vhd - 4-Quadrant Multiplier with Differential Inputs
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
--   4-quadrant multiplier with differential (pos/neg) inputs on X, Y, and Z.
--   Stage 1 computes the differences (pos - neg) for each pair.
--   Stage 2 saturates the differences to the output range.
--   Stages 3+ feed (x_diff * y_diff + z_diff) into the multiplier_s module.
--
-- Pipeline Architecture:
--   Stage 0: Compute differences (pos - neg) for X, Y, Z    [1 cycle]
--   Stage 1: Saturate differences to output range            [1 cycle]
--   Stage 2..N: multiplier_s pipeline                        [(G_WIDTH+1)/2 + 3 cycles data]
--
-- Latency (clock cycles from enable assertion to output):
--   Valid signal:  (G_WIDTH+1)/2 + 4 cycles
--   Data output:   (G_WIDTH+1)/2 + 5 cycles
--
--   Valid leads result by 1 clock cycle (inherited from multiplier_s).
--
--   Example latencies:
--     G_WIDTH=6:  valid=7,  data=8  cycles
--     G_WIDTH=8:  valid=8,  data=9  cycles
--     G_WIDTH=10: valid=9,  data=10 cycles
--     G_WIDTH=12: valid=10, data=11 cycles
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.all;

entity diff_multiplier_s is
  generic (
    G_WIDTH      : integer := 8;
    G_FRAC_BITS  : integer := 7;
    G_OUTPUT_MIN : integer := - 128;
    G_OUTPUT_MAX : integer := 127
  );
  port (
    clk    : in std_logic;
    enable : in std_logic;
    x_pos  : in signed(G_WIDTH - 1 downto 0);
    x_neg  : in signed(G_WIDTH - 1 downto 0);
    y_pos  : in signed(G_WIDTH - 1 downto 0);
    y_neg  : in signed(G_WIDTH - 1 downto 0);
    z_pos  : in signed(G_WIDTH - 1 downto 0);
    z_neg  : in signed(G_WIDTH - 1 downto 0);
    result : out signed(G_WIDTH - 1 downto 0);
    valid  : out std_logic
  );
end diff_multiplier_s;

architecture rtl of diff_multiplier_s is
  constant C_ADDER_STAGE_OUTPUT_MIN : integer := - (2 ** (G_WIDTH - 1));
  constant C_ADDER_STAGE_OUTPUT_MAX : integer := 2 ** (G_WIDTH - 1) - 1;
  constant C_SUM_WIDTH : integer := G_WIDTH + 1;
  constant C_OUTPUT_MIN : signed(G_WIDTH - 1 downto 0) := to_signed(C_ADDER_STAGE_OUTPUT_MIN, G_WIDTH);
  constant C_OUTPUT_MAX : signed(G_WIDTH - 1 downto 0) := to_signed(C_ADDER_STAGE_OUTPUT_MAX, G_WIDTH);
  constant C_OUTPUT_MIN_EXT : signed(C_SUM_WIDTH - 1 downto 0) := to_signed(C_ADDER_STAGE_OUTPUT_MIN, C_SUM_WIDTH);
  constant C_OUTPUT_MAX_EXT : signed(C_SUM_WIDTH - 1 downto 0) := to_signed(C_ADDER_STAGE_OUTPUT_MAX, C_SUM_WIDTH);

  signal s_sum_x : signed(C_SUM_WIDTH - 1 downto 0);
  signal s_sum_y : signed(C_SUM_WIDTH - 1 downto 0);
  signal s_sum_z : signed(C_SUM_WIDTH - 1 downto 0);
  signal s_valid_1 : std_logic;

  signal s_diff_x : signed(G_WIDTH - 1 downto 0);
  signal s_diff_y : signed(G_WIDTH - 1 downto 0);
  signal s_diff_z : signed(G_WIDTH - 1 downto 0);
  signal s_valid_2 : std_logic;

  signal s_multiplier_result : signed(G_WIDTH - 1 downto 0);
  signal s_multiplier_valid : std_logic;
begin

  -- Stage 0: Perform all three subtractions in parallel
  process(clk)
  begin
    if rising_edge(clk) then
      s_sum_x <= resize(x_pos, C_SUM_WIDTH) - resize(x_neg, C_SUM_WIDTH);
      s_sum_y <= resize(y_pos, C_SUM_WIDTH) - resize(y_neg, C_SUM_WIDTH);
      s_sum_z <= resize(z_pos, C_SUM_WIDTH) - resize(z_neg, C_SUM_WIDTH);
      s_valid_1 <= enable;
    end if;
  end process;

  -- Stage 1: Apply saturation to all three results in parallel
  process(clk)
  begin
    if rising_edge(clk) then
      -- Saturate x
      if s_sum_x < C_OUTPUT_MIN_EXT then
        s_diff_x <= C_OUTPUT_MIN;
      elsif s_sum_x > C_OUTPUT_MAX_EXT then
        s_diff_x <= C_OUTPUT_MAX;
      else
        s_diff_x <= resize(s_sum_x, G_WIDTH);
      end if;

      -- Saturate y
      if s_sum_y < C_OUTPUT_MIN_EXT then
        s_diff_y <= C_OUTPUT_MIN;
      elsif s_sum_y > C_OUTPUT_MAX_EXT then
        s_diff_y <= C_OUTPUT_MAX;
      else
        s_diff_y <= resize(s_sum_y, G_WIDTH);
      end if;

      -- Saturate z
      if s_sum_z < C_OUTPUT_MIN_EXT then
        s_diff_z <= C_OUTPUT_MIN;
      elsif s_sum_z > C_OUTPUT_MAX_EXT then
        s_diff_z <= C_OUTPUT_MAX;
      else
        s_diff_z <= resize(s_sum_z, G_WIDTH);
      end if;

      s_valid_2 <= s_valid_1;
    end if;
  end process;

  -- Stage 3+: Multiplier
  multiplier_xyz_inst : entity work.multiplier_s
    generic map(
      G_WIDTH      => G_WIDTH,
      G_FRAC_BITS  => G_FRAC_BITS,
      G_OUTPUT_MIN => G_OUTPUT_MIN,
      G_OUTPUT_MAX => G_OUTPUT_MAX
    )
    port map(
      clk    => clk,
      enable => s_valid_2,
      x      => s_diff_x,
      y      => s_diff_y,
      z      => s_diff_z,
      result => s_multiplier_result,
      valid  => s_multiplier_valid
    );

  result <= s_multiplier_result;
  valid  <= s_multiplier_valid;

end rtl;
