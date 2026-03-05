# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/app/widgets/combo_fix.py - Wayland QComboBox popup fix
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
Workaround for QComboBox popups that fail to auto-dismiss on Wayland.

Qt 6.10 on Wayland leaves the QComboBox popup (a compositor-managed popup
surface) open after the user selects an item because ``hidePopup()`` does
not reliably destroy the Wayland popup surface.

The fix installs an event filter on the combo-view's viewport that
intercepts ``MouseButtonRelease`` and directly **closes** the popup
container ``QFrame`` — bypassing ``hidePopup()`` entirely.
"""

from __future__ import annotations

from PyQt6.QtCore import QEvent, QObject, QTimer
from PyQt6.QtWidgets import QComboBox, QWidget


class _PopupCloseFilter(QObject):
    """Event filter that forces the QComboBox popup closed on click.

    Requires a full press+release cycle *inside the viewport* before
    closing.  The opening click's press is delivered to the combo widget
    itself (not the viewport), so only a deliberate second click inside
    the open popup triggers closure.
    """

    def __init__(self, combo: QComboBox) -> None:
        super().__init__(combo)
        self._combo = combo
        self._press_seen = False

    def eventFilter(self, obj: QObject, event: QEvent) -> bool:  # noqa: N802
        etype = event.type()
        if etype == QEvent.Type.MouseButtonPress:
            view = self._combo.view()
            if view is not None and view.indexAt(event.pos()).isValid():
                self._press_seen = True
        elif etype == QEvent.Type.MouseButtonRelease:
            if self._press_seen:
                self._press_seen = False
                view = self._combo.view()
                if view is not None:
                    idx = view.indexAt(event.pos())
                    if idx.isValid():
                        popup: QWidget | None = view.parent()
                        if popup is not None:
                            QTimer.singleShot(0, popup.close)
        elif etype == QEvent.Type.Hide:
            # Reset when popup is dismissed by other means (focus loss, etc.)
            self._press_seen = False
        return False


def fix_combo_popup(combo: QComboBox) -> None:
    """Install the Wayland popup-close workaround on *combo*.

    Call once after creating each ``QComboBox``; safe to call on non-Wayland
    sessions (the filter simply never fires if the popup closes normally).
    """
    filt = _PopupCloseFilter(combo)
    combo.view().viewport().installEventFilter(filt)
