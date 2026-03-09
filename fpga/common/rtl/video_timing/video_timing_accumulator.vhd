-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: video_timing_accumulator.vhd - Video-Synced Phase Accumulator
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
--   Phase accumulator synchronized to video timing events (vsync, avid, or
--   free-running). Supports animation (per-frame), vertical (per-line), and
--   horizontal (per-pixel) accumulation ranges with optional lock/reset.
--   Outputs the accumulator value, MSB clock, and MSB falling-edge pulse.
--
-- Pipeline Architecture:
--   Stage 0: Register all inputs (timing, range, reset, lock, accumulator)
--   Stage 1: Accumulator logic (conditional add/reset based on range mode)
--   Stage 2: MSB edge detection (s_last_msb latch for pulse generation)
--
-- Latency:
--   o_accumulator: 2 clock cycles from input change (input reg + accum logic)
--   o_clock:       2 clock cycles (combinational from o_accumulator MSB)
--   o_pulse:       3 clock cycles (requires s_last_msb comparison, which is
--                  registered 1 cycle after accumulator updates)
--   Note: o_pulse is combinational comparing s_last_msb (3 cycles) with
--   current MSB (2 cycles), so it asserts on the cycle after MSB falls.
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_timing_pkg.all;

entity video_timing_accumulator is
  generic (
    G_ACCUMULATOR_WIDTH : integer := 16  -- Width of the accumulator
  );
  port (
    clk             : in  std_logic;
    i_timing        : in  t_video_timing_port;
    i_range         : in  t_video_timing_range;
    i_reset         : in  std_logic;
    i_lock          : in  std_logic;
    i_accumulator   : in  std_logic_vector(G_ACCUMULATOR_WIDTH - 1 downto 0);
    o_accumulator   : out std_logic_vector(G_ACCUMULATOR_WIDTH - 1 downto 0);
    o_clock         : out std_logic;
    o_pulse         : out std_logic
  );
end video_timing_accumulator;

architecture rtl of video_timing_accumulator is
  signal s_i_timing        : t_video_timing_port := (others => '0');
  signal s_i_range         : t_video_timing_range := C_ANIMATION;
  signal s_i_accumulator : unsigned(G_ACCUMULATOR_WIDTH - 1 downto 0) := (others => '0');
  signal s_o_accumulator : unsigned(G_ACCUMULATOR_WIDTH - 1 downto 0) := (others => '0');
  signal s_i_reset          : std_logic := '0';
  signal s_lock          : std_logic := '0';
  signal s_last_msb      : std_logic := '0';  -- Last MSB of the accumulator
begin

  -- register inputs
  process(clk)
  begin
    if rising_edge(clk) then
      s_i_timing        <= i_timing;
      s_i_range         <= i_range;
      s_lock            <= i_lock;
      s_i_reset          <= i_reset;
      s_i_accumulator <= unsigned(i_accumulator);
    end if;
  end process;

  -- accumulator logic
  process(clk)
  begin
    if rising_edge(clk) then
      case s_i_range is
        when C_ANIMATION =>
          if s_i_reset = '1' then
            s_o_accumulator <= (others => '0');
          elsif s_i_timing.vsync_start = '1' then
            s_o_accumulator <= s_o_accumulator + s_i_accumulator;
          end if;
        when C_VERTICAL =>
          if (s_i_timing.vsync_start = '1' and s_lock = '1') or s_i_reset = '1' then
            s_o_accumulator <= (others => '0');
          elsif s_i_timing.avid_start = '1' then
            s_o_accumulator <= s_o_accumulator + s_i_accumulator;
          end if;
        when C_HORIZONTAL =>
          if (s_i_timing.avid_start = '1' and s_lock = '1') or s_i_reset = '1' then
            s_o_accumulator <= (others => '0');
          else
            s_o_accumulator <= s_o_accumulator + s_i_accumulator;
          end if;
        when others =>
          null;
      end case;
    end if;
  end process;

  -- store last msb state for pulse generation
  process(clk)
  begin
    if rising_edge(clk) then
      s_last_msb <= s_o_accumulator(G_ACCUMULATOR_WIDTH - 1);
    end if;
  end process;

  o_accumulator <= std_logic_vector(s_o_accumulator);
  o_clock       <= s_o_accumulator(G_ACCUMULATOR_WIDTH - 1);
  o_pulse       <= '1' when s_last_msb = '1' and s_o_accumulator(G_ACCUMULATOR_WIDTH - 1) = '0' else '0';

end rtl;
