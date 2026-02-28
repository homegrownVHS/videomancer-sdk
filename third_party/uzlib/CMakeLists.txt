# uzlib - Tiny DEFLATE inflate library (inflate-only subset)
# Vendored from https://github.com/pfalcon/uzlib
# License: Zlib (see LICENSE)
#
# Only the inflate (decompression) subset is included.
# Compression, checksum, and zlib/gzip header parsing code is excluded.

cmake_minimum_required(VERSION 3.13)

add_library(uzlib STATIC
    ${CMAKE_CURRENT_LIST_DIR}/src/tinflate.c
)

target_include_directories(uzlib PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}/src
)

# Disable debug logging and paranoid checks for production builds
target_compile_definitions(uzlib PRIVATE
    UZLIB_CONF_DEBUG_LOG=0
    UZLIB_CONF_PARANOID_CHECKS=0
)
