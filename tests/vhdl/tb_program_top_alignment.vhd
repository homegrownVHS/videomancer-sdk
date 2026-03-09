-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_program_top_alignment.vhd - Alignment testbench for program_top DUT
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
--   Headless alignment testbench for any program_top DUT (yuv444_30b core).
--   Generates a synthetic horizontal gradient, drives the DUT for
--   G_WARMUP_FRAMES + 2 frames, and captures all active-video output pixels
--   to "alignment_output.txt" in the current working directory.  Each line of
--   the file contains one pixel: "Y U V" (space-separated 10-bit integers).
--
--   The Python alignment stage reads this file and performs:
--     1. Pipeline delay verification (C_PROCESSING_DELAY_CLKS correct).
--     2. Inter-channel timing skew detection (Y/U/V must be co-aligned).
--   It always uses the last G_N_ROWS × G_N_COLS pixels from the file, so
--   extra warmup pixels in the file are harmless.
--
--   Input gradient per active line:
--     Y: ramps from C_Y_LO (100) to C_Y_HI (900)
--     U: ramps from C_U_LO (300) to C_U_HI (700)
--     V: ramps from C_V_HI (700) down to C_V_LO (300)  [descending]
--   All three channels are well away from BT.601 blanking values (Y=64,
--   UV=512 ± 6), enabling accurate edge-of-line blanking detection.
--
--   Generics
--   --------
--   G_N_COLS        Active pixels per line              (default: 90)
--   G_N_ROWS        Active lines per frame               (default: 60)
--   G_H_BLANK       Horizontal blanking clocks per line  (default: 64)
--   G_V_BLANK       Vertical blanking lines per frame    (default: 20)
--   G_WARMUP_FRAMES Pipeline warmup frames               (default: 2)
--
--   Exit codes (via std.env.stop)
--   -----------------------------
--   0  → completed successfully; Python stage analyses the pixel file.
--   1  → pixel count sanity check failed (likely a simulation error).
--   2  → not used by this testbench; reserved for GHDL analysis errors.

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.all;
use work.video_stream_pkg.all;
use work.core_pkg.all;

-- =============================================================================

entity tb_program_top_alignment is
    generic (
        G_N_COLS        : integer := 90;
        G_N_ROWS        : integer := 60;
        G_H_BLANK       : integer := 64;
        G_V_BLANK       : integer := 20;
        G_WARMUP_FRAMES : integer := 2
    );
end entity tb_program_top_alignment;

-- =============================================================================

architecture tb of tb_program_top_alignment is

    constant C_CLK_PERIOD : time    := 10 ns;       -- simulation speed
    constant C_WIDTH      : integer := C_VIDEO_DATA_WIDTH;  -- 10

    signal clk      : std_logic := '0';
    signal data_in  : t_video_stream_yuv444_30b;
    signal data_out : t_video_stream_yuv444_30b;
    signal regs_in  : t_spi_ram := (others => (others => '0'));
    signal sim_done : boolean   := false;

begin

    -- ─── Clock generator ───────────────────────────────────────────────────
    clk <= not clk after C_CLK_PERIOD / 2 when not sim_done else '0';

    -- ─── DUT ──────────────────────────────────────────────────────────────
    dut_inst : entity work.program_top
        port map (
            clk          => clk,
            registers_in => regs_in,
            data_in      => data_in,
            data_out     => data_out
        );

    -- =========================================================================
    --  Stimulus + capture process
    -- =========================================================================
    p_main : process

        -- Gradient extents: well clear of BT.601 blanking (Y=64, UV=512 ±6)
        constant C_Y_LO  : integer := 100;
        constant C_Y_HI  : integer := 900;
        constant C_U_LO  : integer := 300;
        constant C_U_HI  : integer := 700;
        constant C_V_LO  : integer := 300;   -- V descends: HI→LO
        constant C_V_HI  : integer := 700;

        -- Output pixel file
        file     f_out        : text;
        variable v_line       : line;
        variable v_pixel_count : integer := 0;

        -- Temporaries for captured output sample
        variable v_out_y : integer;
        variable v_out_u : integer;
        variable v_out_v : integer;

        -- ─── Linear ramp for a single channel ────────────────────────────
        -- Returns lo + col * (hi - lo) / (G_N_COLS - 1).
        -- When G_N_COLS = 1 returns the midpoint.
        function ramp(col, lo, hi : integer) return integer is
        begin
            if G_N_COLS <= 1 then
                return (lo + hi) / 2;
            end if;
            return lo + col * (hi - lo) / (G_N_COLS - 1);
        end function;

        -- ─── Write one output pixel to the file (when avid is high) ──────
        procedure capture_output is
        begin
            if data_out.avid = '1' then
                v_out_y := to_integer(unsigned(data_out.y));
                v_out_u := to_integer(unsigned(data_out.u));
                v_out_v := to_integer(unsigned(data_out.v));
                write(v_line, v_out_y);
                write(v_line, ' ');
                write(v_line, v_out_u);
                write(v_line, ' ');
                write(v_line, v_out_v);
                writeline(f_out, v_line);
                v_pixel_count := v_pixel_count + 1;
            end if;
        end procedure;

        -- ─── Drive one complete video frame; capture all output avid ──────
        -- first_frame: when true, vsync is asserted on blank rows 0 and 1.
        procedure drive_frame(first_frame : boolean) is
            variable v_y : integer;
            variable v_u : integer;
            variable v_v : integer;
        begin
            -- ── Vertical blanking rows ─────────────────────────────────────
            for vb in 0 to G_V_BLANK - 1 loop
                -- First clock of blank row: hsync pulse
                data_in.avid    <= '0';
                data_in.hsync_n <= '0';
                data_in.vsync_n <= '1';
                if first_frame and vb < 2 then
                    data_in.vsync_n <= '0';
                end if;
                wait until rising_edge(clk);
                capture_output;

                -- Remaining clocks of blank row
                data_in.hsync_n <= '1';
                data_in.vsync_n <= '1';
                for c in 1 to G_H_BLANK + G_N_COLS - 1 loop
                    wait until rising_edge(clk);
                    capture_output;
                end loop;
            end loop;

            -- ── Active lines ───────────────────────────────────────────────
            for row in 0 to G_N_ROWS - 1 loop
                -- Horizontal blanking: first clock has hsync
                data_in.avid    <= '0';
                data_in.hsync_n <= '0';
                data_in.vsync_n <= '1';
                wait until rising_edge(clk);
                capture_output;

                -- Remaining horizontal blanking clocks
                data_in.hsync_n <= '1';
                for c in 1 to G_H_BLANK - 1 loop
                    wait until rising_edge(clk);
                    capture_output;
                end loop;

                -- Active pixels: horizontal gradient (Y, U ascending; V descending)
                for col in 0 to G_N_COLS - 1 loop
                    v_y := ramp(col, C_Y_LO, C_Y_HI);
                    v_u := ramp(col, C_U_LO, C_U_HI);
                    v_v := ramp(col, C_V_HI, C_V_LO);   -- descending
                    data_in.y    <= std_logic_vector(to_unsigned(v_y, C_WIDTH));
                    data_in.u    <= std_logic_vector(to_unsigned(v_u, C_WIDTH));
                    data_in.v    <= std_logic_vector(to_unsigned(v_v, C_WIDTH));
                    data_in.avid <= '1';
                    wait until rising_edge(clk);
                    capture_output;
                end loop;
                data_in.avid <= '0';
            end loop;
        end procedure;

    begin

        -- ── Initialise inputs ──────────────────────────────────────────────
        data_in.y       <= (others => '0');
        data_in.u       <= std_logic_vector(to_unsigned(512, C_WIDTH));
        data_in.v       <= std_logic_vector(to_unsigned(512, C_WIDTH));
        data_in.avid    <= '0';
        data_in.hsync_n <= '1';
        data_in.vsync_n <= '1';
        data_in.field_n <= '1';

        -- ── Open pixel capture file ────────────────────────────────────────
        file_open(f_out, "alignment_output.txt", write_mode);

        -- ── Drive warmup frames + 2 capture frames ─────────────────────────
        -- Python alignment.py takes the *last* G_N_ROWS × G_N_COLS pixels
        -- from the file, so extra warmup pixels are automatically discarded.
        -- Two frames beyond G_WARMUP_FRAMES ensures the DUT pipeline has
        -- fully propagated for the final captured active area.
        for fr in 0 to G_WARMUP_FRAMES + 1 loop
            drive_frame(fr = 0);
        end loop;

        -- ── Flush pipeline tail ────────────────────────────────────────────
        -- Drive one extra blank line so delayed outputs at the very end of
        -- the last active frame are flushed into the capture window.
        data_in.avid    <= '0';
        data_in.hsync_n <= '1';
        data_in.vsync_n <= '1';
        for c in 0 to G_H_BLANK + G_N_COLS - 1 loop
            wait until rising_edge(clk);
            capture_output;
        end loop;

        -- ── Close file and report ─────────────────────────────────────────
        file_close(f_out);

        report "ALIGN_STATS: captured_pixels=" & integer'image(v_pixel_count)
               & " frames=" & integer'image(G_WARMUP_FRAMES + 2)
               & " expected_per_frame=" & integer'image(G_N_ROWS * G_N_COLS)
               severity note;

        sim_done <= true;
        wait for C_CLK_PERIOD;

        -- ── Sanity check and exit ─────────────────────────────────────────
        if v_pixel_count >= G_N_ROWS * G_N_COLS then
            std.env.stop(0);
        else
            report "ALIGNMENT FAIL: captured " & integer'image(v_pixel_count)
                   & " pixels, need at least " & integer'image(G_N_ROWS * G_N_COLS)
                   severity error;
            std.env.stop(1);
        end if;

    end process p_main;

end architecture tb;
