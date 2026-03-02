# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/app/app.py - QApplication factory
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""QApplication factory (imported by tests and the entry point)."""

from __future__ import annotations

import sys
from typing import Sequence

from PyQt6.QtWidgets import QApplication


def create_app(argv: Sequence[str] | None = None) -> QApplication:
    """Create and return a configured QApplication instance."""
    return QApplication(list(argv) if argv is not None else sys.argv)
