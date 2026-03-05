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

from PyQt6.QtCore import Qt, QTimer, pyqtSignal
from PyQt6.QtWidgets import (
    QCheckBox,
    QComboBox,
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

from ...core.program_loader import Parameter, Preset, Program
from .combo_fix import fix_combo_popup


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
    # Emitted when a preset is loaded (preset name)
    preset_loaded: pyqtSignal = pyqtSignal(str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._rows:    list[_PotRow | _ToggleRow] = []
        self._program: Program | None = None
        self._loading_preset: bool = False

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

        # Preset combo (built once, shown/hidden per program)
        self._preset_combo = QComboBox()
        self._preset_combo.setToolTip("Load a factory preset by name")
        self._preset_combo.currentIndexChanged.connect(self._on_preset_changed)
        fix_combo_popup(self._preset_combo)

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
        self._populate_presets(program)

    def load_preset_by_name(self, name: str) -> bool:
        """Apply a preset by name.  Returns True if found and applied."""
        if self._program is None:
            return False
        preset = self._program.get_preset_by_name(name)
        if preset is None:
            return False
        values = self._program.resolve_preset_values(preset)
        self.set_values(values)
        self.preset_loaded.emit(preset.name)
        return True

    @property
    def preset_names(self) -> list[str]:
        """Return available preset names for the current program."""
        if self._program is None:
            return []
        return self._program.get_preset_names()

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
        # Remove _preset_combo from its current layout without destroying it —
        # it is built once in __init__ and reused across program loads.  We
        # temporarily re-parent it to _container so it stays alive even if
        # _build_rows doesn't add it back (no-preset programs).
        self._preset_combo.setParent(self._container)
        self._clear_layout(self._root_layout)

    def _clear_layout(self, layout: QVBoxLayout) -> None:
        """Recursively remove and delete all items from *layout*."""
        while layout.count():
            item = layout.takeAt(0)
            child_layout = item.layout()
            if child_layout is not None:
                self._clear_layout(child_layout)
                child_layout.deleteLater()
            elif item.widget() is not None and item.widget() is not self._preset_combo:
                item.widget().deleteLater()

    def _populate_presets(self, program: Program | None) -> None:
        """Populate the preset combo from the program's embedded presets."""
        self._preset_combo.blockSignals(True)
        self._preset_combo.clear()
        if program is not None and program.presets:
            self._preset_combo.addItem("(select preset)", None)
            for preset in program.presets:
                self._preset_combo.addItem(preset.name, preset)
            self._preset_combo.setVisible(True)
        else:
            self._preset_combo.setVisible(False)
        self._preset_combo.blockSignals(False)

    def _build_rows(self, program: Program) -> None:
        if not program.parameters:
            lbl = QLabel("No parameters defined for this program.")
            lbl.setStyleSheet("color: #888;")
            self._root_layout.addWidget(lbl)
            self._root_layout.addStretch()
            return

        # Preset selector (shown only when program has presets)
        if program.presets:
            preset_row = QHBoxLayout()
            preset_row.setSpacing(6)
            preset_lbl = QLabel("Preset:")
            preset_lbl.setStyleSheet("color: #aaa; font-weight: bold;")
            preset_lbl.setFixedWidth(50)
            preset_row.addWidget(preset_lbl)
            preset_row.addWidget(self._preset_combo, stretch=1)
            self._root_layout.addLayout(preset_row)

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

    def _on_preset_changed(self, index: int) -> None:
        if index <= 0 or self._program is None:
            return  # index 0 is the placeholder "(select preset)"
        preset = self._preset_combo.itemData(index)
        if not isinstance(preset, Preset):
            return
        # The _loading_preset flag prevents _on_any_changed from resetting
        # the combo back to the placeholder while we programmatically update
        # each control.
        self._loading_preset = True
        try:
            values = self._program.resolve_preset_values(preset)
            self.set_values(values)
        finally:
            self._loading_preset = False
        self.registers_changed.emit(self.current_values)
        self.preset_loaded.emit(preset.name)

    def _on_any_changed(self, _param_id: str, _val: int) -> None:
        # Reset the preset combo to the placeholder when the user manually
        # changes a control, so it doesn't falsely indicate a preset is active.
        # Skip the reset while a preset is being programmatically loaded.
        if not self._loading_preset and self._preset_combo.currentIndex() > 0:
            self._preset_combo.blockSignals(True)
            self._preset_combo.setCurrentIndex(0)
            self._preset_combo.blockSignals(False)
        self.registers_changed.emit(self.current_values)
