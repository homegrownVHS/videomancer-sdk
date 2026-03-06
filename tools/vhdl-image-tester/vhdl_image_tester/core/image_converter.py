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

from .config import SIM_DEFAULT_DECIMATION, SIM_DEFAULT_VIDEO_MODE

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


def prepare_image(source: Image.Image, width: int, height: int) -> Image.Image:
    """
    Resize source image to exact *width* × *height* target dimensions.

    The target dimensions are determined by the video mode and decimation
    factor (see :func:`~config.resolve_video_settings`).  The image is
    resampled using Lanczos filtering and converted to RGB.
    """
    return source.convert("RGB").resize((width, height), Image.LANCZOS)


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
    is_interlaced:   bool = False,
) -> list[tuple[int, int, int, int, int, int, int, int]]:
    """
    Generate a flat list of (Y, U, V, avid, hsync_n, vsync_n, field_n, cap)
    tuples — one per clock cycle — covering *warmup_frames* + *capture_frames*
    complete video frames, plus *drain_lines* extra blanking lines to let
    delayed capture complete.

    **Interlaced mode** (``is_interlaced=True``):
      Each frame is split into two sequential fields.  The top field
      (``field_n=1``) carries even-numbered rows (0, 2, 4, …) and the
      bottom field (``field_n=0``) carries odd-numbered rows (1, 3, 5, …).
      One "frame" of stimulus therefore consists of two field sub-frames,
      each with its own vsync pulse.

    Format matches the VHDL testbench stimulus.txt reader:
      Y      : 0-1023
      U      : 0-1023
      V      : 0-1023
      avid   : 1 during active video, 0 in blanking
      hsync_n: 0 during hsync pulse (active low), 1 otherwise
      vsync_n: 0 during vsync pulse (active low), 1 otherwise
      field_n: 1 for top field / progressive, 0 for bottom field
      cap    : 1 if this cycle's output should be written to the output file
    """
    h, w, _ = yuv10.shape
    total_frames = warmup_frames + capture_frames

    if is_interlaced:
        return _build_stimulus_interlaced(
            yuv10, w, h, total_frames, warmup_frames,
            h_blank_clocks, v_blank_lines, drain_lines,
        )
    else:
        return _build_stimulus_progressive(
            yuv10, w, h, total_frames, warmup_frames,
            h_blank_clocks, v_blank_lines, drain_lines,
        )


def _build_stimulus_progressive(
    yuv10:           np.ndarray,
    w:               int,
    h:               int,
    total_frames:    int,
    warmup_frames:   int,
    h_blank_clocks:  int,
    v_blank_lines:   int,
    drain_lines:     int,
) -> list[tuple[int, int, int, int, int, int, int, int]]:
    """Build progressive (non-interlaced) stimulus — one field per frame."""
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


def _build_stimulus_interlaced(
    yuv10:           np.ndarray,
    w:               int,
    h:               int,
    total_frames:    int,
    warmup_frames:   int,
    h_blank_clocks:  int,
    v_blank_lines:   int,
    drain_lines:     int,
) -> list[tuple[int, int, int, int, int, int, int, int]]:
    """Build interlaced stimulus — two fields per frame.

    For each frame, the top field (``field_n=1``) sends even-numbered source
    rows (0, 2, 4, …) and the bottom field (``field_n=0``) sends odd-numbered
    rows (1, 3, 5, …).  Each field has its own vsync/hsync blanking region.
    """
    field_height = h // 2
    # Pre-split into fields: top = even rows, bottom = odd rows
    top_field_data = yuv10[0::2, :, :]
    bottom_field_data = yuv10[1::2, :, :]

    stimulus: list[tuple[int, int, int, int, int, int, int, int]] = []

    for frame_idx in range(total_frames):
        is_capture_frame = frame_idx >= warmup_frames

        for field_idx in range(2):  # 0 = top field, 1 = bottom field
            field_n_val = 1 if field_idx == 0 else 0
            field_data = top_field_data if field_idx == 0 else bottom_field_data

            for line in range(field_height + v_blank_lines):
                vsync_n = 0 if line < 3 else 1
                is_active_line = (v_blank_lines // 2) <= line < (v_blank_lines // 2 + field_height)
                row = line - (v_blank_lines // 2) if is_active_line else 0

                for col in range(w + h_blank_clocks):
                    hsync_n = 0 if col < 8 else 1
                    is_active_col = (h_blank_clocks // 2) <= col < (h_blank_clocks // 2 + w)
                    avid = 1 if (is_active_line and is_active_col) else 0

                    if avid:
                        pixel_col = col - (h_blank_clocks // 2)
                        y = int(field_data[row, pixel_col, 0])
                        u = int(field_data[row, pixel_col, 1])
                        v = int(field_data[row, pixel_col, 2])
                    else:
                        y, u, v = 64, 512, 512

                    cap = 1 if (is_capture_frame and avid) else 0
                    stimulus.append((y, u, v, avid, hsync_n, vsync_n, field_n_val, cap))

    # ── Drain period ─────────────────────────────────────────────────────
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


def read_output_file(
    path: Path,
    width: int,
    height: int,
    is_interlaced: bool = False,
) -> Image.Image:
    """
    Parse the GHDL simulation output file (one captured pixel per line: "Y U V").
    Returns a PIL RGB image of *width* × *height*. If the simulation produced
    more pixels than width×height, the last frame is used. If fewer, the image
    is zero-filled.

    For interlaced modes, the output contains two sequential fields (top then
    bottom, each ``height/2`` lines).  The fields are weaved back into a full
    progressive frame: even rows from the top field, odd rows from the bottom
    field.
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

    if is_interlaced:
        field_height = height // 2
        pixels_per_field = width * field_height

        top_pixels = pixels[:pixels_per_field]
        bottom_pixels = pixels[pixels_per_field:pixels_per_field + pixels_per_field]

        top_field = np.array(top_pixels, dtype=np.uint16).reshape(field_height, width, 3)
        bottom_field = np.array(bottom_pixels, dtype=np.uint16).reshape(field_height, width, 3)

        # Weave: even rows = top field, odd rows = bottom field
        full_frame = np.empty((height, width, 3), dtype=np.uint16)
        full_frame[0::2, :, :] = top_field
        full_frame[1::2, :, :] = bottom_field

        return yuv10_to_rgb(full_frame)
    else:
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
