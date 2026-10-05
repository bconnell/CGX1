import os
import ast
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_disk_budget as disk_budget
import run_clean_cmake_tests


GIB = 1024**3


class DiskBudgetTests(unittest.TestCase):
    def test_developer_profile_warns_below_fifty_gib(self):
        report = disk_budget.evaluate_budget(
            {"warning_free_bytes": 50 * GIB, "minimum_free_bytes": 40 * GIB},
            49 * GIB,
            None,
        )

        self.assertEqual(report["status"], "warning")
        self.assertIsNone(report["projected_free_bytes"])
        self.assertEqual(report["estimate_status"], "unmeasured")

    def test_developer_profile_fails_below_minimum_reserve(self):
        report = disk_budget.evaluate_budget(
            {"warning_free_bytes": 50 * GIB, "minimum_free_bytes": 40 * GIB},
            39 * GIB,
            None,
        )

        self.assertEqual(report["status"], "unsafe")
        self.assertIn("minimum", report["reason"])

    def test_known_estimate_fails_if_projected_free_space_breaches_reserve(self):
        report = disk_budget.evaluate_budget(
            {"warning_free_bytes": 50 * GIB, "minimum_free_bytes": 40 * GIB},
            45 * GIB,
            6 * GIB,
        )

        self.assertEqual(report["status"], "unsafe")
        self.assertEqual(report["projected_free_bytes"], 39 * GIB)

    def test_exact_reserve_boundary_is_not_unsafe(self):
        report = disk_budget.evaluate_budget(
            {"warning_free_bytes": 50 * GIB, "minimum_free_bytes": 40 * GIB},
            50 * GIB,
            10 * GIB,
        )

        self.assertEqual(report["status"], "warning")
        self.assertEqual(report["projected_free_bytes"], 40 * GIB)

    def test_hosted_profile_uses_its_independent_reserve(self):
        report = disk_budget.evaluate_budget(
            {"warning_free_bytes": None, "minimum_free_bytes": 2 * GIB},
            3 * GIB,
            2 * GIB,
        )

        self.assertEqual(report["status"], "unsafe")
        self.assertEqual(report["projected_free_bytes"], GIB)

    def test_warning_can_block_optional_work_in_developer_profile(self):
        report = disk_budget.evaluate_budget(
            {"warning_free_bytes": 50 * GIB, "minimum_free_bytes": 40 * GIB},
            49 * GIB,
            1,
            block_when_warning=True,
        )

        self.assertEqual(report["status"], "unsafe")
        self.assertIn("optional", report["reason"])

    def test_nonexistent_output_path_uses_nearest_existing_parent(self):
        with tempfile.TemporaryDirectory() as temporary:
            expected = Path(temporary).resolve()
            output = expected / "candidate" / "build" / "rtl"

            self.assertEqual(disk_budget.nearest_existing_path(output), expected)

    def test_windows_path_is_rejected_on_posix_until_translated(self):
        if os.name == "nt":
            self.skipTest("Windows-native path syntax is valid on Windows")

        with self.assertRaisesRegex(disk_budget.DiskBudgetError, "translate.*Linux"):
            disk_budget.nearest_existing_path(r"C:\Users\collu\source\repos\CGX1\build")

    def test_volume_measurement_uses_resolved_existing_parent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            output = root / "not-created" / "build"
            usage = type("Usage", (), {"total": 100, "used": 10, "free": 90})()
            with patch.object(disk_budget.shutil, "disk_usage", return_value=usage) as mocked:
                result = disk_budget.measure_output_volume(output)

            self.assertEqual(result["probe_path"], str(root))
            self.assertEqual(result["free_bytes"], 90)
            mocked.assert_called_once_with(root)

    def test_volume_measurement_fails_closed_when_filesystem_cannot_be_read(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(disk_budget.shutil, "disk_usage", side_effect=OSError("denied")):
                with self.assertRaisesRegex(disk_budget.DiskBudgetError, "cannot measure the filesystem"):
                    disk_budget.measure_output_volume(Path(temporary) / "build")

    def test_linux_mnt_c_path_is_measured_in_its_native_view(self):
        translated = Path("/mnt/c")
        if os.name == "nt" or not translated.exists():
            self.skipTest("the translated Windows drive is available only in WSL")

        probe_path = disk_budget.nearest_existing_path(translated / "cgx1-disk-budget-probe" / "build")
        result = disk_budget.measure_output_volume(translated / "cgx1-disk-budget-probe" / "build")

        self.assertTrue(probe_path.is_relative_to(translated.resolve()))
        self.assertEqual(Path(result["probe_path"]), probe_path)
        self.assertEqual(result["free_bytes"], disk_budget.shutil.disk_usage(probe_path).free)

    def test_artifact_scan_rejects_oversized_waveform_or_test_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            waveform = root / "unexpected.vcd"
            with waveform.open("wb") as output:
                output.truncate(1025)
            test_log = root / "oversized-test-output.log"
            with test_log.open("wb") as output:
                output.truncate(2049)

            report = disk_budget.scan_generated_artifacts(
                root, max_waveform_bytes=1024, max_test_output_bytes=1024
            )

            self.assertFalse(report["passed"])
            self.assertEqual({item["path"] for item in report["oversized"]},
                             {str(waveform), str(test_log)})
            by_path = {item["path"]: item for item in report["oversized"]}
            self.assertEqual(by_path[str(waveform)]["bytes"], 1025)
            self.assertEqual(by_path[str(test_log)]["bytes"], 2049)

    def test_artifact_scan_does_not_follow_symlinked_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "output"
            outside = Path(temporary) / "large.vcd"
            root.mkdir()
            with outside.open("wb") as output:
                output.truncate(4096)
            link = root / "external.vcd"
            try:
                link.symlink_to(outside)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation is unavailable: {error}")

            report = disk_budget.scan_generated_artifacts(
                root, max_waveform_bytes=1024, max_test_output_bytes=1024,
            )

            self.assertTrue(report["passed"])
            self.assertEqual(report["files_scanned"], 0)

    def test_artifact_scan_detects_growth_beyond_a_measured_tree_baseline(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "first.log").write_bytes(b"1234")
            (root / "second.log").write_bytes(b"5678")

            report = disk_budget.scan_generated_artifacts(
                root, max_waveform_bytes=16, max_test_output_bytes=16, max_tree_bytes=7,
            )

            self.assertFalse(report["passed"])
            self.assertEqual(report["oversized"][0]["kind"], "output_tree")
            self.assertEqual(report["oversized"][0]["bytes"], 8)

    def test_profile_auto_selects_hosted_only_inside_github_actions(self):
        self.assertEqual(
            disk_budget.select_profile("auto", {"GITHUB_ACTIONS": "true"}), "hosted"
        )
        self.assertEqual(
            disk_budget.select_profile("auto", {"GITHUB_ACTIONS": "false"}), "developer"
        )

    def test_repository_policy_keeps_required_classes_with_unknown_sizes_explicit(self):
        policy = disk_budget.load_disk_policy(Path(__file__).resolve().parents[2])

        self.assertEqual(policy["profiles"]["developer"]["minimum_free_bytes"], 40 * GIB)
        self.assertEqual(policy["profiles"]["hosted"]["minimum_free_bytes"], 2 * GIB)
        for operation in ("gcc-debug", "gcc-release", "clang-debug", "clang-release",
                          "sanitizer-build", "hosted-tool-install", "verilator-toolchain-build",
                          "synthesis-smoke", "formal", "clean-candidate"):
            self.assertIsNone(policy["operations"][operation]["estimated_peak_bytes"])
            self.assertEqual(policy["operations"][operation]["measurement_status"], "unmeasured")
        self.assertEqual(policy["operations"]["icarus"]["estimated_peak_bytes"], 15789147)
        self.assertEqual(policy["operations"]["icarus"]["measurement_status"], "estimate")
        self.assertIn("not a filesystem high-water", policy["operations"]["icarus"]["measurement_source"])
        self.assertEqual(policy["operations"]["icarus"]["maximum_output_tree_bytes"], 2 * 15789147)

    def test_policy_rejects_unmeasured_size_labeled_as_measured(self):
        document = {
            "disk_budget": {
                "profiles": {
                    "developer": {"warning_free_bytes": 50 * GIB, "minimum_free_bytes": 40 * GIB},
                    "hosted": {"warning_free_bytes": None, "minimum_free_bytes": 2 * GIB},
                },
                "operations": {
                    name: {"estimated_peak_bytes": None, "measurement_status": "unmeasured",
                           "block_when_warning": False}
                    for name in ("clean-candidate", "clean-cmake", "wsl-candidate", "gcc-debug",
                                 "gcc-release", "clang-debug", "clang-release", "sanitizer-build",
                                 "hosted-tool-install", "icarus", "verilator-toolchain-build", "rtl-tools",
                                 "synthesis-smoke", "formal")
                },
                "artifact_limits": {
                    "maximum_waveform_file_bytes": 1,
                    "maximum_test_output_file_bytes": 1,
                },
            }
        }
        document["disk_budget"]["operations"]["icarus"]["measurement_status"] = "measured"

        with self.assertRaisesRegex(disk_budget.DiskBudgetError, "must be labeled unmeasured"):
            disk_budget.validate_disk_policy(document)

    def test_unknown_operation_fails_closed(self):
        root = Path(__file__).resolve().parents[2]
        with self.assertRaisesRegex(disk_budget.DiskBudgetError, "has no registered disk-budget policy"):
            disk_budget.preflight_disk_budget(root, "unknown-large-job", root / "build")

    def test_cmake_preflight_precedes_build_directory_creation(self):
        root = Path(__file__).resolve().parents[2]
        source = (root / "scripts/run_clean_cmake_tests.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
        calls = [(node.lineno, node.func.id if isinstance(node.func, ast.Name) else node.func.attr)
                 for node in ast.walk(main) if isinstance(node, ast.Call)]
        preflight_line = min(line for line, name in calls if name == "preflight_disk_budget")
        mkdir_line = min(line for line, name in calls if name == "mkdir")
        temporary_line = min(line for line, name in calls if name == "mkdtemp")

        self.assertLess(preflight_line, mkdir_line)
        self.assertLess(preflight_line, temporary_line)

    def test_cmake_runner_fails_closed_before_creating_output_when_reserve_is_unsafe(self):
        root = Path(__file__).resolve().parents[2]
        build_root = root / "build" / "clean-validation"
        before = sorted(path.name for path in build_root.iterdir()) if build_root.exists() else []
        output = io.StringIO()
        with patch.dict(os.environ, {
            "CGX1_DISK_WARNING_FREE_BYTES": "9999999999999",
            "CGX1_DISK_MINIMUM_FREE_BYTES": "9999999999998",
        }), patch.object(run_clean_cmake_tests.shutil, "which", return_value="mock-tool"), patch.object(
            sys, "argv", ["run_clean_cmake_tests.py", "--root", str(root), "--config", "Debug"],
        ), redirect_stdout(output):
            result = run_clean_cmake_tests.main()

        after = sorted(path.name for path in build_root.iterdir()) if build_root.exists() else []
        self.assertEqual(2, result)
        self.assertIn("[disk-budget] unsafe", output.getvalue())
        self.assertEqual(before, after, "unsafe preflight must not create a temporary build")

    def test_clean_candidate_preflight_precedes_worktree_creation(self):
        root = Path(__file__).resolve().parents[2]
        source = (root / "scripts/validate_clean_candidate.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
        calls = [(node.lineno, node.func.id if isinstance(node.func, ast.Name) else node.func.attr)
                 for node in ast.walk(main) if isinstance(node, ast.Call)]
        preflight_line = min(line for line, name in calls if name == "preflight_disk_budget")
        create_line = min(line for line, name in calls if name == "create_clean_candidate")

        self.assertLess(preflight_line, create_line)

    def test_rtl_shell_preflights_and_scans_before_and_after_output(self):
        root = Path(__file__).resolve().parents[2]
        source = (root / "scripts/validate_rtl.sh").read_text(encoding="utf-8")
        preflight = "--operation icarus --output-path build/rtl --scan-root build/rtl"
        self.assertEqual(source.count(preflight), 2)
        self.assertLess(source.index("python3 scripts/check_disk_budget.py"),
                        source.index("mkdir -p build/rtl/logs"))
        self.assertGreater(source.rindex("python3 scripts/check_disk_budget.py"),
                           source.index("python3 scripts/validate_rtl_warnings.py"))

    def test_rtl_tools_preflight_precedes_output_creation_and_checks_each_yosys_stage(self):
        root = Path(__file__).resolve().parents[2]
        source = (root / "scripts/validate_rtl_tools.sh").read_text(encoding="utf-8")
        self.assertLess(source.index("--operation rtl-tools"), source.index("mkdir -p build/rtl-tools/logs"))
        self.assertIn("--operation formal --output-path", source)
        self.assertIn("--operation synthesis-smoke --output-path", source)
        self.assertEqual(source.count("--scan-root build/rtl-tools"), 2)

    def test_hosted_heavy_workflows_select_hosted_profile_before_builds(self):
        root = Path(__file__).resolve().parents[2]
        sanitizer = (root / ".github/workflows/linux-sanitizers.yml").read_text(encoding="utf-8")
        rtl_tools = (root / ".github/workflows/rtl-tools.yml").read_text(encoding="utf-8")
        rtl_ci = (root / ".github/workflows/rtl-ci.yml").read_text(encoding="utf-8")
        self.assertLess(sanitizer.index("--profile hosted"), sanitizer.index("run: cmake -S . -B build/sanitizers"))
        self.assertLess(rtl_tools.index("--profile hosted"), rtl_tools.index("path: .tools/verilator"))
        self.assertLess(rtl_tools.index("--profile hosted"), rtl_tools.index("- name: Install Yosys and Verilator build prerequisites"))
        self.assertLess(rtl_ci.index("--profile hosted"), rtl_ci.index("- name: Install Icarus Verilog"))
        for output_path in ("/usr", "/var/lib/apt/lists", "/var/cache/apt/archives"):
            self.assertIn(output_path, rtl_ci)
            self.assertIn(output_path, rtl_tools)


if __name__ == "__main__":
    unittest.main()
