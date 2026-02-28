# Bitstream Compression

VMPROG format v1.1 adds optional DEFLATE compression of FPGA bitstream
payloads, reducing flash consumption on the RP2040 by approximately 60%.

## Algorithm

Raw DEFLATE (RFC 1951) with a 1 KB sliding window (`wbits=10`).

- **No zlib/gzip framing** — the VMPROG TOC already provides BLAKE2b-256
  hash verification per section, making Adler-32/CRC-32 redundant.
- **1 KB window** — ICE40 HX4K bitstreams have tile-local repetition
  patterns. A 1 KB window captures 99%+ of the redundancy
  (<1% ratio difference vs. the 32 KB default window).
- **Level 9** — maximum compression is the default. Build time is
  negligible (~1 ms per 135 KB bitstream on modern hardware).

## Measured Impact

| Metric | Value |
|--------|-------|
| ICE40 HX4K raw bitstream | 135,100 bytes |
| Typical compressed size | 54–57 KB (40–42% of original) |
| Average savings per 6-variant `.vmprog` | ~480 KB |
| Full `.vmprog` package reduction | ~58% smaller |

## RAM Requirements (RP2040 Decompression)

| Buffer | Size | Lifetime |
|--------|------|----------|
| Inflate sliding window | 1,024 bytes | During `stream_bitstream_to_fpga()` |
| Compressed input chunk | 512 bytes | During `stream_bitstream_to_fpga()` |
| Decompressed output chunk | 4,096 bytes | Existing (shared with uncompressed path) |
| uzlib state (`uzlib_uncomp`) | ~1.2 KB | During `stream_bitstream_to_fpga()` |
| **Total additional** | **~1.5 KB** | Static, single-load |

All decompression buffers are `static` — only one FPGA configuration can
be in progress at a time.

## Build-Time Options

The `vmprog_pack.py` packer compresses bitstreams by default:

```bash
# Default: compress at level 9
python3 vmprog_pack.py ./build/programs/myprogram ./output/myprogram.vmprog

# Disable compression (produces v1.0 package)
python3 vmprog_pack.py --no-compress ./build/programs/myprogram ./output/myprogram.vmprog

# Custom compression level (1=fastest, 9=best)
python3 vmprog_pack.py --compress-level 6 ./build/programs/myprogram ./output/myprogram.vmprog
```

When compression is enabled, each bitstream is compressed independently.
If compression does not reduce the size (e.g., already-compressed or
random data), the bitstream is stored uncompressed with no flag set.

## Format Details

### Header Changes (v1.1)

- `version_minor` = 1 (was 0)
- `flags` includes `has_compressed_sections` (0x00000002) when any TOC
  entry is compressed

### TOC Entry Changes

- `flags` field: `compressed_deflate` (0x00000001) marks compressed entries
- `uncompressed_size` field at offset 48: original size before compression
  (0 for uncompressed entries)
- `size` field: stores the compressed size (for seek/read operations)
- `sha256` hash: computed over compressed bytes as stored

### Signed Descriptor

Artifact hashes in the signed descriptor are computed over the compressed
payload bytes, matching the TOC entry hashes. Signature verification does
not require decompression.

## Firmware Behavior

The FPGA service (`fpga_service.hpp`) transparently handles both compressed
and uncompressed bitstreams during program loading:

1. Reads the TOC entry for the selected bitstream variant
2. Checks `is_toc_entry_compressed(entry)`
3. If compressed: initializes a `vmprog_inflate_stream`, reads compressed
   chunks from the filesystem, decompresses into the output buffer, and
   sends decompressed data to the ICE40 configurator
4. If uncompressed: reads and sends directly (unchanged from v1.0)
5. Verifies decompressed byte count matches `uncompressed_size`

The retry logic (up to 3 attempts with decreasing SPI baudrate) works
identically for both paths.

## Performance

| Operation | Uncompressed (135 KB) | Compressed (~55 KB) |
|-----------|----------------------|---------------------|
| Flash read (XIP, ~50 MB/s) | ~2.7 ms | ~1.1 ms |
| SD card read (~10 MB/s) | ~13.5 ms | ~5.5 ms |
| DEFLATE decompress (Cortex-M0+) | — | ~5–15 ms |
| SPI to FPGA (20 MHz) | ~54 ms | ~54 ms |
| **Total (flash)** | **~57 ms** | **~60–70 ms** |
| **Total (SD card)** | **~68 ms** | **~63–73 ms** |

The SPI transfer time to the FPGA dominates. Flash/SD read savings
partially or fully offset the decompression overhead.

## SDK Decompressor API

The `vmprog_decompress.hpp` header provides a streaming inflate API:

```cpp
#include <lzx/videomancer/vmprog_decompress.hpp>

uint8_t window[1024];
uint8_t out_buf[4096];
lzx::vmprog_inflate_stream inflater;
inflater.init(window, sizeof(window));
inflater.set_input(compressed_data, compressed_size);

while (!inflater.finished()) {
    auto result = inflater.decompress(out_buf, sizeof(out_buf));
    if (result.status == lzx::vmprog_inflate_result::invalid_data) break;
    // Use result.bytes_produced bytes from out_buf
    if (result.status == lzx::vmprog_inflate_result::need_input) {
        // Feed more compressed data
        inflater.set_input(more_data, more_size);
    }
}
```

## Third-Party Library

Decompression uses [uzlib](https://github.com/pfalcon/uzlib), a minimal
inflate-only C library (zlib license). Only the decompression subset is
vendored at `third_party/uzlib/` — all compression code, checksums, and
the `uzlib_uncompress_chksum` API are stripped.
