#!/usr/bin/env python3
# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/run.py - Convenience launch script
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.
"""Launch the VHDL Image Tester without installing the package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from vhdl_image_tester.__main__ import main

if __name__ == "__main__":
    main()
