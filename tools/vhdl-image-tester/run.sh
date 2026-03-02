#!/bin/bash
# Videomancer SDK - VHDL Image Tester — Linux/macOS launcher
# Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.
#
# Usage:
#   ./run.sh              Launch the application
#   ./run.sh --install    Create venv and install dependencies first
#   ./run.sh --test       Run the test suite
#   ./run.sh --lint       Run linter and type checker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
PYTHON="${VENV_DIR}/bin/python3"
PIP="${VENV_DIR}/bin/pip"

# ── Helpers ───────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║      LZX VHDL Image Tester           ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
}

ensure_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
        echo "Installing dependencies..."
        "$PIP" install --upgrade pip
        "$PIP" install -e "${SCRIPT_DIR}[dev]"
        echo "Environment ready."
    fi
}

# ── Commands ──────────────────────────────────────────────────────────────

do_install() {
    print_header
    echo "Setting up environment..."
    if [ -d "$VENV_DIR" ]; then
        echo "Removing existing venv..."
        rm -rf "$VENV_DIR"
    fi
    python3 -m venv "$VENV_DIR"
    "$PIP" install --upgrade pip
    "$PIP" install -e "${SCRIPT_DIR}[dev]"
    echo ""
    echo "Done. Run ./run.sh to launch."
}

do_test() {
    ensure_venv
    echo "Running tests..."
    "$PYTHON" -m pytest "$SCRIPT_DIR/tests" -v "$@"
}

do_lint() {
    ensure_venv
    echo "Running ruff..."
    "$PYTHON" -m ruff check "$SCRIPT_DIR/vhdl_image_tester/"
    echo ""
    echo "Running mypy..."
    "$PYTHON" -m mypy "$SCRIPT_DIR/vhdl_image_tester/" || true
}

do_run() {
    ensure_venv
    print_header
    "$PYTHON" -m vhdl_image_tester "$@"
}

# ── Entry point ───────────────────────────────────────────────────────────

cd "$SCRIPT_DIR"

case "${1:-}" in
    --install)
        do_install
        ;;
    --test)
        shift
        do_test "$@"
        ;;
    --lint)
        do_lint
        ;;
    --help|-h)
        print_header
        echo "Usage: ./run.sh [OPTION]"
        echo ""
        echo "Options:"
        echo "  (none)      Launch the application"
        echo "  --install   Create venv and install all dependencies"
        echo "  --test      Run the test suite (pytest)"
        echo "  --lint      Run linter (ruff) and type checker (mypy)"
        echo "  --help      Show this help message"
        ;;
    *)
        do_run "$@"
        ;;
esac
