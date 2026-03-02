@echo off
REM Videomancer SDK - VHDL Image Tester — Windows launcher
REM Copyright (C) 2026 LZX Industries LLC. All Rights Reserved.
REM
REM Usage:
REM   run.bat              Launch the application
REM   run.bat --install    Create venv and install dependencies first
REM   run.bat --test       Run the test suite
REM   run.bat --lint       Run linter and type checker

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "VENV_DIR=%SCRIPT_DIR%.venv"
set "PYTHON=%VENV_DIR%\Scripts\python.exe"
set "PIP=%VENV_DIR%\Scripts\pip.exe"

REM ── Route command ───────────────────────────────────────────────────────

if "%~1"=="--install" goto :do_install
if "%~1"=="--test"    goto :do_test
if "%~1"=="--lint"    goto :do_lint
if "%~1"=="--help"    goto :do_help
if "%~1"=="-h"        goto :do_help
goto :do_run

REM ── Helpers ─────────────────────────────────────────────────────────────

:print_header
echo.
echo +======================================+
echo ^|      LZX VHDL Image Tester           ^|
echo +======================================+
echo.
goto :eof

:ensure_venv
if exist "%VENV_DIR%\Scripts\python.exe" goto :eof
echo Creating virtual environment...
python -m venv "%VENV_DIR%"
echo Installing dependencies...
"%PIP%" install --upgrade pip
"%PIP%" install -e "%SCRIPT_DIR%[dev]"
echo Environment ready.
goto :eof

REM ── Commands ────────────────────────────────────────────────────────────

:do_install
call :print_header
echo Setting up environment...
if exist "%VENV_DIR%" (
    echo Removing existing venv...
    rmdir /s /q "%VENV_DIR%"
)
python -m venv "%VENV_DIR%"
"%PIP%" install --upgrade pip
"%PIP%" install -e "%SCRIPT_DIR%[dev]"
echo.
echo Done. Run run.bat to launch.
goto :end

:do_test
call :ensure_venv
echo Running tests...
"%PYTHON%" -m pytest "%SCRIPT_DIR%tests" -v %2 %3 %4 %5
goto :end

:do_lint
call :ensure_venv
echo Running ruff...
"%PYTHON%" -m ruff check "%SCRIPT_DIR%vhdl_image_tester\"
echo.
echo Running mypy...
"%PYTHON%" -m mypy "%SCRIPT_DIR%vhdl_image_tester\"
goto :end

:do_run
call :ensure_venv
call :print_header
"%PYTHON%" -m vhdl_image_tester %*
goto :end

:do_help
call :print_header
echo Usage: run.bat [OPTION]
echo.
echo Options:
echo   (none)      Launch the application
echo   --install   Create venv and install all dependencies
echo   --test      Run the test suite (pytest)
echo   --lint      Run linter (ruff) and type checker (mypy)
echo   --help      Show this help message
goto :end

:end
endlocal
