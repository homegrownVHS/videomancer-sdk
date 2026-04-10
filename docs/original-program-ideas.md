# Videomancer — Original Program Ideas

Ideas filtered against [existing-programs-catalog.md](existing-programs-catalog.md) to ensure
no duplication with the 25 official programs, 4 community programs, or their covered domains.

---

## Processing Programs (transform input video)

### 1. VHS Degradation (`vhs`)
**Category:** Glitch, Temporal, Signal
Simulates VHS tape artifacts: horizontal tracking error bands, head-switching noise
at the bottom of the frame, luma/chroma bandwidth limiting (color bleed), and
dropout lines. Uses LFSR for noise generation and BRAM line buffers for
tracking-error displacement.

**Why original:** Scramble covers analog *scrambling* (encrypted pay-TV). VHS is a
different aesthetic — degraded *playback*, not intentional disruption. No existing
program simulates tape-based artifacts.

**DSP:** variable_delay_u (tracking displacement), lfsr (dropout/noise), variable_filter_s (bandwidth limiting), interpolator_u (mix)

---

### 2. Kaleidoscope (`kaleidoscope`)
**Category:** Mirror, Warp, Optics
Radial symmetry engine — divides the frame into N angular segments (4/6/8/12) and
mirrors one wedge across all others. Uses address computation to remap pixel
coordinates through angular reflection. Optional rotation animation via DDS accumulator.

**Why original:** Faultplane does *horizontal band* mirroring/fracturing. No existing
program implements radial/angular symmetry.

**DSP:** sin_cos_full_lut_10x10 (coordinate transform), variable_delay_u (line buffer for address remap), interpolator_u (mix)

---

### 3. ASCII Art / Tile Map (`ascii`)
**Category:** Text, Pixel, Computer, Retro
Maps each N×M block of pixels to a character glyph from a ROM font based on average
luminance. Output is a text-art rendering of the input video. Adjustable block
size, font brightness threshold, foreground/background color, and optional
color preservation mode.

**Why original:** No existing program does character/glyph-based rendering. STIC
and Stipple restrict *color palettes*, not spatial *shape* representation.

**DSP:** BRAM (font ROM + block accumulator), proc_amp_u (contrast/brightness), interpolator_u (mix)

---

### 4. Pixel Sort (`pixelsort`)
**Category:** Glitch, Pixel, Computer
Sorts pixels within each scanline by luminance value. Pixels above a brightness
threshold are flagged as "active" and shift-sorted rightward during a single-line
pass, creating the characteristic streaked-pixel glitch aesthetic. Adjustable
threshold, direction, and sort length limit.

**Why original:** No existing program implements spatial reordering of pixel values.
Scramble *shuffles lines*, but pixel sort operates *within* each line on pixel values.

**DSP:** BRAM (line buffer for sort workspace), comparator logic, interpolator_u (mix)

---

### 5. Oscilloscope / Waveform Monitor (`scope`)
**Category:** Analysis, Signal, Screen
Renders the input video's luminance as an oscilloscope waveform: each pixel column
becomes a vertical deflection point on a phosphor-green (or selectable color)
trace. Optional vectorscope mode plots U vs V as an XY scatter. Persistence
(IIR decay) creates trailing phosphor glow.

**Why original:** No existing program provides analytical display modes. Isotherm's
HUD is decorative overlay, not signal analysis.

**DSP:** BRAM (framebuffer for trace persistence), variable_filter_s (IIR decay), proc_amp_u (input scaling)

---

### 6. Chroma Key (`chromakey`)
**Category:** Mask, Color, Transition
Luma or chroma threshold keyer — extracts a binary matte based on selectable
channel (Y, U, V, or UV distance from a target) and replaces keyed regions with
a solid color fill or passes them as transparent (black). Adjustable threshold,
softness (via interpolator), and key inversion.

**Why original:** Existing programs have threshold *keys* as secondary features
(Bitcullis, Corollas, Lumarian), but none is a dedicated keying/matting tool with
channel selection and soft edges.

**DSP:** proc_amp_u (threshold scaling), interpolator_u (soft key edge), multiplier_s (UV distance)

---

### 7. Edge Glow / Neon Outline (`neon`)
**Category:** Edges, Color, Optics
Edge detection → brightness-to-hue color mapping → additive bloom overlay.
Detects edges via high-pass or dedicated edge_detector, maps edge intensity to a
rainbow or user-selected hue via sin_cos LUT, then additively blends the colored
edge back onto the original. Creates a neon sign / blacklight poster look.

**Why original:** Lumarian has edge enhancement but outputs it as luminance
correction, not colored additive glow. Kintsugi uses edges for glitch texture.
No program combines edge detect → false color → additive composite.

**DSP:** edge_detector (1 clk), sin_cos_full_lut_10x10 (hue mapping), proc_amp_u (bloom intensity), interpolator_u (mix)

---

### 8. Starfield (`starfield`)
**Category:** Demo, Pattern, Shape, Render
Classic 3D starfield synthesis — N stars stored in BRAM with X/Y/Z coordinates,
projected via perspective division (Z-depth scaling), rendered as bright points
on black. Stars wrap when they pass the camera. Speed and field-of-view
adjustable. Optional trail/streak mode via IIR persistence.

**Why original:** No existing synthesis program generates particle-based 3D
projection. Shadebob is 2D Lissajous additive; Perlin/Moiré are field-based.

**DSP:** BRAM (star table), multiplier_s (perspective division), lfsr (star seeding), variable_filter_s (optional trail)

---

### 9. Slitscan / Time Displacement (`slitscan`)
**Category:** Temporal, Warp, Film
Captures a vertical slice from each frame and maps it across the horizontal axis
with temporal offset — the left edge shows the oldest captured slice, the right
edge shows the newest (or vice versa). Creates the classic slitscan / streak
photography effect. Uses BRAM circular buffer storing one column per frame.

**Why original:** No existing program displaces pixels *temporally* (across frames).
All displacement programs (Elastica, Delirium, YUV Phaser, Scramble) operate
spatially within a single frame.

**DSP:** BRAM (circular frame-slice buffer), interpolator_u (mix). SD-only due to BRAM depth.

---

### 10. Voronoi / Stained Glass (`voronoi`)
**Category:** Pattern, Shape, Fractal, Render
Generates a Voronoi tessellation pattern from N seed points, rendering
nearest-seed regions as flat color cells with optional edge highlighting. Seeds
can be animated (Lissajous or LFSR drift). Input video provides cell colors
(sampled at seed positions) or luminance controls cell brightness.

**Why original:** No existing program generates Voronoi/Delaunay geometry.
Moiré uses sinusoidal interference, not distance-based tessellation.

**DSP:** BRAM (seed table), multiplier_s (distance calculation), interpolator_u (mix). Limited seed count due to iCE40 resources.

---

## Summary Table

| # | Name | Type | Key Technique | BRAM? | Complexity |
|---|------|------|---------------|-------|------------|
| 1 | VHS Degradation | Processing | Tracking displacement + noise + bandwidth limit | Yes | Medium |
| 2 | Kaleidoscope | Processing | Radial coordinate remap | Yes | Medium-High |
| 3 | ASCII Art | Processing | Block luminance → glyph ROM | Yes | Medium |
| 4 | Pixel Sort | Processing | In-line brightness sort | Yes | Medium |
| 5 | Oscilloscope | Processing | Waveform/vectorscope rendering | Yes | Medium-High |
| 6 | Chroma Key | Processing | Channel threshold + soft matte | No | Low-Medium |
| 7 | Edge Glow / Neon | Processing | Edge detect → color map → additive | No | Low-Medium |
| 8 | Starfield | Synthesis | 3D particle projection | Yes | Medium |
| 9 | Slitscan | Processing | Temporal slice buffer | Yes (SD-only) | Medium |
| 10 | Voronoi | Processing/Synth | Nearest-seed tessellation | Yes | High |

### Recommended Starting Points (lowest risk, best bang-for-buck)

1. **Chroma Key** — low resource usage, no BRAM, high utility, simple pipeline
2. **Edge Glow / Neon** — no BRAM, uses existing DSP modules, visually striking
3. **VHS Degradation** — moderate complexity, culturally resonant, good use of SDK DSP library
