-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: video_timing_generator.vhd - Video Timing Generator
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
--   Derives a t_video_timing_port record from raw sync/avid inputs. Uses
--   edge_detector instances for hsync/vsync/avid edge detection and an
--   internal video_field_detector for field parity and interlace status.
--
-- Pipeline Architecture:
--   Stage 0: Register raw inputs (ref_hsync_n, ref_vsync_n, ref_avid)
--   Edge detectors: Each edge_detector has 1 internal register + combinational
--                   edge comparison. Edge pulses (avid_start, avid_end,
--                   hsync_start, vsync_start) are combinational from the
--                   detector, appearing 1 cycle after the registered input.
--
-- Latency:
--   Pass-through signals (avid, hsync_n, vsync_n): 1 clock cycle
--   Edge pulse outputs (avid_start, avid_end, hsync_start, vsync_start):
--     Combinational from edge_detector, which compares current registered
--     input with its own 1-cycle-delayed copy. Effectively 1 cycle after
--     the registered input transitions, i.e., 2 cycles from raw input.
--   field_n, is_interlaced: Event-driven (updated on vsync edges),
--     latency depends on video timing.
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_timing_pkg.all;

entity video_timing_generator is
    port (
        clk         : in std_logic;
        ref_hsync_n : in std_logic;
        ref_vsync_n : in std_logic;
        ref_avid    : in std_logic;
        timing      : out t_video_timing_port
    );
end video_timing_generator;

architecture rtl of video_timing_generator is

  signal s_ref_hsync_n : std_logic := '0';
  signal s_ref_vsync_n : std_logic := '0';
  signal s_ref_avid    : std_logic := '0';
  signal s_timing      : t_video_timing_port;
begin

  process(clk)
  begin
    if rising_edge(clk) then
      s_ref_hsync_n <= ref_hsync_n;
      s_ref_vsync_n <= ref_vsync_n;
      s_ref_avid    <= ref_avid;
    end if;
  end process;

  edge_detector_inst_sav : entity work.edge_detector
    port map (
        clk     => clk,
        a => s_ref_avid,
        rising  => s_timing.avid_start
    );

  edge_detector_inst_eav : entity work.edge_detector
    port map (
        clk     => clk,
        a => s_ref_avid,
        falling  => s_timing.avid_end
    );

  edge_detector_inst_hsync : entity work.edge_detector
    port map (
        clk     => clk,
        a => s_ref_hsync_n,
        falling  => s_timing.hsync_start
    );

  edge_detector_inst_vsync : entity work.edge_detector
    port map (
        clk     => clk,
        a => s_ref_vsync_n,
        falling  => s_timing.vsync_start
    );

    video_field_detector_inst : entity work.video_field_detector
     generic map(
      G_LINE_COUNTER_WIDTH => 12
     )
    port map(
      clk => clk,
      hsync => s_ref_hsync_n,
      vsync => s_ref_vsync_n,
      field_n => s_timing.field_n,
      is_interlaced => s_timing.is_interlaced
    );

    s_timing.avid           <= s_ref_avid;
    s_timing.hsync_n        <= s_ref_hsync_n;
    s_timing.vsync_n        <= s_ref_vsync_n;
    s_timing.vavid          <= '0'; -- Vertical AVID not implemented
    timing                  <= s_timing;

end architecture rtl;
