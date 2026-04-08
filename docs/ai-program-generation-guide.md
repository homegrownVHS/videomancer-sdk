# Generating Videomancer Programs with Claude AI

A step-by-step guide for using Claude to design and implement FPGA video
processing programs for the Videomancer SDK.

---

## Prerequisites

Before you begin, make sure you have:

- The [Videomancer SDK](https://github.com/lzxindustries/videomancer-sdk)
  cloned and its build toolchain working (`ghdl`, `yosys`, `nextpnr-ice40`,
  `icepack`, Python 3.10+).
- A Claude conversation with access to the SDK source files (via a project,
  the VS Code Copilot extension, or file attachments).
- Familiarity with the SDK's
  [Program Development Guide](program-development-guide.md) — you don't need
  to memorise it, but skimming it first helps you evaluate Claude's output.

---

## Overview

A Videomancer program is two files inside `programs/<name>/`:

| File | Purpose |
|------|---------|
| `<name>.toml` | Metadata, parameter definitions, presets |
| `<name>.vhd` | VHDL architecture implementing `program_top` |

Claude can generate both files from a natural-language description. The
recommended workflow is:

```
1. Describe what you want  →  Claude drafts TOML + VHDL
2. Review the design       →  iterate on the prompt if needed
3. Build & simulate        →  verify with the VHDL Image Tester
4. Synthesise              →  check timing and resource usage
```

---

## Step 1 — Give Claude the Right Context

Claude produces dramatically better programs when it can see the SDK source
code rather than working from memory alone. Provide as much of the following
as your context window allows, in priority order:

### Essential (always include)

| File / Directory | Why |
|------------------|-----|
| `fpga/core/yuv444_30b/rtl/program_top.vhd` | The entity your architecture must implement |
| `fpga/common/rtl/video_stream/video_stream_pkg.vhd` | `t_video_stream_yuv444_30b` and `t_spi_ram` type definitions |
| `fpga/common/rtl/video_timing/video_timing_pkg.vhd` | Video timing constants |
| `docs/toml-config-guide.md` | TOML field reference and constraints |
| One or two example programs (TOML + VHD) from `programs/` | Concrete style and structure reference |

### Highly recommended

| File / Directory | Why |
|------------------|-----|
| `docs/program-development-guide.md` | Full development workflow, register mapping, sync delay rules |
| `docs/abi-format.md` | Register map and ABI details |
| `docs/program-categories.md` | Valid category names |
| `fpga/common/rtl/core_config/hd_hdmi_pkg.vhd` | Example core config (so Claude knows what the config packages contain) |

### Include when relevant to your effect

| File | When to include |
|------|-----------------|
| `fpga/common/rtl/dsp/interpolator.vhd` | Dry/wet mix, crossfading |
| `fpga/common/rtl/dsp/proc_amp.vhd` | Contrast/brightness adjustment |
| `fpga/common/rtl/dsp/multiplier.vhd` | General signed fixed-point multiply |
| `fpga/common/rtl/dsp/variable_delay_u.vhd` | Scanline delay, echo, temporal effects |
| `fpga/common/rtl/dsp/variable_filter_s.vhd` | Low-pass / high-pass filtering |
| `fpga/common/rtl/dsp/diff_multiplier_s.vhd` | 4-quadrant (differential) multiply |
| `fpga/common/rtl/dsp/lfsr16.vhd` | Pseudo-random noise |
| `fpga/common/rtl/dsp/sin_cos_full_lut_10x10.vhd` | Sine/cosine lookup |
| `fpga/common/rtl/dsp/frequency_doubler.vhd` | Ramp → triangle conversion |
| A more complex example program (e.g. `howler`, `sabattier`, `kintsugi`) | Shows advanced pipeline patterns and BRAM usage |

> **Tip — VS Code Copilot users:** If you have the full repo open as a
> workspace, Copilot can read files on demand. Paste the relevant filenames
> into your prompt and ask it to read them before generating code.

---

## Step 2 — Write an Effective Prompt

A good program prompt has four parts:

### 2a. Effect description

Describe the visual effect in plain language. Focus on *what the viewer
sees*, not implementation details. Claude will map your description to
appropriate DSP techniques.

### 2b. Parameter mapping

Tell Claude which physical controls should do what. The hardware provides:

| Control | Register | Type |
|---------|----------|------|
| Knobs 1–6 | `registers_in(0)` – `registers_in(5)` | 10-bit (0–1023) |
| Toggle switches 7–11 | `registers_in(6)` bits 0–4 | 1-bit each |
| Fader 12 | `registers_in(7)` | 10-bit (0–1023) |

You don't need to assign every control. Unused ones are simply ignored.

### 2c. Processing vs. synthesis

Tell Claude whether the program is:
- **Processing** — transforms an incoming video signal (`data_in`)
- **Synthesis** — generates imagery from scratch (ignores `data_in`)

### 2d. Constraints (optional but helpful)

Mention any constraints you care about:
- Target BRAM usage (32 max on iCE40 HX4K)
- Whether you want a dry/wet mix fader
- Specific DSP modules to use or avoid
- Whether it needs to work at both SD (27 MHz) and HD (74.25 MHz)

### Example prompt

```
Create a Videomancer program called "shimmer" that adds a shimmering,
heat-haze distortion to the input video.

Effect: Horizontal pixel displacement that varies sinusoidally per
scanline and drifts slowly over time using a free-running counter.

Parameters:
  - Knob 1: Displacement amount (0 = none, max = ±32 pixels)
  - Knob 2: Vertical frequency of the sine wave
  - Knob 3: Drift speed
  - Knob 4: Unused
  - Knob 5: Unused
  - Knob 6: Unused
  - Toggle 7: Horizontal / vertical displacement axis
  - Toggles 8-11: Unused
  - Fader 12: Dry/wet mix

This is a processing program (transforms input video). Use the
interpolator module from the SDK for the dry/wet mix. Keep BRAM
usage under 6 blocks. Target both SD and HD timing.

Please generate both the TOML configuration file and the VHDL
architecture. Follow the SDK conventions shown in the example
programs I've provided.
```

---

## Step 3 — Review Claude's Output

Claude will typically produce a complete `<name>.toml` and `<name>.vhd`.
Check these items before building:

### TOML checklist

- [ ] `program_id` follows reverse-DNS format and is unique
- [ ] `program_name` ≤ 31 characters
- [ ] `description` ≤ 127 characters
- [ ] `categories` uses valid names from [program-categories.md](program-categories.md)
- [ ] `program_type` is `"processing"` or `"synthesis"`
- [ ] Each `[[parameter]]` uses a valid `parameter_id`
- [ ] `value_labels` (toggle) or `control_mode` (knob/fader) is set, not both
- [ ] `initial_value` is in range 0–1023 for knobs/faders
- [ ] String fields are within [length limits](toml-config-guide.md)

### VHDL checklist

- [ ] Architecture is `of program_top` (not a custom entity)
- [ ] Uses `library ieee` + `library work` with correct packages
- [ ] `registers_in` mapping matches the TOML parameter definitions
- [ ] Toggle switches are extracted from `registers_in(6)` as individual bits
- [ ] All processes are synchronous: `if rising_edge(clk) then`
- [ ] No explicit resets (the iCE40 has no global reset; rely on initialisation)
- [ ] Sync signals (`hsync_n`, `vsync_n`, `field_n`, `avid`) are delayed by
      the exact processing pipeline depth
- [ ] If using SDK DSP modules, entity instantiations use `entity work.<name>`
- [ ] Pipeline depth is documented in the file header
- [ ] Output `data_out` is assigned in all cases (no undriven signals)

### Common issues to watch for

| Issue | Fix |
|-------|-----|
| Claude invents a custom entity instead of `program_top` | Ask it to re-do using the existing entity declaration |
| Sync signals not delayed | Ask Claude to add a shift-register delay matching the pipeline depth |
| Uses `std_logic_vector` arithmetic without `numeric_std` | Have it use `unsigned`/`signed` types from `numeric_std` |
| Overly complex design that won't fit iCE40 | Ask Claude to simplify; remind it of the 7,680 LC / 32 BRAM budget |
| Uses `wait`, `after`, or initial signal values in processes | These don't synthesise; ask Claude to use only `rising_edge(clk)` |
| Missing valid-signal pipeline for DSP modules | The SDK multiplier/interpolator have a valid-leads-data-by-1-cycle pattern; ask Claude to account for it |

---

## Step 4 — Build and Test

### 4a. Create the program directory

```bash
mkdir -p programs/shimmer
# Save Claude's output to:
#   programs/shimmer/shimmer.toml
#   programs/shimmer/shimmer.vhd
```

### 4b. Validate the TOML

```bash
python3 tools/toml-validator/toml_schema_validator.py programs/shimmer/shimmer.toml
```

### 4c. Simulate with the VHDL Image Tester

The fastest way to verify your program works is the VHDL Image Tester:

```bash
# GUI mode
cd tools/vhdl-image-tester && ./run.sh

# Or headless CLI
lzx-vhdl-cli simulate shimmer \
    --image /path/to/test-image.png \
    --output /tmp/shimmer_test.png
```

If the simulation fails with VHDL errors, paste the error message back to
Claude and ask it to fix the code.

### 4d. Synthesise a bitstream

Build a single SD-timing bitstream to verify the design fits the FPGA and
meets timing:

```bash
make -C fpga \
    VIDEOMANCER_SDK_ROOT="$(pwd)" \
    PROJECT_ROOT="$(pwd)/programs/shimmer/" \
    BUILD_ROOT="/tmp/fpga_test/shimmer/" \
    PROGRAM=shimmer \
    CONFIG=sd_analog DEVICE=hx4k PACKAGE=tq144 \
    FREQUENCY=27 HARDWARE=rev_b \
    CORE=yuv444_30b PLATFORM=ice40
```

Check the results:

```bash
# Timing
grep "Max frequency" /tmp/fpga_test/shimmer/build.log

# Resource usage
grep -E "ICESTORM_LC:|ICESTORM_RAM:" /tmp/fpga_test/shimmer/build.log
```

If timing fails or resources are exceeded, share the log excerpt with Claude
and ask it to optimise the design (e.g. reduce pipeline width, remove a
BRAM, simplify logic).

---

## Step 5 — Iterate

The first draft is rarely perfect. Common follow-up prompts:

| Situation | Prompt |
|-----------|--------|
| Effect looks wrong in simulation | *"The output is all black. Here's the VHDL — can you check the sync delay and data_out assignment?"* |
| Timing failure at 74.25 MHz | *"nextpnr reports Fmax of 62 MHz. Can you add pipeline registers to break the critical path?"* |
| Uses too many LCs | *"This uses 7,200 LCs out of 7,680. Can you simplify the design?"* |
| Uses too many BRAMs | *"I need this under 16 BRAMs. Can you share the delay buffer across Y/U/V?"* |
| Want to add a parameter | *"Add a toggle on switch 9 that switches between horizontal and diagonal displacement."* |
| Want presets | *"Add three factory presets: 'Gentle' with low displacement, 'Aggressive' with max displacement, and 'Slow Drift' with low speed."* |

### Providing error context

When asking Claude to fix a build or simulation error, always include:

1. The **exact error message** (GHDL error, nextpnr timing report, or
   simulation mismatch)
2. The **current VHDL source** (or at least the relevant section)
3. What you **expected** to see vs. what you got

---

## Tips for Best Results

### Start simple, then elaborate

Begin with a minimal version of your effect (e.g. single-channel processing,
no toggles) and verify it works. Then ask Claude to add features
incrementally. This catches bugs early and keeps each iteration manageable.

### Use existing programs as style references

Point Claude at a program similar to what you want:

- **Simple processing:** `passthru`, `yuv_amplifier`, `sabattier`
- **Synthesis (pattern generation):** `colorbars`, `pong`, `perlin`
- **BRAM-heavy feedback:** `howler`, `stic`
- **Complex DSP chains:** `kintsugi`, `mycelium`

Say: *"Follow the style and conventions of howler.vhd."*

### Remind Claude of hardware constraints

The iCE40 HX4K has limited resources. If your prompt describes an ambitious
effect, include a reminder:

> *"This targets an iCE40 HX4K with 7,680 logic cells and 32 block RAMs
> (4 Kbit each). Keep the design resource-efficient."*

### Ask for documentation in the header

Claude will typically include a detailed VHDL header block with pipeline
documentation and register mapping. If it doesn't, ask:

> *"Add a header comment documenting the pipeline stages, total latency,
> BRAM usage, and register-to-parameter mapping."*

### Let Claude choose the DSP approach

Rather than specifying exact implementation details, describe desired
behaviour and let Claude pick the right technique. For example, prefer
*"add a smooth crossfade between dry and wet signals"* over *"instantiate
the interpolator module with G_WIDTH=10"*. Claude will select the
appropriate SDK module or write inline logic as the design requires.

---

## Quick Reference: SDK DSP Library

These reusable modules are available for instantiation in your program.
Mention them by name if you want Claude to use a specific one.

| Module | Purpose | Latency |
|--------|---------|---------|
| `interpolator` | Linear interpolation / crossfade: `a + (b-a) × t` | 4 cycles |
| `proc_amp` | Contrast & brightness: `(input - 0.5) × contrast + brightness` | ~9 cycles (for 10-bit) |
| `multiplier_s` | Signed fixed-point multiply: `(x × y) >> frac + z` | ~8 cycles (for 10-bit) |
| `diff_multiplier_s` | 4-quadrant differential multiply | ~10 cycles (for 10-bit) |
| `variable_delay_u` | BRAM delay line (read-back at programmable offset) | 2 + delay cycles |
| `variable_filter_s` | 1st-order IIR low-pass / high-pass (no multiplier) | 1 cycle per sample |
| `frequency_doubler` | Ramp → triangle wave (fold at midpoint) | 2 cycles |
| `sin_cos_full_lut_10x10` | 10-bit angle → 10-bit signed sin & cos | Combinational |
| `lfsr16` | 16-bit maximal-length PRNG | 1 cycle per sample |
| `lfsr` | Configurable-width LFSR | 1 cycle per sample |
| `edge_detector` | Rising / falling edge detect | 1 cycle |

---

## Related Documentation

- [Program Development Guide](program-development-guide.md) — full
  development workflow and SDK conventions
- [TOML Configuration Guide](toml-config-guide.md) — complete TOML field
  reference
- [ABI Format](abi-format.md) — register map and SPI protocol
- [Program Categories](program-categories.md) — valid category names
- [Package Signing Guide](package-signing-guide.md) — signing `.vmprog`
  packages
