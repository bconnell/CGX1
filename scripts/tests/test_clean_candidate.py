from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

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
            self.assertFalse((candidate.path / "required_helper.py").exists())
            with self.assertRaisesRegex(CandidateValidationError, "required_helper.py"):
                require_candidate_paths(candidate.path, ["required_helper.py"])
        finally:
            remove_clean_candidate(self.root, candidate)

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

    def test_existing_build_directory_is_rejected_before_candidate_validation(self) -> None:
        candidate = create_clean_candidate(self.root, self.worktree_parent)
        try:
            (candidate.path / "build").mkdir()
            with self.assertRaisesRegex(CandidateValidationError, "without a build directory"):
                require_empty_build_start(candidate.path)
        finally:
            remove_clean_candidate(self.root, candidate)

    def test_root_linux_runner_is_rejected_as_canonical_candidate_evidence(self) -> None:
        with self.assertRaisesRegex(CandidateValidationError, "diagnostic"):
            require_contributor_uid("posix", 0)

        require_contributor_uid("posix", 65534)
        require_contributor_uid("nt", None)


if __name__ == "__main__":
    unittest.main()
