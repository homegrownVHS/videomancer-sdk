# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/app/widgets/image_viewer.py - Before/after image display
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
ImageViewer: side-by-side comparison widget showing the input image (before)
and the VHDL-processed output image (after), with zoom, fit, and save actions.
"""

from __future__ import annotations

import io
from pathlib import Path

from PIL import Image
from PyQt6.QtCore import Qt, QSize
from PyQt6.QtGui import QImage, QKeySequence, QPixmap, QWheelEvent
from PyQt6.QtWidgets import (
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)


# ---------------------------------------------------------------------------
# Zoomable image label
# ---------------------------------------------------------------------------

class _ZoomLabel(QScrollArea):
    """A scroll area wrapping a QLabel that supports mouse-wheel zoom."""

    def __init__(self, title: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._scale    = 1.0
        self._pil_img: Image.Image | None = None

        self.setWidgetResizable(False)
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setFrameShape(QScrollArea.Shape.Box)

        self._lbl = QLabel()
        self._lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._lbl.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Ignored)
        self.setWidget(self._lbl)

        self._title = title
        self._show_placeholder()

    # ── Public API ───────────────────────────────────────────────────────────

    def set_image(self, img: Image.Image) -> None:
        self._pil_img = img
        self._scale   = 1.0
        self._render()

    def clear(self) -> None:
        self._pil_img = None
        self._show_placeholder()

    @property
    def pil_image(self) -> Image.Image | None:
        return self._pil_img

    # ── Rendering ────────────────────────────────────────────────────────────

    def _show_placeholder(self) -> None:
        self._lbl.setPixmap(QPixmap())
        self._lbl.setText(
            f'<span style="color:#555; font-size:13px;">{self._title}</span>'
        )

    def _render(self) -> None:
        if self._pil_img is None:
            return
        w = max(1, int(self._pil_img.width  * self._scale))
        h = max(1, int(self._pil_img.height * self._scale))
        resized = self._pil_img.resize((w, h), Image.NEAREST if self._scale >= 2 else Image.LANCZOS)
        qimg = self._pil_to_qimage(resized)
        pix  = QPixmap.fromImage(qimg)
        self._lbl.setPixmap(pix)
        self._lbl.resize(pix.size())

    @staticmethod
    def _pil_to_qimage(img: Image.Image) -> QImage:
        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="PNG")
        buf.seek(0)
        data = buf.read()
        qimg = QImage()
        qimg.loadFromData(data)
        return qimg

    def fit_to_view(self) -> None:
        if self._pil_img is None:
            return
        vw = self.viewport().width()
        vh = self.viewport().height()
        iw, ih = self._pil_img.size
        self._scale = min(vw / max(iw, 1), vh / max(ih, 1))
        self._render()

    # ── Events ───────────────────────────────────────────────────────────────

    def wheelEvent(self, event: QWheelEvent) -> None:  # type: ignore[override]
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            delta = event.angleDelta().y()
            factor = 1.15 if delta > 0 else 1.0 / 1.15
            self._scale = max(0.1, min(16.0, self._scale * factor))
            self._render()
            event.accept()
        else:
            super().wheelEvent(event)

    def sizeHint(self) -> QSize:
        return QSize(400, 300)


# ---------------------------------------------------------------------------
# Image viewer widget
# ---------------------------------------------------------------------------

class ImageViewer(QWidget):
    """Side-by-side input / output image viewer with save buttons."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._build_ui()

    # ── Public API ──────────────────────────────────────────────────────────

    def set_input(self, img: Image.Image) -> None:
        self._in_view.set_image(img)
        self._in_info.setText(f"{img.width}×{img.height} px")
        self._save_in_btn.setEnabled(True)

    def set_output(self, img: Image.Image) -> None:
        self._out_view.set_image(img)
        self._out_info.setText(f"{img.width}×{img.height} px")
        self._save_out_btn.setEnabled(True)
        self._fit_view()

    def clear_output(self) -> None:
        self._out_view.clear()
        self._out_info.setText("")
        self._save_out_btn.setEnabled(False)

    def clear_all(self) -> None:
        self._in_view.clear()
        self._out_view.clear()
        self._in_info.setText("")
        self._out_info.setText("")
        self._save_in_btn.setEnabled(False)
        self._save_out_btn.setEnabled(False)

    # ── UI Construction ─────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(4)

        # Toolbar
        tb = QHBoxLayout()
        tb.addStretch()

        self._fit_btn = QPushButton("Fit")
        self._fit_btn.setFixedWidth(50)
        self._fit_btn.setToolTip("Fit both images to view (F)")
        self._fit_btn.clicked.connect(self._fit_view)
        tb.addWidget(self._fit_btn)

        self._reset_btn = QPushButton("1:1")
        self._reset_btn.setFixedWidth(50)
        self._reset_btn.setToolTip("Reset zoom to 100%")
        self._reset_btn.clicked.connect(self._reset_zoom)
        tb.addWidget(self._reset_btn)

        root.addLayout(tb)

        # Image pair
        pair = QHBoxLayout()
        pair.setSpacing(6)

        for side, is_input in [("Input (original)", True), ("Output (VHDL processed)", False)]:
            grp = QGroupBox(side)
            inner = QVBoxLayout(grp)
            inner.setContentsMargins(4, 4, 4, 4)
            inner.setSpacing(3)

            view = _ZoomLabel(side)
            inner.addWidget(view, stretch=1)

            info_row = QHBoxLayout()
            info_lbl = QLabel()
            info_lbl.setStyleSheet("color: #888; font-size: 11px;")
            info_row.addWidget(info_lbl)
            info_row.addStretch()

            save_btn = QPushButton("Save…")
            save_btn.setEnabled(False)
            save_btn.setFixedWidth(60)
            if is_input:
                save_btn.clicked.connect(lambda _, v=view: self._save_image(v.pil_image, "input"))
            else:
                save_btn.clicked.connect(lambda _, v=view: self._save_image(v.pil_image, "output"))

            info_row.addWidget(save_btn)
            inner.addLayout(info_row)

            pair.addWidget(grp)

            if is_input:
                self._in_view   = view
                self._in_info   = info_lbl
                self._save_in_btn = save_btn
            else:
                self._out_view  = view
                self._out_info  = info_lbl
                self._save_out_btn = save_btn

        root.addLayout(pair, stretch=1)

    # ── Helpers ──────────────────────────────────────────────────────────────

    def _fit_view(self) -> None:
        self._in_view.fit_to_view()
        self._out_view.fit_to_view()

    def _reset_zoom(self) -> None:
        for view in (self._in_view, self._out_view):
            view._scale = 1.0
            view._render()

    def _save_image(self, img: Image.Image | None, label: str) -> None:
        if img is None:
            return
        path_str, _ = QFileDialog.getSaveFileName(
            self, f"Save {label} image", f"{label}.png",
            "PNG (*.png);;JPEG (*.jpg);;TIFF (*.tif)"
        )
        if path_str:
            img.save(path_str)

    def resizeEvent(self, event) -> None:  # type: ignore[override]
        super().resizeEvent(event)
        self._fit_view()
