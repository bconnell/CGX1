#!/usr/bin/env python3
"""Report CGX1 completeness-branch publication and evidence identity."""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument
from typing import Any

EXPECTED_REMOTE = "https://github.com/bconnell/CGX1.git"
FEATURE_REF = "refs/remotes/origin/codex/cgx1-completeness"
MAIN_REF = "refs/remotes/origin/main"
DEFAULT_REQUIRED_WORKFLOWS = ("RTL CI", "Windows CI", "Linux Sanitizers", "RTL Tools CI")


def publication_preflight_errors(state: dict[str, Any], max_unpublished: int = 3) -> list[str]:
    errors: list[str] = []
    behind = int(state.get("behind", 0))
    ahead = int(state.get("ahead", 0))
    if behind:
        errors.append(f"local branch is behind the remote completeness branch by {behind} commit(s); reconcile before publication")
    if not state.get("fast_forward", False):
        errors.append("local HEAD is not a fast-forward publication of the remote completeness branch")
    if ahead > max_unpublished:
        errors.append(
            f"{ahead} unpublished commit(s) exceed the {max_unpublished}-commit checkpoint limit; explain and checkpoint the gap"
        )
    return errors


def latest_hosted_valid_sha(evidence: Any) -> str | None:
    if not isinstance(evidence, dict):
        return None
    default_required = evidence.get("required_hosted_workflows", list(DEFAULT_REQUIRED_WORKFLOWS))
    if not isinstance(default_required, list) or not default_required or any(not isinstance(x, str) for x in default_required):
        return None
    candidates = evidence.get("candidates", [])
    if not isinstance(candidates, list):
        return None
    latest: str | None = None
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        commit = candidate.get("commit")
        runs = candidate.get("workflow_runs")
        if not isinstance(commit, str) or not isinstance(runs, list):
            continue
        required = candidate.get("required_hosted_workflows", default_required)
        if not isinstance(required, list) or not required or any(not isinstance(x, str) for x in required):
            continue
        passed: set[str] = set()
        for run in runs:
            if not isinstance(run, dict):
                continue
            workflow = run.get("workflow")
            if (workflow in required and run.get("head_sha") == commit
                    and run.get("status") == "completed" and run.get("conclusion") == "success"):
                passed.add(workflow)
        if set(required).issubset(passed):
            latest = commit
    return latest


def _git(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["git", "-c", f"safe.directory={root.resolve()}", "-C", str(root), *args],
        text=True, encoding="utf-8", capture_output=True
    )
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed ({result.returncode})")
    return result


def _is_ancestor(root: Path, ancestor: str, descendant: str) -> bool | None:
    result = _git(root, "merge-base", "--is-ancestor", ancestor, descendant, check=False)
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    return None


def collect_main_integration_state(
    root: Path,
    feature_ref: str = FEATURE_REF,
    main_ref: str = MAIN_REF,
    latest_hosted_sha: str | None = None,
) -> dict[str, Any]:
    feature_result = _git(root, "rev-parse", "--verify", feature_ref, check=False)
    main_result = _git(root, "rev-parse", "--verify", main_ref, check=False)
    feature = feature_result.stdout.strip() if feature_result.returncode == 0 else None
    main = main_result.stdout.strip() if main_result.returncode == 0 else None
    if not feature or not main:
        return {
            "remote_feature_head": feature,
            "remote_main_head": main,
            "latest_integrated_main_sha": None,
            "feature_ahead_of_main": None,
            "feature_behind_main": None,
            "feature_histories_diverged": None,
            "remote_main_is_ancestor_of_feature": None,
            "hosted_sha_is_ancestor_of_remote_feature": None,
            "hosted_sha_is_ancestor_of_remote_main": None,
            "hosted_green_integration_debt": None,
            "hosted_green_unmerged_commits": None,
        }

    merge_base_result = _git(root, "merge-base", feature_ref, main_ref, check=False)
    merge_base = merge_base_result.stdout.strip() if merge_base_result.returncode == 0 else None
    feature_ahead = int(_git(root, "rev-list", "--count", f"{main_ref}..{feature_ref}").stdout.strip())
    feature_behind = int(_git(root, "rev-list", "--count", f"{feature_ref}..{main_ref}").stdout.strip())
    diverged = merge_base is None or (feature_ahead > 0 and feature_behind > 0)
    main_is_ancestor = _is_ancestor(root, main, feature)
    hosted_is_feature_ancestor = (
        _is_ancestor(root, latest_hosted_sha, feature) if latest_hosted_sha else None
    )
    hosted_is_main_ancestor = (
        _is_ancestor(root, latest_hosted_sha, main) if latest_hosted_sha else None
    )
    integration_debt = bool(
        latest_hosted_sha and hosted_is_feature_ancestor is True and hosted_is_main_ancestor is not True
    )
    if integration_debt:
        unmerged = int(_git(root, "rev-list", "--count", f"{main_ref}..{latest_hosted_sha}").stdout.strip())
    elif latest_hosted_sha:
        unmerged = 0
    else:
        unmerged = None
    return {
        "remote_feature_head": feature,
        "remote_main_head": main,
        "latest_integrated_main_sha": merge_base,
        "feature_ahead_of_main": feature_ahead,
        "feature_behind_main": feature_behind,
        "feature_histories_diverged": diverged,
        "remote_main_is_ancestor_of_feature": main_is_ancestor,
        "hosted_sha_is_ancestor_of_remote_feature": hosted_is_feature_ancestor,
        "hosted_sha_is_ancestor_of_remote_main": hosted_is_main_ancestor,
        "hosted_green_integration_debt": integration_debt,
        "hosted_green_unmerged_commits": unmerged,
    }


def major_slice_preflight_errors(state: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if state.get("feature_ahead_of_main") is None or state.get("feature_behind_main") is None:
        return ["remote feature/main relationship is unavailable; refresh refs before a major slice"]
    if state.get("feature_histories_diverged") is True:
        errors.append("completeness and main histories have diverged; diagnose and reconcile before a major slice")
    if int(state["feature_behind_main"]) > 0:
        errors.append(
            f"origin/main has {state['feature_behind_main']} commit(s) absent from completeness; reconcile before a major slice"
        )
    if state.get("hosted_green_integration_debt") is None:
        errors.append("latest hosted-valid feature state cannot be compared with main; repair evidence/refs first")
    elif state["hosted_green_integration_debt"]:
        count = state.get("hosted_green_unmerged_commits")
        detail = f" ({count} commit(s))" if count is not None else ""
        errors.append(f"hosted-green completeness work remains integration debt against main{detail}")
    return errors


def parse_open_pr_result(returncode: int, stdout: str) -> tuple[str, list[dict[str, Any]] | None]:
    if returncode:
        return "unavailable", None
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return "unavailable", None
    if not isinstance(payload, list) or any(not isinstance(item, dict) for item in payload):
        return "unavailable", None
    return "available", payload


def query_open_integration_prs(root: Path) -> tuple[str, list[dict[str, Any]] | None]:
    gh = shutil.which("gh") or shutil.which("gh.exe")
    if not gh:
        return "unavailable", None
    try:
        result = subprocess.run(
            [gh, "pr", "list", "--repo", "bconnell/CGX1", "--head",
             "bconnell:codex/cgx1-completeness", "--base", "main", "--state", "open",
             "--json", "number,title,url,headRefName,baseRefName,headRefOid,baseRefOid"],
            cwd=root, check=False, text=True, encoding="utf-8", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return "unavailable", None
    return parse_open_pr_result(result.returncode, result.stdout)


def collect_state(root: Path, feature_ref: str = FEATURE_REF, main_ref: str = MAIN_REF,
                  evidence_path: Path | None = None, query_pull_requests: bool = True) -> dict[str, Any]:
    root = root.resolve()
    top = Path(_git(root, "rev-parse", "--show-toplevel").stdout.strip()).resolve()
    head = _git(top, "rev-parse", "HEAD").stdout.strip()
    branch = _git(top, "branch", "--show-current").stdout.strip() or "(detached HEAD)"
    remote_url = _git(top, "remote", "get-url", "origin").stdout.strip()
    feature_result = _git(top, "rev-parse", "--verify", feature_ref, check=False)
    feature_head = feature_result.stdout.strip() if feature_result.returncode == 0 else None
    if feature_head:
        mb = _git(top, "merge-base", "HEAD", feature_ref, check=False)
        merge_base = mb.stdout.strip() if mb.returncode == 0 else None
        ahead = int(_git(top, "rev-list", "--count", f"{feature_ref}..HEAD").stdout.strip())
        behind = int(_git(top, "rev-list", "--count", f"HEAD..{feature_ref}").stdout.strip())
        fast_forward = behind == 0 and merge_base == feature_head
    else:
        merge_base = None
        ahead = 0
        behind = 0
        fast_forward = False
    porcelain = _git(top, "status", "--porcelain").stdout.splitlines()
    main_result = _git(top, "rev-parse", "--verify", main_ref, check=False)
    main_head = main_result.stdout.strip() if main_result.returncode == 0 else None
    main_is_ancestor = _is_ancestor(top, main_ref, "HEAD") if main_head else None
    main_merge_base = None
    if main_head:
        main_mb = _git(top, "merge-base", "HEAD", main_ref, check=False)
        main_merge_base = main_mb.stdout.strip() if main_mb.returncode == 0 else None
    if evidence_path is None:
        evidence_path = top / "design/cgx1_validation_evidence.json"
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    hosted_sha = latest_hosted_valid_sha(evidence)
    hosted_is_ancestor = _is_ancestor(top, hosted_sha, "HEAD") if hosted_sha else None
    integration = collect_main_integration_state(top, feature_ref, main_ref, hosted_sha)
    if query_pull_requests:
        pr_status, open_prs = query_open_integration_prs(top)
    else:
        pr_status, open_prs = "not_queried", None
    return {
        "repository": str(top), "origin_url": remote_url, "branch": branch,
        "local_head": head, "remote_completeness_head": feature_head,
        "merge_base": merge_base, "ahead": ahead, "behind": behind,
        "dirty": bool(porcelain), "dirty_entries": len(porcelain),
        "publication_fast_forward": fast_forward,
        "protected_main_head": main_head,
        "protected_main_merge_base": main_merge_base,
        "protected_main_is_ancestor": main_is_ancestor,
        "latest_exact_hosted_valid_sha": hosted_sha,
        "latest_hosted_sha_is_ancestor_of_local_head": hosted_is_ancestor,
        **integration,
        "open_integration_pr_query": pr_status,
        "open_integration_prs": open_prs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    parser.add_argument("--feature-ref", default=FEATURE_REF)
    parser.add_argument("--main-ref", default=MAIN_REF)
    parser.add_argument("--max-unpublished", type=int, default=3)
    parser.add_argument("--for-publish", action="store_true",
                        help="fail closed if the feature branch is behind, diverged, or too far unpublished")
    parser.add_argument("--for-major-slice", action="store_true",
                        help="fail while main has unmerged work or hosted-green integration debt remains")
    parser.add_argument("--json", action="store_true", help="emit one JSON object")
    args = parser.parse_args()
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
        state = collect_state(root, args.feature_ref, args.main_ref)
    except PathTranslationError as error:
        parser.error(str(error))
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"branch state validation error: {error}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(state, indent=2, sort_keys=True))
    else:
        for key, value in state.items():
            print(f"{key}: {value}")
        if state["dirty"]:
            print("note: dirty working-tree content is preserved; publication includes committed HEAD only")
        if state["ahead"] > args.max_unpublished:
            print(f"WARNING: unpublished distance {state['ahead']} exceeds {args.max_unpublished} commits")
        if state.get("hosted_green_integration_debt"):
            print("INTEGRATION DEBT: hosted-green completeness commits are not yet contained in protected main")
    errors = publication_preflight_errors(
        {"ahead": state["ahead"], "behind": state["behind"],
         "fast_forward": state["publication_fast_forward"]}, args.max_unpublished
    ) if args.for_publish else []
    if args.for_publish:
        normalized_remote = state["origin_url"].removesuffix(".git")
        if normalized_remote not in {EXPECTED_REMOTE.removesuffix(".git"), "git@github.com:bconnell/CGX1"}:
            errors.append(f"origin does not resolve to bconnell/CGX1: {state['origin_url']}")
        if state["branch"] != "codex/cgx1-completeness":
            errors.append(f"publication branch must be codex/cgx1-completeness, got {state['branch']}")
        if state.get("remote_main_is_ancestor_of_feature") is not True:
            errors.append("origin/main is not an ancestor of the remote completeness branch; reconcile before publication")
    if args.for_major_slice:
        errors.extend(major_slice_preflight_errors(state))
    for error in errors:
        print(f"publication preflight failed: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
