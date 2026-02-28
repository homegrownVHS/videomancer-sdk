// Videomancer SDK - Open source FPGA-based video effects development kit
// Copyright (C) 2025 LZX Industries LLC
// File: vmprog_decompress.hpp - Streaming DEFLATE decompressor for VMPROG bitstreams
// License: GNU General Public License v3.0
// https://github.com/lzxindustries/videomancer-sdk
//
// This file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// Description:
//   Streaming DEFLATE decompressor for VMPROG bitstream payloads.
//   Wraps the uzlib inflate engine in a fixed-buffer streaming API
//   suitable for RP2040 Cortex-M0+ with minimal RAM usage.
//
//   Decompresses raw DEFLATE data (no zlib/gzip headers) using a
//   configurable sliding window (default 1 KB for wbits=10).
//
//   Memory budget (default configuration):
//     - 1024 bytes: sliding window (wbits=10)
//     - State struct: ~1.2 KB (uzlib_uncomp)
//     - No internal input/output buffers — caller provides them
//
// Usage:
//   The caller is responsible for providing input data (compressed bytes)
//   and an output buffer (for decompressed bytes). The decompressor processes
//   data incrementally:
//
//   ```cpp
//   uint8_t window[1024];
//   uint8_t out_buf[4096];
//   lzx::vmprog_inflate_stream inflater;
//   inflater.init(window, sizeof(window));
//
//   // Set compressed input
//   inflater.set_input(compressed_data, compressed_size);
//
//   while (!inflater.finished()) {
//       auto result = inflater.decompress(out_buf, sizeof(out_buf));
//       if (result.status == lzx::vmprog_inflate_result::invalid_data) {
//           // Handle error
//           break;
//       }
//       // Send result.bytes_produced decompressed bytes to FPGA
//       configurator.send_bitstream_data(out_buf, result.bytes_produced);
//
//       if (result.status == lzx::vmprog_inflate_result::need_input) {
//           // Read more compressed data from filesystem
//           size_t n = stream.read(comp_buf, sizeof(comp_buf));
//           inflater.set_input(comp_buf, n);
//       }
//   }
//   ```

#pragma once

#include <cstdint>
#include <cstddef>
#include <cstring>

extern "C" {
#include "uzlib.h"
}

namespace lzx {

    // =========================================================================
    // Result Codes
    // =========================================================================

    /// @brief Result codes for decompression operations
    enum class vmprog_inflate_result : uint8_t
    {
        ok            = 0,   ///< Output buffer filled, more data available
        stream_end    = 1,   ///< Decompression complete (DEFLATE end marker reached)
        need_input    = 2,   ///< More compressed input data needed to continue
        invalid_data  = 3,   ///< Corrupt or invalid DEFLATE stream
    };

    // =========================================================================
    // Decompress Output
    // =========================================================================

    /// @brief Result of a single decompress() call
    struct vmprog_inflate_output
    {
        vmprog_inflate_result status;   ///< Result status code
        uint32_t bytes_produced;        ///< Number of decompressed bytes written to output buffer
    };

    // =========================================================================
    // Streaming DEFLATE Decompressor
    // =========================================================================

    /// @brief Streaming DEFLATE decompressor with caller-provided buffers.
    ///
    /// Wraps the uzlib inflate engine for incremental decompression of raw
    /// DEFLATE streams (no zlib/gzip framing). Designed for fixed-buffer
    /// operation on embedded systems (RP2040).
    ///
    /// The caller provides:
    ///   - A sliding window buffer (e.g., 1024 bytes for wbits=10)
    ///   - An output buffer for each decompress() call
    ///   - Compressed input data via set_input()
    ///
    /// The decompressor maintains internal state across calls, allowing
    /// compressed data to be fed in arbitrarily-sized chunks.
    class vmprog_inflate_stream
    {
    public:
        /// @brief Initialize the decompressor.
        ///
        /// Must be called before any decompression. The sliding window buffer
        /// must remain valid for the lifetime of the decompressor.
        ///
        /// @param window_buf Sliding window buffer (size determines max back-reference distance)
        /// @param window_size Size of the window buffer in bytes (e.g., 1024 for wbits=10)
        void init(void* window_buf, uint32_t window_size) noexcept
        {
            uzlib_init();
            uzlib_uncompress_init(&_decomp, window_buf, window_size);
            _decomp.source = nullptr;
            _decomp.source_limit = nullptr;
            _decomp.source_read_cb = nullptr;
            _decomp.checksum_type = TINF_CHKSUM_NONE;
            _total_in = 0;
            _total_out = 0;
            _finished = false;
        }

        /// @brief Set the compressed input data buffer.
        ///
        /// Points the decompressor at a new block of compressed input data.
        /// Any unconsumed bytes from a previous set_input() call are abandoned.
        /// The caller should track how much was consumed via input_consumed()
        /// before calling set_input() again.
        ///
        /// @param data Pointer to compressed data
        /// @param size Number of compressed bytes available
        void set_input(const uint8_t* data, uint32_t size) noexcept
        {
            _input_start = data;
            _decomp.source = data;
            _decomp.source_limit = data + size;
        }

        /// @brief Get the number of unconsumed input bytes remaining.
        /// @return Bytes of compressed input not yet processed
        [[nodiscard]] uint32_t input_remaining() const noexcept
        {
            if (_decomp.source && _decomp.source_limit) {
                return static_cast<uint32_t>(_decomp.source_limit - _decomp.source);
            }
            return 0;
        }

        /// @brief Decompress data into the provided output buffer.
        ///
        /// Decompresses as many bytes as possible into out_buf (up to out_size).
        /// Returns the number of bytes produced and a status code indicating
        /// whether more input is needed, output buffer was filled, or the
        /// stream has ended.
        ///
        /// @param out_buf Output buffer for decompressed data
        /// @param out_size Size of the output buffer in bytes
        /// @return Inflate output with status and bytes produced
        [[nodiscard]] vmprog_inflate_output decompress(
            uint8_t* out_buf,
            uint32_t out_size) noexcept
        {
            if (_finished) {
                return { vmprog_inflate_result::stream_end, 0 };
            }

            if (out_size == 0) {
                return { vmprog_inflate_result::ok, 0 };
            }

            // Set up output buffer pointers
            _decomp.dest_start = out_buf;
            _decomp.dest = out_buf;
            _decomp.dest_limit = out_buf + out_size;

            // Record input position before decompression
            const unsigned char* source_before = _decomp.source;

            // Run the inflate engine
            int rc = uzlib_uncompress(&_decomp);

            // Calculate bytes produced and consumed
            uint32_t produced = static_cast<uint32_t>(_decomp.dest - out_buf);
            uint32_t consumed = static_cast<uint32_t>(_decomp.source - source_before);
            _total_out += produced;
            _total_in += consumed;

            if (rc == TINF_DONE) {
                _finished = true;
                return { vmprog_inflate_result::stream_end, produced };
            }

            if (rc == TINF_OK) {
                // Output buffer was filled — check if we ran out of input
                if (_decomp.source >= _decomp.source_limit) {
                    return { vmprog_inflate_result::need_input, produced };
                }
                return { vmprog_inflate_result::ok, produced };
            }

            // Any other return code is an error
            return { vmprog_inflate_result::invalid_data, produced };
        }

        /// @brief Check if decompression is complete.
        /// @return true if the DEFLATE stream end marker has been reached
        [[nodiscard]] bool finished() const noexcept { return _finished; }

        /// @brief Get total compressed bytes consumed across all calls.
        [[nodiscard]] uint32_t total_in() const noexcept { return _total_in; }

        /// @brief Get total decompressed bytes produced across all calls.
        [[nodiscard]] uint32_t total_out() const noexcept { return _total_out; }

    private:
        struct uzlib_uncomp _decomp {};  ///< uzlib decompression state
        const uint8_t* _input_start = nullptr; ///< Start of current input buffer
        uint32_t _total_in = 0;          ///< Total compressed bytes consumed
        uint32_t _total_out = 0;         ///< Total decompressed bytes produced
        bool _finished = false;          ///< True when DEFLATE stream end reached
    };

} // namespace lzx
