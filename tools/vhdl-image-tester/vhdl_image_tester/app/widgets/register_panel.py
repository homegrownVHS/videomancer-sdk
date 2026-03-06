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
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSlider,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from ...core.program_loader import MAX_PRESETS, Parameter, Preset, Program
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
    # Emitted when user requests saving the active preset
    # (preset_index: int, new_values: dict, new_name: str)
    save_preset_requested: pyqtSignal = pyqtSignal(int, dict, str)
    # Emitted when user requests creating a new preset (name: str, values: dict)
    new_preset_requested: pyqtSignal = pyqtSignal(str, dict)
    # Emitted when user requests deleting the active preset (preset_index: int)
    delete_preset_requested: pyqtSignal = pyqtSignal(int)
    # Emitted when user requests saving modified default values
    save_defaults_requested: pyqtSignal = pyqtSignal(dict)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._rows:    list[_PotRow | _ToggleRow] = []
        self._program: Program | None = None
        self._loading_preset: bool = False
        self._active_preset_index: int = -1   # -1 = no preset selected
        self._defaults_selected: bool = False  # True when "Default Settings" is active
        self._active_preset_values: dict[str, int] = {}  # snapshot of preset values

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

        # Preset name editor (shown when a preset is selected and values differ)
        self._preset_name_edit = QLineEdit()
        self._preset_name_edit.setMaxLength(15)
        self._preset_name_edit.setPlaceholderText("Preset name")
        self._preset_name_edit.setToolTip("Edit the preset name (15 chars max)")
        self._preset_name_edit.setFixedWidth(130)
        self._preset_name_edit.setVisible(False)
        self._preset_name_edit.textChanged.connect(self._update_save_button_state)

        # Save Preset button
        self._save_preset_btn = QPushButton("Save")
        self._save_preset_btn.setToolTip(
            "Write the current slider values back to the TOML file's preset"
        )
        self._save_preset_btn.setFixedHeight(28)
        self._save_preset_btn.setVisible(False)
        self._save_preset_btn.clicked.connect(self._on_save_preset)

        # New Preset button
        self._new_preset_btn = QPushButton("+")
        self._new_preset_btn.setToolTip("Save current values as a new preset")
        self._new_preset_btn.setFixedWidth(28)
        self._new_preset_btn.setFixedHeight(28)
        self._new_preset_btn.setVisible(False)
        self._new_preset_btn.clicked.connect(self._on_new_preset)

        # Delete Preset button
        self._delete_preset_btn = QPushButton("−")
        self._delete_preset_btn.setToolTip("Delete the selected preset")
        self._delete_preset_btn.setFixedWidth(28)
        self._delete_preset_btn.setFixedHeight(28)
        self._delete_preset_btn.setVisible(False)
        self._delete_preset_btn.clicked.connect(self._on_delete_preset)

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
        self._active_preset_index = -1
        self._defaults_selected = False
        self._active_preset_values = {}
        # Remove reusable widgets from their current layout without destroying
        # them — they are built once in __init__ and reused across program loads.
        self._preset_combo.setParent(self._container)
        self._preset_name_edit.setParent(self._container)
        self._save_preset_btn.setParent(self._container)
        self._new_preset_btn.setParent(self._container)
        self._delete_preset_btn.setParent(self._container)
        self._save_preset_btn.setVisible(False)
        self._preset_name_edit.setVisible(False)
        self._new_preset_btn.setVisible(False)
        self._delete_preset_btn.setVisible(False)
        self._clear_layout(self._root_layout)

    def _clear_layout(self, layout: QVBoxLayout) -> None:
        """Recursively remove and delete all items from *layout*."""
        _keep = {
            self._preset_combo, self._preset_name_edit, self._save_preset_btn,
            self._new_preset_btn, self._delete_preset_btn,
        }
        while layout.count():
            item = layout.takeAt(0)
            child_layout = item.layout()
            if child_layout is not None:
                self._clear_layout(child_layout)
                child_layout.deleteLater()
            elif item.widget() is not None and item.widget() not in _keep:
                item.widget().deleteLater()

    def _populate_presets(self, program: Program | None) -> None:
        """Populate the preset combo from the program's embedded presets."""
        self._preset_combo.blockSignals(True)
        self._preset_combo.clear()
        has_params = program is not None and program.parameters
        if has_params:
            self._preset_combo.addItem("(select preset)", None)
            self._preset_combo.addItem("Default Settings", "defaults")
            if program is not None:
                for preset in program.presets:
                    self._preset_combo.addItem(preset.name, preset)
            self._preset_combo.setVisible(True)
        else:
            self._preset_combo.setVisible(False)
        # New Preset button is shown whenever there are parameters and room
        can_add = (
            has_params
            and program is not None
            and len(program.presets) < MAX_PRESETS
        )
        self._new_preset_btn.setVisible(bool(can_add))
        self._preset_combo.blockSignals(False)
        # Auto-select "Default Settings" (index 1) on program load
        if has_params and self._preset_combo.count() >= 2:
            self._preset_combo.setCurrentIndex(1)

    def _build_rows(self, program: Program) -> None:
        if not program.parameters:
            lbl = QLabel("No parameters defined for this program.")
            lbl.setStyleSheet("color: #888;")
            self._root_layout.addWidget(lbl)
            self._root_layout.addStretch()
            return

        # Preset selector row (always shown when program has parameters)
        if program.parameters:
            preset_row = QHBoxLayout()
            preset_row.setSpacing(6)
            preset_lbl = QLabel("Preset:")
            preset_lbl.setStyleSheet("color: #aaa; font-weight: bold;")
            preset_lbl.setFixedWidth(50)
            preset_row.addWidget(preset_lbl)
            preset_row.addWidget(self._preset_combo, stretch=1)
            preset_row.addWidget(self._preset_name_edit)
            preset_row.addWidget(self._save_preset_btn)
            preset_row.addWidget(self._new_preset_btn)
            preset_row.addWidget(self._delete_preset_btn)
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
            self._active_preset_index = -1
            self._defaults_selected = False
            self._active_preset_values = {}
            self._save_preset_btn.setVisible(False)
            self._preset_name_edit.setVisible(False)
            self._delete_preset_btn.setVisible(False)
            return  # index 0 is the placeholder "(select preset)"

        item_data = self._preset_combo.itemData(index)

        if item_data == "defaults":
            # "Default Settings" selected — restore program defaults
            self._defaults_selected = True
            self._active_preset_index = -1
            self._loading_preset = True
            try:
                values: dict[str, int] = {}
                for param in self._program.parameters:
                    if param.is_toggle:
                        values[param.parameter_id] = (
                            1 if param.initial_toggle_state else 0
                        )
                    else:
                        values[param.parameter_id] = param.initial_pot_value
                self._active_preset_values = dict(values)
                self.set_values(values)
            finally:
                self._loading_preset = False
            self._preset_name_edit.setVisible(False)
            self._delete_preset_btn.setVisible(False)
            self._update_save_button_state()
            self.registers_changed.emit(self.current_values)
            self.preset_loaded.emit("Default Settings")
            return

        if not isinstance(item_data, Preset):
            return
        # Actual preset — offset 2 accounts for placeholder + Default Settings
        self._defaults_selected = False
        self._active_preset_index = index - 2
        # The _loading_preset flag prevents _on_any_changed from resetting
        # the combo back to the placeholder while we programmatically update
        # each control.
        self._loading_preset = True
        try:
            values = self._program.resolve_preset_values(item_data)
            self._active_preset_values = dict(values)
            self.set_values(values)
        finally:
            self._loading_preset = False
        # Show name editor with current preset name
        self._preset_name_edit.blockSignals(True)
        self._preset_name_edit.setText(item_data.name)
        self._preset_name_edit.blockSignals(False)
        self._preset_name_edit.setVisible(True)
        # Show delete button when a preset is selected
        self._delete_preset_btn.setVisible(True)
        # Save button hidden until values actually differ
        self._update_save_button_state()
        self.registers_changed.emit(self.current_values)
        self.preset_loaded.emit(item_data.name)

    def _on_any_changed(self, _param_id: str, _val: int) -> None:
        # When the user manually tweaks controls while a preset is active,
        # keep the preset selected but show the Save Preset button if
        # values now differ.  If no preset is active, the button stays hidden.
        if not self._loading_preset:
            self._update_save_button_state()
        self.registers_changed.emit(self.current_values)

    def _update_save_button_state(self) -> None:
        """Show the Save Preset button when default settings or a preset is
        active and the current control values (or name) differ."""
        if self._program is None:
            self._save_preset_btn.setVisible(False)
            return

        if self._defaults_selected:
            current = self.current_values
            self._save_preset_btn.setVisible(current != self._active_preset_values)
            return

        if self._active_preset_index < 0:
            self._save_preset_btn.setVisible(False)
            return

        # Check for value differences
        current = self.current_values
        values_differ = current != self._active_preset_values

        # Check for name change
        preset = self._program.presets[self._active_preset_index]
        name_edit_text = self._preset_name_edit.text().strip()
        name_differs = name_edit_text != preset.name and len(name_edit_text) > 0

        self._save_preset_btn.setVisible(values_differ or name_differs)

    def _on_save_preset(self) -> None:
        """Emit the save request with the current values and edited name."""
        if self._program is None:
            return

        if self._defaults_selected:
            self.save_defaults_requested.emit(dict(self.current_values))
            self._active_preset_values = dict(self.current_values)
            self._update_save_button_state()
            return

        if self._active_preset_index < 0:
            return
        name = self._preset_name_edit.text().strip()
        if not name:
            return
        self.save_preset_requested.emit(
            self._active_preset_index,
            dict(self.current_values),
            name,
        )
        # Update the snapshot so the button hides until the next change
        self._active_preset_values = dict(self.current_values)
        # Update the combo item text to reflect the new name
        combo_index = self._active_preset_index + 2  # +2 for placeholder + defaults
        self._preset_combo.setItemText(combo_index, name)
        self._update_save_button_state()

    def _on_new_preset(self) -> None:
        """Create a new preset from the current slider values."""
        if self._program is None:
            return
        if len(self._program.presets) >= MAX_PRESETS:
            return
        name = f"Preset {len(self._program.presets) + 1}"
        self.new_preset_requested.emit(name, dict(self.current_values))

    def _on_delete_preset(self) -> None:
        """Delete the currently selected preset."""
        if self._active_preset_index < 0 or self._program is None:
            return
        self.delete_preset_requested.emit(self._active_preset_index)

    def reload_presets_after_add(self, select_index: int) -> None:
        """Repopulate the preset combo after a new preset was added,
        and select the newly added entry."""
        if self._program is None:
            return
        self._populate_presets(self._program)
        # Select the new preset (combo index = preset_index + 2 for placeholder + defaults)
        combo_idx = select_index + 2
        if combo_idx < self._preset_combo.count():
            self._preset_combo.setCurrentIndex(combo_idx)

    def reload_presets_after_delete(self) -> None:
        """Repopulate the preset combo after a preset was deleted."""
        self._active_preset_index = -1
        self._defaults_selected = False
        self._active_preset_values = {}
        self._save_preset_btn.setVisible(False)
        self._preset_name_edit.setVisible(False)
        self._delete_preset_btn.setVisible(False)
        if self._program is None:
            return
        self._populate_presets(self._program)
