# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/app/widgets/register_panel.py - FPGA register controls
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""
RegisterPanel: displays one control widget per program parameter, matching
the Videomancer ABI layout:

  • rotary_potentiometer_1–6 → QSlider (0–1023) + QSpinBox
  • toggle_switch_7–11       → QCheckBox (maps to bits 0–4 of register 6)
  • linear_potentiometer_12  → QSlider (0–1023) + QSpinBox (vertical fader style)

Labels, initial values, and min/max display values are loaded from the program's
TOML metadata via the Program dataclass.
"""

from __future__ import annotations

from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtWidgets import (
    QCheckBox,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QScrollArea,
    QSizePolicy,
    QSlider,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from ...core.program_loader import Parameter, Program


# ---------------------------------------------------------------------------
# Single pot-control row
# ---------------------------------------------------------------------------

class _PotRow(QWidget):
    """A horizontal row: label | slider | spinbox | suffix."""

    value_changed: pyqtSignal = pyqtSignal(str, int)  # (parameter_id, raw_value)

    def __init__(self, param: Parameter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._param = param
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 2, 0, 2)
        layout.setSpacing(6)

        # Label
        lbl = QLabel(self._param.name_label)
        lbl.setFixedWidth(130)
        lbl.setToolTip(
            f"parameter_id: {self._param.parameter_id}\n"
            f"register: {self._param.register_index}\n"
            f"mode: {self._param.control_mode}"
        )
        layout.addWidget(lbl)

        # Slider
        self._slider = QSlider(Qt.Orientation.Horizontal)
        self._slider.setRange(0, 1023)
        self._slider.setValue(self._param.initial_pot_value)
        self._slider.setTickInterval(128)
        self._slider.setFixedHeight(22)
        layout.addWidget(self._slider, stretch=1)

        # Spinbox (raw 10-bit value)
        self._spin = QSpinBox()
        self._spin.setRange(0, 1023)
        self._spin.setValue(self._param.initial_pot_value)
        self._spin.setFixedWidth(60)
        layout.addWidget(self._spin)

        # Display value label (shows scaled/mapped value)
        self._display_lbl = QLabel()
        self._display_lbl.setFixedWidth(80)
        self._display_lbl.setStyleSheet("color: #aaa; font-size: 11px;")
        layout.addWidget(self._display_lbl)

        self._update_display(self._param.initial_pot_value)

        # Wire signals
        self._slider.valueChanged.connect(self._on_slider_changed)
        self._spin.valueChanged.connect(self._on_spin_changed)

    # ── Slots ────────────────────────────────────────────────────────────────

    def _on_slider_changed(self, val: int) -> None:
        self._spin.blockSignals(True)
        self._spin.setValue(val)
        self._spin.blockSignals(False)
        self._update_display(val)
        self.value_changed.emit(self._param.parameter_id, val)

    def _on_spin_changed(self, val: int) -> None:
        self._slider.blockSignals(True)
        self._slider.setValue(val)
        self._slider.blockSignals(False)
        self._update_display(val)
        self.value_changed.emit(self._param.parameter_id, val)

    def _update_display(self, raw: int) -> None:
        """Show the mapped display value with suffix."""
        lo = self._param.display_min_value
        hi = self._param.display_max_value
        mapped = lo + (hi - lo) * raw / 1023.0
        digits = self._param.display_float_digits
        suffix = self._param.suffix_label
        if digits > 0:
            self._display_lbl.setText(f"{mapped:.{digits}f} {suffix}")
        else:
            self._display_lbl.setText(f"{int(round(mapped))} {suffix}")

    # ── Public API ───────────────────────────────────────────────────────────

    @property
    def raw_value(self) -> int:
        return self._slider.value()

    def reset_to_default(self) -> None:
        self._slider.setValue(self._param.initial_pot_value)


# ---------------------------------------------------------------------------
# Single toggle-control row
# ---------------------------------------------------------------------------

class _ToggleRow(QWidget):
    """A row containing a checkbox for a toggle switch."""

    value_changed: pyqtSignal = pyqtSignal(str, int)  # (parameter_id, 0_or_1)

    def __init__(self, param: Parameter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._param = param
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 2, 0, 2)
        layout.setSpacing(6)

        self._check = QCheckBox(self._param.name_label)
        self._check.setChecked(self._param.initial_toggle_state)
        self._check.setFixedWidth(200)
        self._check.setToolTip(
            f"parameter_id: {self._param.parameter_id}\n"
            f"register: {self._param.register_index}, "
            f"bit: {self._param.toggle_bit}"
        )

        if self._param.value_labels:
            off_lbl, on_lbl = (self._param.value_labels + ["", ""])[:2]
            self._check.setToolTip(
                self._check.toolTip() + f"\nOff = {off_lbl!r}  On = {on_lbl!r}"
            )

        layout.addWidget(self._check)
        layout.addStretch()
        self._check.stateChanged.connect(self._on_changed)

    def _on_changed(self, state: int) -> None:
        val = 1 if state == Qt.CheckState.Checked.value else 0
        self.value_changed.emit(self._param.parameter_id, val)

    @property
    def raw_value(self) -> int:
        return 1 if self._check.isChecked() else 0

    def reset_to_default(self) -> None:
        self._check.setChecked(self._param.initial_toggle_state)


# ---------------------------------------------------------------------------
# Main register panel
# ---------------------------------------------------------------------------

class RegisterPanel(QScrollArea):
    """
    Scrollable panel showing one control row per program parameter.
    Automatically updates when a different program is loaded.
    """

    # Emitted whenever any register value changes
    registers_changed: pyqtSignal = pyqtSignal(dict)  # {parameter_id: raw_value}

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._rows:    list[_PotRow | _ToggleRow] = []
        self._program: Program | None = None

        self.setWidgetResizable(True)
        self.setFrameShape(QFrame.Shape.NoFrame)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        self._container = QWidget()
        self._container.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )
        self._root_layout = QVBoxLayout(self._container)
        self._root_layout.setContentsMargins(4, 4, 4, 4)
        self._root_layout.setSpacing(4)
        self.setWidget(self._container)

    # ── Public API ──────────────────────────────────────────────────────────

    def load_program(self, program: Program | None) -> None:
        """Rebuild all control rows from *program*'s parameters.

        Passing ``None`` clears the panel (used when the programs folder has no
        valid programs).
        """
        self._program = program
        self._clear_rows()
        if program is not None:
            self._build_rows(program)

    @property
    def current_values(self) -> dict[str, int]:
        """Return mapping of parameter_id → raw 10-bit value (0–1023)."""
        return {row._param.parameter_id: row.raw_value for row in self._rows}

    def reset_to_defaults(self) -> None:
        for row in self._rows:
            row.reset_to_default()

    def set_values(self, values: dict[str, int]) -> None:
        """Set register values from a mapping of parameter_id → raw value."""
        for row in self._rows:
            pid = row._param.parameter_id
            if pid in values:
                raw = values[pid]
                if isinstance(row, _ToggleRow):
                    row._check.setChecked(bool(raw))
                else:
                    row._slider.setValue(max(0, min(1023, int(raw))))

    # ── UI helpers ───────────────────────────────────────────────────────────

    def _clear_rows(self) -> None:
        self._rows.clear()
        while self._root_layout.count():
            item = self._root_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

    def _build_rows(self, program: Program) -> None:
        if not program.parameters:
            lbl = QLabel("No parameters defined for this program.")
            lbl.setStyleSheet("color: #888;")
            self._root_layout.addWidget(lbl)
            self._root_layout.addStretch()
            return

        # Group parameters by type for visual separation
        pots     = [p for p in program.parameters if p.is_pot]
        toggles  = [p for p in program.parameters if p.is_toggle]
        faders   = [p for p in program.parameters if p.is_fader]

        if pots:
            self._root_layout.addWidget(self._make_section("Rotary Potentiometers"))
            for param in pots:
                row = _PotRow(param)
                row.value_changed.connect(self._on_any_changed)
                self._rows.append(row)
                self._root_layout.addWidget(row)

        if toggles:
            self._root_layout.addWidget(self._make_section("Toggle Switches"))
            for param in toggles:
                row = _ToggleRow(param)
                row.value_changed.connect(self._on_any_changed)
                self._rows.append(row)
                self._root_layout.addWidget(row)

        if faders:
            self._root_layout.addWidget(self._make_section("Linear Potentiometer (Fader)"))
            for param in faders:
                row = _PotRow(param)
                row.value_changed.connect(self._on_any_changed)
                self._rows.append(row)
                self._root_layout.addWidget(row)

        self._root_layout.addStretch()

    @staticmethod
    def _make_section(title: str) -> QLabel:
        lbl = QLabel(f"<b>{title}</b>")
        lbl.setStyleSheet(
            "color: #ccc; background: #2d2d2d; padding: 3px 6px; "
            "border-radius: 3px; margin-top: 6px;"
        )
        return lbl

    # ── Slots ────────────────────────────────────────────────────────────────

    def _on_any_changed(self, _param_id: str, _val: int) -> None:
        self.registers_changed.emit(self.current_values)
