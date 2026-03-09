-- Videomancer SDK - VUnit Testbench for video_timing_generator
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- video_timing_generator derives a t_video_timing_port record from raw sync
-- inputs. Internally instantiates 4 edge_detector instances (avid rising,
-- avid falling, hsync_n falling, vsync_n falling) and 1 video_field_detector.
--
-- Pipeline: 1-cycle input register + 1-cycle edge_detector a_ff latch
-- Pass-through signals (avid, hsync_n, vsync_n): 1-cycle latency
-- Edge pulses (avid_start, avid_end, hsync_start, vsync_start): 2-cycle latency
--   from raw input. Combinational from edge_detector comparing registered input
--   with its own 1-cycle-delayed copy. Pulses are exactly 1 clock cycle wide.
--
-- Tests:
--   1.  Initial quiescent state (no spurious edges)
--   2.  avid_start on avid rising edge
--   3.  avid_end on avid falling edge
--   4.  hsync_start on hsync_n falling edge
--   5.  vsync_start on vsync_n falling edge
--   6.  Passthrough signals (avid, hsync_n, vsync_n) with 1-cycle latency
--   7.  Full video frame timing sequence
--   8.  Passthrough latency exact (1 cycle, edge-counted)
--   9.  Edge pulse latency exact (2 cycles from raw input)
--  10.  Edge pulse width (exactly 1 clock cycle)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;
use rtl_lib.video_timing_pkg.all;

entity tb_video_timing_gen is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_video_timing_gen is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk         : std_logic := '0';
  signal ref_hsync_n : std_logic := '1';  -- active-low, idle high
  signal ref_vsync_n : std_logic := '1';  -- active-low, idle high
  signal ref_avid    : std_logic := '0';  -- active-high, idle low
  signal timing      : t_video_timing_port;
  signal test_done   : std_logic := '0';

  -- Pipeline settle: generous wait for multi-stage initialization
  constant C_SETTLE : integer := 4;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

  dut : entity rtl_lib.video_timing_generator
    port map (
      clk         => clk,
      ref_hsync_n => ref_hsync_n,
      ref_vsync_n => ref_vsync_n,
      ref_avid    => ref_avid,
      timing      => timing
    );

  main : process
    -- Wait for pipeline to settle after an input change
    procedure settle is
    begin
      for i in 1 to C_SETTLE loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset to quiescent state
      ref_hsync_n <= '1';
      ref_vsync_n <= '1';
      ref_avid    <= '0';
      settle;

      -- ====================================================================
      if run("initial_quiescent_no_edges") then
      -- ====================================================================
        settle;
        check_equal(timing.avid_start, '0', "no avid_start");
        check_equal(timing.avid_end, '0', "no avid_end");
        check_equal(timing.hsync_start, '0', "no hsync_start");
        check_equal(timing.vsync_start, '0', "no vsync_start");

      -- ====================================================================
      elsif run("avid_start_on_rising_edge") then
      -- ====================================================================
        -- avid_start should pulse when ref_avid goes 0->1
        ref_avid <= '1';
        wait until rising_edge(clk);  -- input reg latches '1': s_ref_avid = '1'
        -- edge_detector: a = s_ref_avid = '1', a_ff = '0' -> rising = '1'
        wait for 1 ns;
        check_equal(timing.avid_start, '1', "avid_start pulse on rising avid");

        -- Next clock: edge_detector a_ff latches '1' -> rising = '0'
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.avid_start, '0', "avid_start clears after one cycle");

      -- ====================================================================
      elsif run("avid_end_on_falling_edge") then
      -- ====================================================================
        -- First assert avid high, let it settle
        ref_avid <= '1';
        settle;

        -- Now drop avid: should produce avid_end pulse
        ref_avid <= '0';
        wait until rising_edge(clk);  -- input reg latches '0': s_ref_avid = '0'
        -- edge_detector: a = '0', a_ff = '1' -> falling = '1'
        wait for 1 ns;
        check_equal(timing.avid_end, '1', "avid_end pulse on falling avid");

        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.avid_end, '0', "avid_end clears after one cycle");

      -- ====================================================================
      elsif run("hsync_start_on_falling_hsync_n") then
      -- ====================================================================
        ref_hsync_n <= '0';  -- assert hsync (active low)
        wait until rising_edge(clk);  -- input reg latches '0'
        -- edge_detector: a = '0', a_ff = '1' -> falling = '1'
        wait for 1 ns;
        check_equal(timing.hsync_start, '1', "hsync_start on hsync_n falling");

        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.hsync_start, '0', "hsync_start clears");

      -- ====================================================================
      elsif run("vsync_start_on_falling_vsync_n") then
      -- ====================================================================
        ref_vsync_n <= '0';  -- assert vsync (active low)
        wait until rising_edge(clk);  -- input reg latches '0'
        -- edge_detector: a = '0', a_ff = '1' -> falling = '1'
        wait for 1 ns;
        check_equal(timing.vsync_start, '1', "vsync_start on vsync_n falling");

        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.vsync_start, '0', "vsync_start clears");

      -- ====================================================================
      elsif run("passthrough_signals") then
      -- ====================================================================
        -- avid, hsync_n, vsync_n should pass through with 1-cycle delay
        ref_avid    <= '1';
        ref_hsync_n <= '0';
        ref_vsync_n <= '0';
        wait until rising_edge(clk);  -- input reg latches them
        wait for 1 ns;
        check_equal(timing.avid, '1', "avid passthrough");
        check_equal(timing.hsync_n, '0', "hsync_n passthrough");
        check_equal(timing.vsync_n, '0', "vsync_n passthrough");

        ref_avid    <= '0';
        ref_hsync_n <= '1';
        ref_vsync_n <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.avid, '0', "avid passthrough low");
        check_equal(timing.hsync_n, '1', "hsync_n passthrough high");
        check_equal(timing.vsync_n, '1', "vsync_n passthrough high");

      -- ====================================================================
      elsif run("full_frame_sequence") then
      -- ====================================================================
        -- Simulate a simplified progressive frame:
        -- 1. vsync_n pulse (low for a few clocks)
        -- 2. Several lines with hsync_n + avid patterns

        -- Start of frame: vsync_n pulse
        ref_vsync_n <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        -- vsync_start should have fired (was a one-shot pulse)
        check_equal(timing.vsync_start, '0',
                    "vsync_start is one-shot, cleared by now");

        ref_vsync_n <= '1';
        settle;

        -- Simulate 3 lines
        for line in 0 to 2 loop
          -- Hsync pulse
          ref_hsync_n <= '0';
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(timing.hsync_start, '1',
                      "hsync_start on line " & integer'image(line));
          wait until rising_edge(clk);
          wait until rising_edge(clk);
          ref_hsync_n <= '1';
          settle;

          -- Active video region
          ref_avid <= '1';
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(timing.avid_start, '1',
                      "avid_start on line " & integer'image(line));

          for i in 0 to 4 loop
            wait until rising_edge(clk);
          end loop;

          ref_avid <= '0';
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(timing.avid_end, '1',
                      "avid_end on line " & integer'image(line));

          settle;
        end loop;

      -- ====================================================================
      elsif run("test_passthrough_latency_exact") then
      -- ====================================================================
        -- Verify pass-through latency is exactly 1 clock cycle
        -- Change ref_avid from 0->1 and check at each edge
        ref_avid <= '1';
        -- Before next edge: timing.avid should still be '0' (not yet latched)
        wait for 1 ns;
        check_equal(timing.avid, '0', "avid not yet updated before edge");

        -- Edge 1: s_ref_avid latches '1'
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.avid, '1',
                    "avid passthrough after exactly 1 clock edge");

        -- Now drop it and verify the same going down
        ref_avid <= '0';
        wait for 1 ns;
        check_equal(timing.avid, '1', "avid still high before edge");

        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.avid, '0',
                    "avid passthrough low after exactly 1 clock edge");

      -- ====================================================================
      elsif run("test_edge_pulse_latency_exact") then
      -- ====================================================================
        -- Verify edge pulse latency is exactly 2 cycles from raw input change.
        -- The pipeline is: raw input -> input register (1 cycle) ->
        -- edge_detector a_ff (combinational comparison with current a).
        -- So the edge pulse appears 1 cycle after the input register update,
        -- which is 1 cycle after the raw input was captured.
        --
        -- BUT: the edge pulse is combinational. It appears in the same delta
        -- as the input register update. So from the TB perspective:
        --   raw change -> wait until rising_edge(clk) [captures into input reg]
        --   -> at this point, edge_detector sees new a vs old a_ff
        --   -> avid_start is combinationally '1'
        --   -> wait until rising_edge(clk) [a_ff captures new value]
        --   -> avid_start goes '0'
        --
        -- Test: drive ref_avid '1', after 1 edge check avid_start='1',
        -- after 2nd edge check avid_start='0'.

        ref_avid <= '1';

        -- Edge 1: input register latches '1'. Edge detector: a='1', a_ff='0'
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.avid_start, '1',
                    "edge pulse appears after 1 edge (2 pipelines: input reg + combinational)");

        -- Edge 2: edge_detector a_ff latches '1'. Now a='1', a_ff='1'
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.avid_start, '0',
                    "edge pulse clears after 1 more edge");

      -- ====================================================================
      elsif run("test_edge_pulse_width") then
      -- ====================================================================
        -- Verify edge pulses are exactly 1 clock cycle wide
        -- avid_start should be '1' for exactly 1 clock cycle
        ref_avid <= '1';
        wait until rising_edge(clk);  -- input reg latches '1'
        -- Pulse active now (combinational)
        wait for 1 ns;
        check_equal(timing.avid_start, '1', "avid_start asserted");

        -- Count how many edges avid_start stays high
        wait until rising_edge(clk);  -- a_ff latches '1'
        wait for 1 ns;
        check_equal(timing.avid_start, '0',
                    "avid_start cleared after exactly 1 cycle");

        -- Same test for hsync_start (falling edge of hsync_n)
        settle;
        ref_hsync_n <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.hsync_start, '1', "hsync_start asserted");

        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(timing.hsync_start, '0',
                    "hsync_start cleared after exactly 1 cycle");

      end if;
    end loop;

    test_done <= '1';
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
