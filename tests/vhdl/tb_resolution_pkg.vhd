-- Videomancer SDK - VUnit Testbench for resolution_pkg
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Pure-function testbench for resolution_pkg. Verifies that all 15 video
-- timing IDs map to the correct active pixel dimensions and center
-- coordinates through both unsigned and signed accessors.
--
-- Parameterized via VUnit generics: G_TIMING_ID selects the format and
-- G_H_ACTIVE / G_V_ACTIVE / G_H_CENTER / G_V_CENTER supply the expected
-- values. run.py wires one config per format.
--
-- Tests:
--   1. unsigned_dimensions - all four unsigned resolution functions
--   2. signed_dimensions   - all four signed resolution functions

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.video_timing_pkg.all;
use rtl_lib.resolution_pkg.all;

entity tb_resolution_pkg is
  generic (
    runner_cfg  : string;
    G_TIMING_ID : natural := 0;
    G_H_ACTIVE  : natural := 720;
    G_V_ACTIVE  : natural := 480;
    G_H_CENTER  : natural := 360;
    G_V_CENTER  : natural := 240
  );
end entity;

architecture tb of tb_resolution_pkg is
begin

  main : process
    variable v_tid : t_video_timing_id;
  begin
    test_runner_setup(runner, runner_cfg);

    v_tid := std_logic_vector(to_unsigned(G_TIMING_ID, 4));

    while test_suite loop

      -- ================================================================
      if run("unsigned_dimensions") then
      -- ================================================================
        check_equal(to_integer(get_h_active(v_tid)), G_H_ACTIVE,
                    "get_h_active mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

        check_equal(to_integer(get_v_active(v_tid)), G_V_ACTIVE,
                    "get_v_active mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

        check_equal(to_integer(get_h_center(v_tid)), G_H_CENTER,
                    "get_h_center mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

        check_equal(to_integer(get_v_center(v_tid)), G_V_CENTER,
                    "get_v_center mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

      -- ================================================================
      elsif run("signed_dimensions") then
      -- ================================================================
        check_equal(to_integer(get_h_active_s(v_tid)), G_H_ACTIVE,
                    "get_h_active_s mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

        check_equal(to_integer(get_v_active_s(v_tid)), G_V_ACTIVE,
                    "get_v_active_s mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

        check_equal(to_integer(get_h_center_s(v_tid)), G_H_CENTER,
                    "get_h_center_s mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

        check_equal(to_integer(get_v_center_s(v_tid)), G_V_CENTER,
                    "get_v_center_s mismatch for timing ID " &
                    integer'image(G_TIMING_ID));

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;

end architecture;
