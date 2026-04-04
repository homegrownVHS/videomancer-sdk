# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/core/config.py - Repository paths and constants
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""Central configuration: paths derived from the repository root, build constants."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

# ---------------------------------------------------------------------------
# Repository root detection
# ---------------------------------------------------------------------------

def _find_repo_root() -> tuple[Path, bool]:
    """Walk up from this file to find the repository root.

    Two layouts are supported:

    1. **Firmware repository** — the SDK is a submodule.  The root contains
       both ``programs/`` and ``videomancer-sdk/``.
    2. **Standalone SDK** — the tool is run directly from the SDK checkout.
       The root contains ``fpga/`` and ``tools/vhdl-image-tester/`` but
       *not* ``videomancer-sdk/``.

    Returns:
        A ``(root, is_sdk_standalone)`` tuple.
    """
    candidate = Path(__file__).resolve()
    for _ in range(10):
        candidate = candidate.parent
        # Firmware repo: has both programs/ and videomancer-sdk/
        if (candidate / "programs").is_dir() and (candidate / "videomancer-sdk").is_dir():
            return candidate, False
        # Standalone SDK: has fpga/ and tools/vhdl-image-tester/ but no
        # videomancer-sdk/ subdirectory (because *it is* the SDK).
        if (
            (candidate / "fpga").is_dir()
            and (candidate / "tools" / "vhdl-image-tester").is_dir()
            and not (candidate / "videomancer-sdk").is_dir()
        ):
            return candidate, True
    raise RuntimeError(
        "Cannot locate repository root. "
        "The VHDL Image Tester must be run either from within a Videomancer "
        "firmware repository (containing 'programs/' and 'videomancer-sdk/') "
        "or directly from a standalone Videomancer SDK checkout "
        "(containing 'fpga/' and 'tools/vhdl-image-tester/')."
    )


REPO_ROOT: Path
SDK_STANDALONE: bool
REPO_ROOT, SDK_STANDALONE = _find_repo_root()

# ---------------------------------------------------------------------------
# SDK paths
# ---------------------------------------------------------------------------

SDK_ROOT: Path = REPO_ROOT if SDK_STANDALONE else REPO_ROOT / "videomancer-sdk"
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
#
# In firmware-repo mode the default is ``<repo>/programs``.
# In standalone-SDK mode the default is ``<sdk>/programs`` (example programs).
PROGRAMS_ROOT: Path = Path(
    os.environ["LZX_VIT_PROGRAMS_DIR"]
    if "LZX_VIT_PROGRAMS_DIR" in os.environ
    else REPO_ROOT / "programs"
)

# ---------------------------------------------------------------------------
# Test image paths
# ---------------------------------------------------------------------------

# ``LZX_VIT_TEST_IMAGES_DIR`` overrides the auto-detected test images
# directory.  In firmware-repo mode the default is ``<repo>/docs/test_images``.
# In standalone-SDK mode no test images ship by default so the path may not
# exist — consumers handle this gracefully.
TEST_IMAGES_ROOT: Path = Path(
    os.environ.get(
        "LZX_VIT_TEST_IMAGES_DIR",
        str(REPO_ROOT / "docs/test_images"),
    )
)

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
SIM_DRAIN_LINES          = 32     # extra blanking lines after capture to drain pipeline

# ---------------------------------------------------------------------------
# Video mode definitions (all 15 ABI video standards)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class VideoMode:
    """Video standard definition for simulation."""
    key: str               # lookup key (e.g. "1080p2997")
    display_name: str      # human-readable (e.g. "1080p 29.97 Hz")
    timing_id: int         # ABI register 8 value (0–14)
    width: int             # native active width
    height: int            # native active height
    is_interlaced: bool
    is_sd: bool            # True for SD modes (uses sd_* fpga config)


VIDEO_MODES: dict[str, VideoMode] = {
    "ntsc":      VideoMode("ntsc",      "NTSC 480i 59.94",   0,  720,  486, True,  True),
    "1080i50":   VideoMode("1080i50",   "1080i 50 Hz",       1, 1920, 1080, True,  False),
    "1080i5994": VideoMode("1080i5994", "1080i 59.94 Hz",    2, 1920, 1080, True,  False),
    "1080p24":   VideoMode("1080p24",   "1080p 24 Hz",       3, 1920, 1080, False, False),
    "480p":      VideoMode("480p",      "480p 59.94 Hz",     4,  720,  480, False, True),
    "720p50":    VideoMode("720p50",    "720p 50 Hz",        5, 1280,  720, False, False),
    "720p5994":  VideoMode("720p5994",  "720p 59.94 Hz",     6, 1280,  720, False, False),
    "1080p30":   VideoMode("1080p30",   "1080p 30 Hz",       7, 1920, 1080, False, False),
    "pal":       VideoMode("pal",       "PAL 576i 50",       8,  720,  576, True,  True),
    "1080p2398": VideoMode("1080p2398", "1080p 23.98 Hz",    9, 1920, 1080, False, False),
    "1080i60":   VideoMode("1080i60",   "1080i 60 Hz",      10, 1920, 1080, True,  False),
    "1080p25":   VideoMode("1080p25",   "1080p 25 Hz",      11, 1920, 1080, False, False),
    "576p":      VideoMode("576p",      "576p 50 Hz",       12,  720,  576, False, True),
    "1080p2997": VideoMode("1080p2997", "1080p 29.97 Hz",   13, 1920, 1080, False, False),
    "720p60":    VideoMode("720p60",    "720p 60 Hz",       14, 1280,  720, False, False),
}

VIDEO_MODE_KEYS: list[str] = list(VIDEO_MODES.keys())

# ---------------------------------------------------------------------------
# Decimation factors
# ---------------------------------------------------------------------------

DECIMATION_VALUES: list[int] = [1, 2, 4, 8, 16, 32, 64]

SIM_DEFAULT_VIDEO_MODE: str = "1080p2997"
SIM_DEFAULT_DECIMATION: int = 4

# ---------------------------------------------------------------------------
# Resolved simulation settings
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class SimVideoSettings:
    """Resolved simulation dimensions and configuration from video mode + decimation."""
    sim_width: int          # simulation image width in pixels
    sim_height: int         # simulation image height (full frame)
    fpga_config: str        # "sd_hdmi" or "hd_hdmi"
    timing_id: int          # ABI register 8 value (0–14)
    is_interlaced: bool
    field_height: int       # sim_height // 2 for interlaced, sim_height for progressive
    native_width: int       # native video standard width
    native_height: int      # native video standard height


def resolve_video_settings(video_mode: str, decimation: int) -> SimVideoSettings:
    """Compute simulation parameters from video mode + decimation.

    The FPGA config prefers HDMI input variants: ``sd_hdmi`` for SD modes,
    ``hd_hdmi`` for HD modes.  The image resolution is the native video
    resolution divided by the decimation factor, rounded to even dimensions.

    Raises:
        ValueError: If ``video_mode`` or ``decimation`` is not recognised.
    """
    if video_mode not in VIDEO_MODES:
        raise ValueError(
            f"Unknown video mode: {video_mode!r}. "
            f"Available: {list(VIDEO_MODES.keys())}"
        )
    if decimation not in DECIMATION_VALUES:
        raise ValueError(
            f"Invalid decimation: {decimation}. "
            f"Must be one of {DECIMATION_VALUES}"
        )

    mode = VIDEO_MODES[video_mode]
    w = max(2, mode.width // decimation)
    h = max(2, mode.height // decimation)
    # Ensure even dimensions (required for YUV subsampling)
    w = w if w % 2 == 0 else w - 1
    h = h if h % 2 == 0 else h - 1

    fpga_config = "sd_hdmi" if mode.is_sd else "hd_hdmi"
    field_height = h // 2 if mode.is_interlaced else h

    return SimVideoSettings(
        sim_width=w,
        sim_height=h,
        fpga_config=fpga_config,
        timing_id=mode.timing_id,
        is_interlaced=mode.is_interlaced,
        field_height=field_height,
        native_width=mode.width,
        native_height=mode.height,
    )


# ---------------------------------------------------------------------------
# Supported FPGA configs for simulation (kept for sim_runner source ordering)
# ---------------------------------------------------------------------------

FPGA_CONFIGS = ["sd_analog", "sd_hdmi", "sd_dual", "hd_analog", "hd_hdmi", "hd_dual"]
FPGA_CORES   = ["yuv444_30b"]  # yuv422_20b not tested in sim yet
