# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/core/image_converter.py - RGB↔YUV 10-bit stream conversion
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
Convert between PIL RGB images and the YUV pixel streams used by Videomancer FPGA programs.

Colorspace: BT.601 limited range (studio swing), 10-bit precision.
  Y:    64 – 940  (16–235 × 4)
  U/V: 64 – 960  (16–240 × 4, midpoint = 512)
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from .config import SIM_MAX_IMAGE_DIM

# ---------------------------------------------------------------------------
# Colorspace constants (BT.601, studio / limited range, 10-bit)
# ---------------------------------------------------------------------------

_Y_MIN,  _Y_MAX  = 64,  940
_UV_MID, _UV_MAX = 512, 960
_UV_MIN           = 64

# BT.601 forward matrix (normalised R,G,B ∈ [0,1] → normalised Y,Cb,Cr ∈ [0,1])
_M_RGB_TO_YUV = np.array([
    [ 0.299,      0.587,      0.114    ],   # Y
    [-0.168736,  -0.331264,   0.500000 ],   # Cb (U)
    [ 0.500000,  -0.418688,  -0.081312 ],   # Cr (V)
], dtype=np.float64)

# Inverse matrix for YUV→RGB
_M_YUV_TO_RGB = np.linalg.inv(_M_RGB_TO_YUV)


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

def rgb_to_yuv10(image: Image.Image) -> np.ndarray:
    """
    Convert an RGB PIL Image to a (H, W, 3) uint16 array of 10-bit YUV values.

    Returns array where [..., 0]=Y, [..., 1]=U(Cb), [..., 2]=V(Cr).
    Values are BT.601 limited-range, 10-bit (0–1023).
    """
    rgb_f = np.asarray(image.convert("RGB"), dtype=np.float64) / 255.0  # [0, 1]
    h, w, _ = rgb_f.shape
    flat = rgb_f.reshape(-1, 3) @ _M_RGB_TO_YUV.T                       # → (N, 3) normalised YUV

    # Y: [0,1] → [64, 940]
    y10 = np.clip(flat[:, 0] * (_Y_MAX - _Y_MIN) + _Y_MIN, _Y_MIN, _Y_MAX)
    # U/V: [-0.5, 0.5] → [64, 960] with midpoint at 512
    u10 = np.clip(flat[:, 1] * (_UV_MAX - _UV_MIN) + _UV_MID, _UV_MIN, _UV_MAX)
    v10 = np.clip(flat[:, 2] * (_UV_MAX - _UV_MIN) + _UV_MID, _UV_MIN, _UV_MAX)

    yuv = np.stack([y10, u10, v10], axis=1).round().astype(np.uint16)
    return yuv.reshape(h, w, 3)


def yuv10_to_rgb(yuv10: np.ndarray) -> Image.Image:
    """
    Convert a (H, W, 3) or (N, 3) uint16 array of 10-bit YUV back to an RGB PIL Image.
    """
    flat  = yuv10.astype(np.float64).reshape(-1, 3)
    y_n   = (flat[:, 0] - _Y_MIN)  / (_Y_MAX  - _Y_MIN)
    u_n   = (flat[:, 1] - _UV_MID) / (_UV_MAX - _UV_MIN)
    v_n   = (flat[:, 2] - _UV_MID) / (_UV_MAX - _UV_MIN)

    yuv_n = np.stack([y_n, u_n, v_n], axis=1)
    rgb_f = yuv_n @ _M_YUV_TO_RGB.T
    rgb8  = np.clip(rgb_f * 255.0, 0, 255).round().astype(np.uint8)

    h, w = yuv10.shape[:2] if yuv10.ndim == 3 else (1, yuv10.shape[0])
    return Image.fromarray(rgb8.reshape(h, w, 3), mode="RGB")


def prepare_image(source: Image.Image, max_dim: int = SIM_MAX_IMAGE_DIM) -> Image.Image:
    """
    Resize / crop source image so neither dimension exceeds *max_dim*, preserving
    aspect ratio, and ensure dimensions are even (required for YUV subsampling).
    """
    w, h = source.size
    if w > max_dim or h > max_dim:
        scale = max_dim / max(w, h)
        w, h = max(2, int(w * scale)), max(2, int(h * scale))
    # Ensure even dimensions
    w = w if w % 2 == 0 else w - 1
    h = h if h % 2 == 0 else h - 1
    return source.convert("RGB").resize((w, h), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Stimulus file generator
# ---------------------------------------------------------------------------

def build_stimulus(
    yuv10:           np.ndarray,
    warmup_frames:   int = 2,
    capture_frames:  int = 1,
    h_blank_clocks:  int = 64,
    v_blank_lines:   int = 8,
    drain_lines:     int = 0,
) -> list[tuple[int, int, int, int, int, int, int, int]]:
    """
    Generate a flat list of (Y, U, V, avid, hsync_n, vsync_n, field_n, cap)
    tuples — one per clock cycle — covering *warmup_frames* + *capture_frames*
    complete video frames, plus *drain_lines* extra blanking lines to let
    delayed capture complete.

    Format matches the VHDL testbench stimulus.txt reader:
      Y      : 0-1023
      U      : 0-1023
      V      : 0-1023
      avid   : 1 during active video, 0 in blanking
      hsync_n: 0 during hsync pulse (active low), 1 otherwise
      vsync_n: 0 during vsync pulse (active low), 1 otherwise
      field_n: always 1 (progressive)
      cap    : 1 if this cycle's output should be written to the output file
    """
    h, w, _ = yuv10.shape
    total_frames = warmup_frames + capture_frames
    stimulus: list[tuple[int, int, int, int, int, int, int, int]] = []

    for frame_idx in range(total_frames):
        is_capture_frame = frame_idx >= warmup_frames
        # --- vsync: asserted for first 3 lines (active low) ---
        for line in range(h + v_blank_lines):
            vsync_n = 0 if line < 3 else 1
            is_active_line = (v_blank_lines // 2) <= line < (v_blank_lines // 2 + h)
            row = line - (v_blank_lines // 2) if is_active_line else 0

            # --- hsync: asserted for first 8 clocks (active low) ---
            for col in range(w + h_blank_clocks):
                hsync_n = 0 if col < 8 else 1
                is_active_col = (h_blank_clocks // 2) <= col < (h_blank_clocks // 2 + w)
                avid = 1 if (is_active_line and is_active_col) else 0

                if avid:
                    pixel_col = col - (h_blank_clocks // 2)
                    y, u, v = int(yuv10[row, pixel_col, 0]), int(yuv10[row, pixel_col, 1]), int(yuv10[row, pixel_col, 2])
                else:
                    # Blanking: Y=black (64), UV=neutral (512)
                    y, u, v = 64, 512, 512

                cap = 1 if (is_capture_frame and avid) else 0
                stimulus.append((y, u, v, avid, hsync_n, vsync_n, 1, cap))

    # ── Drain period: extra blanking so delayed capture can finish ────────
    if drain_lines > 0:
        for drain_line in range(drain_lines):
            for col in range(w + h_blank_clocks):
                hsync_n = 0 if col < 8 else 1
                stimulus.append((64, 512, 512, 0, hsync_n, 1, 1, 0))

    return stimulus


def write_stimulus_file(stimulus: list[tuple], path: Path) -> None:
    """Write stimulus list to a space-separated text file (one clock cycle per line)."""
    lines = [f"{y} {u} {v} {avid} {hsync_n} {vsync_n} {field_n} {cap}\n"
             for y, u, v, avid, hsync_n, vsync_n, field_n, cap in stimulus]
    path.write_text("".join(lines), encoding="ascii")


def read_output_file(path: Path, width: int, height: int) -> Image.Image:
    """
    Parse the GHDL simulation output file (one captured pixel per line: "Y U V").
    Returns a PIL RGB image of *width* × *height*. If the simulation produced
    more pixels than width×height, the last frame is used. If fewer, the image
    is zero-filled.
    """
    pixels: list[tuple[int, int, int]] = []
    text = path.read_text(encoding="ascii")
    for raw_line in text.splitlines():
        parts = raw_line.split()
        if len(parts) >= 3:
            try:
                pixels.append((int(parts[0]), int(parts[1]), int(parts[2])))
            except ValueError:
                continue

    expected = width * height
    if len(pixels) >= expected:
        # Take the last complete frame
        pixels = pixels[len(pixels) - expected:]
    else:
        # Pad with black YUV
        pixels = [(64, 512, 512)] * (expected - len(pixels)) + pixels

    yuv10 = np.array(pixels, dtype=np.uint16).reshape(height, width, 3)
    return yuv10_to_rgb(yuv10)


def collect_test_images(root: Path | None = None) -> list[Path]:
    """Return all image files found under the test_images directory tree."""
    from .config import TEST_IMAGES_ROOT
    search_root = root or TEST_IMAGES_ROOT
    if not search_root.exists():
        return []
    exts = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp"}
    return sorted(
        p for p in search_root.rglob("*")
        if p.is_file() and p.suffix.lower() in exts
    )
