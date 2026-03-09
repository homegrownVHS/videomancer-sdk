# Videomancer SDK - FPGA Build Makefile
# Copyright (C) 2025 LZX Industries LLC
# SPDX-License-Identifier: GPL-3.0-only

# Root paths (must be provided by caller)
VIDEOMANCER_SDK_ROOT ?= ..
PROJECT_ROOT ?= $(VIDEOMANCER_SDK_ROOT)/programs/$(PROGRAM)
BUILD_ROOT ?= $(VIDEOMANCER_SDK_ROOT)/build/programs/$(PROGRAM)

PROGRAM = passthru
CONFIG = hd_analog
DEVICE = hx4k
PACKAGE = tq144
FREQUENCY = 74.25
HARDWARE = rev_b
CORE = yuv444_30b
PLATFORM = ice40
SEED ?= 1

# HD clock decimation: 1 = full speed (default), 2 = half, 4 = quarter.
# When > 1 and building an HD config, a PLL divides the program clock.
HD_CLOCK_DIVISOR ?= 1

# Select config package source: static file by default, generated when
# HD_CLOCK_DIVISOR > 1 so that core_config_pkg embeds the correct divisor.
GENERATED_CONFIG = $(BUILD_PREFIX)core_config_pkg.vhd

ifeq ($(HD_CLOCK_DIVISOR),1)
  CONFIG_PKG = $(VIDEOMANCER_SDK_ROOT)/fpga/common/rtl/core_config/$(CONFIG)_pkg.vhd
else
  CONFIG_PKG = $(GENERATED_CONFIG)
endif

VHD_FILES = $(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/core/${CORE}/rtl/*.vhd) \
	$(CONFIG_PKG) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/common/rtl/serial/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/common/rtl/dsp/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/common/rtl/utils/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/common/rtl/video_stream/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/common/rtl/video_timing/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/common/rtl/video_sync/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/platform/$(PLATFORM)/rtl/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/fpga/hardware/$(HARDWARE)/rtl/*.vhd) \
	$(wildcard $(VIDEOMANCER_SDK_ROOT)/third_party/SiliconBlue/rtl/sb_*.vhd) \
	$(wildcard $(PROJECT_ROOT)/*.vhd)

PCF_FILE = \
	$(VIDEOMANCER_SDK_ROOT)/fpga/hardware/$(HARDWARE)/constraints/pin_map.pcf

BUILD_PREFIX = $(BUILD_ROOT)/bitstreams/
BIN_FILE = $(BUILD_PREFIX)$(CONFIG).bin
JSON_FILE = $(BUILD_PREFIX)$(CONFIG).json
ASC_FILE = $(BUILD_PREFIX)$(CONFIG).asc

all: $(BIN_FILE)

# Generate core_config_pkg with HD_CLOCK_DIVISOR baked in.
# Only used when HD_CLOCK_DIVISOR > 1; otherwise the static package is used.
$(GENERATED_CONFIG):
	@mkdir -p $(dir $@)
	@python3 $(VIDEOMANCER_SDK_ROOT)/tools/gen-core-config/gen_core_config.py \
		--config $(CONFIG) --hd-clock-divisor $(HD_CLOCK_DIVISOR) --output $@

$(JSON_FILE): $(VHD_FILES)
	@mkdir -p $(dir $@)
	yosys -m ghdl -p 'ghdl --std=08 $^ -e hardware_top; synth_ice40 -json $@'

$(ASC_FILE): $(JSON_FILE)
	@mkdir -p $(dir $@)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --pcf $(PCF_FILE) --freq $(FREQUENCY) --json $< --asc $@ --seed $(SEED) --timing-allow-fail

$(BIN_FILE): $(ASC_FILE)
	icepack $< $@

prog: $(BIN_FILE)
	iceprog $<

clean:
	rm -f $(JSON_FILE) $(ASC_FILE) $(BIN_FILE) $(GENERATED_CONFIG)

.SECONDARY:

.PHONY: all prog clean