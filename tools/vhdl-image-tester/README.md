# VHDL Image Tester

A PyQt6 GUI application that runs any Videomancer FPGA program as an **authentic GHDL simulation** on a user-selected still image and displays the processed output side-by-side with the original.

Part of the [Videomancer SDK](https://github.com/lzxindustries/videomancer-sdk). Requires a Videomancer repository checkout that includes the `programs/` directory.

---

## Requirements

### GHDL

GHDL is the VHDL simulator used to run programs. The recommended installation is via the **OSS CAD Suite** bundle (already used by the SDK build system):

```bash
# Option A — OSS CAD Suite (recommended, same toolchain as the SDK build)
# Download the latest release from https://github.com/YosysHQ/oss-cad-suite-build/releases
# Then add it to your PATH before running the tester:
export PATH="/path/to/oss-cad-suite/bin:$PATH"

# Option B — system package (Ubuntu/Debian)
sudo apt install ghdl

# Option C — macOS via Homebrew
brew install ghdl
```

Verify: `ghdl --version` (must report ≥ 3.0).

### Python

Python ≥ 3.10 is required.

```bash
# Ubuntu/Debian
sudo apt install python3 python3-venv python3-pip

# macOS (via Homebrew)
brew install python@3.12

# Windows
# Download from https://www.python.org/downloads/
# (Python 3.12 recommended)
```

### Python Dependencies

| Package | Version | Purpose                       |
|---------|---------|-------------------------------|
| PyQt6   | ≥ 6.6   | GUI framework                 |
| Pillow  | ≥ 10.0  | Image I/O                     |
| NumPy   | ≥ 1.24  | YUV pixel arithmetic          |

All Python dependencies are installed automatically by the launchers below.

---

## Installation & Quick Start

### Linux / macOS

```bash
# From the Videomancer repository root:
cd videomancer-sdk/tools/vhdl-image-tester

# First-time setup — creates .venv and installs all dependencies:
./run.sh --install

# Launch the application:
./run.sh
```

### Windows

```bat
rem From the Videomancer repository root:
cd videomancer-sdk\tools\vhdl-image-tester

rem First-time setup — creates .venv and installs all dependencies:
run.bat --install

rem Launch the application:
run.bat
```

### Install as a Python package (any platform)

```bash
# Install into the current Python environment:
pip install -e videomancer-sdk/tools/vhdl-image-tester/

# Launch:
lzx-vhdl-tester
```

### Run without installing (convenience launcher)

```bash
# From the Videomancer repository root:
python videomancer-sdk/tools/vhdl-image-tester/run.py
```

---

## Usage

### GUI mode (default)

1. Launch the application using any method above.
2. **(Optional)** Click the **`…`** button next to the **Folder** row at the top of the FPGA Program panel to choose a different programs source directory. By default the tool uses the `programs/` directory at the repository root.
3. Select a **program** from the dropdown (populated from the programs folder).
4. Select a **source image** from the file browser (or use a test image from `docs/test_images/`).
5. Adjust **register sliders and toggles** to set control values.
6. **(Optional)** If the program defines factory presets, use the **Preset** dropdown
   above the register controls to load a preset by name. All sliders and toggles
   update to match the preset. Manual changes reset the dropdown.
7. Press **F5** (or click **Generate**) to run the GHDL simulation.
8. The before/after images appear side-by-side. Zoom with the scroll wheel.

### CLI mode (headless)

All pipeline features are available without a display server or PyQt6 GUI. CLI
mode is activated when a known sub-command name is the first argument, or when
`--no-gui` is passed.

```bash
# List available programs
lzx-vhdl-cli list
lzx-vhdl-cli list --programs-dir /path/to/programs

# Show program metadata and parameter table
lzx-vhdl-cli info cascade

# Run the full VHDL simulation pipeline
lzx-vhdl-cli simulate cascade \
    --image docs/test_images/kodim23.png \
    --output result.png

# Override register values inline
lzx-vhdl-cli simulate cascade \
    --image photo.png \
    --set rotary_potentiometer_1=800 \
    --set toggle_switch_7=1023 \
    --output result.png

# Load a factory preset by name (with optional per-value overrides)
lzx-vhdl-cli simulate anodize \
    --image photo.png \
    --preset "Highlight" \
    --output result.png

lzx-vhdl-cli simulate anodize \
    --image photo.png \
    --preset "Highlight" \
    --set rotary_potentiometer_1=900 \
    --output result.png

# Export default register values to JSON, edit, then import
lzx-vhdl-cli export-regs cascade --output cascade_regs.json
# … edit cascade_regs.json …
lzx-vhdl-cli simulate cascade \
    --image photo.png \
    --import-regs cascade_regs.json \
    --output result.png

# Same using the combined entrypoint (subcommand detected automatically)
lzx-vhdl-tester simulate cascade --image photo.png --output result.png
python -m vhdl_image_tester simulate cascade --image photo.png --output result.png
```

#### `simulate` options reference

| Option | Default | Description |
|---|---|---|
| `--image PATH` | (required) | Source image (PNG, JPEG, BMP, …) |
| `--programs-dir DIR` | repo `programs/` | Override programs directory |
| `--video-mode MODE` | `1080p2997` | Video standard (see table below) |
| `--decimation N` | 4 | Resolution divisor (1, 2, 4, 8, 16, 32, 64) |
| `--warmup-frames N` | 2 | Warmup frames before capture |
| `--capture-frames N` | 1 | Output capture frames |
| `--preset NAME` | — | Load a factory preset by name (from TOML `[[preset]]`) |
| `--set KEY=VALUE` | — | Override a register value (repeatable) |
| `--import-regs PATH` | — | Load registers from JSON (see `export-regs`) |
| `--output PATH` | `<name>_output.png` | Output image path |
| `--save-input` | off | Also save the resized input image |
| `--build-dir DIR` | `/tmp/lzx_vit/<name>` | Override GHDL working directory |

---

## Architecture

```
videomancer-sdk/tools/vhdl-image-tester/
├── run.py                              # Convenience launcher (no install required)
├── run.sh                              # Linux/macOS launcher with venv management
├── run.bat                             # Windows launcher with venv management
├── pyproject.toml                      # Package metadata and dependency declarations
└── vhdl_image_tester/
    ├── __main__.py                     # python -m vhdl_image_tester / lzx-vhdl-tester entry point
    ├── cli.py                          # Headless CLI (lzx-vhdl-cli) — all sub-commands
    ├── core/
    │   ├── config.py                   # Repo path detection, ABI constants, sim settings
    │   ├── program_loader.py           # Parse TOML → Program / Parameter dataclasses
    │   ├── image_converter.py          # RGB ↔ BT.601 YUV-10bit pixel stream
    │   ├── testbench_gen.py            # Generate tb_vit.vhd with register values
    │   ├── sim_runner.py               # Run GHDL (analyse → elaborate → simulate)
    │   └── pipeline.py                 # run_pipeline() + SimulationWorker QThread wrapper
    └── app/
        ├── main_window.py              # Top-level QMainWindow
        └── widgets/
            ├── program_panel.py        # Program + image source selection panel
            ├── register_panel.py       # Per-parameter control widgets (sliders/toggles)
            ├── image_viewer.py         # Before/after image viewer with zoom
            └── log_panel.py            # Streaming GHDL log output
```

---

## Simulation Pipeline

```
User selects program + image + register settings
        │
        ▼
[1] Resize image to simulation dimensions (native resolution ÷ decimation)
        │
        ▼
[2] Convert RGB → BT.601 YUV-10bit
    Build timing stimulus: N warmup frames + 1 capture frame
    Write stimulus.txt  (one clock cycle per line)
        │
        ▼
[3] Generate tb_vit.vhd VHDL-2008 testbench
    • Reads stimulus.txt → drives program_top DUT clock-by-clock
    • Writes output.txt  (captured avid pixels from capture frame)
        │
        ▼
[4] GHDL simulation
    ghdl -a  (analyse SDK packages + program VHD files + testbench)
    ghdl -e  (elaborate tb_vit)
    ghdl -r  (run; self-terminates with std.env.stop)
        │
        ▼
[5] Read output.txt → convert YUV-10bit → RGB
    Display side-by-side with input in GUI
```

---

## Register / ABI Mapping

```
registers_in(0)     rotary_potentiometer_1   10-bit (0–1023)
registers_in(1)     rotary_potentiometer_2
registers_in(2)     rotary_potentiometer_3
registers_in(3)     rotary_potentiometer_4
registers_in(4)     rotary_potentiometer_5
registers_in(5)     rotary_potentiometer_6
registers_in(6)     toggle_switch_7..11      bit 0..4 packed
registers_in(7)     linear_potentiometer_12  10-bit (0–1023)
registers_in(8)     video_timing_id          4-bit
```

See [ABI Format](../../docs/abi-format.md) for the full specification.

---

## Simulation Settings

| Setting         | Default     | Notes                                          |
|-----------------|-------------|------------------------------------------------|
| Video mode      | 1080p2997   | Any of the 15 ABI video standards; determines  |
|                 |             | FPGA config, timing ID, and native resolution  |
| Decimation      | ÷4          | Resolution divisor (1–64); smaller = faster    |
| Warmup frames   | 2           | Frames driven before capture; increase for     |
|                 |             | programs with deep line-delay pipelines        |

### Video Modes

| Key | Resolution | Interlaced | FPGA Config |
|---|---|---|---|
| `480i5994_composite` | 720×486 | Yes | sd_hdmi |
| `480i5994_svideo` | 720×486 | Yes | sd_hdmi |
| `480i5994_component` | 720×486 | Yes | sd_hdmi |
| `480p5994` | 720×480 | No | sd_hdmi |
| `576i50_composite` | 720×576 | Yes | sd_hdmi |
| `576i50_svideo` | 720×576 | Yes | sd_hdmi |
| `576i50_component` | 720×576 | Yes | sd_hdmi |
| `576p50` | 720×576 | No | sd_hdmi |
| `720p50` | 1280×720 | No | hd_hdmi |
| `720p5994` | 1280×720 | No | hd_hdmi |
| `720p60` | 1280×720 | No | hd_hdmi |
| `1080p24` | 1920×1080 | No | hd_hdmi |
| `1080p25` | 1920×1080 | No | hd_hdmi |
| `1080p2997` | 1920×1080 | No | hd_hdmi |
| `1080p30` | 1920×1080 | No | hd_hdmi |

---

## Build Artefacts

All GHDL working files and stimulus/output pixel data land in:

```
/tmp/lzx_vit/<program_name>/
├── stimulus.txt    # Input pixel stream (one clock cycle per line)
├── output.txt      # Captured output pixels
├── tb_vit.vhd      # Generated testbench
└── work-obj08.cf   # GHDL analysis work library
```

Override the build directory with the `LZX_VIT_BUILD_DIR` environment variable.
Override the programs directory with the `LZX_VIT_PROGRAMS_DIR` environment variable.

| Variable | Default | Purpose |
|---|---|---|
| `LZX_VIT_BUILD_DIR` | `/tmp/lzx_vit` | GHDL working directory |
| `LZX_VIT_PROGRAMS_DIR` | `<repo>/programs` | Programs source directory |

---

## Videomancer Firmware Repo — Wrapper Scripts

When the SDK is used as a submodule inside the full Videomancer firmware
repository, convenience wrappers live in `tools/` at the repo root. They set
`LZX_VIT_PROGRAMS_DIR` to the firmware `programs/` directory automatically so
you do not need to pass `--programs-dir` manually.

**Linux / macOS:**

```bash
# From the Videomancer repo root:
./tools/run-vhdl-tester.sh              # launch GUI
./tools/run-vhdl-tester.sh --install    # first-time setup

# CLI
./tools/run-vhdl-tester.sh list
./tools/run-vhdl-tester.sh simulate cascade --image docs/test_images/img.png --output out.png
./tools/run-vhdl-tester.sh simulate cascade --set rotary_potentiometer_1=800 --image photo.png
./tools/run-vhdl-tester.sh export-regs cascade --output cascade_regs.json
```

**Windows:**

```bat
rem From the Videomancer repo root:
tools\run-vhdl-tester.bat
tools\run-vhdl-tester.bat --install

rem CLI
tools\run-vhdl-tester.bat list
tools\run-vhdl-tester.bat simulate cascade --image docs\test_images\img.png --output out.png
```

---

## Keyboard Shortcuts

| Key    | Action                          |
|--------|---------------------------------|
| F5     | Generate (run simulation)       |
| Ctrl+S | Save output image               |
| F      | Fit images to view              |

---

## Register Import/Export

Save current register settings to a JSON file via **Export Regs**, then reload
them later with **Import Regs**. This lets you create reproducible test presets.

```json
{
  "program": "emboss",
  "program_name": "Emboss",
  "video_mode": "1080p2997",
  "decimation": 4,
  "registers": {
    "rotary_potentiometer_1": 512,
    "toggle_switch_7": 1,
    "linear_potentiometer_12": 1023
  },
  "register_array": [512, 0, 0, 0, 0, 0, 1, 1023, 0, 0, 0, 0, 0, 0, 0, 0,
                     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
}
```

---

## Factory Presets

Many programs ship with **factory presets** defined as `[[preset]]` sections in
their TOML configuration. Each preset is a named set of register values.

### GUI

When a program with presets is loaded, a **Preset** dropdown appears above the
register controls. Selecting a preset applies all its values to the sliders and
toggles. Parameters not specified in the preset keep their default values.
Manually changing any control resets the dropdown to "(select preset)".

### CLI

Use `--preset NAME` to load a preset before any `--set` overrides:

```bash
lzx-vhdl-cli simulate worley \
    --image photo.png \
    --preset "Animated Lava" \
    --output result.png
```

Use `lzx-vhdl-cli info <program>` to see available presets and their values.

---

## Launcher Reference

### run.sh / run.bat

```
Usage: ./run.sh [OPTION]

Options:
  (none)      Launch the application
  --install   Create .venv and install all dependencies (run once after cloning)
  --test      Run the test suite (pytest)
  --lint      Run linter (ruff) and type checker (mypy)
  --help      Show this help message
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `ghdl: command not found` | GHDL not on PATH | Add OSS CAD Suite to PATH, or install GHDL separately |
| `Cannot locate Videomancer repository root` | Tool run outside repo tree | Run from within the Videomancer repository |
| `No programs found` | `programs/` directory empty or missing | Ensure you are running from a full Videomancer repo checkout |
| `ModuleNotFoundError: PyQt6` | Dependencies not installed | Run `./run.sh --install` (or `run.bat --install`) |
| Simulation hangs | Program requires many warmup frames | Increase **Warmup frames** in settings |

---

## Development

```bash
# Install in editable mode with dev extras (linters, type checker, test runner):
pip install -e "videomancer-sdk/tools/vhdl-image-tester/[dev]"

# Run linter:
cd videomancer-sdk/tools/vhdl-image-tester && ./run.sh --lint

# Run tests:
cd videomancer-sdk/tools/vhdl-image-tester && ./run.sh --test
```

---

## License

Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.
Proprietary and confidential. Unauthorized use is prohibited.
