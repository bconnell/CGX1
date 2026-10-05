#!/usr/bin/env python3
"""Resolve repository paths in the shell that owns them."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Callable


class PathTranslationError(RuntimeError):
    """A path could not be translated across a Windows/WSL boundary."""


Runner = Callable[..., subprocess.CompletedProcess[str]]
WSL_COMMAND_TIMEOUT_SECONDS = 120


def _validate_mnt_translation(windows_path: str, linux_path: str) -> str:
    drive = PureWindowsPath(windows_path).drive.rstrip(":").lower()
    parsed = PurePosixPath(linux_path)
    if not drive or not parsed.is_absolute() or parsed.parts[:2] != ("/", "mnt") or len(parsed.parts) < 3:
        expected = f"/mnt/{drive}/" if drive else "/mnt/<drive>/"
        raise PathTranslationError(
            f"Windows path {windows_path!r} translated to {linux_path!r}; expected {expected}..."
        )
    translated_drive = parsed.parts[2].lower()
    if translated_drive != drive:
        raise PathTranslationError(
            f"Windows path {windows_path!r} translated to {linux_path!r}; expected /mnt/{drive}/..."
        )
    return linux_path


def translate_windows_path_to_wsl(
    windows_path: str | Path,
    *,
    wsl_executable: str | Path,
    distribution: str,
    user: str,
    runner: Runner = subprocess.run,
) -> str:
    """Translate a Windows drive path using wslpath in the selected unprivileged distro."""
    raw_path = str(windows_path)
    if not PureWindowsPath(raw_path).is_absolute() or not PureWindowsPath(raw_path).drive:
        raise PathTranslationError(f"expected an absolute Windows drive path, received {raw_path!r}")
    command = [
        str(wsl_executable), "--distribution", distribution, "--user", user,
        "--exec", "wslpath", "-a", "-u", raw_path,
    ]
    try:
        result = runner(
            command, check=False, text=True, encoding="utf-8", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=WSL_COMMAND_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise PathTranslationError(
            f"could not run wslpath for Windows path {raw_path!r}: {error}"
        ) from error
    if result.returncode:
        diagnostic = result.stderr.strip() or result.stdout.strip() or "no wslpath diagnostic"
        raise PathTranslationError(
            f"wslpath could not translate Windows path {raw_path!r}: {diagnostic}"
        )
    translated = result.stdout.strip()
    if not translated:
        raise PathTranslationError(f"wslpath returned an empty path for Windows path {raw_path!r}")
    return _validate_mnt_translation(raw_path, translated)


def resolve_root_argument(
    raw_root: str | Path | None,
    *,
    script_file: str | Path,
    native_os: str | None = None,
    wslpath_runner: Runner = subprocess.run,
) -> Path:
    """Resolve --root natively, translating Windows syntax only inside POSIX/WSL."""
    if raw_root is None:
        return Path(script_file).resolve().parents[1]

    raw_path = str(raw_root)
    native_os = os.name if native_os is None else native_os
    windows_path = PureWindowsPath(raw_path)
    if native_os != "nt" and windows_path.is_absolute() and windows_path.drive:
        try:
            result = wslpath_runner(
                ["wslpath", "-a", "-u", raw_path], check=False, text=True, encoding="utf-8",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=WSL_COMMAND_TIMEOUT_SECONDS,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise PathTranslationError(
                f"cannot use Windows-style --root {raw_path!r} from this POSIX shell: "
                f"wslpath is unavailable ({error}); pass a path native to this shell"
            ) from error
        if result.returncode:
            diagnostic = result.stderr.strip() or result.stdout.strip() or "no wslpath diagnostic"
            raise PathTranslationError(
                f"cannot translate Windows-style --root {raw_path!r}: {diagnostic}; "
                "pass a path native to this shell"
            )
        raw_path = _validate_mnt_translation(raw_path, result.stdout.strip())
    return Path(raw_path).resolve()


def find_wsl_executable() -> str | None:
    """Find WSL despite a Python PATH that differs from the launching PowerShell PATH."""
    system_root = os.environ.get("SystemRoot") or os.environ.get("WINDIR")
    if system_root:
        candidate = Path(system_root) / "System32" / "wsl.exe"
        if candidate.is_file():
            return str(candidate)
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(entry) / "wsl.exe"
        if candidate.is_file():
            return str(candidate)
    return None


def find_windows_powershell() -> str | None:
    """Find Windows PowerShell from SystemRoot before consulting a child Python PATH."""
    system_root = os.environ.get("SystemRoot") or os.environ.get("WINDIR")
    if system_root:
        candidate = Path(system_root) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
        if candidate.is_file():
            return str(candidate)
    return shutil.which("powershell.exe") or shutil.which("powershell") or shutil.which("pwsh")
