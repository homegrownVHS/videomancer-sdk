-- Videomancer SDK - Open source FPGA-based video effects development kit
-- Copyright (C) 2025 LZX Industries LLC
-- File: tb_spi_peripheral.vhd - Testbench for SPI Peripheral Controller
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
--   Comprehensive VUnit testbench for spi_peripheral (SPI peripheral controller).
--   Tests SPI Mode 1 (G_CPOL=0, G_CPHA=1) with 36 tests covering:
--     - Protocol correctness (write, read, SDO data verification)
--     - Signal timing (wr_en/rd_en pulse count, addr output)
--     - Auto-increment (bulk write, bulk read, full-range, max-address stop)
--     - Recovery (CS abort from address, command, data, and sending phases)
--     - Data integrity (walking ones, all-register isolation, zero data)
--     - Edge cases (SCK while CS high, back-to-back, unwritten reads)
--     - Idempotency (non-destructive reads, interleaved write-read cycles)
--     - Address decoding (walking ones on address bits)
--
--   BFM timing: 500 ns SPI clock period vs 10 ns system clock (50:1 ratio)
--   ensures CDC pipeline (3-4 system clocks) settles well within each
--   SPI half-period (250 ns = 25 system clocks).

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library rtl_lib;

entity tb_spi_peripheral is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_spi_peripheral is

  constant C_DATA_WIDTH : natural := 8;
  constant C_ADDR_WIDTH : natural := 4;  -- 16 registers (0..15)
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_SCK_PERIOD : time := 500 ns;  -- SPI clock much slower than system clock

  -- ================================================================
  -- DUT signals
  -- ================================================================
  signal clk   : std_logic := '0';
  signal sck   : std_logic := '0';
  signal sdi   : std_logic := '0';
  signal sdo   : std_logic := 'Z';  -- High-Z: no external driver on inout port
  signal cs_n  : std_logic := '1';
  signal din   : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal dout  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal wr_en : std_logic;
  signal rd_en : std_logic;
  signal addr  : unsigned(C_ADDR_WIDTH - 1 downto 0);

  signal test_done : boolean := false;

  -- ================================================================
  -- Register file backing store
  -- ================================================================
  type t_reg_file is array (0 to 2**C_ADDR_WIDTH - 1) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal reg_file : t_reg_file := (others => (others => '0'));

  -- Control signals (single driver for reg_file via reg_file_proc)
  signal clear_regs    : std_logic := '0';
  signal preload_en    : std_logic := '0';
  signal preload_addr  : natural range 0 to 2**C_ADDR_WIDTH - 1 := 0;
  signal preload_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

  -- ================================================================
  -- Pulse monitoring signals
  -- ================================================================
  signal wr_en_count   : natural := 0;
  signal rd_en_count   : natural := 0;
  signal last_wr_addr  : unsigned(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal last_rd_addr  : unsigned(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal last_wr_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

  -- ================================================================
  -- SPI BFM procedures (Mode 1: G_CPOL=0, G_CPHA=1)
  -- Data changes on rising SCK edge, sampled on falling SCK edge.
  -- ================================================================

  -- Shift one bit out on SDI (MSB first, Mode 1)
  procedure spi_shift_bit(
    signal sck_sig : out std_logic;
    signal sdi_sig : out std_logic;
    constant bit_val : std_logic
  ) is
  begin
    -- Rising edge: data changes
    sck_sig <= '1';
    sdi_sig <= bit_val;
    wait for C_SCK_PERIOD / 2;
    -- Falling edge: data sampled by peripheral
    sck_sig <= '0';
    wait for C_SCK_PERIOD / 2;
  end procedure;

  -- Send address bits (MSB first)
  procedure spi_send_address(
    signal sck_sig : out std_logic;
    signal sdi_sig : out std_logic;
    constant address : unsigned(C_ADDR_WIDTH - 1 downto 0)
  ) is
  begin
    for i in C_ADDR_WIDTH - 1 downto 0 loop
      spi_shift_bit(sck_sig, sdi_sig, address(i));
    end loop;
  end procedure;

  -- Send command bit: 1 = write, 0 = read
  procedure spi_send_command(
    signal sck_sig : out std_logic;
    signal sdi_sig : out std_logic;
    constant is_write : boolean
  ) is
  begin
    if is_write then
      spi_shift_bit(sck_sig, sdi_sig, '1');
    else
      spi_shift_bit(sck_sig, sdi_sig, '0');
    end if;
  end procedure;

  -- Send one data byte (MSB first, write direction)
  procedure spi_send_data(
    signal sck_sig : out std_logic;
    signal sdi_sig : out std_logic;
    constant data : std_logic_vector(C_DATA_WIDTH - 1 downto 0)
  ) is
  begin
    for i in C_DATA_WIDTH - 1 downto 0 loop
      spi_shift_bit(sck_sig, sdi_sig, data(i));
    end loop;
  end procedure;

  -- Receive one data byte with SDO capture (MSB first, read direction)
  -- Samples SDO at end of high phase (250 ns after rising SCK, well after
  -- the ~30 ns CDC + state machine pipeline for SDO output).
  procedure spi_recv_data_capture(
    signal sck_sig : out std_logic;
    signal sdi_sig : out std_logic;
    signal sdo_sig : in  std_logic;
    variable data  : out std_logic_vector(C_DATA_WIDTH - 1 downto 0)
  ) is
  begin
    for i in C_DATA_WIDTH - 1 downto 0 loop
      sck_sig <= '1';
      sdi_sig <= '0';
      wait for C_SCK_PERIOD / 2;
      data(i) := sdo_sig;
      sck_sig <= '0';
      wait for C_SCK_PERIOD / 2;
    end loop;
  end procedure;

  -- Assert CS (begin transaction)
  procedure spi_begin(
    signal cs_n_sig : out std_logic
  ) is
  begin
    cs_n_sig <= '0';
    wait for C_SCK_PERIOD;  -- CS setup time
  end procedure;

  -- Deassert CS (end transaction) with inter-transaction gap
  procedure spi_end(
    signal cs_n_sig : out std_logic
  ) is
  begin
    wait for C_SCK_PERIOD;
    cs_n_sig <= '1';
    wait for C_SCK_PERIOD * 2;  -- Inter-transaction gap
  end procedure;

  -- Full write transaction: CS assert, address, W command, data, CS deassert
  procedure spi_write_reg(
    signal cs_n_sig : out std_logic;
    signal sck_sig  : out std_logic;
    signal sdi_sig  : out std_logic;
    constant address : unsigned(C_ADDR_WIDTH - 1 downto 0);
    constant data    : std_logic_vector(C_DATA_WIDTH - 1 downto 0)
  ) is
  begin
    cs_n_sig <= '0';
    wait for C_SCK_PERIOD;
    spi_send_address(sck_sig, sdi_sig, address);
    spi_send_command(sck_sig, sdi_sig, true);
    spi_send_data(sck_sig, sdi_sig, data);
    wait for C_SCK_PERIOD;
    cs_n_sig <= '1';
    wait for C_SCK_PERIOD * 2;
  end procedure;

  -- Full read transaction with SDO capture
  procedure spi_read_reg_capture(
    signal cs_n_sig : out std_logic;
    signal sck_sig  : out std_logic;
    signal sdi_sig  : out std_logic;
    signal sdo_sig  : in  std_logic;
    constant address : unsigned(C_ADDR_WIDTH - 1 downto 0);
    variable data    : out std_logic_vector(C_DATA_WIDTH - 1 downto 0)
  ) is
  begin
    cs_n_sig <= '0';
    wait for C_SCK_PERIOD;
    spi_send_address(sck_sig, sdi_sig, address);
    spi_send_command(sck_sig, sdi_sig, false);
    -- Wait for peripheral to process read request and enter SENDING_DATA
    -- (CDC + edge detection + REQUESTING_READ + WAITING_READ = ~5 clocks = ~50 ns)
    wait for C_SCK_PERIOD * 3;
    spi_recv_data_capture(sck_sig, sdi_sig, sdo_sig, data);
    wait for C_SCK_PERIOD;
    cs_n_sig <= '1';
    wait for C_SCK_PERIOD * 2;
  end procedure;

  -- Preload a register value (using the preload control signals)
  procedure preload_register(
    signal en_sig   : out std_logic;
    signal addr_sig : out natural;
    signal data_sig : out std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    constant reg_addr : natural;
    constant reg_data : std_logic_vector(C_DATA_WIDTH - 1 downto 0)
  ) is
  begin
    data_sig <= reg_data;
    addr_sig <= reg_addr;
    en_sig   <= '1';
    wait until rising_edge(clk);
    en_sig   <= '0';
    wait for C_CLK_PERIOD * 2;
  end procedure;

begin

  clk <= not clk after C_CLK_PERIOD / 2 when not test_done;

  -- ================================================================
  -- DUT instantiation
  -- ================================================================
  dut : entity rtl_lib.spi_peripheral
    generic map (
      G_DATA_WIDTH => C_DATA_WIDTH,
      G_ADDR_WIDTH => C_ADDR_WIDTH,
      G_CPOL       => '0',
      G_CPHA       => '1'
    )
    port map (
      clk   => clk,
      sck   => sck,
      sdi   => sdi,
      sdo   => sdo,
      cs_n  => cs_n,
      din   => din,
      dout  => dout,
      wr_en => wr_en,
      rd_en => rd_en,
      addr  => addr
    );

  -- ================================================================
  -- Register file backing store (sole driver of reg_file)
  -- ================================================================
  reg_file_proc : process(clk)
  begin
    if rising_edge(clk) then
      if clear_regs = '1' then
        reg_file <= (others => (others => '0'));
      elsif preload_en = '1' then
        reg_file(preload_addr) <= preload_data;
      elsif wr_en = '1' then
        reg_file(to_integer(addr)) <= dout;
      end if;
      if rd_en = '1' then
        din <= reg_file(to_integer(addr));
      end if;
    end if;
  end process;

  -- ================================================================
  -- Pulse monitor (counts wr_en/rd_en pulses, captures addr/data)
  -- ================================================================
  pulse_monitor : process(clk)
  begin
    if rising_edge(clk) then
      if wr_en = '1' then
        wr_en_count <= wr_en_count + 1;
        last_wr_addr <= addr;
        last_wr_data <= dout;
      end if;
      if rd_en = '1' then
        rd_en_count <= rd_en_count + 1;
        last_rd_addr <= addr;
      end if;
    end if;
  end process;

  -- ================================================================
  -- Main test process
  -- ================================================================
  main : process
    variable v_read_data : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    variable v_byte2     : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    variable v_byte3     : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    variable v_byte4     : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  begin
    test_runner_setup(runner, runner_cfg);

    -- Initialize SPI bus idle state
    cs_n <= '1';
    sck  <= '0';
    sdi  <= '0';
    wait for C_CLK_PERIOD * 10;

    while test_suite loop

      -- ================================================================
      -- Test 1: CS idle -- no activity when CS is high
      -- ================================================================
      if run("test_cs_idle") then
        info("Testing CS idle state");
        cs_n <= '1';
        wait for C_SCK_PERIOD * 5;
        check_equal(wr_en, '0', "wr_en should be low when CS is high");
        check_equal(rd_en, '0', "rd_en should be low when CS is high");

      -- ================================================================
      -- Test 2: Single register write
      -- ================================================================
      elsif run("test_single_write") then
        info("Testing single register write");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(3, C_ADDR_WIDTH),
                      x"A5");
        wait for C_SCK_PERIOD * 5;

        check_equal(reg_file(3), std_logic_vector'(x"A5"),
                    "Register 3 should contain 0xA5");

      -- ================================================================
      -- Test 3: Write to address 0
      -- ================================================================
      elsif run("test_write_addr_zero") then
        info("Testing write to address 0");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(0, C_ADDR_WIDTH),
                      x"42");
        wait for C_SCK_PERIOD * 5;

        check_equal(reg_file(0), std_logic_vector'(x"42"),
                    "Register 0 should contain 0x42");

      -- ================================================================
      -- Test 4: Write to max address
      -- ================================================================
      elsif run("test_write_max_addr") then
        info("Testing write to max address");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(2**C_ADDR_WIDTH - 1, C_ADDR_WIDTH),
                      x"FF");
        wait for C_SCK_PERIOD * 5;

        check_equal(reg_file(2**C_ADDR_WIDTH - 1), std_logic_vector'(x"FF"),
                    "Max register should contain 0xFF");

      -- ================================================================
      -- Test 5: Multiple writes to different registers
      -- ================================================================
      elsif run("test_multiple_writes") then
        info("Testing writes to multiple registers");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(0, C_ADDR_WIDTH), x"11");
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(1, C_ADDR_WIDTH), x"22");
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(5, C_ADDR_WIDTH), x"55");
        wait for C_SCK_PERIOD * 5;

        check_equal(reg_file(0), std_logic_vector'(x"11"), "Reg 0 = 0x11");
        check_equal(reg_file(1), std_logic_vector'(x"22"), "Reg 1 = 0x22");
        check_equal(reg_file(5), std_logic_vector'(x"55"), "Reg 5 = 0x55");
        check_equal(reg_file(2), std_logic_vector'(x"00"), "Reg 2 = 0x00 (untouched)");

      -- ================================================================
      -- Test 6: CS deassert resets state machine (abort in address phase)
      -- ================================================================
      elsif run("test_cs_deassert_reset") then
        info("Testing CS deassert resets state machine");
        -- Start a transaction but abort mid-address
        cs_n <= '0';
        wait for C_SCK_PERIOD;
        spi_shift_bit(sck, sdi, '1');
        spi_shift_bit(sck, sdi, '0');
        -- Abort by deasserting CS
        cs_n <= '1';
        wait for C_SCK_PERIOD * 5;

        -- Now do a complete valid write to prove SM recovered
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(7, C_ADDR_WIDTH),
                      x"BB");
        wait for C_SCK_PERIOD * 5;

        check_equal(reg_file(7), std_logic_vector'(x"BB"),
                    "Register 7 should contain 0xBB after CS reset recovery");

      -- ================================================================
      -- Test 7: Read transaction with SDO data verification
      -- ================================================================
      elsif run("test_read_sdo_data") then
        info("Testing read transaction captures correct SDO data");
        -- Preload register 2 with a known value
        preload_register(preload_en, preload_addr, preload_data, 2, x"CD");

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(2, C_ADDR_WIDTH), v_read_data);

        check_equal(v_read_data, std_logic_vector'(x"CD"),
                    "SDO should output 0xCD from register 2");

      -- ================================================================
      -- Test 8: Overwrite register
      -- ================================================================
      elsif run("test_overwrite") then
        info("Testing register overwrite");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(4, C_ADDR_WIDTH), x"AA");
        wait for C_SCK_PERIOD * 3;
        check_equal(reg_file(4), std_logic_vector'(x"AA"), "First write: 0xAA");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(4, C_ADDR_WIDTH), x"55");
        wait for C_SCK_PERIOD * 3;
        check_equal(reg_file(4), std_logic_vector'(x"55"), "Overwrite: 0x55");

      -- ================================================================
      -- Test 9: Write then read roundtrip (end-to-end data integrity)
      -- ================================================================
      elsif run("test_write_read_roundtrip") then
        info("Testing write-then-read roundtrip");

        -- Write a value
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(6, C_ADDR_WIDTH), x"7E");
        wait for C_SCK_PERIOD * 3;

        -- Read it back
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(6, C_ADDR_WIDTH), v_read_data);

        check_equal(v_read_data, std_logic_vector'(x"7E"),
                    "Read-back should match written value 0x7E");

      -- ================================================================
      -- Test 10: wr_en pulse count (exactly 1 per write)
      -- ================================================================
      elsif run("test_wr_en_pulse_count") then
        info("Testing wr_en pulses exactly once per write");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(5, C_ADDR_WIDTH), x"AA");
        wait for C_SCK_PERIOD * 3;

        check_equal(wr_en_count, 1, "wr_en should pulse exactly once for one write");
        check_equal(wr_en, '0', "wr_en should be low after transaction");

        -- Second write
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(6, C_ADDR_WIDTH), x"BB");
        wait for C_SCK_PERIOD * 3;

        check_equal(wr_en_count, 2, "wr_en should pulse twice after two writes");

      -- ================================================================
      -- Test 11: rd_en pulse count (exactly 1 per read)
      -- ================================================================
      elsif run("test_rd_en_pulse_count") then
        info("Testing rd_en pulses exactly once per read");
        -- Read from max address (15) to avoid speculative auto-increment:
        -- at max address, SENDING_DATA goes to IDLE after last bit instead
        -- of issuing another rd_en for the next address.
        preload_register(preload_en, preload_addr, preload_data, 15, x"42");

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_read_data);

        check_equal(rd_en_count, 1, "rd_en should pulse exactly once for max-addr read");
        check_equal(rd_en, '0', "rd_en should be low after transaction");
        check_equal(v_read_data, std_logic_vector'(x"42"), "Read data should match 0x42");

      -- ================================================================
      -- Test 12: addr output matches SPI address on wr_en
      -- ================================================================
      elsif run("test_addr_on_write") then
        info("Testing addr output correctness on write");

        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(9, C_ADDR_WIDTH), x"12");
        wait for C_SCK_PERIOD * 3;

        check_equal(last_wr_addr, to_unsigned(9, C_ADDR_WIDTH),
                    "Captured addr should be 9 on write");
        check_equal(last_wr_data, std_logic_vector'(x"12"),
                    "Captured dout should be 0x12 on write");

      -- ================================================================
      -- Test 13: addr output matches SPI address on rd_en
      -- ================================================================
      elsif run("test_addr_on_read") then
        info("Testing addr output correctness on read");
        -- Read from max address (15) so there is no speculative auto-increment
        -- that would overwrite last_rd_addr with addr+1.
        preload_register(preload_en, preload_addr, preload_data, 15, x"EE");

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_read_data);

        check_equal(last_rd_addr, to_unsigned(15, C_ADDR_WIDTH),
                    "Captured addr should be 15 on read");
        check_equal(v_read_data, std_logic_vector'(x"EE"),
                    "Read data should match 0xEE");

      -- ================================================================
      -- Test 14: SDO tristate when CS is high
      -- ================================================================
      elsif run("test_sdo_tristate_idle") then
        info("Testing SDO is tri-state when CS is high");

        -- Initially idle: SDO should be Z
        wait for C_SCK_PERIOD;
        check(sdo = 'Z', "SDO should be tri-state in idle");

        -- Do a write (SDO gets driven during transaction)
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(0, C_ADDR_WIDTH), x"00");

        -- After CS deasserts: SDO should return to Z
        wait for C_SCK_PERIOD;
        check(sdo = 'Z', "SDO should be tri-state after CS deassert");

      -- ================================================================
      -- Test 15: Auto-increment write (bulk write, 4 bytes)
      -- ================================================================
      elsif run("test_auto_increment_write") then
        info("Testing auto-increment write across 4 registers");

        -- CS low, send address 2, write command, then 4 data bytes
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(2, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, true);
        spi_send_data(sck, sdi, x"AA");
        spi_send_data(sck, sdi, x"BB");
        spi_send_data(sck, sdi, x"CC");
        spi_send_data(sck, sdi, x"DD");
        spi_end(cs_n);

        wait for C_SCK_PERIOD * 3;

        check_equal(reg_file(2), std_logic_vector'(x"AA"), "Addr 2 = 0xAA");
        check_equal(reg_file(3), std_logic_vector'(x"BB"), "Addr 3 = 0xBB");
        check_equal(reg_file(4), std_logic_vector'(x"CC"), "Addr 4 = 0xCC");
        check_equal(reg_file(5), std_logic_vector'(x"DD"), "Addr 5 = 0xDD");
        -- Untouched registers
        check_equal(reg_file(0), std_logic_vector'(x"00"), "Addr 0 untouched");
        check_equal(reg_file(1), std_logic_vector'(x"00"), "Addr 1 untouched");
        check_equal(reg_file(6), std_logic_vector'(x"00"), "Addr 6 untouched");

        -- Should have 4 wr_en pulses
        check_equal(wr_en_count, 4, "wr_en should pulse 4 times for bulk write");

      -- ================================================================
      -- Test 16: Auto-increment read (bulk read, 3 bytes)
      -- ================================================================
      elsif run("test_auto_increment_read") then
        info("Testing auto-increment read across 3 registers");

        -- Start at addr 13 so byte 3 is at addr 15 (max).
        -- At max address, no speculative auto-increment: exactly 3 rd_en pulses.
        preload_register(preload_en, preload_addr, preload_data, 13, x"11");
        preload_register(preload_en, preload_addr, preload_data, 14, x"22");
        preload_register(preload_en, preload_addr, preload_data, 15, x"33");

        -- CS low, send address 13, read command, clock out 3 bytes
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(13, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, false);
        -- Wait for peripheral to enter SENDING_DATA for first byte
        wait for C_SCK_PERIOD * 3;
        spi_recv_data_capture(sck, sdi, sdo, v_read_data);
        -- After last bit of byte 1: auto-increment ->
        --   REQUESTING_READ -> WAITING_READ -> SENDING_DATA
        -- Next SCK pulse is ~500 ns later; state machine needs ~30 ns
        spi_recv_data_capture(sck, sdi, sdo, v_byte2);
        spi_recv_data_capture(sck, sdi, sdo, v_byte3);
        spi_end(cs_n);

        check_equal(v_read_data, std_logic_vector'(x"11"),
                    "Byte 1 (addr 13) = 0x11");
        check_equal(v_byte2, std_logic_vector'(x"22"),
                    "Byte 2 (addr 14) = 0x22");
        check_equal(v_byte3, std_logic_vector'(x"33"),
                    "Byte 3 (addr 15) = 0x33");

        -- 3 rd_en pulses: initial (addr 13) + auto-inc to 14 + auto-inc to 15
        -- No 4th pulse because addr 15 is max -> IDLE
        check_equal(rd_en_count, 3,
                    "rd_en should pulse 3 times for bulk read ending at max");

      -- ================================================================
      -- Test 17: Auto-increment stops at max address
      -- ================================================================
      elsif run("test_auto_increment_max_addr") then
        info("Testing auto-increment write stops at max address");

        -- Write starting at addr 14: writes 14 and 15, then stops
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(14, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, true);
        spi_send_data(sck, sdi, x"E0");  -- addr 14
        spi_send_data(sck, sdi, x"F0");  -- addr 15 (max)
        -- After addr 15 write, SM goes to IDLE (addr at max)
        -- A third byte should NOT be written
        spi_send_data(sck, sdi, x"99");  -- Should be ignored
        spi_end(cs_n);

        wait for C_SCK_PERIOD * 3;

        check_equal(reg_file(14), std_logic_vector'(x"E0"), "Addr 14 = 0xE0");
        check_equal(reg_file(15), std_logic_vector'(x"F0"), "Addr 15 = 0xF0");
        check_equal(wr_en_count, 2,
                    "wr_en should pulse exactly 2 times (stopped at max)");

      -- ================================================================
      -- Test 18: CS abort during data phase recovers
      -- ================================================================
      elsif run("test_cs_abort_data_phase") then
        info("Testing CS abort during data phase");

        -- Start a write, send address and command, but abort mid-data
        cs_n <= '0';
        wait for C_SCK_PERIOD;
        spi_send_address(sck, sdi, to_unsigned(8, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, true);
        -- Send only 4 of 8 data bits
        spi_shift_bit(sck, sdi, '1');
        spi_shift_bit(sck, sdi, '0');
        spi_shift_bit(sck, sdi, '1');
        spi_shift_bit(sck, sdi, '0');
        -- Abort
        cs_n <= '1';
        wait for C_SCK_PERIOD * 5;

        -- Verify the aborted write did NOT commit
        check_equal(reg_file(8), std_logic_vector'(x"00"),
                    "Aborted write should not modify register");

        -- Now do a valid write to prove SM recovered
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(8, C_ADDR_WIDTH), x"77");
        wait for C_SCK_PERIOD * 3;

        check_equal(reg_file(8), std_logic_vector'(x"77"),
                    "Register 8 should contain 0x77 after recovery");

      -- ================================================================
      -- Test 19: Walking ones data pattern (verify all data bits)
      -- ================================================================
      elsif run("test_walking_ones_data") then
        info("Testing walking ones data pattern");

        for bit_pos in 0 to C_DATA_WIDTH - 1 loop
          spi_write_reg(cs_n, sck, sdi,
                        to_unsigned(bit_pos, C_ADDR_WIDTH),
                        std_logic_vector(to_unsigned(2**bit_pos, C_DATA_WIDTH)));
          wait for C_SCK_PERIOD * 3;
        end loop;

        -- Verify each register via register file
        check_equal(reg_file(0), std_logic_vector'(x"01"), "Walk 0: 0x01");
        check_equal(reg_file(1), std_logic_vector'(x"02"), "Walk 1: 0x02");
        check_equal(reg_file(2), std_logic_vector'(x"04"), "Walk 2: 0x04");
        check_equal(reg_file(3), std_logic_vector'(x"08"), "Walk 3: 0x08");
        check_equal(reg_file(4), std_logic_vector'(x"10"), "Walk 4: 0x10");
        check_equal(reg_file(5), std_logic_vector'(x"20"), "Walk 5: 0x20");
        check_equal(reg_file(6), std_logic_vector'(x"40"), "Walk 6: 0x40");
        check_equal(reg_file(7), std_logic_vector'(x"80"), "Walk 7: 0x80");

        -- Read back via SPI and verify SDO matches
        for bit_pos in 0 to C_DATA_WIDTH - 1 loop
          spi_read_reg_capture(cs_n, sck, sdi, sdo,
                               to_unsigned(bit_pos, C_ADDR_WIDTH), v_read_data);
          check_equal(v_read_data,
                      std_logic_vector(to_unsigned(2**bit_pos, C_DATA_WIDTH)),
                      "Walking-1 readback at addr " & integer'image(bit_pos));
        end loop;

      -- ================================================================
      -- Test 20: All registers isolation (no cross-contamination)
      -- ================================================================
      elsif run("test_all_registers_isolation") then
        info("Testing all 16 registers for isolation");

        -- Write unique values to all 16 registers
        -- Pattern: reg(i) = i * 15 + 1 (all non-zero, all unique, max 226 < 256)
        for i in 0 to 2**C_ADDR_WIDTH - 1 loop
          spi_write_reg(cs_n, sck, sdi,
                        to_unsigned(i, C_ADDR_WIDTH),
                        std_logic_vector(to_unsigned(i * 15 + 1, C_DATA_WIDTH)));
          wait for C_SCK_PERIOD * 3;
        end loop;

        -- Verify each register independently
        for i in 0 to 2**C_ADDR_WIDTH - 1 loop
          check_equal(reg_file(i),
                      std_logic_vector(to_unsigned(i * 15 + 1, C_DATA_WIDTH)),
                      "Reg " & integer'image(i) & " isolation check");
        end loop;

        -- Overwrite register 8 and verify neighbors are unchanged
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(8, C_ADDR_WIDTH), x"FF");
        wait for C_SCK_PERIOD * 3;

        check_equal(reg_file(7),
                    std_logic_vector(to_unsigned(7 * 15 + 1, C_DATA_WIDTH)),
                    "Reg 7 unchanged after modifying reg 8");
        check_equal(reg_file(8), std_logic_vector'(x"FF"),
                    "Reg 8 overwritten to 0xFF");
        check_equal(reg_file(9),
                    std_logic_vector(to_unsigned(9 * 15 + 1, C_DATA_WIDTH)),
                    "Reg 9 unchanged after modifying reg 8");

      -- ================================================================
      -- Test 21: CS abort during command phase recovers
      -- ================================================================
      elsif run("test_cs_abort_command_phase") then
        info("Testing CS abort during command phase");

        -- Send full address, then abort before the command bit completes
        cs_n <= '0';
        wait for C_SCK_PERIOD;
        spi_send_address(sck, sdi, to_unsigned(5, C_ADDR_WIDTH));
        -- Start command bit but abort mid-way through
        sck <= '1';
        sdi <= '1';  -- write command
        wait for C_SCK_PERIOD / 4;
        -- Abort before falling edge
        cs_n <= '1';
        sck  <= '0';
        wait for C_SCK_PERIOD * 5;

        -- No write should have occurred
        check_equal(wr_en_count, 0, "No wr_en should pulse from aborted command");
        check_equal(rd_en_count, 0, "No rd_en should pulse from aborted command");

        -- Prove state machine recovered with a valid write
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(5, C_ADDR_WIDTH), x"AC");
        wait for C_SCK_PERIOD * 3;

        check_equal(reg_file(5), std_logic_vector'(x"AC"),
                    "Reg 5 should contain 0xAC after recovery");

      -- ================================================================
      -- Test 22: SCK toggles while CS high are ignored
      -- ================================================================
      elsif run("test_sck_ignored_cs_high") then
        info("Testing SCK activity is ignored when CS is high");

        cs_n <= '1';
        wait for C_SCK_PERIOD;

        -- Toggle SCK several times with data on SDI
        for i in 0 to 15 loop
          spi_shift_bit(sck, sdi, '1');
        end loop;

        wait for C_SCK_PERIOD * 3;

        -- Nothing should have happened
        check_equal(wr_en_count, 0, "wr_en should be 0 with CS high");
        check_equal(rd_en_count, 0, "rd_en should be 0 with CS high");
        check(sdo = 'Z', "SDO should remain tri-state");

      -- ================================================================
      -- Test 23: Back-to-back rapid transactions
      -- ================================================================
      elsif run("test_back_to_back_transactions") then
        info("Testing back-to-back rapid write-read transactions");

        -- Write 3 values rapidly
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(0, C_ADDR_WIDTH), x"10");
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(1, C_ADDR_WIDTH), x"20");
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(2, C_ADDR_WIDTH), x"30");

        -- Read them back immediately
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(0, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"10"),
                    "Back-to-back: reg 0 = 0x10");

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(1, C_ADDR_WIDTH), v_byte2);
        check_equal(v_byte2, std_logic_vector'(x"20"),
                    "Back-to-back: reg 1 = 0x20");

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(2, C_ADDR_WIDTH), v_byte3);
        check_equal(v_byte3, std_logic_vector'(x"30"),
                    "Back-to-back: reg 2 = 0x30");

      -- ================================================================
      -- Test 24: Read unwritten register returns zero
      -- ================================================================
      elsif run("test_read_unwritten_register") then
        info("Testing read of unwritten register returns 0x00");

        -- Register file initializes to all zeros; read addr 10 without writing
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(10, C_ADDR_WIDTH), v_read_data);

        check_equal(v_read_data, std_logic_vector'(x"00"),
                    "Unwritten register should read back as 0x00");

      -- ================================================================
      -- Test 25: Bulk write then bulk read roundtrip
      -- ================================================================
      elsif run("test_bulk_write_read_roundtrip") then
        info("Testing auto-increment bulk write then bulk read roundtrip");

        -- Bulk write 4 registers starting at addr 10
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(10, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, true);
        spi_send_data(sck, sdi, x"DE");
        spi_send_data(sck, sdi, x"AD");
        spi_send_data(sck, sdi, x"BE");
        spi_send_data(sck, sdi, x"EF");
        spi_end(cs_n);

        wait for C_SCK_PERIOD * 3;

        -- Bulk read back starting at addr 10 (ends at 13, not max, so
        -- we expect 4 + 1 speculative rd_en; only check data correctness)
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(10, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, false);
        wait for C_SCK_PERIOD * 3;
        spi_recv_data_capture(sck, sdi, sdo, v_read_data);
        spi_recv_data_capture(sck, sdi, sdo, v_byte2);
        spi_recv_data_capture(sck, sdi, sdo, v_byte3);
        spi_recv_data_capture(sck, sdi, sdo, v_byte4);
        spi_end(cs_n);

        check_equal(v_read_data, std_logic_vector'(x"DE"), "Bulk roundtrip addr 10");
        check_equal(v_byte2, std_logic_vector'(x"AD"), "Bulk roundtrip addr 11");
        check_equal(v_byte3, std_logic_vector'(x"BE"), "Bulk roundtrip addr 12");
        check_equal(v_byte4, std_logic_vector'(x"EF"), "Bulk roundtrip addr 13");

      -- ================================================================
      -- Test 26: Auto-increment write full address range (all 16 regs)
      -- ================================================================
      elsif run("test_auto_increment_write_full_range") then
        info("Testing auto-increment write across all 16 registers");

        -- Single CS assertion, start at addr 0, write 16 bytes
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(0, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, true);
        for i in 0 to 2**C_ADDR_WIDTH - 1 loop
          spi_send_data(sck, sdi,
                        std_logic_vector(to_unsigned(16 * i + 5, C_DATA_WIDTH)));
        end loop;
        spi_end(cs_n);

        wait for C_SCK_PERIOD * 3;

        -- Verify all 16 registers
        for i in 0 to 2**C_ADDR_WIDTH - 1 loop
          check_equal(reg_file(i),
                      std_logic_vector(to_unsigned(16 * i + 5, C_DATA_WIDTH)),
                      "Full-range bulk write reg " & integer'image(i));
        end loop;

        -- 16 wr_en pulses total
        check_equal(wr_en_count, 16, "wr_en should pulse 16 times");

      -- ================================================================
      -- Test 27: CS abort during read/sending phase recovers
      -- ================================================================
      elsif run("test_cs_abort_sending_phase") then
        info("Testing CS abort while peripheral is sending data");

        -- Preload a register
        preload_register(preload_en, preload_addr, preload_data, 3, x"55");

        -- Start read: address + command complete, peripheral enters SENDING_DATA
        cs_n <= '0';
        wait for C_SCK_PERIOD;
        spi_send_address(sck, sdi, to_unsigned(3, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, false);
        -- Wait for peripheral to start sending on SDO
        wait for C_SCK_PERIOD * 3;
        -- Clock out only 3 of 8 data bits then abort
        spi_shift_bit(sck, sdi, '0');
        spi_shift_bit(sck, sdi, '0');
        spi_shift_bit(sck, sdi, '0');
        -- Abort mid-send
        cs_n <= '1';
        wait for C_SCK_PERIOD * 5;

        -- SDO should return to tri-state
        check(sdo = 'Z', "SDO should be tri-state after abort");

        -- Prove recovery: do a complete write + read
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(12, C_ADDR_WIDTH), x"3C");
        wait for C_SCK_PERIOD * 3;

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(12, C_ADDR_WIDTH), v_read_data);

        check_equal(v_read_data, std_logic_vector'(x"3C"),
                    "Read-back after send-abort should return 0x3C");

      -- ================================================================
      -- Test 28: Write 0x00 explicitly (not confused with unwritten)
      -- ================================================================
      elsif run("test_write_zero_data") then
        info("Testing explicit write of 0x00");

        -- First write a non-zero value
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(7, C_ADDR_WIDTH), x"FF");
        wait for C_SCK_PERIOD * 3;
        check_equal(reg_file(7), std_logic_vector'(x"FF"),
                    "Reg 7 should be 0xFF");

        -- Overwrite with 0x00
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(7, C_ADDR_WIDTH), x"00");
        wait for C_SCK_PERIOD * 3;
        check_equal(reg_file(7), std_logic_vector'(x"00"),
                    "Reg 7 should be 0x00 after zero-write");

        -- Read back via SPI to confirm
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(7, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"00"),
                    "SDO should output 0x00 for zero-written register");

      -- ================================================================
      -- Test 29: Non-destructive read (reading doesn't alter register)
      -- ================================================================
      elsif run("test_non_destructive_read") then
        info("Testing that reads are non-destructive");

        -- Preload register 15 with a known value
        preload_register(preload_en, preload_addr, preload_data, 15, x"A7");

        -- Read it 3 times, each time should return the same value
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"A7"),
                    "First read should return 0xA7");

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_byte2);
        check_equal(v_byte2, std_logic_vector'(x"A7"),
                    "Second read should return 0xA7");

        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_byte3);
        check_equal(v_byte3, std_logic_vector'(x"A7"),
                    "Third read should return 0xA7");

      -- ================================================================
      -- Test 30: Walking ones on address bits
      -- ================================================================
      elsif run("test_walking_ones_address") then
        info("Testing walking ones on address bits");

        -- With 4-bit address, write to addr 0001, 0010, 0100, 1000
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(1, C_ADDR_WIDTH), x"A1");
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(2, C_ADDR_WIDTH), x"B2");
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(4, C_ADDR_WIDTH), x"C4");
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(8, C_ADDR_WIDTH), x"D8");
        wait for C_SCK_PERIOD * 3;

        -- Verify targeted registers
        check_equal(reg_file(1), std_logic_vector'(x"A1"), "Addr 0001 = 0xA1");
        check_equal(reg_file(2), std_logic_vector'(x"B2"), "Addr 0010 = 0xB2");
        check_equal(reg_file(4), std_logic_vector'(x"C4"), "Addr 0100 = 0xC4");
        check_equal(reg_file(8), std_logic_vector'(x"D8"), "Addr 1000 = 0xD8");

        -- Verify non-targeted registers are still zero
        check_equal(reg_file(0),  std_logic_vector'(x"00"), "Addr 0000 untouched");
        check_equal(reg_file(3),  std_logic_vector'(x"00"), "Addr 0011 untouched");
        check_equal(reg_file(5),  std_logic_vector'(x"00"), "Addr 0101 untouched");
        check_equal(reg_file(6),  std_logic_vector'(x"00"), "Addr 0110 untouched");
        check_equal(reg_file(7),  std_logic_vector'(x"00"), "Addr 0111 untouched");
        check_equal(reg_file(9),  std_logic_vector'(x"00"), "Addr 1001 untouched");
        check_equal(reg_file(10), std_logic_vector'(x"00"), "Addr 1010 untouched");
        check_equal(reg_file(15), std_logic_vector'(x"00"), "Addr 1111 untouched");

        -- Read back targeted registers via SPI to confirm
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(1, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"A1"),
                    "SPI readback addr 1");
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(8, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"D8"),
                    "SPI readback addr 8");

      -- ================================================================
      -- Test 31: Auto-increment read ignores extra clocks after max
      -- ================================================================
      elsif run("test_auto_increment_read_extra_after_max") then
        info("Testing auto-increment read ignores extra clocks after max");

        preload_register(preload_en, preload_addr, preload_data, 14, x"EE");
        preload_register(preload_en, preload_addr, preload_data, 15, x"FF");

        -- Start read at addr 14, read 2 valid bytes
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(14, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, false);
        wait for C_SCK_PERIOD * 3;
        spi_recv_data_capture(sck, sdi, sdo, v_read_data);
        spi_recv_data_capture(sck, sdi, sdo, v_byte2);
        -- State machine went to IDLE: addr 15 = max.
        -- Clock a 3rd byte: SM is IDLE, no new rd_en, SDO holds last bit.
        spi_recv_data_capture(sck, sdi, sdo, v_byte3);
        spi_end(cs_n);

        check_equal(v_read_data, std_logic_vector'(x"EE"),
                    "Byte 1 (addr 14) = 0xEE");
        check_equal(v_byte2, std_logic_vector'(x"FF"),
                    "Byte 2 (addr 15) = 0xFF");
        -- rd_en: initial (addr 14) + auto-inc (addr 15) = 2, no 3rd pulse
        check_equal(rd_en_count, 2,
                    "rd_en should pulse only 2 times (stopped at max addr)");

      -- ================================================================
      -- Test 32: Recovery after auto-increment naturally completes
      -- ================================================================
      elsif run("test_recovery_after_natural_completion") then
        info("Testing recovery after auto-increment naturally ends at max");

        -- Bulk write that naturally ends at max address
        spi_begin(cs_n);
        spi_send_address(sck, sdi, to_unsigned(14, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, true);
        spi_send_data(sck, sdi, x"E1");  -- addr 14
        spi_send_data(sck, sdi, x"F1");  -- addr 15 (max -> IDLE)
        spi_end(cs_n);
        wait for C_SCK_PERIOD * 3;

        check_equal(reg_file(14), std_logic_vector'(x"E1"), "Addr 14 written");
        check_equal(reg_file(15), std_logic_vector'(x"F1"), "Addr 15 written");

        -- New write transaction should work
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(0, C_ADDR_WIDTH), x"99");
        wait for C_SCK_PERIOD * 3;
        check_equal(reg_file(0), std_logic_vector'(x"99"),
                    "New write works after natural max-addr completion");

        -- And a read should work too
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(14, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"E1"),
                    "Read after natural completion works");

      -- ================================================================
      -- Test 33: Rapid CS toggle (brief assertion)
      -- ================================================================
      elsif run("test_rapid_cs_toggle") then
        info("Testing very brief CS assertion does not corrupt state");

        -- Assert CS for half an SPI clock period then deassert
        cs_n <= '0';
        wait for C_SCK_PERIOD / 2;  -- 250 ns (25 sys clocks, enough for CDC)
        cs_n <= '1';
        wait for C_SCK_PERIOD * 5;

        -- No writes or reads should have occurred
        check_equal(wr_en_count, 0, "No writes from brief CS pulse");
        check_equal(rd_en_count, 0, "No reads from brief CS pulse");

        -- Prove recovery with a valid transaction
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(1, C_ADDR_WIDTH), x"DC");
        wait for C_SCK_PERIOD * 3;
        check_equal(reg_file(1), std_logic_vector'(x"DC"),
                    "Valid write works after brief CS pulse");

      -- ================================================================
      -- Test 34: SDO actively driven (not Z) during read transaction
      -- ================================================================
      elsif run("test_sdo_driven_during_read") then
        info("Testing SDO is actively driven (not Z) during read");

        -- Preload with alternating pattern so SDO exercises both values
        preload_register(preload_en, preload_addr, preload_data, 15, x"A5");

        -- Start read (use max addr to avoid auto-increment)
        cs_n <= '0';
        wait for C_SCK_PERIOD;
        spi_send_address(sck, sdi, to_unsigned(15, C_ADDR_WIDTH));
        spi_send_command(sck, sdi, false);
        wait for C_SCK_PERIOD * 3;  -- Wait for SENDING_DATA entry

        -- Clock out data and verify SDO is driven at each sampling point
        for i in C_DATA_WIDTH - 1 downto 0 loop
          sck <= '1';
          sdi <= '0';
          wait for C_SCK_PERIOD / 2;
          -- At sample point: SDO must be '0' or '1', never 'Z'
          check(sdo = '0' or sdo = '1',
                "SDO should be driven at bit " & integer'image(i));
          sck <= '0';
          wait for C_SCK_PERIOD / 2;
        end loop;

        wait for C_SCK_PERIOD;
        cs_n <= '1';
        wait for C_SCK_PERIOD * 3;

        -- After CS deassert, SDO returns to Z
        check(sdo = 'Z', "SDO should be Z after transaction");

      -- ================================================================
      -- Test 35: Interleaved write-read-write-read on same register
      -- ================================================================
      elsif run("test_interleaved_write_read_same_reg") then
        info("Testing write-read-write-read on same register");

        -- Write 0xAA
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(15, C_ADDR_WIDTH), x"AA");
        wait for C_SCK_PERIOD * 3;

        -- Read back
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"AA"),
                    "First read = 0xAA");

        -- Overwrite with 0x55
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(15, C_ADDR_WIDTH), x"55");
        wait for C_SCK_PERIOD * 3;

        -- Read back again
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"55"),
                    "Second read = 0x55 (overwritten)");

      -- ================================================================
      -- Test 36: Alternating write-read across different registers
      -- ================================================================
      elsif run("test_alternating_write_read_different_regs") then
        info("Testing alternating write-read across different registers");

        -- Write reg 0, read it back
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(0, C_ADDR_WIDTH), x"10");
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(0, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"10"), "Reg 0 = 0x10");

        -- Write reg 15, read it back
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(15, C_ADDR_WIDTH), x"FF");
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"FF"), "Reg 15 = 0xFF");

        -- Re-read reg 0 (verify not corrupted by reg 15 write)
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(0, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"10"),
                    "Reg 0 still = 0x10 after writing reg 15");

        -- Write reg 7
        spi_write_reg(cs_n, sck, sdi,
                      to_unsigned(7, C_ADDR_WIDTH), x"77");

        -- Read regs 0, 7, 15 to verify all intact
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(0, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"10"), "Reg 0 still 0x10");
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(7, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"77"), "Reg 7 = 0x77");
        spi_read_reg_capture(cs_n, sck, sdi, sdo,
                             to_unsigned(15, C_ADDR_WIDTH), v_read_data);
        check_equal(v_read_data, std_logic_vector'(x"FF"), "Reg 15 still 0xFF");

      end if;

    end loop;

    test_done <= true;
    test_runner_cleanup(runner);
  end process;

  test_runner_watchdog(runner, 100 ms);

end architecture;
