# Videomancer SDK

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.en.html)
[![CI](https://github.com/lzxindustries/videomancer-sdk/workflows/CI/badge.svg)](https://github.com/lzxindustries/videomancer-sdk/actions/workflows/ci.yml)

Official SDK for Videomancer FPGA hardware by LZX Industries

## Quick Start

```bash
# Clone and setup
git clone https://github.com/lzxindustries/videomancer-sdk.git
cd videomancer-sdk
bash scripts/setup.sh

# Build programs
bash build_programs.sh

# Clean build artifacts
bash clean_programs.sh

# Output: out/<hardware>/<program>.vmprog
```

**Requirements:** Linux, Windows (WSL2), or macOS (Homebrew) | Python 3.10+ | ~2 GB disk space

## Documentation

- [Program Development Guide](docs/program-development-guide.md) - Create VHDL programs
- [TOML Configuration Guide](docs/toml-config-guide.md) - Define parameters
- [Program Categories](docs/program-categories.md) - Category definitions
- [VMPROG Format](docs/vmprog-format.md) - Package format spec
- [ABI Format](docs/abi-format.md) - Hardware interface
- [Package Signing](docs/package-signing-guide.md) - Ed25519 signing
- [VHDL Image Tester](tools/vhdl-image-tester/README.md) - Simulate programs on still images

## Tools

- `tools/vhdl-image-tester/` - **Simulation test tool** — run any program as a GHDL simulation on a still image; GUI and CLI modes
- `tools/toml-editor/` - Visual TOML editor (browser-based)
- `tools/toml-converter/` - TOML to binary converter
- `tools/toml-validator/` - Configuration validator
- `tools/vmprog-packer/` - Package creator

## Testing Programs

The **VHDL Image Tester** lets you verify a program's behaviour on still images without FPGA hardware, using authentic GHDL simulation of the full SDK source tree. It works both from a standalone SDK checkout and from within the Videomancer firmware repository.

**GUI** (interactive before/after viewer):

```bash
cd tools/vhdl-image-tester
./run.sh --install   # first time: creates .venv, installs PyQt6/NumPy/Pillow
./run.sh
```

**CLI** (headless / CI-friendly):

```bash
# List available programs
lzx-vhdl-cli list

# Simulate and save output
lzx-vhdl-cli simulate passthru --image lfs/library/stock/test-images/your_image.png --output result.png

# Override register values
lzx-vhdl-cli simulate yuv_amplifier \
    --image lfs/library/stock/test-images/your_image.png \
    --set rotary_potentiometer_1=750 \
    --output result.png

# Export default register values for editing, then re-import
lzx-vhdl-cli export-regs yuv_amplifier --output regs.json
lzx-vhdl-cli simulate yuv_amplifier --image photo.png --import-regs regs.json
```

When running from a standalone SDK checkout, the example programs in `programs/` are used by default. Override with `--programs-dir` or `LZX_VIT_PROGRAMS_DIR`.

See the [VHDL Image Tester README](tools/vhdl-image-tester/README.md) for full installation instructions, all CLI options, keyboard shortcuts, and troubleshooting.

## Examples

The SDK ships with ten example programs of varying complexity:

- `programs/passthru/` - Minimal pass-through (no processing)
- `programs/yuv_amplifier/` - YUV brightness, contrast, and hue adjustment
- `programs/colorbars/` - Reference color bar generator (EBU/SMPTE)
- `programs/pong/` - Classic two-player Pong with AI opponent
- `programs/perlin/` - Gradient noise synthesizer with animated palettes
- `programs/mycelium/` - Reaction-diffusion organic pattern growth
- `programs/sabattier/` - Pseudo-solarization with Mackie line edge glow
- `programs/stic/` - Intellivision STIC retro 16-color palette quantizer
- `programs/howler/` - Video feedback loop with zoom, decay, and hue rotation
- `programs/kintsugi/` - Gold crack-repair edge overlay

## License

GPL-3.0-only - Copyright (C) 2025 LZX Industries LLC

---

[lzxindustries.net](https://lzxindustries.net)

