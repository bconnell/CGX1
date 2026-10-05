from __future__ import annotations

import unittest

from scripts.run_wsl_candidate import WslCandidateError, require_fingerprint_match


class WslCandidateIdentityTests(unittest.TestCase):
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
