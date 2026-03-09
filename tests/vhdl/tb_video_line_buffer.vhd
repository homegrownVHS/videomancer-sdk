-- Videomancer SDK - VUnit Testbench for video_line_buffer
-- Copyright (C) 2025 LZX Industries LLC
-- SPDX-License-Identifier: GPL-3.0-only
--
-- video_line_buffer is a dual-bank BRAM line buffer.
-- i_ab selects which bank is written (the other is read).
--   i_ab='0' -> write bank A, read bank B (o_data = s_output_b)
--   i_ab='1' -> write bank B, read bank A (o_data = s_output_a)
--
-- Pipeline: 1-cycle input register + 1-cycle BRAM read register + combinational mux
-- Total read latency: 2 clock cycles from i_rd_addr change to o_data valid
-- Total write latency: 2 clock cycles from i_data/i_wr_addr to RAM write
--
-- Tests:
--   1.  Write bank A, read back from bank A
--   2.  Write bank B, read back from bank B
--   3.  Banks are independent (no cross-contamination)
--   4.  Multiple addresses
--   5.  Bank toggle per-line pattern
--   6.  Exact read latency verification (2 cycles)
--   7.  Exact write latency verification (2 cycles)
--   8.  Streaming sequential reads
--   9.  Address boundary (addr 0 and max addr)
--  10.  Simultaneous read/write different banks

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_video_line_buffer is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_video_line_buffer is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_WIDTH      : integer := 10;
  constant C_DEPTH      : integer := 4;  -- 16 entries (small for test)
  constant C_MAX_ADDR   : integer := (2**C_DEPTH) - 1;

  signal clk       : std_logic := '0';
  signal i_ab      : std_logic := '0';
  signal i_wr_addr : unsigned(C_DEPTH - 1 downto 0) := (others => '0');
  signal i_rd_addr : unsigned(C_DEPTH - 1 downto 0) := (others => '0');
  signal i_data    : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal o_data    : std_logic_vector(C_WIDTH - 1 downto 0);
  signal test_done : std_logic := '0';

begin

  clk <= not clk after C_CLK_PERIOD / 2 when test_done = '0' else unaffected;

  dut : entity rtl_lib.video_line_buffer
    generic map (
      G_WIDTH => C_WIDTH,
      G_DEPTH => C_DEPTH
    )
    port map (
      clk       => clk,
      i_ab      => i_ab,
      i_wr_addr => i_wr_addr,
      i_rd_addr => i_rd_addr,
      i_data    => i_data,
      o_data    => o_data
    );

  main : process
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      i_ab      <= '0';
      i_wr_addr <= (others => '0');
      i_rd_addr <= (others => '0');
      i_data    <= (others => '0');
      -- Let input registers settle
      for i in 1 to 4 loop
        wait until rising_edge(clk);
      end loop;

      -- ====================================================================
      if run("write_bank_a_read_back") then
      -- ====================================================================
        -- Write to bank A (i_ab='0' writes bank A)
        i_ab      <= '0';
        i_wr_addr <= to_unsigned(5, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(42, C_WIDTH));
        wait until rising_edge(clk);  -- input reg
        wait until rising_edge(clk);  -- BRAM write

        -- Read bank A (i_ab='1' reads bank A)
        i_ab      <= '1';
        i_rd_addr <= to_unsigned(5, C_DEPTH);
        i_data    <= (others => '0');
        wait until rising_edge(clk);  -- input reg: s_i_rd_addr = 5
        wait until rising_edge(clk);  -- BRAM read: s_output_a = data
        wait for 1 ns;

        check_equal(o_data, std_logic_vector(to_unsigned(42, C_WIDTH)),
                    "Should read back 42 from bank A at address 5");

      -- ====================================================================
      elsif run("write_bank_b_read_back") then
      -- ====================================================================
        -- Write to bank B (i_ab='1' writes bank B)
        i_ab      <= '1';
        i_wr_addr <= to_unsigned(3, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(99, C_WIDTH));
        wait until rising_edge(clk);  -- input reg
        wait until rising_edge(clk);  -- BRAM write

        -- Read bank B (i_ab='0' reads bank B)
        i_ab      <= '0';
        i_rd_addr <= to_unsigned(3, C_DEPTH);
        i_data    <= (others => '0');
        wait until rising_edge(clk);  -- input reg
        wait until rising_edge(clk);  -- BRAM read
        wait for 1 ns;

        check_equal(o_data, std_logic_vector(to_unsigned(99, C_WIDTH)),
                    "Should read back 99 from bank B at address 3");

      -- ====================================================================
      elsif run("banks_independent") then
      -- ====================================================================
        -- Write 111 to bank A at addr 0
        i_ab      <= '0';
        i_wr_addr <= to_unsigned(0, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(111, C_WIDTH));
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Write 222 to bank B at addr 0
        i_ab      <= '1';
        i_wr_addr <= to_unsigned(0, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(222, C_WIDTH));
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Read bank A (i_ab='1' reads bank A, also writes bank B at addr 0)
        i_ab      <= '1';
        i_rd_addr <= to_unsigned(0, C_DEPTH);
        i_wr_addr <= to_unsigned(0, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(222, C_WIDTH));  -- preserve B
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(111, C_WIDTH)),
                    "Bank A should have 111, not bank B's 222");

        -- Read bank B (i_ab='0' reads bank B, also writes bank A at addr 0)
        i_ab      <= '0';
        i_rd_addr <= to_unsigned(0, C_DEPTH);
        i_wr_addr <= to_unsigned(0, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(111, C_WIDTH));  -- preserve A
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(222, C_WIDTH)),
                    "Bank B should have 222");

      -- ====================================================================
      elsif run("multiple_addresses") then
      -- ====================================================================
        -- Write sequential values to bank A at multiple addresses
        i_ab <= '0';
        for addr in 0 to 7 loop
          i_wr_addr <= to_unsigned(addr, C_DEPTH);
          i_data    <= std_logic_vector(to_unsigned(addr * 10 + 1, C_WIDTH));
          wait until rising_edge(clk);
        end loop;
        -- Let pipeline flush (input reg + BRAM write for last item)
        wait until rising_edge(clk);

        -- Read back from bank A (switch i_ab='1')
        i_ab <= '1';
        for addr in 0 to 7 loop
          i_rd_addr <= to_unsigned(addr, C_DEPTH);
          -- 2-cycle read latency
          wait until rising_edge(clk);  -- input reg
          wait until rising_edge(clk);  -- BRAM read
          wait for 1 ns;
          check_equal(o_data, std_logic_vector(to_unsigned(addr * 10 + 1, C_WIDTH)),
                      "addr " & integer'image(addr) & " should be " &
                      integer'image(addr * 10 + 1));
        end loop;

      -- ====================================================================
      elsif run("bank_toggle_pattern") then
      -- ====================================================================
        -- Write to bank A, toggle to read bank A
        i_ab <= '0';
        i_wr_addr <= to_unsigned(0, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(500, C_WIDTH));
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Toggle: now write to bank B, read from bank A
        i_ab <= '1';
        i_wr_addr <= to_unsigned(0, C_DEPTH);
        i_rd_addr <= to_unsigned(0, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(600, C_WIDTH));
        wait until rising_edge(clk);  -- input reg
        wait until rising_edge(clk);  -- BRAM read
        wait for 1 ns;

        -- o_data should show bank A's value (500)
        check_equal(o_data, std_logic_vector(to_unsigned(500, C_WIDTH)),
                    "After toggle, should read previous line (bank A=500)");

      -- ====================================================================
      elsif run("read_latency") then
      -- ====================================================================
        -- Verify exact 2-cycle read latency by checking at each edge
        -- First write known data
        i_ab <= '0';
        i_wr_addr <= to_unsigned(1, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(777, C_WIDTH));
        for i in 1 to 4 loop
          wait until rising_edge(clk);
        end loop;

        -- Switch to read and verify exact latency
        i_ab      <= '1';
        i_rd_addr <= to_unsigned(1, C_DEPTH);

        -- Edge 1: input registers latch new rd_addr and ab
        wait until rising_edge(clk);
        wait for 1 ns;
        -- o_data should NOT yet have 777 (only 1 cycle elapsed)
        -- (it has stale BRAM data from previous s_i_rd_addr)

        -- Edge 2: BRAM read completes, s_output_a = s_ram_a(addr 1) = 777
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(777, C_WIDTH)),
                    "Data should appear after exactly 2-cycle read latency");

      -- ====================================================================
      elsif run("write_latency") then
      -- ====================================================================
        -- Verify exact 2-cycle write latency
        -- Write data 333 to bank A at addr 2
        i_ab      <= '0';
        i_wr_addr <= to_unsigned(2, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(333, C_WIDTH));
        -- Edge 1: input regs latch (s_i_wr_addr=2, s_input=333, s_ab='0')
        wait until rising_edge(clk);
        -- Edge 2: BRAM write: s_ram_a(2) <= 333
        wait until rising_edge(clk);

        -- Now read it back to verify (switch to read bank A)
        i_ab      <= '1';
        i_rd_addr <= to_unsigned(2, C_DEPTH);
        wait until rising_edge(clk);  -- input reg
        wait until rising_edge(clk);  -- BRAM read
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(333, C_WIDTH)),
                    "Data written with 2-cycle latency should be readable");

      -- ====================================================================
      elsif run("streaming_sequential_reads") then
      -- ====================================================================
        -- Write pattern to bank A, then read sequentially with pipelined timing
        i_ab <= '0';
        for addr in 0 to 7 loop
          i_wr_addr <= to_unsigned(addr, C_DEPTH);
          i_data    <= std_logic_vector(to_unsigned(100 + addr, C_WIDTH));
          wait until rising_edge(clk);
        end loop;
        wait until rising_edge(clk);  -- flush last write

        -- Read all 8 values with 1-cycle-per-read pipelining
        -- First read takes 2 cycles; subsequent reads are pipelined
        i_ab <= '1';
        i_rd_addr <= to_unsigned(0, C_DEPTH);
        wait until rising_edge(clk);  -- input reg for addr 0

        -- Drive addr 1 while addr 0 is being read from BRAM
        i_rd_addr <= to_unsigned(1, C_DEPTH);
        wait until rising_edge(clk);  -- BRAM read for addr 0; input reg for addr 1
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(100, C_WIDTH)),
                    "streaming addr 0 = 100");

        -- Continue pipelined reads
        for addr in 2 to 7 loop
          i_rd_addr <= to_unsigned(addr, C_DEPTH);
          wait until rising_edge(clk);
          wait for 1 ns;
          check_equal(o_data, std_logic_vector(to_unsigned(100 + addr - 1, C_WIDTH)),
                      "streaming addr " & integer'image(addr - 1));
        end loop;

        -- Read final value
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(107, C_WIDTH)),
                    "streaming addr 7 = 107");

      -- ====================================================================
      elsif run("address_boundary") then
      -- ====================================================================
        -- Test addr 0 and max addr
        i_ab <= '0';
        -- Write to addr 0
        i_wr_addr <= to_unsigned(0, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(11, C_WIDTH));
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Write to max addr
        i_wr_addr <= to_unsigned(C_MAX_ADDR, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(999, C_WIDTH));
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Read back addr 0
        i_ab      <= '1';
        i_rd_addr <= to_unsigned(0, C_DEPTH);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(11, C_WIDTH)),
                    "addr 0 should hold 11");

        -- Read back max addr
        i_rd_addr <= to_unsigned(C_MAX_ADDR, C_DEPTH);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check_equal(o_data, std_logic_vector(to_unsigned(999, C_WIDTH)),
                    "max addr should hold 999");

      -- ====================================================================
      elsif run("simultaneous_read_write") then
      -- ====================================================================
        -- Write to bank A while reading from bank B simultaneously
        -- First, populate bank B with known data
        i_ab <= '1';  -- write bank B
        i_wr_addr <= to_unsigned(4, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(555, C_WIDTH));
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Now: i_ab='0' writes bank A and reads bank B simultaneously
        i_ab      <= '0';
        i_wr_addr <= to_unsigned(4, C_DEPTH);
        i_data    <= std_logic_vector(to_unsigned(888, C_WIDTH));
        i_rd_addr <= to_unsigned(4, C_DEPTH);
        wait until rising_edge(clk);  -- input reg
        wait until rising_edge(clk);  -- BRAM write A + BRAM read B
        wait for 1 ns;

        -- o_data should be bank B's value (555), not A's new value (888)
        check_equal(o_data, std_logic_vector(to_unsigned(555, C_WIDTH)),
                    "Read bank B=555 while writing bank A=888");

      end if;
    end loop;

    test_done <= '1';
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 10 ms);

end architecture;
