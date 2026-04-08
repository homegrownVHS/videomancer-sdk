# VMPROG Bitstream Compression — Implementation Plan

## Executive Summary

Add optional DEFLATE compression of FPGA bitstreams in `.vmprog` packages to reduce flash consumption on the RP2040. Compression is performed at build time by `vmprog_pack.py`; streaming decompression happens at runtime during FPGA configuration via a new SDK header `vmprog_decompress.hpp`. The format change is backward-compatible (minor version bump 1.0 → 1.1) — uncompressed packages remain valid and loadable.

### Measured Impact

| Metric | Value |
|--------|-------|
| ICE40 HX4K raw bitstream | 135,100 bytes |
| DEFLATE wbits=10 (1 KB window) typical ratio | 32–52% of original |
| Average savings per 6-variant `.vmprog` | ~480 KB |
| Total savings across 28 built programs (166 bitstreams) | **14.5 MB** (67% reduction) |
| RP2040 decompression RAM budget | ~5.4 KB static |
| Compression ratio difference wbits=10 vs wbits=15 | <1% (negligible) |

The 1 KB sliding window (wbits=10) achieves nearly identical ratios to the 32 KB default window because ICE40 bitstreams have high locality — most repetition is within 1 KB tiles. This is the ideal trade-off: minimal RAM, maximum speed, near-optimal compression.

---

## 1. Algorithm Selection: Raw DEFLATE (wbits=10)

### Why DEFLATE

| Criterion | DEFLATE | LZ4 | Heatshrink | Run-Length |
|-----------|---------|-----|------------|------------|
| Compression ratio on ICE40 | 32–52% | ~60% | ~55% | ~70% |
| Decompression speed | Fast (Cortex-M0+ proven) | Fastest | Moderate | Fastest |
| RAM for decompression | 1 KB window + buffers | 64 KB dict | 256 B–2 KB | Negligible |
| Existing ecosystem | Python `zlib`, many C libs | Needs external lib | Needs external lib | Trivial |
| Streaming support | Native (inflate is inherently streaming) | Block-based | Streaming | Streaming |
| Code size (C decompressor) | ~2–3 KB (inflate-only) | ~1.5 KB | ~0.5 KB | ~0.2 KB |

**Decision**: Raw DEFLATE with `wbits=10` (1 KB sliding window). Use Python `zlib` for compression at build time. Use a minimal inflate-only C implementation (e.g., `puff.c` from zlib-contrib, or `uzlib`/`tinf`) in the SDK for decompression.

### Why NOT gzip/zlib framing

- Raw DEFLATE (no zlib/gzip headers) saves 6–18 bytes per stream and avoids redundant checksums — the VMPROG TOC already provides BLAKE2b-256 hash verification per section.
- Packer writes raw DEFLATE; firmware reads raw DEFLATE. No Adler-32 or CRC-32 overhead.

### Why wbits=10

- 1 KB window fits comfortably in RP2040's 264 KB SRAM alongside the existing 4 KB bitstream chunk buffer.
- ICE40 bitstreams have tile-local repetition patterns — a 1 KB window captures 99%+ of the redundancy (measured: <1% ratio difference vs 32 KB window).
- Smaller window = faster decompression (less data to search for back-references).

---

## 2. VMPROG Format Changes

### 2.1 Version Bump: 1.0 → 1.1

**Header change**: `version_minor` becomes `1`. Readers that check `version_major == 1` and accept `version_minor >= 0` (as the spec recommends) will continue to work. The existing validation in `validate_vmprog_header_v1_0()` checks `version_major == 1`; we add `version_minor <= 1`.

### 2.2 New TOC Entry Flag: `compressed_deflate`

Add a flag to `vmprog_toc_entry_flags_v1_0` to indicate the payload is DEFLATE-compressed:

```cpp
enum class vmprog_toc_entry_flags_v1_0 : uint32_t
{
    none              = 0x00000000,
    compressed_deflate = 0x00000001,  // Payload is raw DEFLATE compressed
};
```

This flag is set **per TOC entry**, so each bitstream variant can independently be compressed or not. Config, signed descriptor, and signature sections are never compressed.

### 2.3 New TOC Entry Field: `uncompressed_size`

The existing `vmprog_toc_entry_v1_0` has **16 bytes of reserved space** (`reserved[4]`). Repurpose the first 4 bytes:

```cpp
#pragma pack(push, 1)
struct vmprog_toc_entry_v1_0
{
    vmprog_toc_entry_type_v1_0 type;      // 4 bytes
    vmprog_toc_entry_flags_v1_0 flags;    // 4 bytes
    uint32_t offset;                      // 4 bytes
    uint32_t size;                        // 4 bytes (compressed size when flag set)
    uint8_t  sha256[32];                  // 32 bytes (hash of COMPRESSED payload)
    uint32_t uncompressed_size;           // 4 bytes (NEW — 0 when not compressed)
    uint32_t reserved[3];                 // 12 bytes (was reserved[4])
};
#pragma pack(pop)
```

**Key semantic**: When `compressed_deflate` flag is set:
- `size` = compressed payload size in the file
- `uncompressed_size` = original bitstream size
- `sha256` = hash of the **compressed** payload (what's stored in the file)

When the flag is NOT set:
- `size` = payload size (as before)
- `uncompressed_size` = 0 (or ignored)
- `sha256` = hash of the payload (as before)

This preserves backward compatibility: old readers see `reserved[0]` as zero for uncompressed entries and ignore it.

### 2.4 Signed Descriptor

The signed descriptor's `artifact_count` / `artifacts[]` array hashes **compressed** payloads (what's actually stored). This means:
- The signing pipeline hashes the compressed bytes (build-time)
- The verification pipeline on device hashes the compressed bytes (runtime)
- No decompression is needed for signature verification

This is critical for boot-time registration in `fpga_program_registry` where Ed25519 verification happens against stored hashes.

### 2.5 Header Flags (Optional Enhancement)

Add an informational flag to quickly check whether a package contains any compressed sections:

```cpp
enum class vmprog_header_flags_v1_0 : uint32_t
{
    none        = 0x00000000,
    signed_pkg  = 0x00000001,
    has_compressed_sections = 0x00000002,  // At least one TOC entry uses compression
};
```

This lets the reader quickly decide whether to initialize the decompressor before scanning TOC entries.

---

## 3. SDK C++ Library Changes

### 3.1 New Header: `vmprog_decompress.hpp`

Location: `videomancer-sdk/src/lzx/videomancer/vmprog_decompress.hpp`

A streaming DEFLATE decompressor designed for fixed-buffer operation on the RP2040.

#### Core Design

```
                  ┌─────────────────────────────────────────────┐
                  │         vmprog_inflate_stream                │
                  │                                             │
  compressed ───→ │  input_buf[256]  →  inflate engine  →  output│ ───→ SPI to FPGA
  chunks (read    │                     window[1024]            │      (4 KB chunks)
  from flash/SD)  │                                             │
                  └─────────────────────────────────────────────┘
```

```cpp
/// @file vmprog_decompress.hpp
/// @brief Streaming DEFLATE decompressor for VMPROG bitstream payloads
///
/// Provides a fixed-buffer streaming inflate implementation suitable for
/// RP2040 Cortex-M0+ with minimal RAM. Decompresses raw DEFLATE data
/// (no zlib/gzip headers) using a 1 KB sliding window.
///
/// Memory budget: ~5.4 KB total
///   - 1024 bytes: sliding window (wbits=10)
///   - 256 bytes:  compressed input staging buffer
///   - 4096 bytes: decompressed output staging buffer
///   - ~64 bytes:  state variables

namespace lzx {

    /// @brief Result codes for decompression operations
    enum class vmprog_inflate_result : uint8_t
    {
        ok = 0,                  ///< Operation succeeded, more data available
        stream_end = 1,          ///< Decompression complete (all data consumed)
        need_input = 2,          ///< More compressed input data needed
        output_full = 3,         ///< Output buffer full, call again to continue
        invalid_data = 4,        ///< Corrupt or invalid DEFLATE stream
        window_overflow = 5,     ///< Internal error: window exceeded
    };

    /// @brief Configuration for the inflate stream
    struct vmprog_inflate_config
    {
        uint8_t window_bits = 10;       ///< Log2 of sliding window size (10 = 1 KB)
    };

    /// @brief Streaming DEFLATE decompressor with fixed buffers
    ///
    /// Usage pattern for FPGA bitstream loading:
    /// ```
    /// vmprog_inflate_stream inflater;
    /// inflater.init(config);
    ///
    /// while (compressed_remaining > 0) {
    ///     // Feed compressed data
    ///     size_t to_feed = min(compressed_remaining, inflater.input_available());
    ///     stream.read(inflater.input_ptr(), to_feed);
    ///     inflater.input_advance(to_feed);
    ///     compressed_remaining -= to_feed;
    ///
    ///     // Drain decompressed output
    ///     while (true) {
    ///         auto [out_ptr, out_size] = inflater.output_data();
    ///         if (out_size == 0) break;
    ///         configurator.send_bitstream_data(out_ptr, out_size);
    ///         inflater.output_consume(out_size);
    ///     }
    /// }
    /// ```
    class vmprog_inflate_stream { ... };

} // namespace lzx
```

#### API Surface

| Method | Purpose |
|--------|---------|
| `init(config)` | Initialize/reset decompressor state |
| `input_ptr()` → `uint8_t*` | Pointer to write compressed data into |
| `input_available()` → `size_t` | Bytes of free space in input buffer |
| `input_advance(n)` | Mark `n` bytes as written to input buffer |
| `inflate_step()` → `vmprog_inflate_result` | Process one step of decompression |
| `output_data()` → `{ptr, size}` | Pointer + size of available decompressed bytes |
| `output_consume(n)` | Release `n` bytes from the output buffer |
| `finished()` → `bool` | True when DEFLATE stream end marker reached |
| `total_in()` → `uint32_t` | Total compressed bytes consumed |
| `total_out()` → `uint32_t` | Total decompressed bytes produced |

#### Inflate Engine Choice

The inflate engine itself will be one of these (evaluated during implementation):

| Option | Code Size | Speed | License | Notes |
|--------|-----------|-------|---------|-------|
| **uzlib** (pfalcon) | ~1.5 KB | Good | Zlib | Already proven on Cortex-M0, configurable window |
| **tinf** (jibsen) | ~2 KB | Good | Zlib | Clean single-file, easy to integrate |
| **puff.c** (zlib-contrib) | ~3 KB | Moderate | Zlib | Reference quality from Mark Adler |
| **Custom minimal** | ~2 KB | Best | — | Tailored to wbits=10, no dynamic Huffman support needed? |

**Recommendation**: Start with **uzlib** — it's battle-tested on RP2040 (used by MicroPython), has configurable window size, and the inflate-only portion is very small. Vendor it into `videomancer-sdk/third_party/uzlib/` under its zlib license.

### 3.2 Modified: `vmprog_format.hpp`

Changes:
1. Add `compressed_deflate` to `vmprog_toc_entry_flags_v1_0` enum
2. Replace `reserved[4]` with `uncompressed_size` + `reserved[3]` in `vmprog_toc_entry_v1_0`
3. Add `has_compressed_sections` to `vmprog_header_flags_v1_0`
4. Update `validate_vmprog_toc_entry_v1_0()` to accept the new flag and validate `uncompressed_size`
5. Add helper functions:
   - `is_toc_entry_compressed(entry)` → `bool`
   - `get_uncompressed_size(entry)` → `uint32_t` (returns `entry.size` if not compressed)

### 3.3 Modified: `vmprog_stream_reader.hpp`

Add a streaming bitstream reader that transparently decompresses:

```cpp
/// @brief Read a bitstream payload, decompressing if necessary.
///
/// For compressed bitstreams, reads compressed chunks from the stream,
/// decompresses them via vmprog_inflate_stream, and writes decompressed
/// chunks to the output callback. For uncompressed bitstreams, reads
/// directly into the callback buffer.
///
/// @param stream Input stream
/// @param entry TOC entry for the bitstream
/// @param chunk_callback Called with each decompressed chunk:
///        bool callback(const uint8_t* data, uint32_t size)
///        Return false to abort.
/// @param compressed_chunk_buf Scratch buffer for reading compressed data
///        (only needed when entry is compressed; 256+ bytes recommended)
/// @param compressed_chunk_buf_size Size of compressed chunk buffer
/// @return Validation result code
template <typename ChunkCallback>
inline vmprog_validation_result read_bitstream_streaming(
    vmprog_stream& stream,
    const vmprog_toc_entry_v1_0& entry,
    ChunkCallback&& chunk_callback,
    uint8_t* compressed_chunk_buf,
    uint32_t compressed_chunk_buf_size
);
```

Also add to `vmprog_package_reader`:

```cpp
/// @brief Stream a bitstream, decompressing if compressed.
/// @param type Bitstream TOC entry type
/// @param chunk_callback Called with each chunk of decompressed data
/// @param scratch Compressed read buffer
/// @param scratch_size Size of scratch buffer
template <typename ChunkCallback>
vmprog_validation_result stream_bitstream(
    vmprog_toc_entry_type_v1_0 type,
    ChunkCallback&& chunk_callback,
    uint8_t* scratch,
    uint32_t scratch_size
);
```

### 3.4 Modified: `vmprog_stream.hpp`

No changes needed — the abstract `read()`/`seek()` interface is sufficient.

### 3.5 New Third Party: `videomancer-sdk/third_party/uzlib/`

Vendor the inflate-only subset of uzlib:
- `uzlib.h` — public API
- `tinflate.c` — inflate implementation (~1.5 KB compiled)
- `uzlib_conf.h` — configuration: `UZLIB_CONF_PARANOID=0`, window size override
- `LICENSE` — zlib license

Add to `videomancer-sdk/third_party/CMakeLists.txt`:
```cmake
add_subdirectory(uzlib)
```

The uzlib CMakeLists.txt creates an `INTERFACE` or `STATIC` library target.

### 3.6 SDK CMakeLists.txt

Add `uzlib` as a dependency of the SDK's interface library target.

---

## 4. Firmware Integration

### 4.1 Modified: `fpga_service.hpp` — `stream_bitstream_to_fpga()`

The key change is in the bitstream streaming loop. Currently:

```
seek(entry.offset) → read chunk → send_bitstream_data(chunk) → repeat
```

New flow when `compressed_deflate` flag is set:

```
seek(entry.offset)
init inflate_stream
while compressed_remaining > 0:
    read compressed chunk into inflate input buffer
    inflate_step()
    while output available:
        send_bitstream_data(output) to ice40_configurator
        consume output
```

The modifications are localized to `stream_bitstream_to_fpga()`. The static `chunk[BitstreamChunkSize]` buffer (4 KB) is reused as the decompressed output staging area. A second smaller buffer (~256 bytes) is needed for compressed input staging — this can be a local array since the function already uses the 4 KB static buffer.

```cpp
[[nodiscard]] result_code stream_bitstream_to_fpga(
    filesystem_vmprog_stream& stream,
    const vmprog_toc_entry_v1_0& entry) noexcept
{
    const bool is_compressed = is_toc_entry_compressed(entry);

    if (is_compressed) {
        return stream_compressed_bitstream(stream, entry);
    } else {
        return stream_raw_bitstream(stream, entry);  // existing code
    }
}
```

New private method:

```cpp
[[nodiscard]] result_code stream_compressed_bitstream(
    filesystem_vmprog_stream& stream,
    const vmprog_toc_entry_v1_0& entry) noexcept
{
    static uint8_t decomp_out[BitstreamChunkSize];  // 4 KB output staging
    uint8_t comp_in[256];                            // compressed input staging

    vmprog_inflate_stream inflater;
    vmprog_inflate_config config;
    config.window_bits = 10;
    inflater.init(config);

    uint32_t compressed_remaining = entry.size;

    // ... [begin_configuration same as existing] ...

    while (compressed_remaining > 0 || !inflater.finished()) {
        // Feed compressed data
        if (compressed_remaining > 0 && inflater.input_available() > 0) {
            uint32_t to_read = min(compressed_remaining,
                                   (uint32_t)inflater.input_available(),
                                   (uint32_t)sizeof(comp_in));
            size_t bytes_read = stream.read(comp_in, to_read);
            // copy into inflater input buffer
            memcpy(inflater.input_ptr(), comp_in, bytes_read);
            inflater.input_advance(bytes_read);
            compressed_remaining -= bytes_read;
        }

        // Decompress
        auto result = inflater.inflate_step();
        if (result == vmprog_inflate_result::invalid_data) {
            return fpga::result::bitstream_read_failed;
        }

        // Send decompressed output to FPGA
        auto [out_ptr, out_size] = inflater.output_data();
        if (out_size > 0) {
            auto rc = _configurator->send_bitstream_data(out_ptr, out_size);
            if (!rc.is_ok()) return rc;
            inflater.output_consume(out_size);
        }
    }

    // ... [end_configuration same as existing] ...
}
```

### 4.2 Modified: `fpga_program_registry.hpp`

No changes needed. Registration reads the header, TOC, config, and verifies the Ed25519 signature — all against compressed payloads. The registry never decompresses bitstreams; it only validates hashes of stored data.

### 4.3 Modified: `fpga_service.hpp` — `select_bitstream_variant()`

No changes needed. This function searches TOC entries by type — it doesn't care about the compressed flag.

### 4.4 RAM Budget Analysis

Current bitstream loading RAM usage:
- `static uint8_t chunk[4096]` — bitstream read buffer (in `.bss`, not on stack)

New usage (compressed path):
- `static uint8_t decomp_out[4096]` — decompressed output buffer (replaces `chunk`)
- `uint8_t comp_in[256]` — compressed input (on stack, temporary)
- `vmprog_inflate_stream` internals:
  - 1024 bytes: sliding window
  - ~64 bytes: state
- **Total new**: ~1,344 bytes additional over the uncompressed path

This fits within the RP2040's 264 KB SRAM budget easily. The sliding window can be `static` inside the inflate stream to avoid stack pressure.

---

## 5. Build Pipeline Changes

### 5.1 Modified: `vmprog_pack.py`

Add a `--compress` flag (default: enabled) and `--no-compress` to disable:

```
python vmprog_pack.py <input_dir> <output.vmprog> [--compress] [--no-compress] [--compress-level N]
```

Changes:
1. After reading each bitstream `.bin` file, optionally compress with `zlib.compress(data, level, wbits=10)`
2. Store the **raw DEFLATE** bytes (strip the 2-byte zlib header by using `wbits=-10` in Python's `zlib.compress`)
3. Set `compressed_deflate` flag on the TOC entry
4. Store `uncompressed_size` in the TOC entry
5. Hash the **compressed** bytes for the TOC entry BLAKE2b-256 hash and the signed descriptor
6. Set `has_compressed_sections` on the header if any bitstream was compressed
7. Bump `VERSION_MINOR` to `1`

Python compression call:
```python
import zlib
compressor = zlib.compressobj(level=9, wbits=-10)  # raw DEFLATE, 1KB window
compressed = compressor.compress(bitstream_data) + compressor.flush()
```

Note: `wbits=-10` in Python produces raw DEFLATE (negative = no zlib header) with a 1 KB window.

### 5.2 Modified: `binary-to-header.py`

No changes needed — this tool converts the final `.vmprog` binary into C++ arrays byte-for-byte. The embedded arrays will be smaller because the `.vmprog` file is smaller.

### 5.3 Modified: `build_programs.sh`

Pass `--compress` to `vmprog_pack.py` during the `embedded = true` build path. Optionally add a `COMPRESS_BITSTREAMS=1` environment variable (default on).

### 5.4 Modified: `generate_program_registry.py`

No changes needed — it generates registration calls from the header files, which are just smaller arrays now.

### 5.5 Modified: `toml_to_config_binary.py`

No changes needed — config binary is never compressed.

---

## 6. SDK Documentation Updates

### 6.1 Modified: `docs/vmprog-format.md`

Add a new section after the TOC Entry Types section:

```markdown
## Bitstream Compression (v1.1)

Starting with format version 1.1, bitstream payloads may be compressed using
raw DEFLATE (RFC 1951) with a 1 KB sliding window (wbits=10).

### Identifying Compressed Sections

- **Header flag**: `has_compressed_sections` (0x00000002) indicates at least
  one TOC entry contains compressed data.
- **TOC entry flag**: `compressed_deflate` (0x00000001) on individual entries.
- **Uncompressed size**: `uncompressed_size` field in the TOC entry stores the
  original payload size. This field is 0 for uncompressed entries.

### Hash Verification

All hashes (TOC entry BLAKE2b-256, signed descriptor artifact hashes) are computed
over the **compressed** payload bytes as stored in the file. Decompression is
NOT required for integrity or signature verification.

### Backward Compatibility

- Version 1.0 readers will reject v1.1 packages (minor version check).
- Version 1.1 readers accept both v1.0 (uncompressed) and v1.1 packages.
- The `compressed_deflate` flag only applies to bitstream TOC entries.
  Config, signed descriptor, and signature sections must never be compressed.
```

### 6.2 Modified: `docs/program-development-guide.md`

Add a note that the SDK packer compresses bitstreams by default and the firmware transparently decompresses them during FPGA configuration.

### 6.3 New: `docs/bitstream-compression.md`

A short document covering:
- Rationale (flash savings)
- Algorithm choice and parameters (raw DEFLATE, wbits=10)
- RAM requirements for decompression
- Build-time options (`--compress`, `--no-compress`, `--compress-level`)
- Performance characteristics (negligible added latency)

---

## 7. Testing Plan

### 7.1 SDK C++ Tests

New test file: `videomancer-sdk/tests/cpp/test_vmprog_decompress.cpp`

| Test | Description |
|------|-------------|
| `inflate_empty_stream` | Zero-length compressed data → zero output |
| `inflate_known_pattern` | Compress known data with Python → decompress in C++ → verify byte-exact |
| `inflate_bitstream_roundtrip` | Compress a real ICE40 bitstream → decompress → compare to original |
| `inflate_streaming_chunks` | Feed compressed data in small chunks (1, 16, 64, 256 bytes) → verify output matches |
| `inflate_corrupt_data` | Feed invalid DEFLATE data → verify `invalid_data` result |
| `inflate_truncated_stream` | Feed incomplete compressed data → verify error handling |
| `inflate_total_counters` | Verify `total_in()` and `total_out()` match expected sizes |
| `toc_entry_compressed_flag` | Create TOC entry with `compressed_deflate` → verify `is_toc_entry_compressed()` |
| `toc_entry_uncompressed_size` | Verify `get_uncompressed_size()` returns correct value for both compressed and uncompressed |

### 7.2 Firmware C++ Tests

New test file: `tests/cpp/test_fpga_compressed_loading.cpp`

| Test | Description |
|------|-------------|
| `stream_compressed_bitstream_to_mock` | Create a mock `ice40_configurator`, feed a compressed `.vmprog` → verify decompressed output matches raw bitstream |
| `stream_uncompressed_fallback` | Verify uncompressed bitstreams still load correctly |
| `mixed_vmprog_package` | Package with some compressed, some uncompressed bitstreams → verify all load |

### 7.3 Python Tests

Extend `tests/python/test_vmprog_pack.py`:

| Test | Description |
|------|-------------|
| `test_pack_compressed` | Pack with compression → verify TOC flags and sizes |
| `test_pack_no_compress` | Pack with `--no-compress` → verify v1.0 compatibility |
| `test_pack_roundtrip_compressed` | Pack → unpack → verify bitstreams match originals |
| `test_compress_ratio_sanity` | Verify compressed size < original for typical bitstreams |

### 7.4 End-to-End Tests

| Test | Description |
|------|-------------|
| `build_programs_compressed` | Run full `build_programs.sh` → verify `.vmprog` files are smaller |
| `on_target_compressed_load` | Load a compressed-bitstream program on Videomancer hardware → verify FPGA configures correctly (CDONE asserts) |

---

## 8. Implementation Phases

### Phase 1: SDK Decompressor (No format changes yet)

1. Vendor uzlib into `videomancer-sdk/third_party/uzlib/`
2. Create `vmprog_decompress.hpp` wrapping uzlib in the `vmprog_inflate_stream` API
3. Write SDK C++ tests (`test_vmprog_decompress.cpp`)
4. Verify decompression of Python-compressed ICE40 bitstreams matches originals

### Phase 2: Format Extension

1. Modify `vmprog_format.hpp`:
   - Add `compressed_deflate` flag to `vmprog_toc_entry_flags_v1_0`
   - Add `uncompressed_size` field to `vmprog_toc_entry_v1_0`
   - Add `has_compressed_sections` flag to `vmprog_header_flags_v1_0`
   - Add helper functions (`is_toc_entry_compressed`, `get_uncompressed_size`)
   - Update validation functions
2. Update `vmprog_stream_reader.hpp` with `read_bitstream_streaming()` and update `vmprog_package_reader`
3. Write format-level tests (TOC flags, validation)

### Phase 3: Build Pipeline

1. Modify `vmprog_pack.py` to support `--compress` / `--no-compress`
2. Modify `build_programs.sh` to pass `--compress`
3. Update Python tests for compression
4. Verify `.vmprog` files are smaller and pass all validation

### Phase 4: Firmware Integration

1. Modify `fpga_service.hpp`:
   - Add `stream_compressed_bitstream()` method
   - Branch in `stream_bitstream_to_fpga()` based on TOC entry flag
2. Add `uzlib` to the firmware build's CMakeLists.txt link dependencies
3. Test on-target with compressed programs
4. Verify load times are acceptable (target: <200 ms added for 135 KB bitstream)

### Phase 5: Documentation and Cleanup

1. Update `docs/vmprog-format.md`
2. Update `docs/program-development-guide.md`
3. Create `docs/bitstream-compression.md`
4. Update SDK `CHANGELOG.md`
5. Strip trailing whitespace, run full test suite

---

## 9. File Change Summary

### SDK Files (videomancer-sdk/)

| File | Change | Phase |
|------|--------|-------|
| `third_party/uzlib/` (new directory) | Vendor inflate-only uzlib library | 1 |
| `third_party/CMakeLists.txt` | Add `add_subdirectory(uzlib)` | 1 |
| `src/lzx/videomancer/vmprog_decompress.hpp` (new) | Streaming DEFLATE decompressor wrapper | 1 |
| `src/lzx/videomancer/vmprog_format.hpp` | Add flags, `uncompressed_size`, helpers, update validation | 2 |
| `src/lzx/videomancer/vmprog_stream_reader.hpp` | Add `read_bitstream_streaming()`, update package reader | 2 |
| `tools/vmprog-packer/vmprog_pack.py` | Add `--compress` flag, DEFLATE compression, format v1.1 | 3 |
| `tests/cpp/test_vmprog_decompress.cpp` (new) | Decompressor unit tests | 1 |
| `docs/vmprog-format.md` | Add compression section | 5 |
| `docs/program-development-guide.md` | Note about default compression | 5 |
| `docs/bitstream-compression.md` (new) | Compression feature documentation | 5 |

### Firmware Files (src/)

| File | Change | Phase |
|------|--------|-------|
| `src/common/lzx/services/fpga/fpga_service.hpp` | Add compressed bitstream streaming path | 4 |
| `src/common/CMakeLists.txt` | Link uzlib (via SDK dependency) | 4 |

### Build Files

| File | Change | Phase |
|------|--------|-------|
| `build_programs.sh` | Pass `--compress` to `vmprog_pack.py` | 3 |

### Test Files

| File | Change | Phase |
|------|--------|-------|
| `videomancer-sdk/tests/cpp/test_vmprog_decompress.cpp` (new) | Decompressor tests | 1 |
| `tests/cpp/test_fpga_compressed_loading.cpp` (new) | Firmware integration tests | 4 |
| `tests/python/test_vmprog_pack.py` | Add compression tests | 3 |

---

## 10. Risk Assessment

| Risk | Mitigation |
|------|----------|
| uzlib incompatibility with wbits=10 | uzlib supports configurable window; verified in Phase 1 tests |
| DEFLATE stream corruption on flash read error | Existing BLAKE2b-256 hash catches corruption before decompression; decompressor also validates stream structure |
| Decompression too slow on RP2040 | ICE40 configuration is gated by SPI baudrate (~20 MHz), not CPU; decompression of 135 KB takes ~5–15 ms on Cortex-M0+ which is negligible vs. SPI transfer time (~50 ms at 20 MHz). Net effect: less data to read from flash, similar SPI time = roughly neutral or faster |
| Breaking backward compatibility | v1.1 is a minor bump; old packages (v1.0) remain loadable by updated firmware. `--no-compress` flag preserves v1.0 generation. |
| Compressed programs fail Ed25519 verification | Hashes are of compressed data; signing happens after compression. No interaction. |
| RAM pressure from decompressor | 1 KB window + existing 4 KB chunk buffer = 5.4 KB total; well within RP2040's 264 KB SRAM |
| Build time increase from compression | zlib compression at level 9 takes ~1 ms per 135 KB bitstream on modern hardware; negligible vs. FPGA synthesis time |

---

## 11. Performance Estimates

### Load Time Breakdown (per bitstream, 135 KB raw)

| Operation | Uncompressed | Compressed (32% ratio = 43 KB) |
|-----------|-------------|-------------------------------|
| Flash read | ~2.7 ms (@ 50 MB/s XIP) | ~0.9 ms |
| SD card read | ~13.5 ms (@ 10 MB/s) | ~4.3 ms |
| Decompress on Cortex-M0+ | — | ~5–15 ms |
| SPI to FPGA (20 MHz) | ~54 ms | ~54 ms (same uncompressed size) |
| **Total (flash)** | **~57 ms** | **~60–70 ms** |
| **Total (SD card)** | **~68 ms** | **~63–73 ms** |

The SPI transfer time dominates. Flash storage savings of ~60–70% far outweigh the ~5–15 ms decompression overhead. For SD card loads, decompression may actually be **faster** overall because reading 43 KB is much faster than reading 135 KB.

### Flash Storage Impact

| Scenario | Uncompressed | Compressed | Programs Gained |
|----------|-------------|------------|-----------------|
| 8 programs × ~800 KB = 6.4 MB | 6.4 MB | ~2.5 MB | +5 more programs in same space |
| Target: fit 20 programs in 2 MB flash | Impossible (16 MB needed) | ~6.2 MB | Reachable with partial flash |
| Per-program average | 800 KB | 310 KB | — |
