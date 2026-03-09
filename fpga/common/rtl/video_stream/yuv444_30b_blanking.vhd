-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: yuv444_30b_blanking.vhd - YUV444 Blanking
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
--   Blanking insertion for YUV444 30-bit video streams. Replaces pixel data
--   with black level (Y=0, U=512, V=512) during blanking intervals (avid='0').
--   All sync signals pass through with the same 2-cycle delay as data.
--
-- Pipeline Architecture (2 stages, 2 clock cycles latency):
--   Stage 0: Register all input signals (data + sync)
--   Stage 1: Apply blanking (mux active data or black level based on avid),
--            register all output signals
--
-- Latency:
--   All outputs (Y, U, V, avid, hsync_n, vsync_n, field_n): 2 clock cycles
--   Data and sync signals are aligned (arrive on the same clock edge).
--
-- Authors:
--   Lars Larsen

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_stream_pkg.all;

entity yuv444_30b_blanking is
    port (
        clk        : in  std_logic;
        data_in    : in  t_video_stream_yuv444_30b;
        data_out   : out t_video_stream_yuv444_30b
    );
end yuv444_30b_blanking;

architecture rtl of yuv444_30b_blanking is
    signal s_data_reg : t_video_stream_yuv444_30b;
begin

    process(clk)
    begin
        if rising_edge(clk) then
            -- Input register (cycle 1)
            s_data_reg <= data_in;

            -- Processing with 2-cycle total delay
            if s_data_reg.avid = '1' then
                data_out.y <= s_data_reg.y;
                data_out.u <= s_data_reg.u;
                data_out.v <= s_data_reg.v;
            else
                data_out.y <= std_logic_vector(to_unsigned(0,   10));
                data_out.u <= std_logic_vector(to_unsigned(512, 10));
                data_out.v <= std_logic_vector(to_unsigned(512, 10));
            end if;

            data_out.avid <= s_data_reg.avid;
            data_out.hsync_n <= s_data_reg.hsync_n;
            data_out.vsync_n <= s_data_reg.vsync_n;
            data_out.field_n <= s_data_reg.field_n;
        end if;
    end process;

end architecture rtl;
