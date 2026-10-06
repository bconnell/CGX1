import os
import ast
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
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

    def test_verilator_file_limit_allows_measured_binary_without_guessing_combined_tree_size(self):
        root = Path(__file__).resolve().parents[2]
        policy = disk_budget.load_disk_policy(root)
        operation = policy["operations"]["verilator-toolchain-build"]
        limits = disk_budget.artifact_limits_for_operation(
            policy, "verilator-toolchain-build",
        )

        self.assertEqual(268435456, limits["maximum_test_output_file_bytes"])
        self.assertGreater(limits["maximum_test_output_file_bytes"], 231709824)
        self.assertIsNone(operation.get("maximum_output_tree_bytes"))
        self.assertIsNone(operation["estimated_peak_bytes"])
        self.assertEqual("unmeasured", operation["measurement_status"])
        self.assertTrue(any(
            "257,576,704" in note and "complete Verilator source-build plus installed-prefix size remains unmeasured" in note
            for note in policy["measurement_notes"]
        ))

        with tempfile.TemporaryDirectory(prefix="cgx1-verilator-budget-") as temporary:
            output = Path(temporary) / "bin" / "verilator_bin_dbg"
            output.parent.mkdir()
            output.write_bytes(b"x" * 2048)
            policy["artifact_limits"]["maximum_test_output_file_bytes"] = 1024
            policy["operations"]["verilator-toolchain-build"][
                "maximum_test_output_file_bytes"
            ] = 4096
            limits = disk_budget.artifact_limits_for_operation(
                policy, "verilator-toolchain-build",
            )
            report = disk_budget.scan_generated_artifacts(
                temporary,
                max_waveform_bytes=limits["maximum_waveform_file_bytes"],
                max_test_output_bytes=limits["maximum_test_output_file_bytes"],
                max_tree_bytes=operation.get("maximum_output_tree_bytes"),
            )
            self.assertTrue(report["passed"], report)
            report = disk_budget.scan_generated_artifacts(
                temporary,
                max_waveform_bytes=limits["maximum_waveform_file_bytes"],
                max_test_output_bytes=limits["maximum_test_output_file_bytes"],
                max_tree_bytes=1024,
            )
            self.assertFalse(report["passed"])
            self.assertEqual("output_tree", report["oversized"][0]["kind"])

    def test_cli_applies_operation_specific_artifact_file_limit(self):
        budget = {
            "profiles": {"hosted": {"minimum_free_bytes": 1}},
            "operations": {"verilator-toolchain-build": {
                "estimated_peak_bytes": None,
                "block_when_warning": False,
                "maximum_test_output_file_bytes": 4096,
                "maximum_output_tree_bytes": 8192,
            }},
            "artifact_limits": {
                "maximum_waveform_file_bytes": 1024,
                "maximum_test_output_file_bytes": 1024,
            },
        }
        with tempfile.TemporaryDirectory(prefix="cgx1-disk-cli-") as temporary:
            source_root = Path(temporary) / "verilator-source"
            install_root = Path(temporary) / "verilator-install"
            source_root.mkdir()
            install_root.mkdir()
            (source_root / "verilator_bin_dbg").write_bytes(b"x" * 2048)
            (install_root / "verilator").write_bytes(b"y" * 2048)
            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch.object(sys, "argv", [
                "check_disk_budget.py", "--root", temporary, "--profile", "hosted",
                "--operation", "verilator-toolchain-build", "--output-path", temporary,
                "--scan-root", str(source_root), "--scan-root", str(install_root),
            ]), patch.object(
                disk_budget, "preflight_disk_budget", return_value={"status": "info"},
            ), patch.object(
                disk_budget, "format_preflight_report", return_value="disk fixture",
            ), patch.object(
                disk_budget, "load_disk_policy", return_value=budget,
            ), redirect_stdout(stdout), redirect_stderr(stderr):
                result = disk_budget.main()

            self.assertEqual(0, result, stderr.getvalue())
            self.assertIn('"passed": true', stdout.getvalue())
            self.assertIn('"total_bytes": 4096', stdout.getvalue())

    def test_multi_root_artifact_scan_applies_one_aggregate_tree_limit(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-artifact-roots-") as temporary:
            root = Path(temporary)
            source = root / "source-build"
            install = root / "installed-prefix"
            source.mkdir()
            install.mkdir()
            (source / "object.o").write_bytes(b"abcd")
            (install / "tool").write_bytes(b"efgh")

            report = disk_budget.scan_generated_artifact_roots(
                [source, install],
                max_waveform_bytes=1024,
                max_test_output_bytes=1024,
                max_tree_bytes=7,
            )

            self.assertFalse(report["passed"])
            self.assertEqual(2, report["files_scanned"])
            self.assertEqual(8, report["total_bytes"])
            self.assertEqual(2, len(report["roots"]))
            self.assertEqual("output_tree", report["oversized"][0]["kind"])

    def test_multi_root_artifact_scan_rejects_overlapping_roots(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-overlapping-roots-") as temporary:
            root = Path(temporary)
            child = root / "child"
            child.mkdir()

            with self.assertRaisesRegex(disk_budget.DiskBudgetError, "overlap"):
                disk_budget.scan_generated_artifact_roots(
                    [root, child], max_waveform_bytes=1024, max_test_output_bytes=1024,
                )

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

    def test_repository_policy_uses_measured_gate_sizes_and_labels_unknowns(self):
        policy = disk_budget.load_disk_policy(Path(__file__).resolve().parents[2])

        self.assertEqual(policy["profiles"]["developer"]["minimum_free_bytes"], 40 * GIB)
        self.assertEqual(policy["profiles"]["hosted"]["minimum_free_bytes"], 2 * GIB)
        for operation in ("clean-candidate", "clean-cmake", "wsl-candidate", "clang-debug",
                          "clang-release", "hosted-tool-install", "verilator-toolchain-build",
                          "rtl-tools", "synthesis-smoke", "formal"):
            self.assertIsNone(policy["operations"][operation]["estimated_peak_bytes"])
            self.assertEqual(policy["operations"][operation]["measurement_status"], "unmeasured")
        measured = {
            "gcc-debug": 28471237,
            "gcc-release": 3612512,
            "sanitizer-build": 87320145,
            "icarus": 11022503,
        }
        for operation, size in measured.items():
            self.assertEqual(size, policy["operations"][operation]["estimated_peak_bytes"])
            self.assertEqual("estimate", policy["operations"][operation]["measurement_status"])
            self.assertIn("not a filesystem high-water", policy["operations"][operation]["measurement_source"])
            self.assertEqual(2 * size, policy["operations"][operation]["maximum_output_tree_bytes"])
            self.assertIn("ae0dbd016ed32abfcaec24351e0679f3b892f3db",
                          policy["operations"][operation]["measurement_source"])
        self.assertIn("98 files", policy["operations"]["icarus"]["measurement_source"])
        self.assertIn("Clang", policy["operations"]["sanitizer-build"]["measurement_source"])
        verilator = policy["operations"]["verilator-toolchain-build"]
        self.assertIsNone(verilator["estimated_peak_bytes"], "the combined Verilator build peak is still unknown")
        self.assertGreater(verilator["maximum_test_output_file_bytes"], 231709824)
        self.assertIsNone(verilator.get("maximum_output_tree_bytes"))
        self.assertTrue(any("257,576,704" in note for note in policy["measurement_notes"]))

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
        source_preflight = rtl_tools.index("--operation verilator-toolchain-build")
        source_checkout = rtl_tools.index("- name: Check out Verilator v5.052 source")
        source_scan = rtl_tools.index("--scan-root .tools/verilator")
        self.assertLess(source_preflight, source_checkout)
        self.assertGreater(source_scan, rtl_tools.index("make install"))
        self.assertLess(source_scan, rtl_tools.index("- name: Run bounded lint, formal, and synthesis smoke"))
        prefix_scan = rtl_tools.index('--scan-root "$RUNNER_TEMP/verilator-5.052"')
        self.assertGreater(prefix_scan, rtl_tools.index("make install"))
        self.assertLess(prefix_scan, rtl_tools.index("- name: Run bounded lint, formal, and synthesis smoke"))
        self.assertLess(rtl_ci.index("--profile hosted"), rtl_ci.index("- name: Install Icarus Verilog"))
        for output_path in ("/usr", "/var/lib/apt/lists", "/var/cache/apt/archives"):
            self.assertIn(output_path, rtl_ci)
            self.assertIn(output_path, rtl_tools)


if __name__ == "__main__":
    unittest.main()
