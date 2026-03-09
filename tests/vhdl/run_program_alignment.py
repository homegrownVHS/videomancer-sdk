#!/usr/bin/env python3
# Videomancer SDK - Open source FPGA-based video effects development kit
# Copyright (C) 2025 LZX Industries LLC
# File: videomancer-sdk/tests/vhdl/run_program_alignment.py - SDK alignment runner
# License: GNU General Public License v3.0
# https://github.com/lzxindustries/videomancer-sdk
"""
Run the tb_program_top_alignment VHDL testbench against an arbitrary
program_top DUT to validate:

  1. Pixel count correctness (active pixels captured = g_n_cols * g_n_rows)
  2. Pipeline delay alignment (no BT.601-blanking pixels at line edges)
  3. Inter-channel leading-flat skew (Y / U / V pipeline depth agreement)

This script is the single entry point for the alignment stage of the program
pipeline.  The vmprog alignment stage calls it instead of the vhdl-image-tester.

Usage
-----
    python3 run_program_alignment.py \\
        --program-dir  /path/to/programs/<name> \\
        --build-dir    /tmp/lzx_alignment/<name> \\
        --output-file  /tmp/lzx_alignment/<name>/alignment_output.txt \\
        [--n-cols 90] [--n-rows 60] [--h-blank 64] [--v-blank 20] \\
        [--warmup-frames 2] [--verbose]

Exit codes
----------
  0  — All checks passed (ALIGNMENT PASS).
  1  — One or more checks failed (ALIGNMENT FAIL).
  2  — GHDL not found or analysis/elaboration error.

The output pixel file (Y U V per active pixel, one pixel per line) is always
written before the exit code is set, so the Python alignment stage can read it
for detailed analysis and C_PROCESSING_DELAY_CLKS auto-correction even when
the testbench reports a delay mismatch.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# ==============================================================================
#  Repository and SDK path resolution
# ==============================================================================

# This script lives at  videomancer-sdk/tests/vhdl/run_program_alignment.py
_SELF_DIR    = Path(__file__).resolve().parent   # videomancer-sdk/tests/vhdl/
_SDK_ROOT    = _SELF_DIR.parent.parent           # videomancer-sdk/
_SDK_FPGA    = _SDK_ROOT / "fpga"

# Testbench resides in the same directory as this script
_TB_ALIGN    = _SELF_DIR / "tb_program_top_alignment.vhd"

# SDK RTL directories
_DIR_VS      = _SDK_FPGA / "common" / "rtl" / "video_stream"
_DIR_VT      = _SDK_FPGA / "common" / "rtl" / "video_timing"
_DIR_VSYNC   = _SDK_FPGA / "common" / "rtl" / "video_sync"
_DIR_DSP     = _SDK_FPGA / "common" / "rtl" / "dsp"
_DIR_UTILS   = _SDK_FPGA / "common" / "rtl" / "utils"
_DIR_SERIAL  = _SDK_FPGA / "common" / "rtl" / "serial"
_DIR_CCFG    = _SDK_FPGA / "common" / "rtl" / "core_config"
_DIR_CORE    = _SDK_FPGA / "core" / "yuv444_30b" / "rtl"

# GHDL standard flag
_GHDL_STD = "--std=08"

# Top entity name (must match VHDL entity declaration)
_TOP_ENTITY = "tb_program_top_alignment"

# ==============================================================================
#  GHDL detection
# ==============================================================================

def _probe_ghdl(path: str) -> str | None:
    """Return path if it is a working GHDL binary, else None."""
    try:
        r = subprocess.run([path, "--version"], capture_output=True,
                           text=True, timeout=5)
        if r.returncode == 0:
            return path
    except Exception:  # noqa: BLE001
        pass
    return None


def _find_ghdl() -> str:
    """Return the absolute path to the best available GHDL binary.

    Probe order:
      1. LZX_ALIGN_GHDL environment variable (explicit override)
      2. ghdl-llvm   (compiled backend, fastest)
      3. ghdl-gcc    (compiled backend)
      4. ghdl        (any backend)
    """
    env_override = os.environ.get("LZX_ALIGN_GHDL")
    if env_override:
        found = _probe_ghdl(env_override)
        if found:
            return found
        raise RuntimeError(
            f"LZX_ALIGN_GHDL is set to {env_override!r} but is not a working GHDL binary."
        )

    for candidate in ("ghdl-llvm", "ghdl-gcc", "ghdl"):
        binary = shutil.which(candidate)
        if binary:
            found = _probe_ghdl(binary)
            if found:
                return found

    raise RuntimeError(
        "GHDL not found on PATH. Install the LLVM backend:\n"
        "  Ubuntu/Debian:  sudo apt install ghdl-llvm\n"
        "  macOS:          brew install ghdl\n"
        "  Any platform:   download OSS CAD Suite from\n"
        "                  https://github.com/YosysHQ/oss-cad-suite-build/releases"
    )


# ==============================================================================
#  Source file ordering
# ==============================================================================

def _ordered_sdk_sources(config: str = "sd_analog") -> list[Path]:
    """Return SDK VHDL sources in GHDL analysis order (packages before entities).

    Analysis order (dependency graph, earlier → later):
      1.  Packages: video_stream_pkg, video_timing_pkg, video_sync_pkg
      2.  Core config package (e.g. sd_analog_pkg)
      3.  Core package (core_pkg)
      4.  DSP entities — multiplier.vhd first (diff_multiplier_s and proc_amp
          depend on entity work.multiplier_s defined there); all DSP before
          video_timing because video_timing_generator uses edge_detector
      4b. video_field_detector (video_sync) — promoted ahead of video_timing
          because video_timing_generator also instantiates it
      5.  Utilities (sync_slv etc.)
      6.  Serial peripheral
      7.  Video stream entities (converters, blanking — depend on core_pkg)
      8.  Video timing entities (resolution_pkg, accumulator, generator)
      9.  Remaining video sync entities (field_detector already added in 4b)
     10.  program_top entity declaration
    """
    srcs: list[Path] = []

    def _add(p: Path) -> None:
        if p.exists():
            srcs.append(p)

    # ── 1. Packages (strict dependency order) ────────────────────────────────
    _add(_DIR_VS    / "video_stream_pkg.vhd")
    _add(_DIR_VT    / "video_timing_pkg.vhd")
    _add(_DIR_VSYNC / "video_sync_pkg.vhd")

    # ── 2. Core config package ────────────────────────────────────────────────
    cfg_pkg = _DIR_CCFG / f"{config}_pkg.vhd"
    if not cfg_pkg.exists():
        raise FileNotFoundError(
            f"Core config package not found: {cfg_pkg}\n"
            f"Available configs: "
            f"{[p.stem.replace('_pkg', '') for p in sorted(_DIR_CCFG.glob('*_pkg.vhd'))]}"
        )
    srcs.append(cfg_pkg)

    # ── 3. Core package ───────────────────────────────────────────────────────
    _add(_DIR_CORE / "core_pkg.vhd")

    # ── 4. DSP entities ───────────────────────────────────────────────────────
    #    multiplier.vhd must come first: diff_multiplier_s.vhd and proc_amp.vhd
    #    both instantiate entity work.multiplier_s (defined in multiplier.vhd).
    #    All DSP must precede video_timing entities (video_timing_generator
    #    instantiates entity work.edge_detector from this group).
    dsp_all   = sorted(_DIR_DSP.glob("*.vhd"))
    dsp_first = [f for f in dsp_all if f.name == "multiplier.vhd"]
    dsp_rest  = [f for f in dsp_all if f.name != "multiplier.vhd"]
    srcs.extend(dsp_first + dsp_rest)

    # ── 4b. video_field_detector (video_sync) — promoted early ───────────────
    #     video_timing_generator instantiates entity work.video_field_detector,
    #     which lives in video_sync but has no entity dependencies of its own.
    _add(_DIR_VSYNC / "video_field_detector.vhd")

    # ── 5. Utilities ──────────────────────────────────────────────────────────
    srcs.extend(sorted(_DIR_UTILS.glob("*.vhd")))

    # ── 6. Serial peripheral ──────────────────────────────────────────────────
    srcs.extend(sorted(_DIR_SERIAL.glob("*.vhd")))

    # ── 7. Video stream entities ──────────────────────────────────────────────
    for f in sorted(_DIR_VS.glob("*.vhd")):
        if f.name != "video_stream_pkg.vhd" and f not in srcs:
            srcs.append(f)

    # ── 8. Video timing entities ──────────────────────────────────────────────
    for f in sorted(_DIR_VT.glob("*.vhd")):
        if f.name != "video_timing_pkg.vhd" and f not in srcs:
            srcs.append(f)

    # ── 9. Video sync entities ────────────────────────────────────────────────
    for f in sorted(_DIR_VSYNC.glob("*.vhd")):
        if f.name != "video_sync_pkg.vhd" and f not in srcs:
            srcs.append(f)

    # ── 10. program_top entity declaration ────────────────────────────────────
    _add(_DIR_CORE / "program_top.vhd")

    return srcs


def _is_program_top_arch(path: Path) -> bool:
    """Return True if the file defines an architecture of program_top."""
    try:
        txt = path.read_text(encoding="utf-8", errors="replace").lower()
        return bool(re.search(r"architecture\s+\w+\s+of\s+program_top", txt))
    except OSError:
        return False


def _toposort_vhdl(files: list[Path]) -> list[Path]:
    """Topologically sort VHDL files by entity instantiation dependencies.

    Files that declare an entity required by another file come first.
    Falls back to alphabetical order for files without cross-dependencies.
    """
    if len(files) <= 1:
        return list(files)

    re_decl = re.compile(r"^\s*entity\s+(\w+)\s+is\b", re.IGNORECASE | re.MULTILINE)
    re_inst = re.compile(r"\bentity\s+work\.(\w+)\b", re.IGNORECASE)

    entity_to_file: dict[str, Path] = {}
    file_deps: dict[Path, set[str]] = {}

    for f in files:
        try:
            txt = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            file_deps[f] = set()
            continue
        for m in re_decl.finditer(txt):
            entity_to_file[m.group(1).lower()] = f
        file_deps[f] = {m.group(1).lower() for m in re_inst.finditer(txt)}

    # Build adjacency: file → set of files it depends on (within this list)
    adj: dict[Path, set[Path]] = {}
    for f in files:
        deps: set[Path] = set()
        for ent in file_deps.get(f, set()):
            dep = entity_to_file.get(ent)
            if dep and dep != f:
                deps.add(dep)
        adj[f] = deps

    # Kahn's algorithm — preserves alphabetical tiebreaking
    in_degree: dict[Path, int] = {f: 0 for f in files}
    for f in files:
        for dep in adj[f]:
            in_degree[f] = in_degree.get(f, 0) + 1

    queue = [f for f in files if in_degree[f] == 0]
    result: list[Path] = []
    while queue:
        node = queue.pop(0)
        result.append(node)
        for f in files:
            if node in adj[f]:
                in_degree[f] -= 1
                if in_degree[f] == 0:
                    queue.append(f)

    # Cycle fallback (should not happen in well-structured programs)
    for f in files:
        if f not in result:
            result.append(f)

    return result


def _ordered_program_sources(program_dir: Path) -> list[Path]:
    """Return the program's VHDL files in analysis order.

    Supporting entities (sub-modules) are topologically sorted so that each
    entity is analysed before any file that instantiates it.  The program_top
    architecture comes last.
    """
    all_vhd   = sorted(program_dir.glob("*.vhd"))
    main_arch = [f for f in all_vhd if _is_program_top_arch(f)]
    supporting = [f for f in all_vhd if f not in main_arch]
    return _toposort_vhdl(supporting) + main_arch


# ==============================================================================
#  GHDL runner
# ==============================================================================

def _run_cmd(
    cmd: list[str],
    cwd: Path,
    verbose: bool,
    description: str,
) -> tuple[bool, str]:
    """Run a subprocess, returning (success, combined_output)."""
    if verbose:
        print(f"  $ {' '.join(cmd)}")
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(cwd),
    )
    output = (result.stdout or "") + (result.stderr or "")
    if result.returncode != 0:
        if verbose:
            for line in output.strip().splitlines():
                print(f"    {line}")
        else:
            # Always show errors even in quiet mode
            for line in output.strip().splitlines()[-10:]:
                print(f"    {line}", file=sys.stderr)
    elif verbose and output.strip():
        for line in output.strip().splitlines():
            print(f"    {line}")
    return result.returncode == 0, output


def run_alignment(
    program_dir:  Path,
    build_dir:    Path,
    output_file:  Path,
    n_cols:       int = 90,
    n_rows:       int = 60,
    h_blank:      int = 64,
    v_blank:      int = 20,
    warmup_frames: int = 2,
    config:       str = "sd_analog",
    verbose:      bool = False,
) -> int:
    """Run the alignment testbench and return an exit code (0=PASS, 1=FAIL, 2=ERROR).

    The captured pixel file is written to *output_file* before the exit code
    is determined, so callers can read it for delay-shift analysis even when
    the testbench fails.
    """
    build_dir.mkdir(parents=True, exist_ok=True)

    # ── Locate GHDL ───────────────────────────────────────────────────────────
    try:
        ghdl = _find_ghdl()
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    workdir_flag = f"--workdir={build_dir}"

    # ── Collect sources in analysis order ─────────────────────────────────────
    try:
        sdk_srcs   = _ordered_sdk_sources(config)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    prog_srcs  = _ordered_program_sources(program_dir)
    testbench  = [_TB_ALIGN]
    all_srcs   = sdk_srcs + prog_srcs + testbench

    if verbose:
        print(f"  Sources: {len(sdk_srcs)} SDK + {len(prog_srcs)} program + 1 testbench")

    # ── Step 1: Analyse ───────────────────────────────────────────────────────
    if verbose:
        print(f"  [1/3] Analysing {len(all_srcs)} VHDL files...")
    for src in all_srcs:
        cmd = [ghdl, "-a", _GHDL_STD, workdir_flag, str(src)]
        ok, out = _run_cmd(cmd, build_dir, verbose,
                           description=f"analyse {src.name}")
        if not ok:
            print(f"  ERROR: GHDL analysis failed for {src.name}", file=sys.stderr)
            return 2

    # ── Step 2: Elaborate ─────────────────────────────────────────────────────
    if verbose:
        print(f"  [2/3] Elaborating {_TOP_ENTITY}...")

    # Detect whether this GHDL binary uses a compiled backend (for -O2)
    try:
        ver_out = subprocess.run([ghdl, "--version"], capture_output=True,
                                 text=True, timeout=5).stdout
    except Exception:  # noqa: BLE001
        ver_out = ""
    is_compiled = any(kw in ver_out.lower() for kw in ("llvm", "gcc code"))

    elab_cmd = [ghdl, "-e", _GHDL_STD, workdir_flag]
    if is_compiled:
        elab_cmd.append("-O2")
    elab_cmd.append(_TOP_ENTITY)

    ok, out = _run_cmd(elab_cmd, build_dir, verbose, description="elaborate")
    if not ok:
        print(f"  ERROR: GHDL elaboration failed.", file=sys.stderr)
        return 2

    # ── Step 3: Run simulation ─────────────────────────────────────────────────
    # Pass generic overrides.  The testbench writes alignment_output.txt to cwd.
    if verbose:
        print(f"  [3/3] Running simulation ({n_cols}×{n_rows} px, "
              f"{warmup_frames} warmup frame(s))...")

    run_cmd = [
        ghdl, "-r", _GHDL_STD, workdir_flag, _TOP_ENTITY,
        f"-gG_N_COLS={n_cols}",
        f"-gG_N_ROWS={n_rows}",
        f"-gG_H_BLANK={h_blank}",
        f"-gG_V_BLANK={v_blank}",
        f"-gG_WARMUP_FRAMES={warmup_frames}",
    ]

    # Run from build_dir so VHDL's relative "alignment_output.txt" lands there
    result = subprocess.run(
        run_cmd,
        capture_output=True,
        text=True,
        cwd=str(build_dir),
    )

    sim_output = (result.stdout or "") + (result.stderr or "")

    if verbose:
        for line in sim_output.strip().splitlines():
            print(f"    {line}")
    else:
        # Always print ALIGN_STATS and CHECK FAIL lines for diagnostics
        for line in sim_output.strip().splitlines():
            if any(tag in line for tag in ("ALIGN_STATS:", "CHECK FAIL", "ALIGNMENT")):
                print(f"    {line}", file=sys.stderr)

    # ── Move output file to the requested location ─────────────────────────────
    default_output = build_dir / "alignment_output.txt"
    if default_output.exists() and default_output != output_file:
        output_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(default_output), str(output_file))

    # ── Determine exit code ────────────────────────────────────────────────────
    # GHDL exits 0 when std.env.stop(0) is called (PASS).
    # GHDL exits 1 when std.env.stop(1) is called (FAIL) or on fatal errors.
    if result.returncode == 0:
        return 0
    elif result.returncode == 1:
        return 1
    else:
        # Unexpected exit code — treat as ERROR (e.g. segfault, out of memory)
        print(f"  ERROR: GHDL simulation exited with code {result.returncode}",
              file=sys.stderr)
        return 2


# ==============================================================================
#  CLI entry point
# ==============================================================================

def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Run tb_program_top_alignment against a program_top DUT.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--program-dir",   required=True, type=Path,
                   help="Directory containing the program's .vhd files.")
    p.add_argument("--build-dir",     required=True, type=Path,
                   help="Build directory for GHDL work library objects.")
    p.add_argument("--output-file",   required=True, type=Path,
                   help="Destination path for the captured pixel file.")
    p.add_argument("--n-cols",        type=int, default=90,
                   help="Active pixels per line (default: 90).")
    p.add_argument("--n-rows",        type=int, default=60,
                   help="Active lines per frame (default: 60).")
    p.add_argument("--h-blank",       type=int, default=64,
                   help="Horizontal blanking clocks per line (default: 64).")
    p.add_argument("--v-blank",       type=int, default=20,
                   help="Vertical blanking lines per frame (default: 20).")
    p.add_argument("--warmup-frames", type=int, default=2,
                   help="Frames to discard before capture (default: 2).")
    p.add_argument("--config",        default="sd_analog",
                   help="SDK core config package name (default: sd_analog).")
    p.add_argument("--verbose", "-v", action="store_true",
                   help="Print all GHDL command output.")
    return p.parse_args()


def main() -> int:
    args = _parse_args()
    return run_alignment(
        program_dir   = args.program_dir.resolve(),
        build_dir     = args.build_dir.resolve(),
        output_file   = args.output_file.resolve(),
        n_cols        = args.n_cols,
        n_rows        = args.n_rows,
        h_blank       = args.h_blank,
        v_blank       = args.v_blank,
        warmup_frames = args.warmup_frames,
        config        = args.config,
        verbose       = args.verbose,
    )


if __name__ == "__main__":
    sys.exit(main())
