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

# Output: out/*.vmprog
```

**Requirements:** Linux, Windows (WSL2), or macOS (Homebrew) | Python 3.7+ | ~2 GB disk space

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

The **VHDL Image Tester** lets you verify a program's behaviour on still images without FPGA hardware, using authentic GHDL simulation of the full SDK source tree.

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
lzx-vhdl-cli simulate passthru --image docs/test_images/your_image.png --output result.png

# Override register values
lzx-vhdl-cli simulate yuv_amplifier \
    --image docs/test_images/your_image.png \
    --set rotary_potentiometer_1=750 \
    --output result.png

# Export default register values for editing, then re-import
lzx-vhdl-cli export-regs yuv_amplifier --output regs.json
lzx-vhdl-cli simulate yuv_amplifier --image photo.png --import-regs regs.json
```

See the [VHDL Image Tester README](tools/vhdl-image-tester/README.md) for full installation instructions, all CLI options, keyboard shortcuts, and troubleshooting.

## Examples

- `programs/passthru/` - Minimal pass-through program
- `programs/yuv_amplifier/` - Multi-parameter processor

## License

GPL-3.0-only - Copyright (C) 2025 LZX Industries LLC

---

[lzxindustries.net](https://lzxindustries.net)

