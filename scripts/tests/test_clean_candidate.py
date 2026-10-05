from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from validate_clean_candidate import (  # noqa: E402
    CandidateValidationError,
    create_clean_candidate,
    remove_clean_candidate,
    require_contributor_uid,
    require_empty_build_start,
    require_candidate_paths,
    CleanCandidate,
    run_linux_candidate_validation,
    require_no_existing_candidate_worktrees,
)


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        check=True,
        text=True,
        encoding="utf-8",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


class CleanCandidateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="cgx1-candidate-test-")
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        git(self.root, "init", "--quiet")
        git(self.root, "config", "user.name", "CGX1 candidate test")
        git(self.root, "config", "user.email", "candidate-test@localhost")
        (self.root / "tracked.txt").write_text("tracked\n", encoding="utf-8")
        git(self.root, "add", "tracked.txt")
        git(self.root, "commit", "--quiet", "-m", "base")
        self.worktree_parent = self.root / "build" / "cgx1-clean-candidates"
        self.worktree_parent.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_untracked_required_helper_cannot_satisfy_candidate(self) -> None:
        (self.root / "required_helper.py").write_text("value = 1\n", encoding="utf-8")
        candidate = create_clean_candidate(self.root, self.worktree_parent)
        try:
            self.assertEqual(candidate.path.name, "candidate-" + candidate.tree)
            self.assertFalse((candidate.path / "required_helper.py").exists())
            with self.assertRaisesRegex(CandidateValidationError, "required_helper.py"):
                require_candidate_paths(candidate.path, ["required_helper.py"])
        finally:
            remove_clean_candidate(self.root, candidate)
        self.assertFalse(candidate.path.exists(), "candidate worktree cleanup must remove its owned tree")

    def test_staged_required_helper_is_present_in_candidate(self) -> None:
        (self.root / "required_helper.py").write_text("value = 1\n", encoding="utf-8")
        git(self.root, "add", "required_helper.py")
        candidate = create_clean_candidate(self.root, self.worktree_parent)
        try:
            require_candidate_paths(candidate.path, ["required_helper.py"])
            self.assertEqual("value = 1\n", (candidate.path / "required_helper.py").read_text(encoding="utf-8"))
            self.assertEqual(candidate.tree, git(candidate.path, "rev-parse", "HEAD^{tree}"))
        finally:
            remove_clean_candidate(self.root, candidate)

    def test_required_path_cannot_escape_candidate_root(self) -> None:
        with self.assertRaisesRegex(CandidateValidationError, "must be repository-relative"):
            require_candidate_paths(self.root, ["../outside.txt"])

    def test_candidate_output_parent_must_be_in_the_designated_build_area(self) -> None:
        unowned_parent = self.root / "other-output"
        with self.assertRaisesRegex(CandidateValidationError, "build directory"):
            create_clean_candidate(self.root, unowned_parent)
        self.assertFalse(unowned_parent.exists(), "rejected output parents must not be created")

    def test_candidate_output_parent_must_use_the_deterministic_directory(self) -> None:
        alternate_parent = self.root / "build" / "other-candidates"
        with self.assertRaisesRegex(CandidateValidationError, "deterministic"):
            create_clean_candidate(self.root, alternate_parent)
        self.assertFalse(alternate_parent.exists(), "alternate output parents must not be created")

    def test_candidate_output_parent_rejects_a_reported_redirected_path(self) -> None:
        with patch(
            "validate_clean_candidate.is_redirected_path",
            side_effect=lambda path, *_args: Path(path) == self.worktree_parent,
        ):
            with self.assertRaisesRegex(CandidateValidationError, "redirected"):
                create_clean_candidate(self.root, self.worktree_parent)

        self.assertEqual([], list(self.worktree_parent.iterdir()))

    def test_existing_build_directory_is_rejected_before_candidate_validation(self) -> None:
        candidate = create_clean_candidate(self.root, self.worktree_parent)
        try:
            (candidate.path / "build").mkdir()
            with self.assertRaisesRegex(CandidateValidationError, "without a build directory"):
                require_empty_build_start(candidate.path)
        finally:
            remove_clean_candidate(self.root, candidate)

    def test_registered_candidate_blocks_duplicate_clean_validation(self) -> None:
        candidate = create_clean_candidate(self.root, self.worktree_parent)
        try:
            with self.assertRaisesRegex(CandidateValidationError, "active status not proven"):
                require_no_existing_candidate_worktrees(self.root, self.worktree_parent)
        finally:
            remove_clean_candidate(self.root, candidate)

    def test_unregistered_candidate_output_is_preserved_and_reported(self) -> None:
        stale = self.worktree_parent / "candidate-unclassified"
        stale.mkdir()

        with self.assertRaisesRegex(CandidateValidationError, "unregistered output"):
            require_no_existing_candidate_worktrees(self.root, self.worktree_parent)

        self.assertTrue(stale.is_dir(), "uncertain candidate output must not be deleted by the guard")

    def test_root_linux_runner_is_rejected_as_canonical_candidate_evidence(self) -> None:
        with self.assertRaisesRegex(CandidateValidationError, "diagnostic"):
            require_contributor_uid("posix", 0)

        require_contributor_uid("posix", 65534)
        require_contributor_uid("nt", None)

    def test_linux_candidate_runs_release_failure_proof_after_both_ctest_builds(self) -> None:
        candidate = CleanCandidate(
            path=Path("/tmp/cgx1-candidate"), tree="tree", commit="commit", ref="ref",
        )
        with patch("validate_clean_candidate._run") as run, patch(
            "validate_clean_candidate.run_rtl_validation", return_value="passed",
        ) as rtl:
            result = run_linux_candidate_validation(candidate, 1800, False)

        commands = [call.args[0] for call in run.call_args_list]
        cmake_index = next(index for index, command in enumerate(commands)
                           if any("run_clean_cmake_tests.py" in argument for argument in command))
        failure_probe_index = next(index for index, command in enumerate(commands)
                                   if any("prove_release_test_check_failure.py" in argument
                                          for argument in command))
        self.assertEqual(sys.executable, commands[cmake_index][0])
        self.assertIn("both", commands[cmake_index])
        self.assertEqual(
            [sys.executable, "scripts/prove_release_test_check_failure.py", "--root",
             str(candidate.path)],
            commands[failure_probe_index],
        )
        self.assertLess(cmake_index, failure_probe_index)
        rtl.assert_called_once_with(candidate.path, 1800, False)
        self.assertEqual("passed", result)


if __name__ == "__main__":
    unittest.main()
