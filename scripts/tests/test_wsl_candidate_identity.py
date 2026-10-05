from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.run_wsl_candidate import (
    WslCandidateError,
    require_fingerprint_match,
    require_git_candidate_identity,
)


class WslCandidateIdentityTests(unittest.TestCase):
    def test_linux_git_candidate_identity_is_resolved_and_verified(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-linux-git-identity-") as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "CGX1 identity test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "identity-test@example.invalid"], cwd=root, check=True)
            (root / "candidate.txt").write_text("candidate\n", encoding="utf-8")
            subprocess.run(["git", "add", "candidate.txt"], cwd=root, check=True)
            subprocess.run(["git", "commit", "--quiet", "-m", "candidate"], cwd=root, check=True)
            commit = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, check=True, text=True,
                stdout=subprocess.PIPE,
            ).stdout.strip()
            tree = subprocess.run(
                ["git", "rev-parse", "HEAD^{tree}"], cwd=root, check=True, text=True,
                stdout=subprocess.PIPE,
            ).stdout.strip()

            self.assertEqual((commit, tree), require_git_candidate_identity(root, commit, tree))
            with self.assertRaisesRegex(WslCandidateError, "Linux Git candidate identity mismatch"):
                require_git_candidate_identity(root, commit, "0" * 40)

    def test_missing_linux_git_identity_has_a_clear_diagnostic(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-no-linux-git-identity-") as directory:
            with self.assertRaisesRegex(WslCandidateError, "git rev-parse --show-toplevel failed"):
                require_git_candidate_identity(Path(directory), "commit", "tree")

    def test_same_candidate_fingerprint_is_accepted_across_windows_and_linux_views(self):
        fingerprint = "a" * 64

        require_fingerprint_match(fingerprint, fingerprint, view="in the isolated Linux worktree")

    def test_cross_view_fingerprint_mismatch_fails_with_both_observed_values(self):
        with self.assertRaisesRegex(WslCandidateError, "cross-environment source fingerprint mismatch") as caught:
            require_fingerprint_match("a" * 64, "b" * 64, view="before configure")

        self.assertIn("Windows=" + "a" * 64, str(caught.exception))
        self.assertIn("Linux=" + "b" * 64, str(caught.exception))


if __name__ == "__main__":
    unittest.main()
