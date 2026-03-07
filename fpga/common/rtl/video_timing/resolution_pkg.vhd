-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: resolution_pkg.vhd - Active resolution lookup by video timing ID
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
--   Pure-function package mapping a t_video_timing_id to the active pixel
--   dimensions of the corresponding video standard. Programs use these
--   functions to adapt viewport, grid, and center-of-screen constants at
--   run time instead of hardcoding 1920x1080.
--
--   Resolution tiers:
--     SD 480   (NTSC / 480p)  :  720 x  480
--     SD 576   (PAL  / 576p)  :  720 x  576
--     HD 720   (720p variants):  1280 x  720
--     HD 1080  (1080i / 1080p):  1920 x 1080
--
-- Authors:
--   Lars Larsen

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_timing_pkg.all;

package resolution_pkg is

    -- Unsigned active-pixel dimensions (12-bit).
    function get_h_active  (timing_id : t_video_timing_id) return unsigned;
    function get_v_active  (timing_id : t_video_timing_id) return unsigned;
    function get_h_center  (timing_id : t_video_timing_id) return unsigned;
    function get_v_center  (timing_id : t_video_timing_id) return unsigned;

    -- Signed active-pixel dimensions (12-bit).
    function get_h_active_s (timing_id : t_video_timing_id) return signed;
    function get_v_active_s (timing_id : t_video_timing_id) return signed;
    function get_h_center_s (timing_id : t_video_timing_id) return signed;
    function get_v_center_s (timing_id : t_video_timing_id) return signed;

end package;

--------------------------------------------------------------------------------

package body resolution_pkg is

    -- ======================================================================
    --  Unsigned helpers
    -- ======================================================================

    function get_h_active (timing_id : t_video_timing_id) return unsigned is
    begin
        case timing_id is
            when C_NTSC | C_PAL | C_480P | C_576P =>
                return to_unsigned(720, 12);
            when C_720P60 | C_720P5994 | C_720P50 =>
                return to_unsigned(1280, 12);
            when others =>
                return to_unsigned(1920, 12);
        end case;
    end function;

    function get_v_active (timing_id : t_video_timing_id) return unsigned is
    begin
        case timing_id is
            when C_NTSC | C_480P =>
                return to_unsigned(480, 12);
            when C_PAL | C_576P =>
                return to_unsigned(576, 12);
            when C_720P60 | C_720P5994 | C_720P50 =>
                return to_unsigned(720, 12);
            when others =>
                return to_unsigned(1080, 12);
        end case;
    end function;

    function get_h_center (timing_id : t_video_timing_id) return unsigned is
    begin
        case timing_id is
            when C_NTSC | C_PAL | C_480P | C_576P =>
                return to_unsigned(360, 12);
            when C_720P60 | C_720P5994 | C_720P50 =>
                return to_unsigned(640, 12);
            when others =>
                return to_unsigned(960, 12);
        end case;
    end function;

    function get_v_center (timing_id : t_video_timing_id) return unsigned is
    begin
        case timing_id is
            when C_NTSC | C_480P =>
                return to_unsigned(240, 12);
            when C_PAL | C_576P =>
                return to_unsigned(288, 12);
            when C_720P60 | C_720P5994 | C_720P50 =>
                return to_unsigned(360, 12);
            when others =>
                return to_unsigned(540, 12);
        end case;
    end function;

    -- ======================================================================
    --  Signed helpers
    -- ======================================================================

    function get_h_active_s (timing_id : t_video_timing_id) return signed is
    begin
        return signed(get_h_active(timing_id));
    end function;

    function get_v_active_s (timing_id : t_video_timing_id) return signed is
    begin
        return signed(get_v_active(timing_id));
    end function;

    function get_h_center_s (timing_id : t_video_timing_id) return signed is
    begin
        return signed(get_h_center(timing_id));
    end function;

    function get_v_center_s (timing_id : t_video_timing_id) return signed is
    begin
        return signed(get_v_center(timing_id));
    end function;

end package body;
