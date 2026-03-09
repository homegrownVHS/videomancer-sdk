# Program Categories

Videomancer programs are organized into 37 categories. Every program's TOML
configuration **must** set `categories` to an array of one or more values
from the list below (up to 8 tags per program).

Categories determine how the firmware groups programs in its on-screen
browser. A program's type (*processing* or *synthesis*) is declared
explicitly via the separate `program_type` field — it is **not** inferred
from the category.

## Category List

| Category | Description |
|----------|-------------|
| Analysis | Waveform monitors, thermal maps and motion detection |
| Camera | Consumer and surveillance camera artifacts |
| Color | Color channel processors and palette quantization |
| Computer | Recreations of Amiga, Atari and ZX computers |
| Craft | Pottery, marbling, and cave paintings |
| Curve | Parametric curves, spirographs and attractors |
| Demo | Classic graphics demo effects like plasma and starfield |
| Edges | Outline extraction and topographic rendering |
| Fairlight | Device specific CVI emulations |
| Film | Photochemical processes and optical printing |
| Fractal | Mathematical fractals, space-filling curves and procedural tiles |
| Game | Recreations of NES, SNES and other console graphics |
| Glitch | Intentional data corruption, databending, and circuit-bent artifacts |
| Grid | Geometric grids, overlays and polygon renderers |
| Illusion | Optical illusions, moiré and lenticular effects |
| Mask | Matte generation, keying, and region isolation |
| Material | Painted surfaces and textile weaving patterns |
| Mirror | Reflection, folding and depth mapping |
| NewTek | Device specific Video Toaster emulations |
| Noise | Stochastic noise fields, static, and random textures |
| Optics | Holography, anaglyphs, diffraction and interference |
| Organic | Biological simulations, cellular automata, flocking, metaballs |
| Pattern | Repeating geometric tilings, tessellations, and wallpaper groups |
| Pixel | Spatial resampling, pixelation and displacement |
| Print | Halftone, engraving, cyanotype and woodblock |
| Quantel | Device specific Paintbox, Picturebox and Harry emulations |
| Render | Rasterization, noise fields and illumination |
| Screen | Classic screensaver homages: mystify, pipes, worms |
| Shape | Solid primitives, wireframes, and constructive geometry |
| Signal | Analog and digital signal degradation: VHS, LaserDisc, NTSC, codec failure |
| Temporal | Frame delay, freeze, strobe, and temporal feedback |
| Text | Teletext, ASCII, ANSI, Morse code, barcodes |
| Transition | Wipe patterns, dissolves, and animated reveals |
| Tube | Cathode ray tube emulation and phosphor persistence |
| Vision | Wipes and keys inspired by broadcast vision mixers |
| Warp | Continuous spatial deformation and distortion |
| Weather | Organic texture generation for rain, fog, and water |

## Adding a New Category

1. Add the new category to this document (keep the table sorted
   alphabetically).
2. Add the category name to the `items.enum` list in
   `docs/schemas/vmprog_program_config_schema_v1_0.json`.
3. Rebuild the TOML editor (`tools/toml-editor/`) — it reads the schema at
   build time.
