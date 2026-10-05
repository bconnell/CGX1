import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "check_branch_state.py"
SPEC = importlib.util.spec_from_file_location("check_branch_state", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments], check=True, text=True,
        encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


class BranchStateTests(unittest.TestCase):
    def test_fast_forward_checkpoint_is_publishable_even_with_later_dirty_work(self):
        state = {"ahead": 1, "behind": 0, "fast_forward": True, "dirty": True}
        self.assertEqual(MODULE.publication_preflight_errors(state), [])

    def test_unexplained_remote_advance_fails_publication_preflight(self):
        state = {"ahead": 0, "behind": 2, "fast_forward": False, "dirty": False}
        errors = MODULE.publication_preflight_errors(state)
        self.assertTrue(any("behind" in error for error in errors))
        self.assertTrue(any("fast-forward" in error for error in errors))

    def test_diverged_history_fails_closed(self):
        state = {"ahead": 3, "behind": 1, "fast_forward": False, "dirty": False}
        self.assertTrue(MODULE.publication_preflight_errors(state))

    def test_large_unpublished_distance_fails_closed(self):
        state = {"ahead": 4, "behind": 0, "fast_forward": True, "dirty": False}
        errors = MODULE.publication_preflight_errors(state, max_unpublished=3)
        self.assertTrue(any("unpublished" in error for error in errors))

    def test_latest_hosted_valid_sha_requires_all_exact_successful_workflows(self):
        evidence = {"candidates": [
            {"commit": "a" * 40, "workflow_runs": [
                {"workflow": "RTL CI", "head_sha": "a" * 40, "status": "completed", "conclusion": "success"},
                {"workflow": "Windows CI", "head_sha": "a" * 40, "status": "completed", "conclusion": "success"},
                {"workflow": "Linux Sanitizers", "head_sha": "a" * 40, "status": "completed", "conclusion": "success"},
                {"workflow": "RTL Tools CI", "head_sha": "a" * 40, "status": "completed", "conclusion": "success"}]},
            {"commit": "b" * 40, "workflow_runs": [
                {"workflow": "RTL CI", "head_sha": "b" * 40, "status": "completed", "conclusion": "success"},
                {"workflow": "Windows CI", "head_sha": "c" * 40, "status": "completed", "conclusion": "success"},
                {"workflow": "Linux Sanitizers", "head_sha": "b" * 40, "status": "completed", "conclusion": "success"},
                {"workflow": "RTL Tools CI", "head_sha": "b" * 40, "status": "completed", "conclusion": "success"}]},
        ]}
        self.assertEqual(MODULE.latest_hosted_valid_sha(evidence), "a" * 40)

    def test_missing_exact_hosted_success_returns_none(self):
        self.assertIsNone(MODULE.latest_hosted_valid_sha({"candidates": []}))

    def test_candidate_specific_hosted_policy_preserves_prior_candidate_evidence(self):
        old_sha = "a" * 40
        new_sha = "b" * 40
        evidence = {
            "required_hosted_workflows": ["RTL CI", "Windows CI", "Linux Sanitizers", "RTL Tools CI"],
            "candidates": [
                {"commit": old_sha, "required_hosted_workflows": ["RTL CI", "Windows CI"],
                 "workflow_runs": [
                     {"workflow": "RTL CI", "head_sha": old_sha, "status": "completed", "conclusion": "success"},
                     {"workflow": "Windows CI", "head_sha": old_sha, "status": "completed", "conclusion": "success"}]},
                {"commit": new_sha, "required_hosted_workflows": ["RTL CI", "Windows CI", "Linux Sanitizers", "RTL Tools CI"],
                 "workflow_runs": [
                     {"workflow": name, "head_sha": new_sha, "status": "completed", "conclusion": "success"}
                     for name in ["RTL CI", "Windows CI", "Linux Sanitizers"]]},
            ],
        }
        self.assertEqual(MODULE.latest_hosted_valid_sha(evidence), old_sha)

    def test_candidate_specific_hosted_policy_preserves_prior_candidate_evidence(self):
        old_sha = "a" * 40
        new_sha = "b" * 40
        evidence = {
            "required_hosted_workflows": ["RTL CI", "Windows CI", "Linux Sanitizers", "RTL Tools CI"],
            "candidates": [
                {"commit": old_sha, "required_hosted_workflows": ["RTL CI", "Windows CI"],
                 "workflow_runs": [
                     {"workflow": "RTL CI", "head_sha": old_sha, "status": "completed", "conclusion": "success"},
                     {"workflow": "Windows CI", "head_sha": old_sha, "status": "completed", "conclusion": "success"}]},
                {"commit": new_sha, "required_hosted_workflows": ["RTL CI", "Windows CI", "Linux Sanitizers", "RTL Tools CI"],
                 "workflow_runs": [
                     {"workflow": name, "head_sha": new_sha, "status": "completed", "conclusion": "success"}
                     for name in ["RTL CI", "Windows CI", "Linux Sanitizers"]]},
            ],
        }
        self.assertEqual(MODULE.latest_hosted_valid_sha(evidence), old_sha)

    def test_hosted_green_feature_work_is_integration_debt_until_main_contains_it(self):
        with tempfile.TemporaryDirectory(prefix="cgx1-branch-integration-") as temporary:
            root = Path(temporary)
            git(root, "init", "--quiet", "-b", "main")
            git(root, "config", "user.name", "CGX1 branch test")
            git(root, "config", "user.email", "branch-test@localhost")
            (root / "base.txt").write_text("base\n", encoding="utf-8")
            git(root, "add", "base.txt")
            git(root, "commit", "--quiet", "-m", "base")
            base = git(root, "rev-parse", "HEAD")
            git(root, "switch", "--quiet", "-c", "feature")
            (root / "feature.txt").write_text("feature\n", encoding="utf-8")
            git(root, "add", "feature.txt")
            git(root, "commit", "--quiet", "-m", "feature")
            feature = git(root, "rev-parse", "HEAD")
            git(root, "switch", "--quiet", "main")
            (root / "main.txt").write_text("main\n", encoding="utf-8")
            git(root, "add", "main.txt")
            git(root, "commit", "--quiet", "-m", "independent main change")
            git(root, "rev-parse", "HEAD")

            state = MODULE.collect_main_integration_state(root, "feature", "main", feature)

            self.assertEqual(base, state["latest_integrated_main_sha"])
            self.assertEqual(1, state["feature_ahead_of_main"])
            self.assertEqual(1, state["feature_behind_main"])
            self.assertTrue(state["feature_histories_diverged"])
            self.assertTrue(state["hosted_green_integration_debt"])
            self.assertEqual(1, state["hosted_green_unmerged_commits"])
            self.assertTrue(MODULE.major_slice_preflight_errors(state))

            git(root, "switch", "--quiet", "feature")
            git(root, "merge", "--quiet", "--no-edit", "main")
            feature_merge = git(root, "rev-parse", "HEAD")
            integration = MODULE.collect_main_integration_state(root, "feature", "main", feature)
            self.assertTrue(integration["hosted_green_integration_debt"])
            self.assertEqual(0, integration["feature_behind_main"])
            self.assertTrue(MODULE.major_slice_preflight_errors(integration))

            git(root, "switch", "--quiet", "main")
            git(root, "merge", "--quiet", "--ff-only", "feature")
            reconciled = MODULE.collect_main_integration_state(root, "feature", "main", feature)
            self.assertEqual(feature_merge, reconciled["latest_integrated_main_sha"])
            self.assertFalse(reconciled["feature_histories_diverged"])
            self.assertEqual(0, reconciled["feature_behind_main"])
            self.assertFalse(reconciled["hosted_green_integration_debt"])
            self.assertEqual(0, reconciled["hosted_green_unmerged_commits"])
            self.assertEqual([], MODULE.major_slice_preflight_errors(reconciled))

    def test_unintegrated_main_commit_blocks_a_major_slice(self):
        state = {
            "feature_behind_main": 2,
            "feature_histories_diverged": False,
            "hosted_green_integration_debt": False,
        }
        self.assertTrue(any("main" in error for error in MODULE.major_slice_preflight_errors(state)))

    def test_pull_request_query_distinguishes_empty_from_unavailable(self):
        available, prs = MODULE.parse_open_pr_result(0, '[{"number":17,"headRefName":"codex/cgx1-completeness","baseRefName":"main"}]')
        self.assertEqual("available", available)
        self.assertEqual(17, prs[0]["number"])
        unavailable, unknown = MODULE.parse_open_pr_result(1, "permission denied")
        self.assertEqual("unavailable", unavailable)
        self.assertIsNone(unknown)


if __name__ == "__main__":
    unittest.main()
