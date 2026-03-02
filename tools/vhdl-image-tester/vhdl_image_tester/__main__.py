# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/__main__.py - Application entry point
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
Entry point: python -m vhdl_image_tester   or  lzx-vhdl-tester
"""

from __future__ import annotations

import sys

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import QApplication

from .app.main_window import MainWindow


def main() -> None:
    # High-DPI support
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )

    app = QApplication(sys.argv)
    app.setApplicationName("LZX VHDL Image Tester")
    app.setOrganizationName("LZX Industries LLC")
    app.setApplicationVersion("0.1.0")

    # Set a clean default font
    font = QFont("Segoe UI", 10)
    font.setStyleHint(QFont.StyleHint.SansSerif)
    app.setFont(font)

    window = MainWindow()
    window.resize(1280, 820)
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
