# Videomancer SDK - VHDL Image Tester
# File: videomancer-sdk/tools/vhdl-image-tester/vhdl_image_tester/core/program_loader.py - TOML program metadata parser
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.

"""Load and represent Videomancer FPGA program metadata from TOML files."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    try:
        import tomllib  # type: ignore[no-redef]
    except ImportError:
        import tomli as tomllib  # type: ignore[no-redef]

from .config import PROGRAMS_ROOT, PARAM_ID_TO_REGISTER, ABI_REG_TOGGLES, ABI_TOGGLE_BIT


# ---------------------------------------------------------------------------
# Preset dataclass
# ---------------------------------------------------------------------------

@dataclass
class Preset:
    """A named factory preset loaded from a ``[[preset]]`` TOML section.

    Each preset stores a *name* and a sparse mapping of ``parameter_id`` →
    raw value.  Parameters not listed in the preset inherit the program's
    default ``initial_value`` / ``initial_value_label``.
    """

    name:   str
    values: dict[str, int] = field(default_factory=dict)
    """Mapping of parameter_id → raw value (0–1023 for pots, 0/1 for toggles)."""


# ---------------------------------------------------------------------------
# Parameter dataclass
# ---------------------------------------------------------------------------

@dataclass
class Parameter:
    """Describes a single control parameter from the TOML [[parameter]] array."""

    parameter_id:        str
    name_label:          str
    control_mode:        str         = "linear"
    display_min_value:   float       = 0.0
    display_max_value:   float       = 100.0
    initial_value:       int         = 512         # raw 10-bit register value (pots)
    initial_value_label: str         = ""          # "Off" | "On" (toggles)
    suffix_label:        str         = ""
    value_labels:        list[str]   = field(default_factory=list)
    display_float_digits: int        = 0

    @property
    def is_toggle(self) -> bool:
        return self.parameter_id.startswith("toggle_switch_")

    @property
    def is_pot(self) -> bool:
        return self.parameter_id.startswith("rotary_potentiometer_")

    @property
    def is_fader(self) -> bool:
        return self.parameter_id == "linear_potentiometer_12"

    @property
    def register_index(self) -> int:
        return PARAM_ID_TO_REGISTER.get(self.parameter_id, 0)

    @property
    def toggle_bit(self) -> int | None:
        """Bit position within register 6 for toggle switches (or None)."""
        return ABI_TOGGLE_BIT.get(self.parameter_id)

    @property
    def initial_toggle_state(self) -> bool:
        """Resolved initial boolean state for toggle switches.

        Compares ``initial_value_label`` against ``value_labels[0]``
        (the OFF position) when both are available.  Falls back to a
        string exclusion list when ``value_labels`` is not set.
        """
        if self.initial_value_label:
            if len(self.value_labels) >= 2:
                return self.initial_value_label != self.value_labels[0]
            return self.initial_value_label.lower() not in ("off", "0", "false", "")
        return bool(self.initial_value > 511)

    @property
    def initial_pot_value(self) -> int:
        """10-bit raw register value clamped to [0, 1023]."""
        return max(0, min(1023, self.initial_value))


# ---------------------------------------------------------------------------
# Program dataclass
# ---------------------------------------------------------------------------

@dataclass
class Program:
    """Complete metadata for a Videomancer FPGA program."""

    name:           str
    toml_path:      Path
    program_dir:    Path

    # [program] fields
    program_id:     str    = ""
    program_name:   str    = ""
    version:        str    = "1.0.0"
    author:         str    = ""
    categories:     list[str] = field(default_factory=list)
    program_type:   str    = "processing"
    description:    str    = ""
    core:           str    = "yuv444_30b"

    # Pipeline delay override (-1 = auto-detect via testbench, >=0 = fixed clocks)
    pipeline_delay: int    = -1

    # [[parameter]] array
    parameters:     list[Parameter] = field(default_factory=list)

    # [[preset]] array — factory presets from TOML
    presets:        list[Preset] = field(default_factory=list)

    @property
    def vhd_files(self) -> list[Path]:
        """All VHDL files in the program directory, dependency-sorted,
        main architecture last."""
        from .sim_runner import _toposort_vhdl
        all_vhd = sorted(self.program_dir.glob("*.vhd"))
        main_arch = [f for f in all_vhd if _is_program_top_arch(f)]
        supporting = [f for f in all_vhd if f not in main_arch]
        return _toposort_vhdl(supporting) + main_arch

    @property
    def display_name(self) -> str:
        return self.program_name or self.name.title()
    @property
    def effective_pipeline_delay(self) -> int:
        """
        Resolve the pipeline delay in priority order:
          1. TOML ``pipeline_delay`` field (>= 0)
          2. ``C_PROCESSING_DELAY_CLKS`` parsed from the program's VHDL source
          3. 0  (no delay compensation)
        """
        if self.pipeline_delay >= 0:
            return self.pipeline_delay
        vhdl_delay = _parse_processing_delay(self.program_dir)
        if vhdl_delay is not None:
            return vhdl_delay
        return 0
    def get_preset_names(self) -> list[str]:
        """Return a list of available preset names."""
        return [p.name for p in self.presets]

    def get_preset_by_name(self, name: str) -> Preset | None:
        """Look up a preset by name (case-insensitive)."""
        lower = name.lower()
        for p in self.presets:
            if p.name.lower() == lower:
                return p
        return None

    def resolve_preset_values(self, preset: Preset) -> dict[str, int]:
        """Resolve a preset into a full parameter_id → raw value mapping.

        Parameters not specified in the preset inherit from the program's
        default initial values.
        """
        resolved: dict[str, int] = {}
        for param in self.parameters:
            if param.parameter_id in preset.values:
                resolved[param.parameter_id] = preset.values[param.parameter_id]
            elif param.is_toggle:
                resolved[param.parameter_id] = 1 if param.initial_toggle_state else 0
            else:
                resolved[param.parameter_id] = param.initial_pot_value
        return resolved

    def build_register_array(self, values: dict[str, int]) -> list[int]:
        """
        Given a mapping of parameter_id → raw 10-bit value, build the
        full 32-element register array for the FPGA ABI.

        values: {
            "rotary_potentiometer_1": 512,
            "toggle_switch_7": 1,   # 1 = ON, 0 = OFF
            ...
        }
        """
        from .config import ABI_SPI_RAM_SIZE
        regs = [0] * ABI_SPI_RAM_SIZE
        for param in self.parameters:
            raw = values.get(param.parameter_id, param.initial_pot_value if not param.is_toggle else 0)
            if param.is_toggle:
                bit = param.toggle_bit
                if bit is not None and raw:
                    regs[ABI_REG_TOGGLES] |= (1 << bit)
            else:
                regs[param.register_index] = max(0, min(1023, raw))
        return regs


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------

def _is_program_top_arch(path: Path) -> bool:
    """Return True if the file contains 'architecture ... of program_top'."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace").lower()
        return "of program_top" in text
    except OSError:
        return False


_RE_PROCESSING_DELAY = re.compile(
    r"C_PROCESSING_DELAY_CLKS\s*:\s*integer\s*:=\s*(\d+)",
    re.IGNORECASE,
)


def _parse_processing_delay(program_dir: Path) -> int | None:
    """
    Scan .vhd files in *program_dir* for a ``C_PROCESSING_DELAY_CLKS``
    constant declaration and return its integer value, or None if not found.
    """
    for vhd_file in sorted(program_dir.glob("*.vhd")):
        try:
            text = vhd_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        m = _RE_PROCESSING_DELAY.search(text)
        if m:
            return int(m.group(1))
    return None


def load_program(name: str, programs_root: Path | None = None) -> Program:
    """Load a Program from its TOML file by directory name.

    Args:
        name:          The program directory name (e.g. ``"emboss"``)
        programs_root: Override the programs directory. Defaults to the
                       repository-deduced ``PROGRAMS_ROOT`` from *config*.
    """
    root        = programs_root if programs_root is not None else PROGRAMS_ROOT
    program_dir = root / name
    toml_path   = program_dir / f"{name}.toml"
    if not toml_path.exists():
        raise FileNotFoundError(f"TOML not found: {toml_path}")

    with toml_path.open("rb") as fh:
        data = tomllib.load(fh)

    prog_data = data.get("program", {})
    parameters: list[Parameter] = []
    for p in data.get("parameter", []):
        parameters.append(Parameter(
            parameter_id         = p.get("parameter_id", ""),
            name_label           = p.get("name_label", ""),
            control_mode         = p.get("control_mode", "linear"),
            display_min_value    = float(p.get("display_min_value", 0)),
            display_max_value    = float(p.get("display_max_value", 100)),
            initial_value        = int(p.get("initial_value", 512)),
            initial_value_label  = p.get("initial_value_label", ""),
            suffix_label         = p.get("suffix_label", ""),
            value_labels         = p.get("value_labels", []),
            display_float_digits = int(p.get("display_float_digits", 0)),
        ))

    # Parse [[preset]] sections
    presets: list[Preset] = []
    for preset_dict in data.get("preset", []):
        preset_name = preset_dict.get("name", "")
        preset_values: dict[str, int] = {}
        for key, value in preset_dict.items():
            if key == "name":
                continue
            if key in PARAM_ID_TO_REGISTER and isinstance(value, (int, float)):
                preset_values[key] = int(value)
        if preset_name:
            presets.append(Preset(name=preset_name, values=preset_values))

    return Program(
        name         = name,
        toml_path    = toml_path,
        program_dir  = program_dir,
        program_id   = prog_data.get("program_id", ""),
        program_name = prog_data.get("program_name", name.title()),
        version      = prog_data.get("program_version", "1.0.0"),
        author       = prog_data.get("author", ""),
        categories   = (prog_data.get("categories", []) or ([prog_data["category"]] if prog_data.get("category") else [])),
        program_type = prog_data.get("program_type", "processing"),
        description  = prog_data.get("description", ""),
        core         = prog_data.get("core", "yuv444_30b"),
        pipeline_delay = int(prog_data.get("pipeline_delay", -1)),
        parameters   = parameters,
        presets      = presets,
    )


def save_preset_to_toml(
    program: Program,
    preset_index: int,
    new_values: dict[str, int],
    new_name: str | None = None,
) -> None:
    """Rewrite a single ``[[preset]]`` block in the program's TOML file.

    Performs a surgical text-based edit to preserve comments, formatting,
    and all other sections.  Only the target preset block is replaced.

    Args:
        program:      The loaded Program whose TOML file will be modified.
        preset_index: Zero-based index of the preset to update.
        new_values:   Sparse mapping of parameter_id → raw value.  Parameters
                      whose value equals the program default are omitted from
                      the written block to keep the TOML minimal.
        new_name:     Optional new name for the preset.  ``None`` keeps the
                      existing name.

    Raises:
        IndexError:     If *preset_index* is out of range.
        FileNotFoundError: If the TOML file does not exist.
    """
    if preset_index < 0 or preset_index >= len(program.presets):
        raise IndexError(
            f"Preset index {preset_index} out of range "
            f"(program has {len(program.presets)} presets)"
        )

    toml_path = program.toml_path
    lines = toml_path.read_text(encoding="utf-8").splitlines(keepends=True)

    # Locate all [[preset]] block boundaries (start line, exclusive end line).
    preset_starts: list[int] = []
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "[[preset]]":
            preset_starts.append(i)

    if preset_index >= len(preset_starts):
        raise IndexError(
            f"Found only {len(preset_starts)} [[preset]] blocks in {toml_path}"
        )

    block_start  = preset_starts[preset_index]
    if preset_index + 1 < len(preset_starts):
        block_end = preset_starts[preset_index + 1]
    else:
        # Last preset — extends to EOF.  Trim any trailing blank lines so we
        # can add our own clean ending.
        block_end = len(lines)

    # Build the replacement block
    preset = program.presets[preset_index]
    name   = new_name if new_name is not None else preset.name

    new_block_lines = _build_preset_block(program, name, new_values)
    sparse = _sparse_values(program, new_values)

    # Splice into the file
    new_lines = lines[:block_start] + new_block_lines + lines[block_end:]
    toml_path.write_text("".join(new_lines), encoding="utf-8")

    # Update the in-memory preset so the UI stays consistent
    preset.name   = name
    preset.values = sparse


# SDK-defined maximum number of presets per program.
# From vmprog_format.hpp: vmprog_program_config_v1_0::max_presets = 8.
MAX_PRESETS = 8


def _build_preset_block(
    program: Program,
    name: str,
    values: dict[str, int],
) -> list[str]:
    """Build a ``[[preset]]`` TOML block as a list of text lines.

    Only parameters that differ from the program defaults are written
    (sparse representation matching the existing TOML convention).
    """
    _PARAM_ORDER = [
        "rotary_potentiometer_1", "rotary_potentiometer_2",
        "rotary_potentiometer_3", "rotary_potentiometer_4",
        "rotary_potentiometer_5", "rotary_potentiometer_6",
        "toggle_switch_7", "toggle_switch_8", "toggle_switch_9",
        "toggle_switch_10", "toggle_switch_11",
        "linear_potentiometer_12",
    ]
    sparse: dict[str, int] = {}
    for param in program.parameters:
        pid = param.parameter_id
        if pid not in values:
            continue
        raw = values[pid]
        if param.is_toggle:
            default = 1 if param.initial_toggle_state else 0
        else:
            default = param.initial_pot_value
        if raw != default:
            sparse[pid] = raw

    block: list[str] = ["[[preset]]\n", f'name = "{name}"\n']
    for pid in _PARAM_ORDER:
        if pid in sparse:
            block.append(f"{pid} = {sparse[pid]}\n")
    block.append("\n")
    return block


def add_preset_to_toml(
    program: Program,
    name: str,
    values: dict[str, int],
) -> int:
    """Append a new ``[[preset]]`` block to the program's TOML file.

    Args:
        program: The loaded Program whose TOML file will be modified.
        name:    Preset name (max 15 characters).
        values:  Full mapping of parameter_id → raw value.

    Returns:
        The zero-based index of the newly added preset.

    Raises:
        ValueError:  If the program already has ``MAX_PRESETS`` presets.
    """
    if len(program.presets) >= MAX_PRESETS:
        raise ValueError(
            f"Cannot add preset: program already has the maximum of "
            f"{MAX_PRESETS} presets (SDK limit)"
        )
    name = name[:15]  # enforce SDK name_max_length - 1

    toml_path = program.toml_path
    text = toml_path.read_text(encoding="utf-8")

    # Ensure file ends with a newline before we append
    if text and not text.endswith("\n"):
        text += "\n"

    block = _build_preset_block(program, name, values)
    text += "".join(block)
    toml_path.write_text(text, encoding="utf-8")

    # Update in-memory model
    sparse = {k: v for k, v in _sparse_values(program, values).items()}
    new_preset = Preset(name=name, values=sparse)
    program.presets.append(new_preset)
    return len(program.presets) - 1


def _sparse_values(program: Program, values: dict[str, int]) -> dict[str, int]:
    """Return only the values that differ from program defaults."""
    sparse: dict[str, int] = {}
    for param in program.parameters:
        pid = param.parameter_id
        if pid not in values:
            continue
        raw = values[pid]
        if param.is_toggle:
            default = 1 if param.initial_toggle_state else 0
        else:
            default = param.initial_pot_value
        if raw != default:
            sparse[pid] = raw
    return sparse


def delete_preset_from_toml(
    program: Program,
    preset_index: int,
) -> None:
    """Remove a ``[[preset]]`` block from the program's TOML file.

    Args:
        program:      The loaded Program whose TOML file will be modified.
        preset_index: Zero-based index of the preset to delete.

    Raises:
        IndexError: If *preset_index* is out of range.
    """
    if preset_index < 0 or preset_index >= len(program.presets):
        raise IndexError(
            f"Preset index {preset_index} out of range "
            f"(program has {len(program.presets)} presets)"
        )

    toml_path = program.toml_path
    lines = toml_path.read_text(encoding="utf-8").splitlines(keepends=True)

    # Locate all [[preset]] block boundaries.
    preset_starts: list[int] = []
    for i, line in enumerate(lines):
        if line.strip() == "[[preset]]":
            preset_starts.append(i)

    if preset_index >= len(preset_starts):
        raise IndexError(
            f"Found only {len(preset_starts)} [[preset]] blocks in {toml_path}"
        )

    block_start = preset_starts[preset_index]
    if preset_index + 1 < len(preset_starts):
        block_end = preset_starts[preset_index + 1]
    else:
        block_end = len(lines)

    new_lines = lines[:block_start] + lines[block_end:]
    toml_path.write_text("".join(new_lines), encoding="utf-8")

    # Update in-memory model
    del program.presets[preset_index]


def save_defaults_to_toml(
    program: Program,
    values: dict[str, int],
) -> None:
    """Rewrite ``initial_value`` / ``initial_value_label`` fields in each
    ``[[parameter]]`` block of the program's TOML file.

    Performs a surgical text-based edit to preserve comments, formatting,
    and all other sections.

    Args:
        program: The loaded Program whose TOML file will be modified.
        values:  Full mapping of parameter_id → raw value (0–1023 for
                 pots/faders, 0/1 for toggles).
    """
    toml_path = program.toml_path
    lines = toml_path.read_text(encoding="utf-8").splitlines(keepends=True)

    # Locate all [[parameter]] block boundaries.
    param_starts: list[int] = []
    for i, line in enumerate(lines):
        if line.strip() == "[[parameter]]":
            param_starts.append(i)

    for block_idx, start in enumerate(param_starts):
        # Find end of this parameter block.
        if block_idx + 1 < len(param_starts):
            block_end = param_starts[block_idx + 1]
        else:
            block_end = len(lines)
            for j in range(start + 1, len(lines)):
                if lines[j].strip().startswith("["):
                    block_end = j
                    break

        # Identify the parameter_id.
        pid = None
        for j in range(start, block_end):
            m = re.match(r'parameter_id\s*=\s*"([^"]+)"', lines[j].strip())
            if m:
                pid = m.group(1)
                break

        if pid is None or pid not in values:
            continue

        raw = values[pid]
        param = next(
            (p for p in program.parameters if p.parameter_id == pid), None
        )
        if param is None:
            continue

        if param.is_toggle:
            if len(param.value_labels) >= 2:
                label = param.value_labels[1] if raw else param.value_labels[0]
            else:
                label = "On" if raw else "Off"
            for j in range(start, block_end):
                if lines[j].strip().startswith("initial_value_label"):
                    lines[j] = f'initial_value_label = "{label}"\n'
                    break
        else:
            for j in range(start, block_end):
                stripped = lines[j].strip()
                if (
                    stripped.startswith("initial_value")
                    and not stripped.startswith("initial_value_label")
                ):
                    lines[j] = f"initial_value = {raw}\n"
                    break

    toml_path.write_text("".join(lines), encoding="utf-8")

    # Update the in-memory Parameter objects.
    for param in program.parameters:
        pid = param.parameter_id
        if pid not in values:
            continue
        raw = values[pid]
        if param.is_toggle:
            if len(param.value_labels) >= 2:
                param.initial_value_label = (
                    param.value_labels[1] if raw else param.value_labels[0]
                )
            else:
                param.initial_value_label = "On" if raw else "Off"
            param.initial_value = 1023 if raw else 0
        else:
            param.initial_value = raw


def list_programs(programs_root: Path | None = None) -> list[str]:
    """Return sorted list of program directory names that have a matching TOML file.

    Args:
        programs_root: Directory to scan.  Defaults to the repository-deduced
                       ``PROGRAMS_ROOT`` from *config*.
    """
    root = programs_root if programs_root is not None else PROGRAMS_ROOT
    if not root.exists():
        return []
    return sorted(
        d.name
        for d in root.iterdir()
        if d.is_dir() and (d / f"{d.name}.toml").exists()
    )
