# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/__main__.py - Application entry point
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
Entry point for both GUI and CLI modes.

GUI  (default):
    python -m vhdl_image_tester
    lzx-vhdl-tester

CLI (headless):
    python -m vhdl_image_tester simulate cascade --image photo.png
    lzx-vhdl-tester list
    lzx-vhdl-cli simulate cascade --image photo.png   ← dedicated script

CLI routing rules:
  * ``--no-gui`` anywhere in argv → CLI mode
  * argv[1] is a known sub-command name → CLI mode
  * otherwise → GUI mode
"""

from __future__ import annotations

import sys

# Sub-command names understood by cli.py
_CLI_SUBCMDS = {"list", "info", "simulate", "export-regs"}


def _wants_cli() -> bool:
    """Return True when the user wants headless CLI operation."""
    args = sys.argv[1:]
    if "--no-gui" in args:
        # Strip the flag so cli.py sees clean argv
        sys.argv = [sys.argv[0]] + [a for a in args if a != "--no-gui"]
        return True
    if args and args[0] in _CLI_SUBCMDS:
        return True
    return False


def main() -> None:
    if _wants_cli():
        from .cli import main as cli_main
        cli_main()
        return

    # ── GUI mode ──────────────────────────────────────────────────────────────
    from PyQt6.QtCore import Qt
    from PyQt6.QtGui import QFont
    from PyQt6.QtWidgets import QApplication

    from .app.main_window import MainWindow

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
