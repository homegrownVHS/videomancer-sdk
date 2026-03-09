-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: variable_filter_s.vhd - Variable LPF/HPF Filter (Signed)
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
--   Simple LPF/HPF variable filter for signed values with 8-bit cutoff control.
--   Coarse shift (upper 4 bits) selects the exponential decay rate.
--   Fine sigma-delta mixing (lower 4 bits) interpolates between adjacent
--   shift amounts without a multiplier, providing 256 smooth cutoff steps.
--
-- Pipeline Architecture (1 stage):
--   Single clocked process computes next filter state and output each cycle.
--   low_pass output is combinational from the filter state register.
--   high_pass output is combinational: a - low_pass (current input minus state).
--
-- Latency:
--   valid:     1 clock cycle (registered copy of enable)
--   low_pass:  0 clock cycles (combinational from registered state, but state
--              updates 1 cycle after input changes)
--   high_pass: 0 clock cycles (combinational: current a minus registered state)
--   Note: The filter is an IIR (infinite impulse response) accumulator, not a
--   fixed-depth pipeline. Output tracks input with exponential convergence
--   controlled by the cutoff parameter.
--
-- Authors:
--   Lars Larsen
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity variable_filter_s is
  generic (
    G_WIDTH : integer := 16 -- data width (signed)
  );
  port (
    clk       : in std_logic;
    enable    : in std_logic;
    a         : in signed(G_WIDTH - 1 downto 0);
    cutoff    : in unsigned(7 downto 0);
    low_pass  : out signed(G_WIDTH - 1 downto 0);
    high_pass : out signed(G_WIDTH - 1 downto 0);
    valid     : out std_logic
  );
end entity;

architecture rtl of variable_filter_s is
  signal s_y_reg   : signed(G_WIDTH - 1 downto 0) := (others => '0');

  -- 4-bit sigma-delta accumulator for fine mixing density (0..15 threshold 16)
  signal s_mix_acc : unsigned(4 downto 0)         := (others => '0'); -- 5 bits to hold carry

  -- saturating resize helper
  function sat_signed(x : signed; width : natural) return signed is
    variable v_res   : signed(width - 1 downto 0);
    constant C_MAX   : signed(width - 1 downto 0) := to_signed(2 ** (width - 1) - 1, width);
    constant C_MIN   : signed(width - 1 downto 0) := to_signed(-2 ** (width - 1), width);
  begin
    if x > resize(C_MAX, x'length) then
      v_res := C_MAX;
    elsif x < resize(C_MIN, x'length) then
      v_res := C_MIN;
    else
      v_res := resize(x, width);
    end if;
    return v_res;
  end function;

begin
  process (clk)
    variable v_k           : natural; -- 0..15
    variable v_f           : unsigned(3 downto 0);
    -- widen a bit for math headroom
    variable v_a_w         : signed(G_WIDTH + 2 downto 0);
    variable v_y_w         : signed(G_WIDTH + 2 downto 0);
    variable v_err_w       : signed(G_WIDTH + 2 downto 0);
    variable v_base_d      : signed(G_WIDTH + 2 downto 0); -- err >> v_k
    variable v_mix_d       : signed(G_WIDTH + 2 downto 0); -- either v_base_d or v_base_d>>1
    variable v_sum_wide    : signed(G_WIDTH + 3 downto 0);
    variable v_y_next      : signed(G_WIDTH - 1 downto 0);
    variable v_choose_half : std_logic;
    variable v_k_limit     : natural;
  begin
    if rising_edge(clk) then
      -- Decode control
      v_k       := to_integer(cutoff(7 downto 4)); -- coarse shift 0..15
      v_f       := cutoff(3 downto 0);             -- fine 0..15

      -- e = a - y
      v_a_w     := resize(a, v_a_w'length);
      v_y_w     := resize(s_y_reg, v_y_w'length);
      v_err_w   := v_a_w - v_y_w;

      -- Protect extreme v_k (avoid shifting >= width -> X on some tools)
      v_k_limit := v_k;
      if v_k_limit >= v_err_w'length then
        v_k_limit := v_err_w'length - 1;
      end if;

      -- Base delta: err >> v_k
      v_base_d      := shift_right(v_err_w, v_k_limit);

      -- Sigma-delta mixing: average between v_base_d and v_base_d>>1 with density = v_f/16
      v_choose_half := '0';
      if (s_mix_acc(4) = '1') then
        v_choose_half := '1';
      else
        if unsigned(resize(v_f, 5)) + s_mix_acc >= to_unsigned(16, 5) then
          v_choose_half := '1';
        else
          v_choose_half := '0';
        end if;
      end if;

      if v_choose_half = '1' then
        v_mix_d := shift_right(v_base_d, 1); -- use v_k+1 this cycle
      else
        v_mix_d := v_base_d; -- use v_k this cycle
      end if;

      -- v_y_next = y + v_mix_d  (with saturation)
      v_sum_wide := resize(v_y_w, v_sum_wide'length) + resize(v_mix_d, v_sum_wide'length);
      v_y_next   := sat_signed(v_sum_wide, G_WIDTH);
      s_y_reg <= v_y_next;

      -- Update the accumulator register (wrap modulo 16)
      if (unsigned(resize(v_f, 5)) + s_mix_acc >= to_unsigned(16, 5)) then
        s_mix_acc <= unsigned(resize(v_f, 5)) + s_mix_acc - to_unsigned(16, 5);
      else
        s_mix_acc <= unsigned(resize(v_f, 5)) + s_mix_acc;
      end if;

      valid <= enable; -- output valid when enabled

    end if;
  end process;

  low_pass  <= s_y_reg;
  high_pass <= a - s_y_reg;

end architecture;
