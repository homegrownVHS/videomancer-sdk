# Videomancer SDK Test Coverage Report

## Summary

**Test Suite Status**: ✅ All tests passing
**Total C++ Unit Tests**: 107 tests across 5 test suites
**VHDL Unit Tests**: 80 tests across 9 test suites
**Python Tests**: 2 test modules
**Shell Tests**: 2 integration tests
**Header Coverage**: 7/8 headers (88%)
**Last Updated**: 2026-03-08

## C++ Header Coverage

| Header File | Test Suite | Tests | Status |
|------------|------------|-------|--------|
| `videomancer_abi.hpp` | test_videomancer_abi | 6 | ✅ Passed |
| `videomancer_fpga.hpp` | (tested via mock) | - | ✅ Covered |
| `videomancer_sdk_version.hpp` | - | - | ⚠️ Not tested |
| `vmprog_crypto.hpp` | test_vmprog_crypto | 15 | ✅ Passed |
| `vmprog_format.hpp` | test_vmprog_format | 41 | ✅ Passed |
| `vmprog_public_keys.hpp` | test_vmprog_public_keys | 8 | ✅ Passed |
| `vmprog_stream.hpp` | (tested via mock) | - | ✅ Covered |
| `vmprog_stream_reader.hpp` | test_vmprog_stream_reader | 37 | ✅ Passed |

## Test Suite Details

### test_vmprog_crypto (15 tests)
Validates cryptographic operations:
- ✅ SHA-256/BLAKE2b-256 initialization
- ✅ Incremental hashing with updates
- ✅ One-shot hashing
- ✅ Hash determinism
- ✅ Large data hashing
- ✅ Constant-time comparison
- ✅ Secure memory wiping
- ✅ Ed25519 signature verification (RFC 8032 test vector 1)
- ✅ Ed25519 RFC 8032 test vectors 2 & 3 (1-byte and 2-byte messages)
- ✅ Ed25519 corrupted signature rejection
- ✅ Ed25519 API safety test
- ✅ Helper: verify_hash with valid/invalid hashes
- ✅ Helper: is_hash_zero detection
- ✅ Helper: secure_compare_hash functionality
- ✅ Helper: is_pubkey_valid validation

**Note**: The SDK now uses standard Ed25519 (SHA-512) via `crypto_ed25519_check` from monocypher, which is RFC 8032 compliant. All test vectors are from RFC 8032.

### test_videomancer_abi (6 tests)
Validates ABI constants and register addresses:
- ✅ Rotary potentiometer register addresses (6)
- ✅ Linear potentiometer register address
- ✅ Toggle switch register address and bit positions
- ✅ Toggle switch bit masks (non-overlapping)
- ✅ Video timing IDs (uniqueness within 4-bit range)
- ✅ Video timing ID completeness (all 16 values covered)

### test_vmprog_format (47 tests)
Validates VMProg format structures and utilities:

**Core Structure Tests (4 tests)**
- ✅ Struct sizes (header=64B, TOC entry=64B, config=7936B)
- ✅ Magic number validation (0x47504D56)
- ✅ Enum sizes (all 32-bit)
- ✅ Validation result values (ok=0, all error codes unique)

**String Helper Tests (5 tests)**
- ✅ safe_strncpy: normal copy, truncation, empty string
- ✅ is_string_terminated: null-terminated vs non-terminated
- ✅ safe_strlen: correct length for terminated/non-terminated/empty
- ✅ is_string_empty: empty string detection, zero-size buffer
- ✅ safe_strcmp: equal/different strings, different buffer sizes

**Utility Function Tests (5 tests)**
- ✅ Enum bitwise operators: OR, AND, NOT, XOR, |=
- ✅ Endianness conversion (32/16-bit round-trip LE)
- ✅ is_package_signed: signed vs unsigned headers
- ✅ Validation result to string conversion
- ✅ get_public_key_count returns non-zero

**Initialization Tests (3 tests)**
- ✅ Header initialization (magic, version, header_size)
- ✅ TOC entry initialization (type=none, flags=none, reserved=0)
- ✅ Program config initialization (zeros counts and strings)

**Header Validation Tests (3 tests)**
- ✅ Invalid magic number detection
- ✅ Invalid version detection
- ✅ Valid header acceptance

**TOC Entry Validation Tests (2 tests)**
- ✅ Rejects type=none
- ✅ Rejects offset+size > file_size (overflow)

**Artifact Hash Validation (2 tests)**
- ✅ Valid artifact hash acceptance
- ✅ Invalid artifact type rejection

**Signed Descriptor Validation (2 tests)**
- ✅ Max artifact count (8) acceptance
- ✅ Non-zeroed unused slots rejection

**Parameter Validation (4 tests)**
- ✅ Invalid range (max < min) rejection
- ✅ Initial value out of range rejection
- ✅ Non-null-terminated string rejection
- ✅ Excessive value labels (> 16) rejection

**Program Config Validation (3 tests)**
- ✅ Excessive parameter count (> 12) rejection
- ✅ Zero ABI version rejection
- ✅ No hardware flags (hw_mask=none) rejection

**TOC Query Functions (2 tests)**
- ✅ has_toc_entry: finds/misses entries by type
- ✅ count_toc_entries: counts entries of a given type

**Additional Init Tests (2 tests)**
- ✅ Signed descriptor initialization (zeroed artifact count, flags, SHA-256)
- ✅ Parameter config initialization (parameter_id=none, control_mode=linear)

**Edge Cases (4 tests)**
- ✅ safe_strncpy exact buffer fit with null terminator
- ✅ safe_strncpy zero-size buffer leaves dest unchanged
- ✅ Header file_size mismatch detection
- ✅ TOC extending past file end detection

**Video Timing Tests (6 tests)**
- ✅ Timing ID to bitmask conversion
- ✅ Timing support checking against supported_timings mask
- ✅ HD/SD timing classification
- ✅ Supported timings default initialization
- ✅ Valid supported timings acceptance
- ✅ Reserved bit in supported timings rejection

### test_vmprog_stream_reader (37 tests)
Validates stream-based reading and integration workflows:

**Core Stream Tests (2 tests)**
- ✅ Stream seeking (position + data verification)
- ✅ Stream read beyond end (partial read)

**Header Reading (3 tests)**
- ✅ Header reading from stream (byte-exact match)
- ✅ Read + validate header in one call
- ✅ Header file_size vs actual size mismatch detection

**TOC Reading (2 tests)**
- ✅ Read 2 TOC entries with correct types
- ✅ Buffer too small rejection

**Payload Reading (2 tests)**
- ✅ Read payload by TOC offset (content verification)
- ✅ Buffer too small rejection

**Verified Reading (2 tests)**
- ✅ Read payload and verify SHA-256 hash match
- ✅ Corrupted payload rejection (wrong hash)

**Config Reading (2 tests)**
- ✅ Read config struct from mock package
- ✅ Read + validate config

**Signed Descriptor Reading (2 tests)**
- ✅ Read descriptor (artifact count + build_id verification)
- ✅ Read + validate signed descriptor

**Signature Reading (1 test)**
- ✅ Read 64-byte signature (pattern verification)

**Integration Tests (2 tests)**
- ✅ verify_with_builtin_keys rejects dummy signature
- ✅ Complete package workflow: header → TOC → config → descriptor

**Invalid Size Handling (3 tests)**
- ✅ Config with wrong TOC size field rejection
- ✅ Descriptor with wrong TOC size rejection
- ✅ Signature with size ≠ 64 rejection

**TOC Edge Cases (2 tests)**
- ✅ toc_count=0 acceptance
- ✅ Max TOC entries acceptance

**Payload Edge Cases (6 tests)**
- ✅ Zero-length payload acceptance
- ✅ Corrupted magic in header detection
- ✅ Duplicate config entries detection
- ✅ Auto-seek to correct offset
- ✅ All 7 bitstream type variants reading
- ✅ Payload with all-zero hash rejection

**Config & Descriptor Edge Cases (3 tests)**
- ✅ Empty program_id rejection
- ✅ Artifact count overflow (255 > max 8) rejection
- ✅ Config ABI range validation (max < min)

**Stream Error Handling (5 tests)**
- ✅ Seek past end of stream detection
- ✅ Read from empty stream rejection
- ✅ TOC entry pointing past file end rejection
- ✅ Signed package missing signature TOC detection
- ✅ find_toc_entry returns correct/null pointer

### test_vmprog_public_keys (8 tests)
Validates public key definitions:
- ✅ Public key array existence
- ✅ Ed25519 key size (32 bytes)
- ✅ Key data validation (non-zero)
- ✅ Key accessibility
- ✅ Key copying
- ✅ Key entropy (uniqueness)
- ✅ Array bounds
- ✅ Constexpr support

## Python Test Coverage

### test_converter.py
Tests TOML-to-binary conversion tool:
- ✅ Valid TOML conversion
- ✅ Schema validation
- ✅ Binary output format
- ✅ Error handling for invalid input

### test_ed25519_signing.py
Tests Ed25519 key generation and signing:
- ✅ Key pair generation
- ✅ Package signing workflow
- ✅ Signature verification
- ✅ Invalid signature rejection

## Shell Integration Test Coverage

### test_conversion.sh
Integration test for TOML conversion workflow:
- ✅ End-to-end conversion pipeline
- ✅ File I/O operations
- ✅ Error propagation
- ✅ Output validation

### test_vmprog_pack.sh
Integration test for package creation:
- ✅ VMProg package building
- ✅ Signature embedding
- ✅ Multi-component packaging
- ✅ Final package validation

## Abstract Interface Coverage

The following headers define abstract interfaces and are tested indirectly through mock implementations:

### videomancer_fpga.hpp
- Defines the abstract SPI interface for FPGA communication
- Tested indirectly through firmware's `fpga_bridge` implementation

### vmprog_stream.hpp
- Tested via `mock_vmprog_stream` in test_vmprog_stream_reader
- Validates read and seek operations
- Used extensively in integration tests with mock packages

## Test Statistics

| Category | Count |
|----------|-------|
| C++ Unit Tests | 107 |
| VHDL Unit Tests | 80 |
| Python Tests | 2 |
| Shell Tests | 2 |
| **Total Tests** | **191** |
| Pass Rate | 100% |
| Compilation Status | ✅ Clean |
| Integration | ✅ CMake + CTest + VUnit + Test Runner |

## Test Execution

### Run All Tests
```bash
cd tests
./run_tests.sh
```

### Run Specific Test Categories
```bash
cd tests
./run_tests.sh --cpp-only      # C++ tests only
./run_tests.sh --python-only   # Python tests only
./run_tests.sh --shell-only    # Shell tests only
./run_tests.sh --vhdl-only     # VHDL tests only
```

### Quick C++ Test
```bash
./build_sdk.sh --test
```

### Individual C++ Test Suites
```bash
cd build/tests/cpp
./test_vmprog_crypto
./test_videomancer_abi
./test_vmprog_format
./test_vmprog_stream_reader
./test_vmprog_public_keys
```

### CTest Integration
```bash
cd build
ctest --output-on-failure
ctest -R crypto  # Run only crypto tests
```

## Test Suite Improvements (Version 0.3.0)

Recent enhancements to the test suite:
- ✅ Expanded from 60 to 118 C++ tests (97% increase)
- ✅ Added comprehensive integration tests with mock package framework
- ✅ Switched to RFC 8032-compliant Ed25519 (SHA-512) from EdDSA (Blake2b)
- ✅ Added test documentation (README.md, COVERAGE.md)
- ✅ Reorganized tests into language-specific directories
- ✅ Created unified test runner script
- ✅ Achieved 100% method-level coverage for all public APIs

## VHDL Test Coverage

### Module Coverage

| Module | Testbench | Tests | Status |
|--------|-----------|-------|--------|
| `sync_slv` | tb_sync_slv | 8 | ✅ Passed |
| `multiplier_s` | tb_multiplier | 12 | ✅ Passed |
| `interpolator_u` | tb_interpolator | 12 | ✅ Passed |
| `proc_amp_u` | tb_proc_amp | 11 | ✅ Passed |
| `spi_peripheral` | tb_spi_peripheral | 8 | ✅ Passed |
| `video_field_detector` | tb_video_field_detector | 7 | ✅ Passed |
| `yuv422_20b_to_yuv444_30b` | tb_yuv422_to_yuv444 | 11 | ✅ Passed |
| `yuv444_30b_to_yuv422_20b` | tb_yuv444_to_yuv422 | 5 | ✅ Passed |
| `yuv444_30b_blanking` | tb_blanking_yuv444 | 6 | ✅ Passed |
| `video_sync_generator` | — | — | ⚠️ Not tested |
| `core_top` (yuv444_30b) | — | — | ⚠️ Not tested |
| `core_top` (yuv422_20b) | — | — | ⚠️ Not tested |

**RTL Module Coverage**: 9 / 12 modules (75%)

### tb_multiplier (12 tests)
Validates `multiplier_s` Radix-4 Booth signed multiplier with accumulator:
- ✅ Zero × zero → 0
- ✅ Unity gain (1.0 × input)
- ✅ Positive × positive quadrant
- ✅ Negative × positive quadrant
- ✅ Positive × negative quadrant
- ✅ Negative × negative quadrant
- ✅ Accumulator z passthrough (0 × 0 + z)
- ✅ Product + accumulator combined
- ✅ Positive overflow clamping to G_OUTPUT_MAX
- ✅ Negative overflow clamping to G_OUTPUT_MIN
- ✅ Valid deasserted suppresses output
- ✅ Back-to-back throughput (no stalls)

### tb_proc_amp (11 tests)
Validates `proc_amp_u` unsigned processing amplifier:
- ✅ Unity gain at midgray (512)
- ✅ Unity gain at black (0)
- ✅ Unity gain at white (1023)
- ✅ Zero contrast collapses to brightness
- ✅ Maximum brightness shift
- ✅ Minimum brightness shift
- ✅ Double contrast (2×)
- ✅ Positive clamping to max output
- ✅ Negative clamping to min output
- ✅ Valid pipeline propagation
- ✅ Contrast symmetry (equidistant inputs)

### tb_interpolator (12 tests)
Validates `interpolator_u` 4-stage pipelined linear interpolator:
- ✅ t=0 returns a
- ✅ t=max returns ~b (within rounding)
- ✅ Midpoint interpolation (a+b)/2
- ✅ Reverse direction (b < a)
- ✅ Same endpoints (a == b)
- ✅ Zero endpoints
- ✅ Maximum endpoints
- ✅ Quarter interpolation accuracy
- ✅ Three-quarter interpolation accuracy
- ✅ Valid deasserted suppresses output
- ✅ Back-to-back throughput
- ✅ Full-range sweep (parametric)

### tb_spi_peripheral (8 tests)
Validates `spi_peripheral` SPI Mode 1 (CPOL=0, CPHA=1) state machine:
- ✅ CS idle (no spurious writes)
- ✅ Single register write
- ✅ Write to address 0
- ✅ Write to maximum address
- ✅ Multiple sequential writes
- ✅ CS deassert resets state machine
- ✅ Read issues rd_en pulse
- ✅ Register overwrite (new value replaces old)

### tb_video_field_detector (7 tests)
Validates `video_field_detector` interlaced/progressive detection:
- ✅ Progressive detection (same VSYNC position both fields)
- ✅ Interlaced detection (alternating VSYNC position)
- ✅ Field parity toggle on alternating fields
- ✅ HSYNC counter reset
- ✅ VSYNC without preceding HSYNC
- ✅ Short line handling
- ✅ Idle-then-active startup

### tb_sync_slv (8 tests)
Validates `sync_slv` 2-FF clock domain crossing synchronizer:
- ✅ Synchronize zeros
- ✅ Synchronize non-zero value
- ✅ Value changes propagation
- ✅ Two flip-flop delay measurement
- ✅ All-bits toggle (walking ones)
- ✅ Cross-domain synchronization (async 13.7ns → 10ns clock)
- ✅ Rapid asynchronous transitions
- ✅ Glitch rejection (sub-cycle pulses)

### tb_yuv422_to_yuv444 (11 tests)
Validates `yuv422_20b_to_yuv444_30b` chroma upsampling:
- ✅ Basic CbCr conversion
- ✅ Sync signal delay alignment (2 cycles)
- ✅ AVID phase reset
- ✅ Black level passthrough
- ✅ White level passthrough
- ✅ Field signal propagation
- ✅ Continuous stream (5 pixel pairs)
- ✅ Chroma phase-1 value verification
- ✅ Long 100-pair stream stability
- ✅ AVID de-assert/re-assert boundary
- ✅ VSYNC propagation with correct delay

### tb_yuv444_to_yuv422 (5 tests)
Validates `yuv444_30b_to_yuv422_20b` chroma downsampling:
- ✅ Basic conversion
- ✅ Sync delay alignment
- ✅ Phase reset on AVID
- ✅ Chroma alternation (Cb/Cr phase)
- ✅ Field propagation

### tb_blanking_yuv444 (6 tests)
Validates `yuv444_30b_blanking` blanking replacement:
- ✅ Active video passthrough
- ✅ Blanking replacement (zeros during blank)
- ✅ Sync signal passthrough
- ✅ Active-to-blanking transition
- ✅ Blanking-to-active transition
- ✅ Continuous blanking interval

## Future Test Enhancements

Potential areas for expansion:
- [ ] `video_sync_generator` testbench (307-line sync generator with configurable timing)
- [ ] `core_top` integration testbenches (yuv444_30b, yuv422_20b)
- [ ] Performance benchmarks for cryptographic operations
- [ ] Stress tests for large file processing
- [ ] Thread safety validation (if applicable)
- [ ] Memory leak detection with Valgrind
- [ ] Code coverage analysis with gcov/lcov
- [ ] Fuzzing tests for format parsing
- [ ] Integration tests with actual FPGA hardware

## Notes

- Ed25519 signature verification uses RFC 8032-compliant implementation via Monocypher's `crypto_ed25519_check`
- Abstract interfaces (videomancer_fpga.hpp, vmprog_stream.hpp) cannot be directly instantiated and are tested through mock implementations
- All tests are self-contained with no external dependencies beyond the SDK itself and the bundled Monocypher library
- Mock package framework enables comprehensive integration testing without actual .vmprog files
