# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/core/pipeline.py - Full simulation pipeline orchestrator
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
SimulationPipeline: a QThread worker that runs the complete VHDL image
processing pipeline end-to-end:

  1. Prepare source image (resize to simulation dimensions)
  2. Convert RGB → YUV-10bit & write stimulus.txt
  3. Generate tb_vit.vhd testbench with register values
  4. Run GHDL (analyse → elaborate → simulate)
  5. Read output.txt → convert YUV-10bit → RGB image
  6. Emit result images back to the GUI thread via Qt signals
"""

from __future__ import annotations

import time
import traceback
from pathlib import Path

from PIL import Image
from PyQt6.QtCore import QThread, pyqtSignal

from .config import (
    BUILD_DIR,
    SIM_WARMUP_FRAMES,
    SIM_CAPTURE_FRAMES,
    SIM_MAX_IMAGE_DIM,
    SIM_CLK_PERIOD_NS,
    SIM_DEFAULT_CONFIG,
    SIM_DRAIN_LINES,
)
from .image_converter import (
    prepare_image,
    rgb_to_yuv10,
    build_stimulus,
    write_stimulus_file,
    read_output_file,
)
from .program_loader import Program
from .testbench_gen import generate_testbench
from .sim_runner import run_simulation


# ---------------------------------------------------------------------------
# Pipeline result type
# ---------------------------------------------------------------------------

class PipelineResult:
    """Holds the outcome of a completed simulation pipeline run."""

    def __init__(
        self,
        success:      bool,
        input_image:  Image.Image | None = None,
        output_image: Image.Image | None = None,
        elapsed_s:    float = 0.0,
        error:        str   = "",
        run_dir:      Path | None = None,
    ) -> None:
        self.success      = success
        self.input_image  = input_image
        self.output_image = output_image
        self.elapsed_s    = elapsed_s
        self.error        = error
        self.run_dir      = run_dir


# ---------------------------------------------------------------------------
# QThread worker
# ---------------------------------------------------------------------------

class SimulationWorker(QThread):
    """
    Background thread that executes the full pipeline without blocking the GUI.

    Signals
    -------
    log_line(str)   : Emitted for each line of GHDL output or pipeline status.
    finished(PipelineResult) : Emitted when the pipeline completes (success or failure).
    """

    log_line: pyqtSignal = pyqtSignal(str)
    finished: pyqtSignal = pyqtSignal(object)  # PipelineResult

    def __init__(
        self,
        program:          Program,
        source_image:     Image.Image,
        register_values:  dict[str, int],
        fpga_config:      str             = SIM_DEFAULT_CONFIG,
        max_image_dim:    int             = SIM_MAX_IMAGE_DIM,
        warmup_frames:    int             = SIM_WARMUP_FRAMES,
        capture_frames:   int             = SIM_CAPTURE_FRAMES,
    ) -> None:
        super().__init__()
        self._program         = program
        self._source_image    = source_image
        self._register_values = register_values
        self._fpga_config     = fpga_config
        self._max_image_dim   = max_image_dim
        self._warmup_frames   = warmup_frames
        self._capture_frames  = capture_frames

    # -- QThread entry point -------------------------------------------------

    def run(self) -> None:
        t0 = time.perf_counter()
        result = self._execute()
        result.elapsed_s = time.perf_counter() - t0
        self.finished.emit(result)

    # -- Internal pipeline ---------------------------------------------------

    def _execute(self) -> PipelineResult:
        program = self._program
        try:
            # ── Build directory for this run ─────────────────────────────────
            run_dir = BUILD_DIR / program.name
            run_dir.mkdir(parents=True, exist_ok=True)

            stim_path = run_dir / "stimulus.txt"
            out_path  = run_dir / "output.txt"
            tb_path   = run_dir / "tb_vit.vhd"

            # ── 1. Prepare image ─────────────────────────────────────────────
            self._emit(f"[1/5] Preparing image (max dim {self._max_image_dim}px)...")
            input_img = prepare_image(self._source_image, self._max_image_dim)
            w, h = input_img.size
            self._emit(f"      → {w}×{h} px")

            # ── 2. Convert to YUV & write stimulus ───────────────────────────
            self._emit(f"[2/5] Building stimulus ({self._warmup_frames + self._capture_frames} frames + {SIM_DRAIN_LINES} drain lines)...")
            yuv10    = rgb_to_yuv10(input_img)
            stimulus = build_stimulus(
                yuv10,
                warmup_frames  = self._warmup_frames,
                capture_frames = self._capture_frames,
                drain_lines    = SIM_DRAIN_LINES,
            )
            write_stimulus_file(stimulus, stim_path)
            self._emit(f"      → {len(stimulus):,} clock cycles → {stim_path.name}")

            # ── 3. Compute register array & generate testbench ────────────────
            self._emit("[3/5] Generating VHDL testbench...")
            reg_array = program.build_register_array(self._register_values)
            generate_testbench(
                output_path      = tb_path,
                stimulus_path    = stim_path,
                output_img_path  = out_path,
                register_values  = reg_array,
                img_width        = w,
                img_height       = h,
                clk_period_ns    = SIM_CLK_PERIOD_NS,
                warmup_frames    = self._warmup_frames,
            )
            self._emit(f"      → {tb_path.name} (output-sync capture, {w}×{h})")
            self._log_registers(reg_array)

            # ── 4. Run GHDL ──────────────────────────────────────────────────
            self._emit("[4/5] Running GHDL simulation...")
            run_simulation(
                program_dir    = program.program_dir,
                testbench_path = tb_path,
                build_dir      = run_dir,
                config         = self._fpga_config,
                core           = program.core,
                log_callback   = self._emit,
            )

            # ── 5. Read output ───────────────────────────────────────────────
            self._emit("[5/5] Reading simulation output...")
            if not out_path.exists() or out_path.stat().st_size == 0:
                raise RuntimeError(
                    f"Output file is empty or missing: {out_path}\n"
                    "The simulation may have produced no active-video output."
                )
            output_img = read_output_file(out_path, w, h)
            self._emit(f"      → captured {out_path.stat().st_size // 8} pixels")

            return PipelineResult(
                success      = True,
                input_image  = input_img,
                output_image = output_img,
                run_dir      = run_dir,
            )

        except Exception:  # noqa: BLE001
            tb = traceback.format_exc()
            self._emit(f"\n[ERROR]\n{tb}")
            return PipelineResult(success=False, error=tb)

    def _emit(self, msg: str) -> None:
        self.log_line.emit(msg)

    def _log_registers(self, regs: list[int]) -> None:
        parts = [f"reg[{i}]={v}" for i, v in enumerate(regs[:12])]
        self._emit("      Registers: " + "  ".join(parts))
