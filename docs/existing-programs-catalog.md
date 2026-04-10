# Videomancer — Existing Programs Catalog

A comprehensive inventory of all known Videomancer programs: official (device-bundled),
open-source SDK examples, and community contributions.

---

## Official Programs (Device-Bundled)

These ship with Videomancer or are available via official program updates.
Programs marked **open-source** have their full VHDL source in the SDK `programs/` directory.

### Processing Programs (transform input video)

| # | Program | Source | Summary |
|---|---------|--------|---------|
| 1 | **Bitcullis** | Closed | Video bitcrusher — H/V pixel decimation, independent luma/chroma posterization, ordered & random dithering, bit-order reversal, luma→chroma saturation modulation, threshold key |
| 2 | **Corollas** | Closed | Harmonic video processor — 4 cascaded frequency doublers (2×/4×/8×/16×), luma→multi-harmonic color mapping, per-harmonic hue offsets & inversions, threshold key |
| 3 | **Delirium** | Closed | Two-layer cascaded sinusoidal distortion (EarthBound-inspired) — per-layer amplitude/frequency/speed, horizontal/vertical modes, phase link/lock, quarter-wave sine LUT in BRAM, line buffers for displacement |
| 4 | **Elastica** | Closed | Scanimate-style per-scanline horizontal displacement — DDS phase accumulator, 4 waveshapes (sine/triangle/sawtooth/square), H+V frequency & amplitude, cross-modulation, V-warp (line skipping), edge clamp/wrap, animation, dual-bank ping-pong line buffer |
| 5 | **Faultplane** | Closed | Mirror-displacement processor — fractures image into horizontal bands via 2 timing accumulators, independent top/bottom delay/displacement/flip/invert, H+V frequency accumulators, XOR bank selection, line blanking |
| 6 | **Fauxtress** | Closed | Reimplementation of LZX Fortress module — 3 phase accumulators (H/V/animation), BRAM delay line (0–511 px), saturating feedback loop, XOR phase wrap, content-adaptive luma clock mode, depth crossfade, shift register manipulation |
| 7 | **Glorious** | Closed | Three-strip Technicolor film simulation — YUV→RGB→film response→RGB→YUV pipeline, per-channel exposure, H&D curve (toe/straight/shoulder), chromatic fringe via shift register delay, matrix bleed (dye contamination), era toggle, film fade (aging), mono separation mode, negative |
| 8 | **Howler** | **Open-source** | Video feedback loop — 3 BRAM scanline delays, independent Y/U/V IIR filters, HD/SD adaptive, adjustable feedback depth and gain |
| 9 | **Isotherm** | Closed | False-color thermal camera simulator — 4 palettes (Ironbow/Rainbow/White-Hot/Black-Hot) with 16-keypoint piecewise-linear LUT, isotherm contour lines, posterization, IIR smoothing, auto-range normalization, HUD overlay (crosshair + brackets), contrast/brightness |
| 10 | **Kintsugi** | **Open-source** | Glitch / broken-repair aesthetic — edge detection, BRAM line buffers, complex DSP chain |
| 11 | **Lumarian** | Closed | Comprehensive color correction + edge enhancement — proc amp (contrast/brightness), saturation, gamma (algebraic approximation), variable high-pass edge enhancement with 8-mode rectifier, luma/chroma invert, luma threshold key, ~47 cycle Y latency |
| 12 | **Mycelium** | **Open-source** | Reaction-diffusion cellular automaton (Gray-Scott model) — BRAM framebuffer, diffusion & reaction rates, pattern seeding |
| 13 | **Pinwheel** | Closed | Luminance-driven hue rotation — true UV vector rotation via hardware sine/cosine LUT and 2×2 matrix multiplier, luma→hue modulation, colorize mode, independent luma/chroma bit-level crush (AND or XOR), luma/chroma invert, 36-clock pipeline |
| 14 | **Sabattier** | **Open-source** | Darkroom Sabatier/solarization re-exposure effect — 16-clock pipeline, piecewise luminance curve, no BRAM |
| 15 | **Scramble** | Closed | Analog TV scrambling simulator (VideoCrypt/Nagravision) — LFSR-driven per-line cut-and-rotate shuffle, decode alignment knob, periodic video inversion (luma or full YUV), horizontal jitter, seed control, drift (auto-cycling decode), luma modulation, double scramble mode, sawtooth/LFSR mode |
| 16 | **STIC** | **Open-source** | Intellivision (STIC chip) palette quantiser — retro console color restriction |
| 17 | **Stipple** | Closed | Retro palette quantizer — 8 classic platform palettes (Game Boy, CGA, Macintosh, NES, EGA, C64, Amiga OCS, Amstrad CPC), Bayer ordered dithering (2×2/4×4/8×8) or LFSR noise, brightness/contrast, saturation, pixel doubling, scanline emulation, invert, dither phase |
| 18 | **YUV Amplifier** | **Open-source** | Processing amplifier — per-channel contrast/brightness/saturation via proc_amp + interpolator chain |
| 19 | **YUV Phaser** | Closed | Per-channel horizontal displacement engine — independent Y/U/V phase (fixed offset) and displace (data-dependent modulation), per-channel inversion, fade-to-color stage (black/white), BRAM delay lines, 8-clock pipeline |

### Synthesis Programs (generate imagery, no input required)

| # | Program | Source | Summary |
|---|---------|--------|---------|
| 20 | **Colorbars** | **Open-source** | SMPTE-style color bar test pattern generator |
| 21 | **Moiré** | Closed | Dual sinusoidal grid interference pattern generator — 2 grids with independent pitch (8 steps), angle (16 steps via trig LUT), shape (sine/ellipse, circles/arcs), 4 combination modes (multiply/add × diff/min), video modulation on Grid B, animation via DDS, 256-entry sine BRAM LUT, alpha-max-beta-min distance |
| 22 | **Perlin** | **Open-source** | Perlin noise texture generator — animated coherent noise patterns |
| 23 | **Pong** | **Open-source** | Classic Pong game — ball, paddles, score display |
| 24 | **Shadebob** | Closed | Amiga demoscene shade bob — Lissajous trajectory, additive compositing on 64×36 persistent framebuffer, rainbow palette (256-entry), hue/luma decay modes, dual bob, circle/diamond shapes, video brightness modulation, gamma correction |

### Utility

| # | Program | Source | Summary |
|---|---------|--------|---------|
| 25 | **Passthru** | **Open-source** | Signal passthrough / bypass — 1 clock, no DSP, baseline reference |

---

## Community Programs (boneoh/Videomancer)

| # | Program | Author | Summary |
|---|---------|--------|---------|
| 26 | **RGB Bit Rotator** | boneoh | Bitwise rotation of RGB channels — rotates bit positions within each color channel |
| 27 | **YUV Bit Rotator** | boneoh | Bitwise rotation of YUV channels — same concept in YUV domain |
| 28 | **RGB Bit Logic** | boneoh | Bitwise logic operations (AND/OR/XOR/NOT) across RGB channels |
| 29 | **YUV Bit Logic** | boneoh | Bitwise logic operations across YUV channels |

---

## Capability Coverage Matrix

This maps the functional domains already covered by existing programs.
Use this to identify gaps when brainstorming new program ideas.

| Domain | Covered By |
|--------|-----------|
| **Color correction** (brightness/contrast/saturation) | YUV Amplifier, Lumarian |
| **Hue rotation / color shifting** | Pinwheel |
| **Gamma / tonal curve** | Lumarian, Sabattier |
| **Edge detection / enhancement** | Lumarian, Kintsugi |
| **Bit-level manipulation** (crush/rotate/logic) | Bitcullis, Pinwheel, RGB/YUV Bit Rotator, RGB/YUV Bit Logic |
| **Posterization / quantization** | Bitcullis, Stipple, Isotherm |
| **Ordered dithering** | Bitcullis, Stipple |
| **Retro palette restriction** | STIC (Intellivision), Stipple (8 platforms) |
| **Film emulation** | Glorious (Technicolor) |
| **False color / thermal mapping** | Isotherm, Pinwheel (colorize mode) |
| **Chromatic aberration / channel offset** | YUV Phaser |
| **Horizontal scanline displacement** | Elastica, Delirium, Scramble |
| **Mirror / image fracturing** | Faultplane |
| **Frequency doubling / harmonics** | Corollas |
| **Feedback loop** | Howler, Fauxtress |
| **Analog scrambling / signal disruption** | Scramble |
| **Sinusoidal distortion** | Delirium, Elastica |
| **Interference patterns / moiré** | Moiré |
| **Coherent noise generation** | Perlin |
| **Reaction-diffusion / cellular automaton** | Mycelium |
| **Demoscene effects** | Shadebob |
| **Game / interactive** | Pong |
| **Test patterns** | Colorbars |
| **Solarization / re-exposure** | Sabattier |

### Domains NOT Yet Covered

- Spatial blur / convolution (box, Gaussian)
- Pixel sorting / datamosh
- Oscilloscope / vectorscope display
- VHS / tape degradation artifacts (tracking, head-switching)
- ASCII / text overlay / character mapping
- Kaleidoscope / radial symmetry
- Chroma key / luma key extraction
- Zoom / scale / rotation (geometric transform)
- Temporal echo / frame blending
- Slitscan / time displacement
- Voronoi / Delaunay patterns
- Starfield / particle systems

---

## Notes

- **Open-source** programs have full VHDL + TOML in `programs/<name>/`.
- **Closed** programs ship as pre-built bitstreams; their behavior is documented at
  [docs.lzxindustries.net/docs/category/program-guides](https://docs.lzxindustries.net/docs/category/program-guides).
- Community programs are at [github.com/boneoh/Videomancer](https://github.com/boneoh/Videomancer).
