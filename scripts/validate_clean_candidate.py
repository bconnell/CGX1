#!/usr/bin/env python3
"""Validate the staged Git tree from a clean detached worktree."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Sequence

try:
    from scripts.validation_paths import (
        PathTranslationError,
        WSL_COMMAND_TIMEOUT_SECONDS,
        find_wsl_executable,
        find_windows_powershell,
        resolve_root_argument,
        translate_windows_path_to_wsl,
    )
except ModuleNotFoundError:  # direct execution places scripts/, not the repository root, on sys.path
    from validation_paths import (
        PathTranslationError,
        WSL_COMMAND_TIMEOUT_SECONDS,
        find_wsl_executable,
        find_windows_powershell,
        resolve_root_argument,
        translate_windows_path_to_wsl,
    )

DEFAULT_REQUIRED_PATHS = (
    "CMakeLists.txt",
    "source/testing/cgx1_test_check.h",
    "scripts/check_release_test_checks.py",
    "scripts/check_markdown_links.py",
    "scripts/validate_clean_candidate.py",
    "scripts/run_wsl_candidate.py",
    "scripts/run_clean_cmake_tests.py",
    "scripts/validate_evidence.py",
    "scripts/validate_hardening_ledgers.py",
    "scripts/validate_randomized_tests.py",
    "scripts/validate_resource_limits.py",
    "scripts/validate_rtl_inventory.py",
    "scripts/validate_rtl.sh",
    "scripts/validation_paths.py",
)
DEFAULT_CANDIDATE_TIMEOUT_SECONDS = 1800


class CandidateValidationError(RuntimeError):
    pass


def require_contributor_uid(native_os: str, uid: int | None) -> None:
    if native_os != "nt" and uid == 0:
        raise CandidateValidationError(
            "root-only runs are diagnostic and cannot be clean-candidate evidence; "
            "run as an unprivileged Linux user"
        )


@dataclass(frozen=True)
class CleanCandidate:
    path: Path
    tree: str
    commit: str
    ref: str


def _git(root: Path, *arguments: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", "-c", f"safe.directory={root.resolve()}", "-C", str(root), *arguments],
        check=False,
        text=True,
        encoding="utf-8",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise CandidateValidationError(
            f"git {' '.join(arguments)} failed ({result.returncode}): {detail}"
        )
    return result.stdout.strip()


def require_candidate_paths(root: Path, required_paths: Sequence[str]) -> None:
    root = root.resolve()
    missing: list[str] = []
    for raw_path in required_paths:
        normalized = raw_path.replace("\\", "/")
        parts = normalized.split("/")
        if (not normalized or normalized.startswith("/") or PureWindowsPath(raw_path).is_absolute()
                or any(part in {"", ".", ".."} for part in parts)):
            raise CandidateValidationError(f"required path must be repository-relative: {raw_path!r}")
        candidate = (root / Path(*parts)).resolve()
        if not candidate.is_relative_to(root):
            raise CandidateValidationError(f"required path resolves outside candidate: {raw_path!r}")
        if not candidate.is_file():
            missing.append(normalized)
    if missing:
        raise CandidateValidationError(
            "clean candidate is missing required committed file(s): " + ", ".join(sorted(missing))
        )


def require_empty_build_start(root: Path) -> None:
    build = root.resolve() / "build"
    if build.exists():
        raise CandidateValidationError(
            f"clean candidate must start without a build directory; found {build}"
        )


def create_clean_candidate(root: Path, worktree_parent: Path | None = None) -> CleanCandidate:
    root = Path(_git(root.resolve(), "rev-parse", "--show-toplevel")).resolve()
    if worktree_parent is None:
        worktree_parent = root / "build" / "cgx1-clean-candidates"
    worktree_parent = worktree_parent.resolve()
    if not worktree_parent.is_relative_to(root):
        raise CandidateValidationError("candidate worktree parent must remain inside the repository build directory")
    worktree_parent.mkdir(parents=True, exist_ok=True)

    tree = _git(root, "write-tree")
    head = _git(root, "rev-parse", "HEAD")
    head_tree = _git(root, "rev-parse", "HEAD^{tree}")
    if tree == head_tree:
        commit = head
    else:
        commit = _git(
            root,
            "-c", "user.name=CGX1 clean-candidate validator",
            "-c", "user.email=clean-candidate@localhost",
            "commit-tree", tree, "-p", head, "-m", "CGX1 staged clean-validation candidate",
        )

    token = uuid.uuid4().hex
    path = worktree_parent / f"candidate-{tree[:12]}-{token[:8]}"
    ref = f"refs/cgx1/clean-candidates/{token}"
    if path.exists():
        raise CandidateValidationError(f"refusing to reuse existing candidate path: {path}")
    _git(root, "update-ref", ref, commit)
    try:
        _git(root, "worktree", "add", "--detach", "--quiet", str(path), commit)
        checked_out_tree = _git(path, "rev-parse", "HEAD^{tree}")
        if checked_out_tree != tree:
            raise CandidateValidationError(
                f"clean worktree tree mismatch: expected {tree}, found {checked_out_tree}"
            )
        status = _git(path, "status", "--porcelain=v1", "--untracked-files=all")
        if status:
            raise CandidateValidationError(f"new candidate worktree is not clean: {status}")
        return CleanCandidate(path=path, tree=tree, commit=commit, ref=ref)
    except Exception:
        _git(root, "worktree", "remove", "--force", str(path), check=False)
        _git(root, "update-ref", "-d", ref, commit, check=False)
        raise


def remove_clean_candidate(root: Path, candidate: CleanCandidate) -> None:
    root = Path(_git(root.resolve(), "rev-parse", "--show-toplevel")).resolve()
    candidate_path = candidate.path.resolve()
    expected_parent = (root / "build" / "cgx1-clean-candidates").resolve()
    if candidate_path.parent != expected_parent or not candidate_path.name.startswith("candidate-"):
        raise CandidateValidationError(f"refusing to remove a path outside the owned candidate root: {candidate_path}")
    _git(root, "worktree", "remove", "--force", str(candidate_path))
    _git(root, "update-ref", "-d", candidate.ref, candidate.commit)


def _source_fingerprint(root: Path, commit: str) -> str:
    sys.path.insert(0, str(root / "scripts"))
    import validate_evidence

    ledger = json.loads((root / "design/cgx1_validation_evidence.json").read_text(encoding="utf-8"))
    excluded = ledger.get("fingerprint_excluded_paths", [])
    return validate_evidence.source_fingerprint(root, commit, excluded)


def _working_fingerprint(root: Path) -> str:
    sys.path.insert(0, str(root / "scripts"))
    import validate_evidence

    ledger = json.loads((root / "design/cgx1_validation_evidence.json").read_text(encoding="utf-8"))
    excluded = ledger.get("fingerprint_excluded_paths", [])
    return validate_evidence.source_fingerprint(root, None, excluded)


def _candidate_git_identity(candidate: CleanCandidate) -> dict[str, str]:
    head = _git(candidate.path, "rev-parse", "HEAD")
    head_tree = _git(candidate.path, "rev-parse", "HEAD^{tree}")
    index_tree = _git(candidate.path, "write-tree")
    status = _git(candidate.path, "status", "--porcelain=v1", "--untracked-files=all")
    if head != candidate.commit or head_tree != candidate.tree or index_tree != candidate.tree:
        raise CandidateValidationError(
            "candidate commit/tree/index identity mismatch: "
            f"expected={candidate.commit}/{candidate.tree}/{candidate.tree}, "
            f"found={head}/{head_tree}/{index_tree}"
        )
    if status:
        raise CandidateValidationError(f"candidate worktree is not clean: {status}")
    return {
        "candidate_commit": head,
        "candidate_tree": head_tree,
        "candidate_index_tree": index_tree,
        "candidate_path": str(candidate.path.resolve()),
    }


def _run(command: Sequence[str], cwd: Path, timeout_seconds: int) -> None:
    printable = subprocess.list2cmdline(list(command)) if os.name == "nt" else " ".join(command)
    print(f"[clean-candidate] + {printable}", flush=True)
    try:
        result = subprocess.run(list(command), cwd=cwd, check=False, timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        raise CandidateValidationError(
            f"candidate validation command exceeded {timeout_seconds}s: {printable}"
        ) from error
    if result.returncode:
        raise CandidateValidationError(
            f"candidate validation command failed ({result.returncode}): {printable}"
        )


def _capture(command: Sequence[str], timeout_seconds: int, *, label: str) -> str:
    printable = subprocess.list2cmdline(list(command))
    print(f"[clean-candidate] + {printable}", flush=True)
    try:
        result = subprocess.run(
            list(command), check=False, text=True, encoding="utf-8",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout_seconds,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise CandidateValidationError(f"could not establish {label}: {error}") from error
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or "no diagnostic"
        raise CandidateValidationError(f"could not establish {label} ({result.returncode}): {detail}")
    return result.stdout.strip()


def run_windows_validation(root: Path, timeout_seconds: int) -> None:
    powershell = find_windows_powershell()
    if not powershell:
        raise CandidateValidationError("PowerShell is required for the Windows repository/design gates")
    arguments = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                 str(root / "scripts" / "validate_windows.ps1"), "-CleanCandidate"]
    if os.environ.get("GITHUB_ACTIONS", "").lower() != "true":
        arguments.append("-DeferCmakeToUnprivilegedWsl")
    _run(
        [powershell, *arguments],
        root, timeout_seconds,
    )


def run_rtl_validation(root: Path, timeout_seconds: int, skip_rtl: bool) -> str:
    if skip_rtl:
        print("[clean-candidate] RTL is covered by the exact-SHA hosted RTL workflow.", flush=True)
        return "delegated_to_exact_sha_hosted_workflow"
    bash = shutil.which("bash")
    iverilog = shutil.which("iverilog")
    if bash and iverilog:
        _run([bash, "scripts/validate_rtl.sh"], root, timeout_seconds)
        return "passed"
    raise CandidateValidationError(
        "RTL validation is required; Linux clean candidates must provide Bash and Icarus Verilog"
    )


def run_unprivileged_wsl_candidate_validation(
    source_root: Path,
    candidate: CleanCandidate,
    source_fingerprint: str,
    timeout_seconds: int,
) -> str:
    if os.name != "nt":
        raise CandidateValidationError("the WSL candidate runner can only be launched from Windows")
    wsl = find_wsl_executable()
    if not wsl:
        raise CandidateValidationError(
            "unprivileged Linux validation requires wsl.exe; install/use a supported WSL distribution "
            "or run the canonical Linux gate in hosted CI"
        )
    distribution = os.environ.get("CGX1_WSL_DISTRO", "Ubuntu")
    user = os.environ.get("CGX1_WSL_USER", "nobody")
    uid = _capture(
        [wsl, "--distribution", distribution, "--user", user, "--exec", "id", "-u"],
        WSL_COMMAND_TIMEOUT_SECONDS, label=f"unprivileged WSL identity for {distribution}/{user}",
    )
    if not uid.isdecimal() or int(uid) == 0:
        raise CandidateValidationError(
            f"WSL Linux validation requires a non-root UID; {distribution}/{user} reported {uid!r}"
        )

    try:
        linux_source_root = translate_windows_path_to_wsl(
            source_root, wsl_executable=wsl, distribution=distribution, user=user,
        )
        linux_candidate_root = translate_windows_path_to_wsl(
            candidate.path, wsl_executable=wsl, distribution=distribution, user=user,
        )
    except PathTranslationError as error:
        raise CandidateValidationError(str(error)) from error

    command = [
        wsl, "--distribution", distribution, "--user", user, "--exec", "env",
        "GIT_CONFIG_COUNT=1", "GIT_CONFIG_KEY_0=safe.directory",
        f"GIT_CONFIG_VALUE_0={linux_source_root}", "python3",
        f"{linux_candidate_root}/scripts/run_wsl_candidate.py",
        "--git-root", linux_source_root,
        "--commit", candidate.commit,
        "--tree", candidate.tree,
        "--source-fingerprint", source_fingerprint,
        "--timeout-seconds", str(timeout_seconds),
    ]
    _run(command, source_root, timeout_seconds)
    return f"passed_unprivileged_wsl_uid_{uid}"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    parser.add_argument("--required-path", action="append", default=[],
                        help="additional committed file that must exist in the clean candidate")
    parser.add_argument("--skip-rtl", action="store_true",
                        help="use only when the exact commit is covered by the required hosted RTL workflow")
    parser.add_argument("--timeout-seconds", type=int, default=DEFAULT_CANDIDATE_TIMEOUT_SECONDS)
    args = parser.parse_args(argv)
    if args.timeout_seconds < 1:
        parser.error("--timeout-seconds must be positive")
    if args.skip_rtl and os.environ.get("GITHUB_ACTIONS", "").lower() != "true":
        parser.error("--skip-rtl is reserved for hosted Windows CI with a required exact-SHA RTL workflow")
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    try:
        require_contributor_uid(os.name, os.geteuid() if hasattr(os, "geteuid") else None)
    except CandidateValidationError as error:
        parser.error(str(error))
    required = tuple(dict.fromkeys((*DEFAULT_REQUIRED_PATHS, *args.required_path)))
    candidate: CleanCandidate | None = None
    exit_code = 1
    try:
        candidate = create_clean_candidate(root)
        require_empty_build_start(candidate.path)
        require_candidate_paths(candidate.path, required)
        candidate_git_before = _candidate_git_identity(candidate)
        before = _source_fingerprint(candidate.path, candidate.commit)
        checkout_before = _working_fingerprint(candidate.path)
        print(json.dumps({
            "candidate_commit": candidate.commit,
            "candidate_tree": candidate.tree,
            "candidate_index_tree": candidate_git_before["candidate_index_tree"],
            "candidate_path": candidate_git_before["candidate_path"],
            "source_fingerprint": before,
            "checkout_fingerprint": checkout_before,
            "worktree_clean": True,
            "required_paths_present": list(required),
        }, indent=2, sort_keys=True), flush=True)

        if os.name == "nt":
            run_windows_validation(candidate.path, args.timeout_seconds)
            if args.skip_rtl:
                rtl_status = "delegated_to_exact_sha_hosted_workflow"
            else:
                rtl_status = run_unprivileged_wsl_candidate_validation(
                    root, candidate, before, args.timeout_seconds,
                )
        else:
            python = sys.executable
            for script in (
                "validate_resource_limits.py", "validate_hardening_ledgers.py",
                "validate_rtl_inventory.py", "validate_randomized_tests.py",
                "check_release_test_checks.py",
            ):
                _run([python, str(candidate.path / "scripts" / script)], candidate.path,
                     args.timeout_seconds)
            _run([python, "-m", "unittest", "discover", "-s", "scripts/tests", "-v"],
                 candidate.path, args.timeout_seconds)
            _run([python, "scripts/validate_evidence.py", "--root", str(candidate.path),
                  "--candidate", candidate.commit], candidate.path, args.timeout_seconds)
            _run([python, "scripts/check_markdown_links.py", "--root", str(candidate.path)],
                 candidate.path, args.timeout_seconds)
            _run([python, "scripts/run_clean_cmake_tests.py", "--root", str(candidate.path),
                  "--config", "both", "--jobs", "2"], candidate.path, args.timeout_seconds)

            rtl_status = run_rtl_validation(candidate.path, args.timeout_seconds, args.skip_rtl)
        after_git = _candidate_git_identity(candidate)
        after_checkout = _working_fingerprint(candidate.path)
        after_commit = _source_fingerprint(candidate.path, candidate.commit)
        if after_git != candidate_git_before or after_checkout != checkout_before or after_commit != before:
            raise CandidateValidationError(
                "validation changed candidate source identity: "
                f"before={candidate_git_before}/{before}/{checkout_before}, "
                f"after={after_git}/{after_commit}/{after_checkout}"
            )
        print(
            f"[clean-candidate] PASS commit={candidate.commit} tree={candidate.tree} "
            f"source_fingerprint={before} path={candidate.path.resolve()} rtl={rtl_status}",
            flush=True,
        )
        exit_code = 0
    except (OSError, ValueError, CandidateValidationError, subprocess.SubprocessError) as error:
        print(f"clean-candidate validation failed: {error}", file=sys.stderr)
        exit_code = 1
    finally:
        if candidate is not None:
            try:
                remove_clean_candidate(root, candidate)
            except Exception as error:  # cleanup failure is itself a gate failure
                print(f"clean-candidate cleanup failed: {error}", file=sys.stderr)
                exit_code = 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
