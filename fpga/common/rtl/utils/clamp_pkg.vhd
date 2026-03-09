-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: clamp_pkg.vhd - Saturation/Clamping Utility Functions
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
--   Pure combinational functions for clamping/saturating arithmetic results
--   to a target bit width. Replaces the ubiquitous inline if/elsif/else
--   saturation blocks found throughout FPGA programs.
--
--   fn_clamp_s_to_u  Clamp a signed value to unsigned [0 .. 2^width-1].
--   fn_clamp_u       Clamp a wider unsigned value to unsigned [0 .. 2^width-1].
--
-- Resource cost:
--   Zero (pure combinational logic, no registers or BRAM).

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package clamp_pkg is

    -- ======================================================================
    --  fn_clamp_s_to_u
    -- ======================================================================
    -- Clamp a signed value to an unsigned range [0 .. 2^width - 1].
    --   Negative values   -> 0
    --   Values > max      -> 2^width - 1 (all ones)
    --   Values in range   -> truncated to lower 'width' bits
    --
    -- Typical usage (10-bit video):
    --   s_out_y <= fn_clamp_s_to_u(v_sum, 10);
    --
    function fn_clamp_s_to_u(val : signed; width : natural) return unsigned;

    -- ======================================================================
    --  fn_clamp_u
    -- ======================================================================
    -- Clamp an unsigned value to fit in 'width' bits.
    --   Values > 2^width - 1  -> 2^width - 1 (all ones)
    --   Values in range       -> truncated to lower 'width' bits
    --
    -- Typical usage (10-bit video):
    --   s_out_y <= fn_clamp_u(v_wide_sum, 10);
    --
    function fn_clamp_u(val : unsigned; width : natural) return unsigned;

    -- ======================================================================
    --  fn_clamp_int_to_u
    -- ======================================================================
    -- Clamp an integer value to an unsigned range [0 .. 2^width - 1].
    --   Negative values   -> 0
    --   Values > max      -> 2^width - 1 (all ones)
    --   Values in range   -> to_unsigned(val, width)
    --
    -- Typical usage (10-bit video):
    --   s_out_y <= fn_clamp_int_to_u(v_sum, 10);
    --
    function fn_clamp_int_to_u(val : integer; width : natural) return unsigned;

end package clamp_pkg;

--------------------------------------------------------------------------------

package body clamp_pkg is

    function fn_clamp_s_to_u(val : signed; width : natural) return unsigned is
        constant C_MAX : integer := 2**width - 1;
        variable v_result : unsigned(width - 1 downto 0);
    begin
        if val < 0 then
            v_result := (others => '0');
        elsif val > C_MAX then
            v_result := (others => '1');
        else
            v_result := unsigned(val(width - 1 downto 0));
        end if;
        return v_result;
    end function;

    function fn_clamp_u(val : unsigned; width : natural) return unsigned is
        constant C_MAX : unsigned(width - 1 downto 0) := (others => '1');
        variable v_result : unsigned(width - 1 downto 0);
    begin
        if val > C_MAX then
            v_result := C_MAX;
        else
            v_result := val(width - 1 downto 0);
        end if;
        return v_result;
    end function;

    function fn_clamp_int_to_u(val : integer; width : natural) return unsigned is
        constant C_MAX : integer := 2**width - 1;
        variable v_result : unsigned(width - 1 downto 0);
    begin
        if val < 0 then
            v_result := (others => '0');
        elsif val > C_MAX then
            v_result := (others => '1');
        else
            v_result := to_unsigned(val, width);
        end if;
        return v_result;
    end function;

end package body clamp_pkg;
