from __future__ import annotations

import subprocess
import unittest
import os
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch

from scripts.validation_paths import (
    PathTranslationError,
    find_wsl_executable,
    find_windows_powershell,
    resolve_root_argument,
    translate_windows_path_to_wsl,
)


class ValidationPathTests(unittest.TestCase):
    def test_windows_path_crosses_wsl_boundary_with_wslpath_and_preserves_spaces(self):
        windows_path = r"C:\Users\Collu\CGX1 Repo"
        runner = Mock(return_value=subprocess.CompletedProcess(
            args=[], returncode=0, stdout="/mnt/c/Users/Collu/CGX1 Repo\n", stderr=""
        ))

        linux_path = translate_windows_path_to_wsl(
            windows_path, wsl_executable="C:/Windows/System32/wsl.exe",
            distribution="Ubuntu", user="nobody", runner=runner,
        )

        self.assertEqual("/mnt/c/Users/Collu/CGX1 Repo", linux_path)
        command = runner.call_args.args[0]
        self.assertEqual(
            ["C:/Windows/System32/wsl.exe", "--distribution", "Ubuntu", "--user", "nobody",
             "--exec", "wslpath", "-a", "-u", windows_path],
            command,
        )
        self.assertEqual(120, runner.call_args.kwargs["timeout"])

    def test_wsl_translation_must_return_the_expected_mnt_drive_path(self):
        runner = Mock(return_value=subprocess.CompletedProcess(
            args=[], returncode=0, stdout="/home/nobody/CGX1\n", stderr=""
        ))

        with self.assertRaisesRegex(PathTranslationError, r"expected /mnt/c/"):
            translate_windows_path_to_wsl(
                r"C:\Users\Collu\CGX1", wsl_executable="wsl.exe", distribution="Ubuntu",
                user="nobody", runner=runner,
            )

    def test_translation_failure_reports_wslpath_diagnostic(self):
        runner = Mock(return_value=subprocess.CompletedProcess(
            args=[], returncode=1, stdout="", stderr="wslpath: path not found"
        ))

        with self.assertRaisesRegex(PathTranslationError, "wslpath: path not found"):
            translate_windows_path_to_wsl(
                r"C:\missing\CGX1", wsl_executable="wsl.exe", distribution="Ubuntu",
                user="nobody", runner=runner,
            )

    @unittest.skipIf(os.name == "nt", "exercise POSIX pathlib semantics in the unprivileged WSL suite")
    def test_windows_syntax_passed_inside_wsl_is_translated_explicitly(self):
        runner = Mock(return_value=subprocess.CompletedProcess(
            args=[], returncode=0, stdout="/mnt/c/Users/Collu/CGX1\n", stderr=""
        ))

        root = resolve_root_argument(
            r"C:\Users\Collu\CGX1", script_file=Path("/mnt/c/Users/Collu/CGX1/scripts/tool.py"),
            native_os="posix", wslpath_runner=runner,
        )

        self.assertEqual(Path("/mnt/c/Users/Collu/CGX1"), root)
        self.assertEqual(["wslpath", "-a", "-u", r"C:\Users\Collu\CGX1"],
                         runner.call_args.args[0])
        self.assertEqual(120, runner.call_args.kwargs["timeout"])

    @unittest.skipIf(os.name == "nt", "exercise POSIX pathlib semantics in the unprivileged WSL suite")
    def test_default_root_is_discovered_from_the_script_location(self):
        root = resolve_root_argument(
            None, script_file=Path("/mnt/c/project/scripts/validator.py"), native_os="posix"
        )

        self.assertEqual(Path("/mnt/c/project"), root)

    def test_windows_powershell_is_found_from_systemroot_when_child_path_differs(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-systemroot-") as directory:
            executable = Path(directory) / "System32/WindowsPowerShell/v1.0/powershell.exe"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b"")

            with patch.dict(os.environ, {"SystemRoot": directory, "PATH": ""}, clear=False):
                self.assertEqual(str(executable), find_windows_powershell())

    def test_wsl_is_found_from_systemroot_when_child_path_differs(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-systemroot-wsl-") as directory:
            executable = Path(directory) / "System32/wsl.exe"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b"")

            with patch.dict(os.environ, {"SystemRoot": directory, "PATH": ""}, clear=False):
                self.assertEqual(str(executable), find_wsl_executable())


if __name__ == "__main__":
    unittest.main()
