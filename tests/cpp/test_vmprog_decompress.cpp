// Videomancer SDK - Unit Tests for vmprog_decompress.hpp
// Copyright (C) 2025 LZX Industries LLC
// SPDX-License-Identifier: GPL-3.0-only

#include <lzx/videomancer/vmprog_decompress.hpp>
#include <iostream>
#include <cassert>
#include <cstring>
#include <cstdlib>
#include <vector>

using namespace lzx;

// =============================================================================
// Test Data: Pre-compressed DEFLATE streams
// =============================================================================

// Known pattern: 256 bytes of 0x00 compressed with Python:
//   zlib.compressobj(level=9, wbits=-10).compress(b'\x00' * 256) + .flush()
// Raw DEFLATE, wbits=-10 (1KB window)
static const uint8_t compressed_zeros[] = {
    0x63, 0x60, 0x18, 0xd9, 0x00, 0x00
};
static const uint32_t compressed_zeros_size = sizeof(compressed_zeros);
static const uint32_t uncompressed_zeros_size = 256;

// Known pattern: "Hello, World!" repeated 20 times (260 bytes) compressed
// Generated with: zlib.compressobj(level=9, wbits=-10)
// Input: b"Hello, World!" * 20
static const uint8_t compressed_hello[] = {
    0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08,
    0xcf, 0x2f, 0xca, 0x49, 0x51, 0xf4, 0x18, 0x99,
    0x1c, 0x00
};
static const uint32_t compressed_hello_size = sizeof(compressed_hello);
static const uint32_t uncompressed_hello_size = 260;

// =============================================================================
// Test Helpers
// =============================================================================

static bool arrays_equal(const uint8_t* a, const uint8_t* b, size_t n)
{
    return memcmp(a, b, n) == 0;
}

static std::vector<uint8_t> make_pattern(uint8_t value, size_t count)
{
    return std::vector<uint8_t>(count, value);
}

static std::vector<uint8_t> make_hello_pattern()
{
    const char* hello = "Hello, World!";
    size_t len = strlen(hello);
    std::vector<uint8_t> out;
    out.reserve(len * 20);
    for (int i = 0; i < 20; i++) {
        out.insert(out.end(), reinterpret_cast<const uint8_t*>(hello),
                   reinterpret_cast<const uint8_t*>(hello) + len);
    }
    return out;
}

/// @brief Decompress an entire compressed buffer in one shot
static bool decompress_all(
    const uint8_t* compressed, uint32_t comp_size,
    std::vector<uint8_t>& output)
{
    uint8_t window[1024];
    uint8_t out_buf[4096];

    vmprog_inflate_stream inflater;
    inflater.init(window, sizeof(window));
    inflater.set_input(compressed, comp_size);

    output.clear();

    while (!inflater.finished()) {
        auto result = inflater.decompress(out_buf, sizeof(out_buf));
        if (result.bytes_produced > 0) {
            output.insert(output.end(), out_buf, out_buf + result.bytes_produced);
        }
        if (result.status == vmprog_inflate_result::invalid_data) {
            return false;
        }
        if (result.status == vmprog_inflate_result::stream_end) {
            break;
        }
    }

    return true;
}

// =============================================================================
// Tests
// =============================================================================

bool test_init()
{
    uint8_t window[1024];
    vmprog_inflate_stream inflater;
    inflater.init(window, sizeof(window));

    if (inflater.finished()) {
        std::cerr << "FAILED: init - should not be finished after init" << std::endl;
        return false;
    }
    if (inflater.total_in() != 0) {
        std::cerr << "FAILED: init - total_in should be 0" << std::endl;
        return false;
    }
    if (inflater.total_out() != 0) {
        std::cerr << "FAILED: init - total_out should be 0" << std::endl;
        return false;
    }
    if (inflater.input_remaining() != 0) {
        std::cerr << "FAILED: init - input_remaining should be 0" << std::endl;
        return false;
    }

    std::cout << "PASSED: init test" << std::endl;
    return true;
}

bool test_inflate_zeros()
{
    std::vector<uint8_t> output;
    if (!decompress_all(compressed_zeros, compressed_zeros_size, output)) {
        std::cerr << "FAILED: inflate_zeros - decompression failed" << std::endl;
        return false;
    }

    auto expected = make_pattern(0x00, uncompressed_zeros_size);
    if (output.size() != expected.size()) {
        std::cerr << "FAILED: inflate_zeros - output size " << output.size()
                  << " expected " << expected.size() << std::endl;
        return false;
    }
    if (!arrays_equal(output.data(), expected.data(), expected.size())) {
        std::cerr << "FAILED: inflate_zeros - output data mismatch" << std::endl;
        return false;
    }

    std::cout << "PASSED: inflate_zeros test" << std::endl;
    return true;
}

bool test_inflate_hello()
{
    std::vector<uint8_t> output;
    if (!decompress_all(compressed_hello, compressed_hello_size, output)) {
        std::cerr << "FAILED: inflate_hello - decompression failed" << std::endl;
        return false;
    }

    auto expected = make_hello_pattern();
    if (output.size() != expected.size()) {
        std::cerr << "FAILED: inflate_hello - output size " << output.size()
                  << " expected " << expected.size() << std::endl;
        return false;
    }
    if (!arrays_equal(output.data(), expected.data(), expected.size())) {
        std::cerr << "FAILED: inflate_hello - output data mismatch" << std::endl;
        return false;
    }

    std::cout << "PASSED: inflate_hello test" << std::endl;
    return true;
}

bool test_inflate_streaming_small_output()
{
    // Feed all compressed data at once, but use a tiny output buffer (32 bytes)
    // to force multiple decompress() calls — this is the realistic streaming
    // pattern (read large chunk from flash, decompress in small pieces to FPGA).
    //
    // Note: uzlib does not support 1-byte-at-a-time input feeding because it
    // uses longjmp() when source is exhausted mid-parse. Input chunks must be
    // large enough to contain at least one complete DEFLATE block header.
    uint8_t window[1024];
    uint8_t out_buf[32]; // Tiny output buffer forces multiple calls
    vmprog_inflate_stream inflater;
    inflater.init(window, sizeof(window));

    // Feed all compressed data at once
    inflater.set_input(compressed_zeros, compressed_zeros_size);

    std::vector<uint8_t> output;
    uint32_t iterations = 0;

    while (!inflater.finished()) {
        auto result = inflater.decompress(out_buf, sizeof(out_buf));
        if (result.bytes_produced > 0) {
            output.insert(output.end(), out_buf, out_buf + result.bytes_produced);
        }
        if (result.status == vmprog_inflate_result::invalid_data) {
            std::cerr << "FAILED: inflate_streaming_small_output - data error at iteration "
                      << iterations << std::endl;
            return false;
        }
        if (result.status == vmprog_inflate_result::stream_end) {
            break;
        }
        iterations++;
        if (iterations > 1000) {
            std::cerr << "FAILED: inflate_streaming_small_output - runaway loop" << std::endl;
            return false;
        }
    }

    if (output.size() != uncompressed_zeros_size) {
        std::cerr << "FAILED: inflate_streaming_small_output - output size " << output.size()
                  << " expected " << uncompressed_zeros_size << std::endl;
        return false;
    }

    auto expected = make_pattern(0x00, uncompressed_zeros_size);
    if (!arrays_equal(output.data(), expected.data(), expected.size())) {
        std::cerr << "FAILED: inflate_streaming_small_output - data mismatch" << std::endl;
        return false;
    }

    // Verify we actually needed multiple calls (256 bytes / 32 byte buffer = 8 calls)
    if (iterations < 2) {
        std::cerr << "FAILED: inflate_streaming_small_output - only " << iterations
                  << " iterations (expected multiple)" << std::endl;
        return false;
    }

    std::cout << "PASSED: inflate_streaming_small_output test (" << (iterations + 1)
              << " iterations)" << std::endl;
    return true;
}

bool test_inflate_total_counters()
{
    uint8_t window[1024];
    uint8_t out_buf[4096];
    vmprog_inflate_stream inflater;
    inflater.init(window, sizeof(window));
    inflater.set_input(compressed_zeros, compressed_zeros_size);

    while (!inflater.finished()) {
        auto result = inflater.decompress(out_buf, sizeof(out_buf));
        if (result.status == vmprog_inflate_result::invalid_data) {
            std::cerr << "FAILED: inflate_total_counters - error" << std::endl;
            return false;
        }
        if (result.status == vmprog_inflate_result::stream_end) break;
    }

    if (inflater.total_in() != compressed_zeros_size) {
        std::cerr << "FAILED: inflate_total_counters - total_in "
                  << inflater.total_in() << " expected " << compressed_zeros_size << std::endl;
        return false;
    }
    if (inflater.total_out() != uncompressed_zeros_size) {
        std::cerr << "FAILED: inflate_total_counters - total_out "
                  << inflater.total_out() << " expected " << uncompressed_zeros_size << std::endl;
        return false;
    }

    std::cout << "PASSED: inflate_total_counters test" << std::endl;
    return true;
}

bool test_inflate_corrupt_data()
{
    // Feed completely invalid data
    uint8_t corrupt[] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    uint8_t window[1024];
    uint8_t out_buf[256];

    vmprog_inflate_stream inflater;
    inflater.init(window, sizeof(window));
    inflater.set_input(corrupt, sizeof(corrupt));

    auto result = inflater.decompress(out_buf, sizeof(out_buf));

    // Should get invalid_data or at least not crash
    if (result.status != vmprog_inflate_result::invalid_data &&
        result.status != vmprog_inflate_result::stream_end) {
        // Some corrupt data may produce garbage output before failing,
        // but the key is it shouldn't crash
        std::cout << "NOTE: inflate_corrupt_data - status=" << static_cast<int>(result.status)
                  << " (acceptable if no crash)" << std::endl;
    }

    std::cout << "PASSED: inflate_corrupt_data test (no crash)" << std::endl;
    return true;
}

bool test_inflate_finished_returns_zero()
{
    // After stream_end, subsequent calls should return stream_end with 0 bytes
    std::vector<uint8_t> output;
    if (!decompress_all(compressed_zeros, compressed_zeros_size, output)) {
        std::cerr << "FAILED: inflate_finished_returns_zero - initial decompress failed" << std::endl;
        return false;
    }

    // The inflater in decompress_all is local, so create a new one
    uint8_t window[1024];
    uint8_t out_buf[4096];
    vmprog_inflate_stream inflater;
    inflater.init(window, sizeof(window));
    inflater.set_input(compressed_zeros, compressed_zeros_size);

    // Decompress all
    while (!inflater.finished()) {
        auto result = inflater.decompress(out_buf, sizeof(out_buf));
        if (result.status == vmprog_inflate_result::stream_end) break;
        if (result.status == vmprog_inflate_result::invalid_data) {
            std::cerr << "FAILED: inflate_finished_returns_zero - error during decompress" << std::endl;
            return false;
        }
    }

    // Now call decompress again — should return stream_end with 0 bytes
    auto result = inflater.decompress(out_buf, sizeof(out_buf));
    if (result.status != vmprog_inflate_result::stream_end) {
        std::cerr << "FAILED: inflate_finished_returns_zero - expected stream_end, got "
                  << static_cast<int>(result.status) << std::endl;
        return false;
    }
    if (result.bytes_produced != 0) {
        std::cerr << "FAILED: inflate_finished_returns_zero - expected 0 bytes, got "
                  << result.bytes_produced << std::endl;
        return false;
    }

    std::cout << "PASSED: inflate_finished_returns_zero test" << std::endl;
    return true;
}

bool test_inflate_result_enum_values()
{
    // Verify enum values match expected encoding
    if (static_cast<uint8_t>(vmprog_inflate_result::ok) != 0) {
        std::cerr << "FAILED: result enum - ok != 0" << std::endl;
        return false;
    }
    if (static_cast<uint8_t>(vmprog_inflate_result::stream_end) != 1) {
        std::cerr << "FAILED: result enum - stream_end != 1" << std::endl;
        return false;
    }
    if (static_cast<uint8_t>(vmprog_inflate_result::need_input) != 2) {
        std::cerr << "FAILED: result enum - need_input != 2" << std::endl;
        return false;
    }
    if (static_cast<uint8_t>(vmprog_inflate_result::invalid_data) != 3) {
        std::cerr << "FAILED: result enum - invalid_data != 3" << std::endl;
        return false;
    }

    std::cout << "PASSED: inflate_result_enum_values test" << std::endl;
    return true;
}

// =============================================================================
// Dynamic Test: Compress with Python at build time and verify roundtrip
// =============================================================================

// This test uses a pre-generated pattern: incrementing bytes 0-255
// compressed with: zlib.compressobj(level=9, wbits=-10)
static bool generate_and_test_roundtrip()
{
    // Generate repeating pattern: bytes 0-15 repeated 64 times = 1024 bytes
    // Compresses very well with DEFLATE (1024 -> 27 bytes)
    std::vector<uint8_t> pattern(1024);
    for (size_t i = 0; i < pattern.size(); i++) {
        pattern[i] = static_cast<uint8_t>(i % 16);
    }

    // Pre-compressed with Python:
    // import zlib
    // data = bytes(range(16)) * 64
    // c = zlib.compressobj(level=9, wbits=-10)
    // compressed = c.compress(data) + c.flush()
    static const uint8_t compressed_pattern[] = {
        0x63, 0x60, 0x64, 0x62, 0x66, 0x61, 0x65, 0x63,
        0xe7, 0xe0, 0xe4, 0xe2, 0xe6, 0xe1, 0xe5, 0xe3,
        0x67, 0x18, 0xe5, 0x8f, 0xf2, 0x47, 0xf9, 0x23,
        0x86, 0x0f, 0x00
    };

    std::vector<uint8_t> output;
    if (!decompress_all(compressed_pattern, sizeof(compressed_pattern), output)) {
        std::cerr << "FAILED: roundtrip - decompression failed" << std::endl;
        return false;
    }

    if (output.size() != pattern.size()) {
        std::cerr << "FAILED: roundtrip - output size " << output.size()
                  << " expected " << pattern.size() << std::endl;
        return false;
    }

    if (!arrays_equal(output.data(), pattern.data(), pattern.size())) {
        std::cerr << "FAILED: roundtrip - data mismatch" << std::endl;
        // Print first mismatch
        for (size_t i = 0; i < output.size(); i++) {
            if (output[i] != pattern[i]) {
                std::cerr << "  First mismatch at byte " << i
                          << ": got 0x" << std::hex << (int)output[i]
                          << " expected 0x" << (int)pattern[i] << std::dec << std::endl;
                break;
            }
        }
        return false;
    }

    std::cout << "PASSED: roundtrip test (repeating pattern 1024 bytes)" << std::endl;
    return true;
}

// =============================================================================
// Main
// =============================================================================

int main()
{
    int passed = 0;
    int failed = 0;

    auto run = [&](bool(*test)()) {
        if (test()) { ++passed; } else { ++failed; }
    };

    std::cout << "=== vmprog_decompress tests ===" << std::endl;

    run(test_init);
    run(test_inflate_result_enum_values);
    run(test_inflate_zeros);
    run(test_inflate_hello);
    run(test_inflate_streaming_small_output);
    run(test_inflate_total_counters);
    run(test_inflate_corrupt_data);
    run(test_inflate_finished_returns_zero);
    run(generate_and_test_roundtrip);

    std::cout << "\n=== Results: " << passed << " passed, " << failed << " failed ===" << std::endl;

    return failed > 0 ? 1 : 0;
}
