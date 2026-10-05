#!/usr/bin/env python3
"""Run the canonical Linux gates as an unprivileged WSL user on an isolated Git worktree."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Sequence

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:  # direct execution places scripts/, not the repository root, on sys.path
    from validation_paths import PathTranslationError, resolve_root_argument

try:
    from scripts.run_clean_cmake_tests import CleanSourceIdentityError, source_identity, tree_bytes
except ModuleNotFoundError:
    from run_clean_cmake_tests import CleanSourceIdentityError, source_identity, tree_bytes

try:
    from scripts.check_disk_budget import (
        DiskBudgetError, format_preflight_report, preflight_disk_budget,
    )
except ModuleNotFoundError:
    from check_disk_budget import (
        DiskBudgetError, format_preflight_report, preflight_disk_budget,
    )


class WslCandidateError(RuntimeError):
    pass


def require_fingerprint_match(windows_fingerprint: str, linux_fingerprint: str, *, view: str) -> None:
    if windows_fingerprint != linux_fingerprint:
        raise WslCandidateError(
            f"cross-environment source fingerprint mismatch {view}: "
            f"Windows={windows_fingerprint}, Linux={linux_fingerprint}"
        )


def require_git_candidate_identity(
    root: Path,
    expected_commit: str,
    expected_tree: str,
) -> tuple[str, str]:
    top_level = Path(git(root, "rev-parse", "--show-toplevel")).resolve()
    if top_level != root.resolve():
        raise WslCandidateError(
            f"Linux Git selected repository {top_level}, expected translated checkout {root.resolve()}"
        )
    commit = git(root, "rev-parse", f"{expected_commit}^{{commit}}")
    tree = git(root, "rev-parse", f"{commit}^{{tree}}")
    if commit != expected_commit or tree != expected_tree:
        raise WslCandidateError(
            f"Linux Git candidate identity mismatch: requested commit/tree={expected_commit}/{expected_tree}, "
            f"resolved={commit}/{tree}"
        )
    return commit, tree


def git(root: Path, *arguments: str, check: bool = True) -> str:
    command = [
        "git", "-c", f"safe.directory={root.resolve()}", "-C", str(root), *arguments,
    ]
    result = subprocess.run(
        command, check=False, text=True, encoding="utf-8",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or "no Git diagnostic"
        raise WslCandidateError(f"git {' '.join(arguments)} failed ({result.returncode}): {detail}")
    return result.stdout.strip()


def run(command: Sequence[str], cwd: Path, timeout_seconds: int) -> None:
    printable = " ".join(command)
    print(f"[wsl-clean-candidate] + {printable}", flush=True)
    try:
        result = subprocess.run(list(command), cwd=cwd, check=False, timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        raise WslCandidateError(
            f"Linux candidate command exceeded {timeout_seconds}s: {printable}"
        ) from error
    if result.returncode:
        raise WslCandidateError(
            f"Linux candidate command failed ({result.returncode}): {printable}"
        )


def required_linux_tools() -> None:
    required = ("git", "cmake", "ctest", "cc", "c++", "bash", "iverilog", "vvp", "timeout")
    missing = [name for name in required if shutil.which(name) is None]
    if missing:
        raise WslCandidateError(
            "required Linux tools are missing from the WSL user's PATH: " + ", ".join(missing)
        )


def require_no_existing_linux_candidates(
    repository_root: Path,
    candidate_parent: Path = Path("/tmp"),
) -> None:
    existing = sorted(candidate_parent.glob("cgx1-clean-candidate-*"))
    if not existing:
        return
    registered: set[Path] = set()
    for line in git(repository_root, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            registered.add(Path(line.removeprefix("worktree ")).resolve(strict=False))
    details = []
    for path in existing:
        state = "registered Git worktree (active status not proven)" if path.resolve(strict=False) in registered else "unregistered output"
        details.append(f"{path} [{state}]")
    raise WslCandidateError(
        "an earlier CGX1 Linux clean-candidate output remains; determine whether it is active "
        "and remove only a positively identified stale candidate before starting another: "
        + "; ".join(details)
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--git-root", required=True,
                        help="Windows checkout path translated to Linux syntax by the caller")
    parser.add_argument("--commit", required=True)
    parser.add_argument("--tree", required=True)
    parser.add_argument("--source-fingerprint", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    args = parser.parse_args(argv)
    if args.timeout_seconds < 1:
        parser.error("--timeout-seconds must be positive")
    if not hasattr(os, "geteuid") or os.geteuid() == 0:
        parser.error("canonical WSL validation must run as an unprivileged Linux user")

    try:
        root = resolve_root_argument(args.git_root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))

    candidate_path: Path | None = None
    added_worktree = False
    pass_message: str | None = None
    result_code = 1
    try:
        required_linux_tools()
        linux_output_root = Path("/tmp")
        disk_report = preflight_disk_budget(
            root, "wsl-candidate", linux_output_root,
        )
        print(format_preflight_report(disk_report), flush=True)
        if disk_report["status"] == "unsafe":
            raise DiskBudgetError(disk_report["reason"])
        require_no_existing_linux_candidates(root, linux_output_root)

        commit, tree = require_git_candidate_identity(root, args.commit, args.tree)

        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import validate_evidence

        ledger_path = Path(__file__).resolve().parents[1] / "design/cgx1_validation_evidence.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        excluded = ledger.get("fingerprint_excluded_paths", [])
        linux_commit_fingerprint = validate_evidence.source_fingerprint(root, commit, excluded)
        require_fingerprint_match(args.source_fingerprint, linux_commit_fingerprint,
                                  view="before configure")

        candidate_path = linux_output_root / f"cgx1-clean-candidate-{commit}"
        if candidate_path.exists():
            raise WslCandidateError(f"refusing to reuse existing Linux candidate path: {candidate_path}")
        added_worktree = True
        git(root, "worktree", "add", "--detach", "--quiet", str(candidate_path), commit)
        identity_before = source_identity(candidate_path)
        if identity_before["git_head"] != commit or identity_before["head_tree"] != tree:
            raise WslCandidateError(
                f"isolated Linux worktree has wrong Git identity: {identity_before}"
            )
        if identity_before["index_tree"] != tree:
            raise WslCandidateError(
                f"isolated Linux worktree index differs from candidate tree: {identity_before}"
            )
        status = git(candidate_path, "status", "--porcelain=v1", "--untracked-files=all")
        if status:
            raise WslCandidateError(f"isolated Linux candidate is not clean: {status}")

        print(json.dumps({
            "runner_uid": os.geteuid(),
            "candidate_commit": commit,
            "candidate_tree": tree,
            "source_fingerprint_windows": args.source_fingerprint,
            "source_fingerprint_linux": linux_commit_fingerprint,
            "linux_checkout_fingerprint": identity_before["source_fingerprint"],
            "isolated_candidate_path": str(candidate_path),
            "candidate_clean_before_validation": True,
        }, indent=2, sort_keys=True), flush=True)

        python = sys.executable
        for script in (
            "validate_resource_limits.py", "validate_hardening_ledgers.py",
            "validate_rtl_inventory.py", "validate_randomized_tests.py",
            "check_release_test_checks.py",
        ):
            run([python, f"scripts/{script}"], candidate_path, args.timeout_seconds)
        run([python, "-m", "unittest", "discover", "-s", "scripts/tests", "-v"],
            candidate_path, args.timeout_seconds)
        run([python, "scripts/validate_evidence.py", "--root", str(candidate_path),
             "--candidate", commit], candidate_path, args.timeout_seconds)
        run([python, "scripts/check_markdown_links.py", "--root", str(candidate_path)],
            candidate_path, args.timeout_seconds)
        run([python, "scripts/run_clean_cmake_tests.py", "--root", str(candidate_path),
             "--config", "both", "--jobs", "2"], candidate_path, args.timeout_seconds)
        run([python, "scripts/prove_release_test_check_failure.py", "--root", str(candidate_path)],
            candidate_path, args.timeout_seconds)
        run(["bash", "scripts/validate_rtl.sh"], candidate_path, args.timeout_seconds)

        identity_after = source_identity(candidate_path)
        if identity_after != identity_before:
            raise WslCandidateError(
                "Linux validation changed the isolated candidate identity: "
                f"before={identity_before}, after={identity_after}"
            )
        if git(candidate_path, "status", "--porcelain=v1", "--untracked-files=all"):
            raise WslCandidateError("Linux validation left non-ignored changes in the isolated candidate")
        linux_fingerprint_after = validate_evidence.source_fingerprint(root, commit, excluded)
        require_fingerprint_match(args.source_fingerprint, linux_fingerprint_after,
                                  view="after validation")
        candidate_bytes_after_validation = tree_bytes(candidate_path)
        print(json.dumps({
            "candidate_commit": commit,
            "linux_candidate_tree_bytes_after_validation": candidate_bytes_after_validation,
            "linux_free_bytes_before": disk_report["free_bytes"],
            "disk_output_root": str(linux_output_root),
        }, sort_keys=True), flush=True)
        pass_message = (
            f"[wsl-clean-candidate] PASS uid={os.geteuid()} commit={commit} tree={tree} "
            f"source_fingerprint={args.source_fingerprint} path={candidate_path}"
        )
        result_code = 0
    except (DiskBudgetError, OSError, ValueError, WslCandidateError, CleanSourceIdentityError,
            subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"unprivileged WSL candidate validation failed: {error}", file=sys.stderr)
        result_code = 2 if isinstance(error, DiskBudgetError) else 1
    finally:
        if added_worktree and candidate_path is not None:
            cleanup = subprocess.run(
                ["git", "-c", f"safe.directory={root}", "-C", str(root),
                 "worktree", "remove", "--force", str(candidate_path)],
                check=False, text=True, encoding="utf-8",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            if cleanup.returncode:
                detail = cleanup.stderr.strip() or cleanup.stdout.strip() or "no Git diagnostic"
                print(f"Linux candidate cleanup failed for {candidate_path}: {detail}", file=sys.stderr)
                result_code = 1
            elif candidate_path.exists():
                print(f"Linux candidate cleanup failed; path remains: {candidate_path}", file=sys.stderr)
                result_code = 1
            else:
                try:
                    after_cleanup = shutil.disk_usage(linux_output_root).free
                    print(
                        f"[wsl-clean-candidate] storage: linux_free_before={disk_report['free_bytes']} "
                        f"linux_free_after_cleanup={after_cleanup}; Windows host free space and WSL VHDX "
                        "allocation are separate measurements",
                        flush=True,
                    )
                except (OSError, UnboundLocalError):
                    pass
    if result_code == 0 and pass_message is not None:
        print(pass_message, flush=True)
    return result_code


if __name__ == "__main__":
    raise SystemExit(main())
