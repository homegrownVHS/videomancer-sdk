-- Videomancer SDK - VUnit Testbench for clamp_pkg
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tests:
--   fn_clamp_s_to_u:
--     1.  Positive in-range value passes through (10-bit)
--     2.  Zero passes through
--     3.  Negative value clamps to 0
--     4.  Overflow value clamps to all-ones
--     5.  Max value (1023) passes through
--     6.  Max+1 (1024) clamps to all-ones
--     7.  Large negative clamps to 0
--     8.  Works with 8-bit output width
--     9.  Works with 12-bit output width
--    10.  Boundary: -1 clamps to 0
--   fn_clamp_u:
--    11.  In-range value passes through (10-bit)
--    12.  Max value passes through
--    13.  Overflow clamps to all-ones
--    14.  Zero passes through
--    15.  Works with 8-bit output width
--    16.  Works with 12-bit output width
--    17.  Large overflow clamps to all-ones
--   fn_clamp_int_to_u:
--    18.  Positive in-range integer passes through (10-bit)
--    19.  Zero integer passes through
--    20.  Negative integer clamps to 0
--    21.  Overflow integer clamps to all-ones
--    22.  Max value (1023) passes through
--    23.  Max+1 (1024) clamps to all-ones
--    24.  Works with 8-bit output width

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.clamp_pkg.all;

entity tb_clamp_pkg is
    generic (runner_cfg : string);
end entity;

architecture tb of tb_clamp_pkg is
begin

    main : process
        -- Signed inputs must be at least width+2 bits to represent overflow values
        variable v_s12  : signed(11 downto 0);  -- 12-bit signed for 10-bit output tests
        variable v_s10  : signed(9 downto 0);   -- 10-bit signed for 8-bit output tests
        variable v_s14  : signed(13 downto 0);  -- 14-bit signed for 12-bit output tests
        variable v_u11  : unsigned(10 downto 0);
        variable v_u9   : unsigned(8 downto 0);
        variable v_u13  : unsigned(12 downto 0);
        variable v_res  : unsigned(9 downto 0);
        variable v_res8 : unsigned(7 downto 0);
        variable v_res12 : unsigned(11 downto 0);
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- ==============================================================
            -- fn_clamp_s_to_u tests
            -- ==============================================================

            -- ==============================================================
            if run("s_to_u_positive_in_range") then
            -- ==============================================================
                -- 500 is in [0, 1023] -> pass through
                v_s12 := to_signed(500, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(500, 10),
                    "500 should pass through for 10-bit");

            -- ==============================================================
            elsif run("s_to_u_zero") then
            -- ==============================================================
                v_s12 := to_signed(0, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(0, 10),
                    "0 should pass through");

            -- ==============================================================
            elsif run("s_to_u_negative_clamps_zero") then
            -- ==============================================================
                v_s12 := to_signed(-100, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(0, 10),
                    "-100 should clamp to 0");

            -- ==============================================================
            elsif run("s_to_u_overflow_clamps_max") then
            -- ==============================================================
                v_s12 := to_signed(1024, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "1024 should clamp to 1023");

            -- ==============================================================
            elsif run("s_to_u_max_passes") then
            -- ==============================================================
                v_s12 := to_signed(1023, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "1023 should pass through");

            -- ==============================================================
            elsif run("s_to_u_max_plus_one_clamps") then
            -- ==============================================================
                -- Same as overflow test but using exact boundary
                v_s12 := to_signed(1024, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "1024 should clamp to all-ones (1023)");

            -- ==============================================================
            elsif run("s_to_u_large_negative") then
            -- ==============================================================
                v_s12 := to_signed(-1024, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(0, 10),
                    "-1024 should clamp to 0");

            -- ==============================================================
            elsif run("s_to_u_8bit_width") then
            -- ==============================================================
                v_s10 := to_signed(200, 10);
                v_res8 := fn_clamp_s_to_u(v_s10, 8);
                check_equal(v_res8, to_unsigned(200, 8),
                    "200 should pass through for 8-bit");

                v_s10 := to_signed(256, 10);
                v_res8 := fn_clamp_s_to_u(v_s10, 8);
                check_equal(v_res8, to_unsigned(255, 8),
                    "256 should clamp to 255 for 8-bit");

                v_s10 := to_signed(-1, 10);
                v_res8 := fn_clamp_s_to_u(v_s10, 8);
                check_equal(v_res8, to_unsigned(0, 8),
                    "-1 should clamp to 0 for 8-bit");

            -- ==============================================================
            elsif run("s_to_u_12bit_width") then
            -- ==============================================================
                v_s14 := to_signed(3000, 14);
                v_res12 := fn_clamp_s_to_u(v_s14, 12);
                check_equal(v_res12, to_unsigned(3000, 12),
                    "3000 should pass through for 12-bit");

                v_s14 := to_signed(4096, 14);
                v_res12 := fn_clamp_s_to_u(v_s14, 12);
                check_equal(v_res12, to_unsigned(4095, 12),
                    "4096 should clamp to 4095 for 12-bit");

            -- ==============================================================
            elsif run("s_to_u_minus_one_clamps") then
            -- ==============================================================
                v_s12 := to_signed(-1, 12);
                v_res := fn_clamp_s_to_u(v_s12, 10);
                check_equal(v_res, to_unsigned(0, 10),
                    "-1 should clamp to 0");

            -- ==============================================================
            -- fn_clamp_u tests
            -- ==============================================================

            -- ==============================================================
            elsif run("u_in_range") then
            -- ==============================================================
                v_u11 := to_unsigned(500, 11);
                v_res := fn_clamp_u(v_u11, 10);
                check_equal(v_res, to_unsigned(500, 10),
                    "500 should pass through for 10-bit");

            -- ==============================================================
            elsif run("u_max_passes") then
            -- ==============================================================
                v_u11 := to_unsigned(1023, 11);
                v_res := fn_clamp_u(v_u11, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "1023 should pass through");

            -- ==============================================================
            elsif run("u_overflow_clamps") then
            -- ==============================================================
                v_u11 := to_unsigned(1024, 11);
                v_res := fn_clamp_u(v_u11, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "1024 should clamp to 1023");

            -- ==============================================================
            elsif run("u_zero_passes") then
            -- ==============================================================
                v_u11 := to_unsigned(0, 11);
                v_res := fn_clamp_u(v_u11, 10);
                check_equal(v_res, to_unsigned(0, 10),
                    "0 should pass through");

            -- ==============================================================
            elsif run("u_8bit_width") then
            -- ==============================================================
                v_u9 := to_unsigned(200, 9);
                v_res8 := fn_clamp_u(v_u9, 8);
                check_equal(v_res8, to_unsigned(200, 8),
                    "200 should pass through for 8-bit");

                v_u9 := to_unsigned(300, 9);
                v_res8 := fn_clamp_u(v_u9, 8);
                check_equal(v_res8, to_unsigned(255, 8),
                    "300 should clamp to 255 for 8-bit");

            -- ==============================================================
            elsif run("u_12bit_width") then
            -- ==============================================================
                v_u13 := to_unsigned(3000, 13);
                v_res12 := fn_clamp_u(v_u13, 12);
                check_equal(v_res12, to_unsigned(3000, 12),
                    "3000 should pass through for 12-bit");

                v_u13 := to_unsigned(5000, 13);
                v_res12 := fn_clamp_u(v_u13, 12);
                check_equal(v_res12, to_unsigned(4095, 12),
                    "5000 should clamp to 4095 for 12-bit");

            -- ==============================================================
            elsif run("u_large_overflow") then
            -- ==============================================================
                v_u11 := to_unsigned(2047, 11);
                v_res := fn_clamp_u(v_u11, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "2047 should clamp to 1023 for 10-bit");

            -- ==============================================================
            -- fn_clamp_int_to_u tests
            -- ==============================================================

            -- ==============================================================
            elsif run("int_positive_in_range") then
            -- ==============================================================
                v_res := fn_clamp_int_to_u(500, 10);
                check_equal(v_res, to_unsigned(500, 10),
                    "500 should pass through for 10-bit");

            -- ==============================================================
            elsif run("int_zero") then
            -- ==============================================================
                v_res := fn_clamp_int_to_u(0, 10);
                check_equal(v_res, to_unsigned(0, 10),
                    "0 should pass through");

            -- ==============================================================
            elsif run("int_negative_clamps_to_zero") then
            -- ==============================================================
                v_res := fn_clamp_int_to_u(-42, 10);
                check_equal(v_res, to_unsigned(0, 10),
                    "negative should clamp to 0");

            -- ==============================================================
            elsif run("int_overflow_clamps_to_max") then
            -- ==============================================================
                v_res := fn_clamp_int_to_u(2000, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "2000 should clamp to 1023 for 10-bit");

            -- ==============================================================
            elsif run("int_max_value") then
            -- ==============================================================
                v_res := fn_clamp_int_to_u(1023, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "1023 should pass through for 10-bit");

            -- ==============================================================
            elsif run("int_max_plus_one") then
            -- ==============================================================
                v_res := fn_clamp_int_to_u(1024, 10);
                check_equal(v_res, to_unsigned(1023, 10),
                    "1024 should clamp to 1023 for 10-bit");

            -- ==============================================================
            elsif run("int_8bit_width") then
            -- ==============================================================
                v_res8 := fn_clamp_int_to_u(100, 8);
                check_equal(v_res8, to_unsigned(100, 8),
                    "100 should pass through for 8-bit");

                v_res8 := fn_clamp_int_to_u(300, 8);
                check_equal(v_res8, to_unsigned(255, 8),
                    "300 should clamp to 255 for 8-bit");

                v_res8 := fn_clamp_int_to_u(-1, 8);
                check_equal(v_res8, to_unsigned(0, 8),
                    "-1 should clamp to 0 for 8-bit");

            end if;

        end loop;

        test_runner_cleanup(runner);
    end process;

end architecture tb;
