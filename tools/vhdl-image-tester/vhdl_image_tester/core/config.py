# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/core/config.py - Repository paths and constants
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""Central configuration: paths derived from the repository root, build constants."""

from __future__ import annotations

import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Repository root detection
# ---------------------------------------------------------------------------

def _find_repo_root() -> Path:
    """Walk up from this file until we find the Videomancer repository root.

    Looks for a directory that contains both ``programs/`` and
    ``videomancer-sdk/``.  When the SDK is checked out as a submodule inside a
    Videomancer firmware repository this will resolve to the firmware root,
    which is the expected runtime context.  The tool cannot function when run
    from a standalone SDK clone — a ``programs/`` directory is required.
    """
    candidate = Path(__file__).resolve()
    for _ in range(10):
        candidate = candidate.parent
        if (candidate / "programs").is_dir() and (candidate / "videomancer-sdk").is_dir():
            return candidate
    raise RuntimeError(
        "Cannot locate Videomancer repository root. "
        "The VHDL Image Tester must be run from within a Videomancer firmware "
        "repository that contains both a 'programs/' directory and the "
        "'videomancer-sdk/' submodule. "
        "Standalone SDK checkouts are not supported by this tool."
    )


REPO_ROOT: Path = _find_repo_root()

# ---------------------------------------------------------------------------
# SDK paths
# ---------------------------------------------------------------------------

SDK_ROOT: Path = REPO_ROOT / "videomancer-sdk"
SDK_FPGA: Path = SDK_ROOT / "fpga"

SDK_VHDL_SOURCES: dict[str, list[Path]] = {
    "video_stream":  sorted((SDK_FPGA / "common/rtl/video_stream").glob("*.vhd")),
    "video_timing":  sorted((SDK_FPGA / "common/rtl/video_timing").glob("*.vhd")),
    "video_sync":    sorted((SDK_FPGA / "common/rtl/video_sync").glob("*.vhd")),
    "dsp":           sorted((SDK_FPGA / "common/rtl/dsp").glob("*.vhd")),
    "utils":         sorted((SDK_FPGA / "common/rtl/utils").glob("*.vhd")),
    "serial":        sorted((SDK_FPGA / "common/rtl/serial").glob("*.vhd")),
}

# Core config packages: keyed by (config_name) → Path
SDK_CORE_CONFIG_DIR: Path = SDK_FPGA / "common/rtl/core_config"

# YUV444 core files (entity declaration + package)
SDK_CORE_YUV444_DIR: Path = SDK_FPGA / "core/yuv444_30b/rtl"

# ---------------------------------------------------------------------------
# Program paths
# ---------------------------------------------------------------------------

# ``LZX_VIT_PROGRAMS_DIR`` overrides the auto-detected programs directory.
# Set this environment variable (or use the wrapper scripts in ``tools/``) to
# point the tool at a custom programs directory without changing the working
# directory.  Both GUI and CLI modes respect this setting.
PROGRAMS_ROOT: Path = Path(
    os.environ["LZX_VIT_PROGRAMS_DIR"]
    if "LZX_VIT_PROGRAMS_DIR" in os.environ
    else REPO_ROOT / "programs"
)

# ---------------------------------------------------------------------------
# Test image paths
# ---------------------------------------------------------------------------

TEST_IMAGES_ROOT: Path = REPO_ROOT / "docs/test_images"

# ---------------------------------------------------------------------------
# Simulation build directory (under system tmp)
# ---------------------------------------------------------------------------

BUILD_DIR: Path = Path(os.environ.get("LZX_VIT_BUILD_DIR", "/tmp/lzx_vit"))

# ---------------------------------------------------------------------------
# ABI register layout (Videomancer ABI v1.0)
# ---------------------------------------------------------------------------

ABI_REG_ROT_POT_1    = 0   # rotary_potentiometer_1  (0-1023)
ABI_REG_ROT_POT_2    = 1   # rotary_potentiometer_2
ABI_REG_ROT_POT_3    = 2   # rotary_potentiometer_3
ABI_REG_ROT_POT_4    = 3   # rotary_potentiometer_4
ABI_REG_ROT_POT_5    = 4   # rotary_potentiometer_5
ABI_REG_ROT_POT_6    = 5   # rotary_potentiometer_6
ABI_REG_TOGGLES      = 6   # toggle_switch_7..11 packed as bits 0..4
ABI_REG_LINEAR_POT   = 7   # linear_potentiometer_12 (0-1023)
ABI_REG_VIDEO_TIMING = 8   # video_timing_id (4-bit)
ABI_SPI_RAM_SIZE     = 32  # C_SPI_RAM_ARRAY_SIZE from core_pkg.vhd

ABI_TOGGLE_BIT: dict[str, int] = {
    "toggle_switch_7":  0,
    "toggle_switch_8":  1,
    "toggle_switch_9":  2,
    "toggle_switch_10": 3,
    "toggle_switch_11": 4,
}

PARAM_ID_TO_REGISTER: dict[str, int] = {
    "rotary_potentiometer_1":  ABI_REG_ROT_POT_1,
    "rotary_potentiometer_2":  ABI_REG_ROT_POT_2,
    "rotary_potentiometer_3":  ABI_REG_ROT_POT_3,
    "rotary_potentiometer_4":  ABI_REG_ROT_POT_4,
    "rotary_potentiometer_5":  ABI_REG_ROT_POT_5,
    "rotary_potentiometer_6":  ABI_REG_ROT_POT_6,
    "toggle_switch_7":         ABI_REG_TOGGLES,
    "toggle_switch_8":         ABI_REG_TOGGLES,
    "toggle_switch_9":         ABI_REG_TOGGLES,
    "toggle_switch_10":        ABI_REG_TOGGLES,
    "toggle_switch_11":        ABI_REG_TOGGLES,
    "linear_potentiometer_12": ABI_REG_LINEAR_POT,
}

# ---------------------------------------------------------------------------
# Simulation constants
# ---------------------------------------------------------------------------

SIM_WARMUP_FRAMES        = 2      # frames driven before capture (pipeline warmup)
SIM_CAPTURE_FRAMES       = 1      # frames during which output is captured
SIM_CLK_PERIOD_NS        = 10     # 100 MHz simulation clock
SIM_MAX_IMAGE_DIM        = 480    # max width/height for simulation (pixels)
SIM_DEFAULT_CONFIG       = "sd_analog"
SIM_DRAIN_LINES          = 32     # extra blanking lines after capture to drain pipeline

# ---------------------------------------------------------------------------
# Supported FPGA configs for simulation
# ---------------------------------------------------------------------------

FPGA_CONFIGS = ["sd_analog", "sd_hdmi", "sd_dual", "hd_analog", "hd_hdmi", "hd_dual"]
FPGA_CORES   = ["yuv444_30b"]  # yuv422_20b not tested in sim yet
