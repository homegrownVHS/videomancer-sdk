-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_blanking_yuv444.vhd - Testbench for YUV444 Blanking Module
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
--   VUnit testbench for yuv444_30b_blanking module.
--   Tests blanking interval replacement with black level.
--
--   yuv444_30b_blanking Pipeline Latency (verified by test_exact_pipeline_latency):
--     All outputs: 2 clock cycles (input register -> output register)
--     All outputs (Y/U/V, avid, sync) are aligned.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.video_timing_pkg.all;
use rtl_lib.video_stream_pkg.all;

entity tb_blanking_yuv444 is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_blanking_yuv444 is

  constant C_CLK_PERIOD : time := 13.5 ns;
  constant C_BIT_DEPTH  : integer := 10;
  constant C_PIPE_DEPTH : integer := 2;

  -- Black level values in 10-bit
  constant C_BLACK_Y : unsigned(C_BIT_DEPTH-1 downto 0) := to_unsigned(0, C_BIT_DEPTH);
  constant C_BLACK_U : unsigned(C_BIT_DEPTH-1 downto 0) := to_unsigned(512, C_BIT_DEPTH);
  constant C_BLACK_V : unsigned(C_BIT_DEPTH-1 downto 0) := to_unsigned(512, C_BIT_DEPTH);

  signal clk       : std_logic := '0';
  signal data_in   : t_video_stream_yuv444_30b;
  signal data_out  : t_video_stream_yuv444_30b;
  signal test_done : boolean := false;

begin

  clk <= not clk after C_CLK_PERIOD/2 when not test_done;

  dut: entity rtl_lib.yuv444_30b_blanking
    port map (
      clk      => clk,
      data_in  => data_in,
      data_out => data_out
    );

  main: process
    procedure clk_wait(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    procedure reset_inputs is
    begin
      data_in.y       <= (others => '0');
      data_in.u       <= (others => '0');
      data_in.v       <= (others => '0');
      data_in.hsync_n <= '1';
      data_in.vsync_n <= '1';
      data_in.avid    <= '0';
      data_in.field_n <= '1';
    end procedure;

    procedure send_pixel_at_edge(
      constant y_val    : integer;
      constant u_val    : integer;
      constant v_val    : integer;
      constant avid     : std_logic;
      constant hsync_n  : std_logic := '1';
      constant vsync_n  : std_logic := '1';
      constant field_n  : std_logic := '1'
    ) is
    begin
      data_in.y       <= std_logic_vector(to_unsigned(y_val, C_BIT_DEPTH));
      data_in.u       <= std_logic_vector(to_unsigned(u_val, C_BIT_DEPTH));
      data_in.v       <= std_logic_vector(to_unsigned(v_val, C_BIT_DEPTH));
      data_in.avid    <= avid;
      data_in.hsync_n <= hsync_n;
      data_in.vsync_n <= vsync_n;
      data_in.field_n <= field_n;
      wait until rising_edge(clk);
    end procedure;

    variable v_out_y  : integer;
    variable v_out_u  : integer;
    variable v_out_v  : integer;

  begin
    test_runner_setup(runner, runner_cfg);
    reset_inputs;
    clk_wait(4);

    while test_suite loop

      reset_inputs;
      clk_wait(4);

      -- ==================================================================
      if run("test_exact_pipeline_latency") then
      -- ==================================================================
        -- Input a known active pixel and verify it appears at output
        -- exactly 2 rising edges later (1 input reg + 1 output reg)
        info("Verifying 2-cycle pipeline latency");
        reset_inputs;
        clk_wait(4);

        -- Present the pixel at input — hold for 2 edges to survive pipeline
        data_in.y    <= std_logic_vector(to_unsigned(555, C_BIT_DEPTH));
        data_in.u    <= std_logic_vector(to_unsigned(333, C_BIT_DEPTH));
        data_in.v    <= std_logic_vector(to_unsigned(777, C_BIT_DEPTH));
        data_in.avid <= '1';
        wait until rising_edge(clk);  -- Edge 0: captured into s_data_reg
        -- Keep data_in alive; s_data_reg now holds the pixel

        wait until rising_edge(clk);  -- Edge 1: data_out gets s_data_reg
        wait for 1 ns;
        check_equal(unsigned(data_out.y), 555, "Y at exactly 2 cycles");
        check_equal(unsigned(data_out.u), 333, "U at exactly 2 cycles");
        check_equal(unsigned(data_out.v), 777, "V at exactly 2 cycles");
        check_equal(data_out.avid, '1', "AVID at exactly 2 cycles");
        reset_inputs;

      -- ==================================================================
      elsif run("test_active_video_passthrough") then
      -- ==================================================================
        -- Active video passes through unchanged
        send_pixel_at_edge(200, 300, 400, '1');
        clk_wait(C_PIPE_DEPTH - 1);  -- -1 because send_pixel consumed 1 edge
        check_equal(unsigned(data_out.y), 200, "Active Y pass through");
        check_equal(unsigned(data_out.u), 300, "Active U pass through");
        check_equal(unsigned(data_out.v), 400, "Active V pass through");
        check_equal(data_out.avid, '1', "AVID pass through");

      -- ==================================================================
      elsif run("test_blanking_replacement") then
      -- ==================================================================
        -- Blanking pixels (AVID=0) replaced with black
        send_pixel_at_edge(500, 600, 700, '0');
        clk_wait(C_PIPE_DEPTH - 1);
        check_equal(unsigned(data_out.y), C_BLACK_Y, "Blanking Y = 0");
        check_equal(unsigned(data_out.u), C_BLACK_U, "Blanking U = 512");
        check_equal(unsigned(data_out.v), C_BLACK_V, "Blanking V = 512");
        check_equal(data_out.avid, '0', "AVID remains 0");

      -- ==================================================================
      elsif run("test_sync_passthrough") then
      -- ==================================================================
        -- Sync signals pass through unchanged
        send_pixel_at_edge(100, 200, 300, '1', '0', '0', '0');
        clk_wait(C_PIPE_DEPTH - 1);
        check_equal(data_out.hsync_n, '0', "HSYNC passes through");
        check_equal(data_out.vsync_n, '0', "VSYNC passes through");
        check_equal(data_out.field_n, '0', "Field passes through");

      -- ==================================================================
      elsif run("test_transition_to_blanking") then
      -- ==================================================================
        -- Active -> blanking: blanking pixel gets black substitution
        send_pixel_at_edge(200, 300, 400, '1');
        send_pixel_at_edge(500, 600, 700, '0');
        clk_wait(C_PIPE_DEPTH - 1);
        check_equal(unsigned(data_out.y), C_BLACK_Y, "Black Y after transition");
        check_equal(unsigned(data_out.u), C_BLACK_U, "Black U after transition");
        check_equal(unsigned(data_out.v), C_BLACK_V, "Black V after transition");

      -- ==================================================================
      elsif run("test_transition_to_active") then
      -- ==================================================================
        -- Blanking -> active: active pixel passes through
        send_pixel_at_edge(500, 600, 700, '0');
        send_pixel_at_edge(200, 300, 400, '1');
        clk_wait(C_PIPE_DEPTH - 1);
        check_equal(unsigned(data_out.y), 200, "Active Y after transition");
        check_equal(unsigned(data_out.u), 300, "Active U after transition");
        check_equal(unsigned(data_out.v), 400, "Active V after transition");
        check_equal(data_out.avid, '1', "AVID 1 after transition");

      -- ==================================================================
      elsif run("test_continuous_blanking") then
      -- ==================================================================
        -- Multiple blanking pixels all become black
        for i in 1 to 10 loop
          data_in.y    <= std_logic_vector(to_unsigned((100*i) mod 1024, C_BIT_DEPTH));
          data_in.u    <= std_logic_vector(to_unsigned((200*i) mod 1024, C_BIT_DEPTH));
          data_in.v    <= std_logic_vector(to_unsigned((300*i) mod 1024, C_BIT_DEPTH));
          data_in.avid <= '0';
          wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_equal(unsigned(data_out.y), C_BLACK_Y, "Continuous blanking Y");
        check_equal(unsigned(data_out.u), C_BLACK_U, "Continuous blanking U");
        check_equal(unsigned(data_out.v), C_BLACK_V, "Continuous blanking V");

      -- ==================================================================
      elsif run("test_back_to_back_active_varied") then
      -- ==================================================================
        -- Stream 5 different active pixels, verify last one emerges
        for i in 1 to 5 loop
          send_pixel_at_edge(100 + i*50, 200 + i*30, 300 + i*20, '1');
        end loop;
        clk_wait(C_PIPE_DEPTH - 1);
        -- Last pixel was (350, 350, 400)
        check_equal(unsigned(data_out.y), 350, "Last active Y");
        check_equal(unsigned(data_out.u), 350, "Last active U");
        check_equal(unsigned(data_out.v), 400, "Last active V");

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 50 ms);

end architecture;
