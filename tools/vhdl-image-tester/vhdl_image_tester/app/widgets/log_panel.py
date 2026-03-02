# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/app/widgets/log_panel.py - Simulation log display
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
LogPanel: scrollable monospace text area that streams GHDL output and
pipeline status messages during simulation runs.
"""

from __future__ import annotations

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont, QTextCursor
from PyQt6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)


class LogPanel(QWidget):
    """Monospace terminal-style log panel with clear and copy buttons."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._build_ui()

    # ── Public API ──────────────────────────────────────────────────────────

    def append(self, text: str) -> None:
        """Append *text* to the log, scrolling to bottom."""
        cursor = self._text.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        self._text.setTextCursor(cursor)
        self._text.insertPlainText(text + "\n")
        self._text.ensureCursorVisible()

    def clear(self) -> None:
        self._text.clear()

    def set_status(self, msg: str, color: str = "#ccc") -> None:
        self._status_lbl.setText(msg)
        self._status_lbl.setStyleSheet(f"color: {color}; font-size: 12px;")

    # ── UI Construction ─────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(3)

        # Header bar
        header = QHBoxLayout()
        title = QLabel("Simulation Log")
        title.setStyleSheet("font-weight: bold; color: #ccc;")
        header.addWidget(title)

        self._status_lbl = QLabel("Ready")
        self._status_lbl.setStyleSheet("color: #888; font-size: 12px;")
        header.addWidget(self._status_lbl)
        header.addStretch()

        clear_btn = QPushButton("Clear")
        clear_btn.setFixedWidth(55)
        clear_btn.clicked.connect(self.clear)
        header.addWidget(clear_btn)

        copy_btn = QPushButton("Copy All")
        copy_btn.setFixedWidth(70)
        copy_btn.clicked.connect(self._copy_all)
        header.addWidget(copy_btn)

        root.addLayout(header)

        # Text area
        self._text = QTextEdit()
        self._text.setReadOnly(True)
        self._text.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self._text.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap)

        mono = QFont("Monospace")
        mono.setStyleHint(QFont.StyleHint.TypeWriter)
        mono.setPointSize(10)
        self._text.setFont(mono)

        self._text.setStyleSheet(
            "background: #111; color: #d0d0d0; border: 1px solid #333;"
        )
        root.addWidget(self._text)

    # ── Helpers ──────────────────────────────────────────────────────────────

    def _copy_all(self) -> None:
        self._text.selectAll()
        self._text.copy()
        cursor = self._text.textCursor()
        cursor.clearSelection()
        self._text.setTextCursor(cursor)
