# Videomancer SDK — Copilot Workspace Instructions

This workspace is the **Videomancer SDK** — an open source FPGA video effects
development kit by LZX Industries. Programs are synthesised for iCE40 HX4K FPGAs
and run on the Videomancer hardware module.

---

## Before Generating Any Program Code

Always read these files first (use file reading tools):

**Essential — always:**
- `fpga/core/yuv444_30b/rtl/program_top.vhd` — the entity all architectures implement
- `fpga/common/rtl/video_stream/video_stream_pkg.vhd` — `t_video_stream_yuv444_30b`, `t_spi_ram`
- `fpga/common/rtl/video_timing/video_timing_pkg.vhd` — timing constants and `C_NTSC`/`C_PAL`/etc.
- `docs/toml-config-guide.md` — TOML field reference and length constraints
- An appropriate example program from `programs/` (see Reference Programs below)

**Highly recommended:**
- `docs/program-development-guide.md` — register mapping, sync delay rules, full workflow
- `docs/abi-format.md` — register map and ABI details including timing ID table
- `docs/program-categories.md` — complete list of valid category names

**When relevant to the effect:**
- `fpga/common/rtl/dsp/interpolator.vhd` — linear interpolation / dry-wet mix (4 cycles)
- `fpga/common/rtl/dsp/proc_amp.vhd` — contrast/brightness (9 cycles for 10-bit)
- `fpga/common/rtl/dsp/multiplier.vhd` — signed fixed-point multiply (~8 cycles)
- `fpga/common/rtl/dsp/variable_delay_u.vhd` — BRAM scanline delay (2 + delay cycles)
- `fpga/common/rtl/dsp/variable_filter_s.vhd` — 1st-order IIR filter (1 cycle)
- `fpga/common/rtl/dsp/diff_multiplier_s.vhd` — 4-quadrant differential multiply (~10 cycles)
- `fpga/common/rtl/dsp/lfsr16.vhd` — pseudo-random noise (free-running, period 2^16−1)
- `fpga/common/rtl/dsp/sin_cos_full_lut_10x10.vhd` — sine/cosine LUT (combinational)
- `fpga/common/rtl/dsp/frequency_doubler.vhd` — ramp→triangle (2 cycles)

---

## Reference Programs by Style

| Style | Program | Notes |
|-------|---------|-------|
| Minimal passthrough | `programs/passthru/` | 1 clock, no DSP — baseline reference |
| Simple multi-stage processing | `programs/yuv_amplifier/` | proc_amp + interpolator chain |
| Simple processing | `programs/sabattier/` | 16-clock pipeline, no BRAM |
| Synthesis / pattern generation | `programs/colorbars/`, `programs/pong/`, `programs/perlin/` | ignores `data_in` |
| BRAM feedback loop | `programs/howler/` | 3 BRAM, scan-line IIR, HD/SD adaptive |
| BRAM retro palette | `programs/stic/` | Intellivision palette quantiser |
| Complex DSP chains | `programs/kintsugi/`, `programs/mycelium/` | edge detect, BRAM line buffers |
| Community programs | `boneoh/Videomancer` on GitHub | YUV/RGB bit rotation and logic programs |

---

## Program File Structure

Every program lives in `programs/<name>/` and consists of a required pair of files
plus optional extras:

```
programs/<name>/
  <name>.toml        ← metadata, parameters, presets (required)
  <name>.vhd         ← VHDL architecture implementing program_top (required)
  <name>.py          ← optional Python build hook (runs before synthesis)
  component.vhd      ← optional additional VHDL modules
```

---

## Video Stream Type

The `data_in` and `data_out` ports are both of type `t_video_stream_yuv444_30b`:

```vhdl
type t_video_stream_yuv444_30b is record
    y       : std_logic_vector(9 downto 0);   -- Luma        0–1023
    u       : std_logic_vector(9 downto 0);   -- Cb chroma   0–1023, centred at 512
    v       : std_logic_vector(9 downto 0);   -- Cr chroma   0–1023, centred at 512
    avid    : std_logic;                       -- Active video flag (high during active pixels)
    hsync_n : std_logic;                       -- Horizontal sync (active low)
    vsync_n : std_logic;                       -- Vertical sync (active low)
    field_n : std_logic;                       -- Field indicator for interlaced signals
end record;
```

---

## TOML Conventions

```toml
[program]
program_id = "com.<author>.<name>"   # reverse-DNS, globally unique (max 63 chars)
program_version = "1.0.0"
abi_version = ">=1.0,<2.0"
program_name = "..."                 # ≤ 31 characters
author = "..."
license = "GPL-3.0"
categories = ["..."]                 # see docs/program-categories.md (up to 8)
program_type = "processing"          # "processing" (transforms input) or "synthesis" (generates)
description = "..."                  # ≤ 127 characters
hardware_compatibility = ["rev_b"]
core = "yuv444_30b"
# supported_timings = ["ntsc", "pal", ...]  # omit to support all timings

# Numeric control (knob or fader):
[[parameter]]
parameter_id = "rotary_potentiometer_1"
name_label = "..."            # ≤ 31 characters
control_mode = "linear"       # see control modes below
initial_value = 512           # hardware value 0–1023
display_min_value = 0
display_max_value = 100
suffix_label = "%"            # ≤ 3 characters

# Toggle / discrete control:
[[parameter]]
parameter_id = "toggle_switch_7"
name_label = "..."
value_labels = ["Off", "On"]        # 2–16 labels, each ≤ 31 chars; mutually exclusive with control_mode
initial_value_label = "Off"         # must match one of value_labels exactly
```

### String Length Limits

| Field | Max chars |
|-------|-----------|
| `program_id` | 63 |
| `program_name` | 31 |
| `description`, `url` | 127 |
| `author`, `license` | 31–63 |
| `name_label` | 31 |
| `suffix_label` | 3 |
| `value_labels` entries | 31 |
| `categories` entries | 31 |

### `control_mode` Values (numeric parameters only)

`linear`, `linear_half`, `linear_quarter`, `linear_double`, `boolean`,
`steps_4`, `steps_8`, `steps_16`, `steps_32`, `steps_64`, `steps_128`, `steps_256`,
`polar_degs_90`, `polar_degs_180`, `polar_degs_360`, `polar_degs_720`, `polar_degs_1440`, `polar_degs_2880`,
plus easing variants: `quad_in`, `quad_out`, `quad_in_out`, `sine_in`, `sine_out`, `sine_in_out`,
`circ_in`, `circ_out`, `circ_in_out`, `quint_in`, ... `expo_in`, `expo_out`, `expo_in_out`

### `categories` — Valid Values (37 total)

`Analysis`, `Camera`, `Color`, `Computer`, `Craft`, `Curve`, `Demo`, `Edges`,
`Fairlight`, `Film`, `Fractal`, `Game`, `Glitch`, `Grid`, `Illusion`, `Mask`,
`Material`, `Mirror`, `NewTek`, `Noise`, `Optics`, `Organic`, `Pattern`, `Pixel`,
`Print`, `Quantel`, `Render`, `Screen`, `Shape`, `Signal`, `Temporal`, `Text`,
`Transition`, `Tube`, `Vision`, `Warp`, `Weather`

### `supported_timings` — Valid Values

Omit this field to support all timings. Include it to restrict (e.g. SD-only BRAM designs):

```toml
# SD-only
supported_timings = ["ntsc", "pal", "480p", "576p"]
# HD-only
supported_timings = ["720p50","720p5994","720p60","1080i50","1080i5994","1080i60",
                     "1080p2398","1080p24","1080p25","1080p2997","1080p30"]
```

---

## Register Map (Hardware Controls → VHDL Signals)

| Control | `registers_in` index | Bits | Type |
|---------|---------------------|------|------|
| Knob 1 | `registers_in(0)` | 9:0 | 10-bit unsigned (0–1023) |
| Knob 2 | `registers_in(1)` | 9:0 | 10-bit unsigned |
| Knob 3 | `registers_in(2)` | 9:0 | 10-bit unsigned |
| Knob 4 | `registers_in(3)` | 9:0 | 10-bit unsigned |
| Knob 5 | `registers_in(4)` | 9:0 | 10-bit unsigned |
| Knob 6 | `registers_in(5)` | 9:0 | 10-bit unsigned |
| Toggle switch 7 | `registers_in(6)(0)` | bit 0 | std_logic |
| Toggle switch 8 | `registers_in(6)(1)` | bit 1 | std_logic |
| Toggle switch 9 | `registers_in(6)(2)` | bit 2 | std_logic |
| Toggle switch 10 | `registers_in(6)(3)` | bit 3 | std_logic |
| Toggle switch 11 | `registers_in(6)(4)` | bit 4 | std_logic (bypass by convention) |
| Fader 12 | `registers_in(7)` | 9:0 | 10-bit unsigned |
| Video timing ID | `registers_in(8)(3 downto 0)` | bits 3:0 | 4-bit, written by firmware at load |

Toggle switch 11 / `registers_in(6)(4)` is the **bypass** enable by convention.

`registers_in(8)(3 downto 0)` holds the active video timing ID. Most programs ignore it.
Use it only when the algorithm must scale to frame dimensions (e.g., scanline buffer depth).
Constants: `C_NTSC`, `C_PAL`, `C_480P`, `C_576P`, `C_720P50`, `C_1080I50`, etc. from `video_timing_pkg`.

---

## VHDL Rules — Non-Negotiable

1. **Entity is always `program_top`** — never define a custom entity. The architecture name should match the program name:
   ```vhdl
   architecture my_program of program_top is
   ```

2. **Required library/package declarations:**
   ```vhdl
   library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   library work;
   use work.all;
   use work.core_pkg.all;
   use work.video_stream_pkg.all;
   use work.video_timing_pkg.all;
   -- Optional (add when needed):
   use work.clamp_pkg.all;   -- saturating clamp helpers
   ```

3. **All processes must be synchronous** — only `rising_edge(clk)`:
   ```vhdl
   process(clk)
   begin
       if rising_edge(clk) then
           ...
       end if;
   end process;
   ```

4. **No resets, no `wait`, no `after`** — the iCE40 has no global reset. Use signal initialisation values instead. Do not use `wait` or `after` constructs (non-synthesisable).

5. **Sync signal pipeline delay** — `hsync_n`, `vsync_n`, `field_n`, and `avid` must be
   delayed by a shift register matching the **total sync path depth** in clocks.
   When DSP submodules appear at the end of the chain (e.g. an interpolator after a
   processing stage), the sync delay = processing depth + submodule depth.
   Implement with a `variable` array inside the sync process:
   ```vhdl
   constant C_PROCESSING_DELAY_CLKS : integer := 12;  -- inline processing stages
   constant C_SYNC_DELAY_CLKS       : integer := 16;  -- 12 + 4 (interpolator)
   ...
   p_sync_delay : process(clk)
       type t_sync_delay is array (0 to C_SYNC_DELAY_CLKS - 1) of std_logic;
       variable v_hsync_n : t_sync_delay := (others => '1');
       variable v_vsync_n : t_sync_delay := (others => '1');
       variable v_field_n : t_sync_delay := (others => '1');
       variable v_avid    : t_sync_delay := (others => '0');
   begin
       if rising_edge(clk) then
           v_hsync_n := data_in.hsync_n & v_hsync_n(0 to C_SYNC_DELAY_CLKS - 2);
           v_vsync_n := data_in.vsync_n & v_vsync_n(0 to C_SYNC_DELAY_CLKS - 2);
           v_field_n := data_in.field_n & v_field_n(0 to C_SYNC_DELAY_CLKS - 2);
           v_avid    := data_in.avid    & v_avid   (0 to C_SYNC_DELAY_CLKS - 2);
           data_out.hsync_n <= v_hsync_n(C_SYNC_DELAY_CLKS - 1);
           data_out.vsync_n <= v_vsync_n(C_SYNC_DELAY_CLKS - 1);
           data_out.field_n <= v_field_n(C_SYNC_DELAY_CLKS - 1);
           data_out.avid    <= v_avid   (C_SYNC_DELAY_CLKS - 1);
       end if;
   end process p_sync_delay;
   ```

6. **`data_out` must always be assigned** — no undriven outputs. Assign to `data_in` or a registered version in bypass/default cases.

7. **SDK DSP submodule instantiation** — use `entity work.<name>` syntax:
   ```vhdl
   u_interp : entity work.interpolator_u
       generic map (G_WIDTH => C_VIDEO_DATA_WIDTH)
       port map (clk => clk, a => s_dry, b => s_wet, t => s_blend, q => s_out);
   ```

8. **Arithmetic uses `unsigned`/`signed` from `numeric_std`** — never raw `std_logic_vector` arithmetic.

9. **UV offset convention** — U and V channels are centred at 512 (not 0). Subtract 512 before signed operations; add 512 back at the output.

10. **Process labelling** — label every process descriptively: `p_stage0:`, `p_stage1:`, `p_sync_delay:`.

---

## Required VHD File Header

Every `.vhd` must begin with the GPL licence block (copy from an existing program),
then a comment block documenting:

```vhdl
-- Program Name:        My Effect
-- Author:              ...
-- Overview:            Plain-language description of the visual effect
-- Resources:
--   N BRAM, M LUTs (approximate)
-- Pipeline:
--   Stage 0 (input register):          1 clock  → T+1
--   Stage 1 (processing):              3 clocks → T+4
--   ...
--   interpolator_u (wet/dry mix):      4 clocks → T+8
--   Total: 8 clocks
-- Submodules:
--   interpolator_u: linear blend, 4 clocks
-- Parameters:
--   Pot 1  (registers_in(0)):  ...
--   ...
--   Tog 7  (registers_in(6)(0)): ...
--   Tog 11 (registers_in(6)(4)): Bypass
--   Fader  (registers_in(7)):   Mix (dry/wet)
-- Timing:
--   C_PROCESSING_DELAY_CLKS = N (inline stages)
--   C_SYNC_DELAY_CLKS       = M (total, including trailing submodules)
```

---

## SDK DSP Library — Latencies

| Module | Entity name | Purpose | Latency |
|--------|-------------|---------|---------|
| Linear interpolator | `interpolator_u` | Crossfade: `a + (b−a)×t` | 4 cycles |
| Process amplifier | `proc_amp_u` | Contrast + brightness | 9 cycles (10-bit) |
| Signed multiplier | `multiplier_s` | `(x × y) >> frac + z` | ~8 cycles (10-bit) |
| Differential multiplier | `diff_multiplier_s` | 4-quadrant multiply | ~10 cycles (10-bit) |
| BRAM delay line | `variable_delay_u` | Scanline/pixel delay | 2 + delay cycles |
| IIR filter | `variable_filter_s` | 1st-order low/high-pass | 1 cycle |
| Ramp→triangle | `frequency_doubler` | Fold at midpoint | 2 cycles |
| Sine/cosine LUT | `sin_cos_full_lut_10x10` | 10-bit angle → sin, cos | Combinational |
| LFSR noise | `lfsr16` | 16-bit pseudo-random | Free-running |

---

## iCE40 HX4K Resource Budget

| Resource | Budget |
|----------|--------|
| Logic Cells (LCs) | ≤ 7,680 |
| Block RAMs (4 Kbit each) | ≤ 32 |
| SD pixel clock | 13.5 MHz (SD interlaced) / 27 MHz (SD progressive) |
| HD pixel clock | 74.25 MHz |

If a design is resource-heavy:
- Share a single BRAM across Y/U/V channels
- Pre-compute values in LUTs rather than runtime multiplies
- Add pipeline registers to break critical paths (improves Fmax)
- Declare `supported_timings` in TOML to restrict to SD-only if BRAM depth is SD-only

---

## Common Pitfalls

| Issue | Fix |
|-------|-----|
| Custom entity instead of `program_top` | Architecture must be `of program_top` |
| Sync delay too short | Sync delay = ALL processing stages + any trailing DSP submodule latency |
| `std_logic_vector` arithmetic | Convert to `unsigned`/`signed` from `numeric_std` |
| Missing `data_out` assignment | Always assign; use bypass path when needed |
| `wait`/`after` in processes | Not synthesisable; use only `rising_edge(clk)` |
| U/V not offset-corrected | Subtract 512 before signed math, add 512 at output |
| DSP valid-signal misalignment | `interpolator_u`/`multiplier_s` valid and data arrive together; pipeline `dry` tap to same depth as wet path |
| `value_labels` on a knob | Use `control_mode` for knobs/faders, `value_labels` for toggles/discrete only |
| `initial_value` with `value_labels` | Use `initial_value_label` (must match a label exactly) not `initial_value` |
| `suffix_label` too long | Max 3 characters (not 15) |
| `value_labels` entry too long | Max 31 characters per label |
| TOML string over length limit | `program_name` ≤ 31, `description` ≤ 127 |
| Design only fits SD BRAM depth | Add `supported_timings` to restrict to SD modes |

---

## Build, Test & Validate Commands

```bash
# Validate TOML schema
python3 tools/toml-validator/toml_schema_validator.py programs/<name>/<name>.toml

# Simulate with VHDL Image Tester (first time: --install sets up venv)
cd tools/vhdl-image-tester && ./run.sh --install
./run.sh                         # GUI mode

# Headless simulation
lzx-vhdl-cli simulate <name> \
    --image lfs/library/stock/test-images/kodim23.png \
    --output /tmp/<name>_result.png
# Override specific registers:
lzx-vhdl-cli simulate <name> --image photo.png \
    --set rotary_potentiometer_1=800 --set toggle_switch_7=1 \
    --output /tmp/result.png

# Build all programs (or a single named program)
./build_programs.sh
./build_programs.sh <name>

# Synthesise a test bitstream (SD timing, rev_b hardware)
make -C fpga \
    VIDEOMANCER_SDK_ROOT="$(pwd)" \
    PROJECT_ROOT="$(pwd)/programs/<name>/" \
    BUILD_ROOT="/tmp/fpga_test/<name>/" \
    PROGRAM=<name> \
    CONFIG=sd_analog DEVICE=hx4k PACKAGE=tq144 \
    FREQUENCY=27 HARDWARE=rev_b \
    CORE=yuv444_30b PLATFORM=ice40

# Check timing and resource usage after synthesis
grep "Max frequency" /tmp/fpga_test/<name>/build.log
grep -E "ICESTORM_LC:|ICESTORM_RAM:" /tmp/fpga_test/<name>/build.log
```
