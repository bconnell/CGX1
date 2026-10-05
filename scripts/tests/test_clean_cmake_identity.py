from __future__ import annotations

import subprocess
import shutil
import json
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.run_clean_cmake_tests import (
    CleanSourceIdentityError,
    classify_execution_uid,
    require_unchanged_source_identity,
    source_identity,
)

ROOT = Path(__file__).resolve().parents[2]


class CleanCMakeIdentityTests(unittest.TestCase):
    def test_root_runner_is_classified_as_diagnostic_only(self):
        self.assertEqual("root_diagnostic_only", classify_execution_uid(0))
        self.assertEqual("unprivileged", classify_execution_uid(65534))

    def test_identity_failure_is_reported_with_the_failed_boundary(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-no-git-identity-") as directory:
            root = Path(directory)

            with self.assertRaisesRegex(CleanSourceIdentityError, r"Git repository-root.*identity"):
                source_identity(root)

    def test_clean_runner_stops_before_build_when_git_identity_is_missing(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-runner-no-git-") as directory:
            root = Path(directory)
            (root / "CMakeLists.txt").write_text("project(identity)\n", encoding="utf-8")
            summary_path = root / "identity-summary.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/run_clean_cmake_tests.py"),
                 "--root", str(root), "--config", "Debug", "--summary-json", str(summary_path)],
                check=False, text=True, encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )

            self.assertEqual(2, result.returncode, result.stdout + result.stderr)
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            self.assertEqual("identity_unavailable", summary["status"])
            self.assertIn("Git repository-root identity", summary["failure"]["message"])
            self.assertFalse((root / "build").exists(), "identity failure must precede build-tree creation")

    def test_source_identity_includes_commit_tree_index_and_fingerprint(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-identity-") as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "CGX1 identity test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "identity-test@example.invalid"], cwd=root, check=True)
            (root / "CMakeLists.txt").write_text("cmake_minimum_required(VERSION 3.20)\n", encoding="utf-8")
            (root / "design").mkdir()
            (root / "design/cgx1_validation_evidence.json").write_text(
                '{"fingerprint_excluded_paths": []}\n', encoding="utf-8"
            )
            (root / "scripts").mkdir()
            shutil.copyfile(ROOT / "scripts/validate_evidence.py", root / "scripts/validate_evidence.py")
            subprocess.run(["git", "add", "CMakeLists.txt", "design", "scripts"], cwd=root, check=True)
            subprocess.run(["git", "commit", "--quiet", "-m", "identity fixture"], cwd=root, check=True)

            identity = source_identity(root)
            head = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, check=True, text=True,
                stdout=subprocess.PIPE,
            ).stdout.strip()

            self.assertEqual(head, identity["git_head"])
            self.assertEqual(identity["head_tree"], identity["index_tree"])
            self.assertRegex(identity["source_fingerprint"], r"^[0-9a-f]{64}$")
            self.assertEqual(str(root.resolve()), identity["candidate_path"])

    def test_missing_fingerprint_fails_closed_with_a_specific_diagnostic(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-no-fingerprint-") as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "CGX1 identity test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "identity-test@example.invalid"], cwd=root, check=True)
            (root / "CMakeLists.txt").write_text("project(identity)\n", encoding="utf-8")
            (root / "design").mkdir()
            (root / "design/cgx1_validation_evidence.json").write_text("not-json\n", encoding="utf-8")
            (root / "scripts").mkdir()
            shutil.copyfile(ROOT / "scripts/validate_evidence.py", root / "scripts/validate_evidence.py")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "--quiet", "-m", "no fingerprint fixture"], cwd=root, check=True)

            with self.assertRaisesRegex(CleanSourceIdentityError, "source fingerprint"):
                source_identity(root)

    def test_identity_change_after_validation_is_rejected(self):
        before = {"git_head": "a", "head_tree": "b", "index_tree": "b", "source_fingerprint": "c"}
        after = {**before, "source_fingerprint": "d"}

        with self.assertRaisesRegex(CleanSourceIdentityError, "candidate identity changed"):
            require_unchanged_source_identity(before, after)


if __name__ == "__main__":
    unittest.main()
