from __future__ import annotations

import json
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
import tempfile
from unittest.mock import patch

from scripts import run_clean_cmake_tests


class CleanCMakeInventoryTests(unittest.TestCase):
    def test_human_inventory_fallback_recovers_registered_tests(self) -> None:
        inventory = getattr(run_clean_cmake_tests, "ctest_inventory_count", None)
        self.assertIsNotNone(inventory, "clean runner must provide a tested CTest inventory parser")
        count, source = inventory(
            '{"kind":"ctestInfo","tests":[]}',
            "Test project C:/build\n  Test #1: first_check\n  Test #2: second_check\n",
        )
        self.assertEqual((2, "human"), (count, source))

    def test_empty_json_and_human_inventories_stay_empty(self) -> None:
        inventory = getattr(run_clean_cmake_tests, "ctest_inventory_count", None)
        self.assertIsNotNone(inventory, "clean runner must provide a tested CTest inventory parser")
        self.assertEqual(
            (0, "empty"),
            inventory('{"kind":"ctestInfo","tests":[]}', "Test project C:/build\nNo tests were found!!!\n"),
        )

    def test_json_inventory_remains_preferred_when_present(self) -> None:
        inventory = getattr(run_clean_cmake_tests, "ctest_inventory_count", None)
        self.assertIsNotNone(inventory, "clean runner must provide a tested CTest inventory parser")
        self.assertEqual(
            (2, "json"),
            inventory('{"kind":"ctestInfo","tests":[{},{}]}', "No tests were found!!!\n"),
        )

    def test_old_temporary_build_is_reported_before_new_candidate_is_created(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-stale-clean-build-") as temporary:
            root = Path(temporary)
            stale = root / "cgx1-clean-cmake-interrupted"
            stale.mkdir()

            with self.assertRaisesRegex(RuntimeError, "determine whether it is active"):
                run_clean_cmake_tests.require_no_stale_clean_builds(root)

            self.assertTrue(stale.is_dir(), "the stale-output guard must not delete unknown build data")

    def test_clean_build_root_must_remain_under_the_build_directory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-build-root-") as temporary:
            root = Path(temporary)
            build_root = root / "other-output"
            with self.assertRaisesRegex(run_clean_cmake_tests.DiskBudgetError, "build directory"):
                run_clean_cmake_tests.require_build_root_inside_repo(root, build_root)

    def test_clean_build_root_rejects_a_redirected_path_inside_the_repository(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-build-link-") as temporary:
            root = Path(temporary)
            build_directory = root / "build"
            build_directory.mkdir()
            target = root / "docs"
            target.mkdir()
            build_root = build_directory / "clean-validation"
            with patch(
                "scripts.run_clean_cmake_tests.is_redirected_path",
                side_effect=lambda path, *_args: Path(path) == build_root,
            ):
                with self.assertRaisesRegex(run_clean_cmake_tests.DiskBudgetError, "redirected"):
                    run_clean_cmake_tests.require_build_root_inside_repo(root, build_root)

    def test_output_size_measurement_fails_closed_when_a_file_cannot_be_read(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-size-read-") as temporary:
            root = Path(temporary)
            (root / "unreadable.bin").write_bytes(b"output")
            with patch.object(Path, "lstat", side_effect=PermissionError("denied")):
                with self.assertRaisesRegex(run_clean_cmake_tests.DiskBudgetError, "cannot measure"):
                    run_clean_cmake_tests.tree_bytes(root)

    def test_failed_build_records_partial_output_size_before_cleanup(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-build-failure-") as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text("project(failure_fixture)\n", encoding="utf-8")
            summary_path = root / "summary.json"
            identity = {
                "candidate_path": str(root.resolve()),
                "git_head": "a" * 40,
                "head_tree": "b" * 40,
                "index_tree": "b" * 40,
                "source_fingerprint": "c" * 64,
            }
            build_commands = []

            def fake_run(command, cwd, started, budget_seconds):
                del cwd, started, budget_seconds
                if command[0] == "cmake" and "-B" in command:
                    build = Path(command[command.index("-B") + 1])
                    build.mkdir(parents=True)
                    (build / "partial-output.bin").write_bytes(b"x" * 16384)
                    return 0.01
                if command[0] == "cmake" and "--build" in command:
                    build_commands.append(command)
                    raise subprocess.CalledProcessError(1, command, output="mock build failure")
                self.fail(f"unexpected command: {command}")

            def fake_ctest_inventory(command, **kwargs):
                return subprocess.CompletedProcess(
                    command, 0, stdout='{"tests":[{}]}', stderr="",
                )

            output = StringIO()
            error = StringIO()
            with patch.object(sys, "argv", [
                "run_clean_cmake_tests.py", "--root", str(root), "--config", "Debug",
                "--summary-json", str(summary_path),
            ]), patch.object(run_clean_cmake_tests, "source_identity", return_value=identity), patch.object(
                run_clean_cmake_tests, "preflight_disk_budget", return_value={
                    "status": "info", "reason": "fixture", "free_bytes": 10**9,
                    "minimum_free_bytes": 1, "filesystem_probe_path": str(root),
                },
            ), patch.object(run_clean_cmake_tests, "format_preflight_report", return_value="disk fixture"), patch.object(
                run_clean_cmake_tests.shutil, "which", return_value="mock-tool",
            ), patch.object(run_clean_cmake_tests, "first_line", return_value="mock version"), patch.object(
                run_clean_cmake_tests, "run", side_effect=fake_run,
            ), patch.object(run_clean_cmake_tests.subprocess, "run", side_effect=fake_ctest_inventory), redirect_stdout(
                output,
            ), redirect_stderr(error):
                result = run_clean_cmake_tests.main()

            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            self.assertEqual(1, result)
            self.assertEqual(1, len(build_commands))
            self.assertEqual(
                run_clean_cmake_tests.os.name == "nt",
                "--verbose" in build_commands[0],
                "Windows clean builds need compiler invocation diagnostics in the hosted log",
            )
            self.assertEqual("failed", summary["status"])
            self.assertEqual("Debug", summary["failed_configuration"]["name"])
            self.assertEqual(16384, summary["failed_configuration"]["build_tree_bytes"])
            self.assertEqual(16384, summary["peak_configuration_tree_bytes"])
            self.assertFalse((root / "build").exists(), "partial clean-build output must be removed after measurement")

    def test_clean_cmake_output_tree_uses_the_compiler_operation_budget(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-tree-budget-") as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text("project(tree_fixture)\n", encoding="utf-8")
            summary_path = root / "summary.json"
            identity = {
                "candidate_path": str(root.resolve()),
                "git_head": "a" * 40,
                "head_tree": "b" * 40,
                "index_tree": "b" * 40,
                "source_fingerprint": "c" * 64,
            }

            def fake_run(command, cwd, started, budget_seconds):
                del cwd, started, budget_seconds
                if command[0] == "cmake" and "-B" in command:
                    build = Path(command[command.index("-B") + 1])
                    build.mkdir(parents=True)
                    (build / "large-build-output.bin").write_bytes(b"x" * 2048)
                    return 0.01
                if command[0] == "cmake" and "--build" in command:
                    return 0.01
                if command[0] == "ctest":
                    return 0.01
                self.fail(f"unexpected command: {command}")

            def fake_ctest_inventory(command, **kwargs):
                return subprocess.CompletedProcess(
                    command, 0, stdout='{"tests":[{}]}', stderr="",
                )

            policy = {
                "operations": {"clean-cmake": {"maximum_output_tree_bytes": 1024}},
                "artifact_limits": {
                    "maximum_waveform_file_bytes": 1024,
                    "maximum_test_output_file_bytes": 4096,
                },
            }
            with patch.object(sys, "argv", [
                "run_clean_cmake_tests.py", "--root", str(root), "--config", "Debug",
                "--summary-json", str(summary_path),
            ]), patch.object(run_clean_cmake_tests, "source_identity", return_value=identity), patch.object(
                run_clean_cmake_tests, "preflight_disk_budget", return_value={
                    "status": "info", "reason": "fixture", "free_bytes": 10**9,
                    "minimum_free_bytes": 1, "filesystem_probe_path": str(root),
                },
            ), patch.object(run_clean_cmake_tests, "format_preflight_report", return_value="disk fixture"), patch.object(
                run_clean_cmake_tests, "compiler_operation", return_value="clean-cmake",
            ), patch.object(run_clean_cmake_tests, "load_disk_policy", return_value=policy), patch.object(
                run_clean_cmake_tests.shutil, "which", return_value="mock-tool",
            ), patch.object(run_clean_cmake_tests, "first_line", return_value="mock version"), patch.object(
                run_clean_cmake_tests, "run", side_effect=fake_run,
            ), patch.object(run_clean_cmake_tests.subprocess, "run", side_effect=fake_ctest_inventory), redirect_stdout(
                StringIO(),
            ), redirect_stderr(StringIO()):
                result = run_clean_cmake_tests.main()

            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            self.assertEqual(1, result)
            self.assertEqual("output_tree", summary["artifact_scan_failure"]["oversized"][0]["kind"])
            self.assertEqual(1024, summary["artifact_scan_failure"]["oversized"][0]["limit_bytes"])
            self.assertEqual(2048, summary["failed_configuration"]["build_tree_bytes"])
            self.assertFalse((root / "build").exists(), "unsafe build output must be measured before cleanup")

    def test_cleanup_guard_refuses_a_symlink_inside_its_owned_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-cleanup-redirection-") as temporary:
            root = Path(temporary)
            parent = root / "parent"
            owned = parent / "cgx1-clean-cmake-test"
            outside = root / "outside"
            parent.mkdir()
            owned.mkdir()
            outside.mkdir()
            link = owned / "redirect"
            try:
                link.symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation is unavailable: {error}")

            with self.assertRaisesRegex(RuntimeError, "redirected path"):
                run_clean_cmake_tests.require_safe_owned_tree(owned, parent, "cgx1-clean-cmake-")

            self.assertTrue(outside.is_dir(), "cleanup preflight must not traverse the redirection")


if __name__ == "__main__":
    unittest.main()
