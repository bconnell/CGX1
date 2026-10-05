#!/usr/bin/env python3
"""Configure from empty build trees, build every target, and run CTest."""
from __future__ import annotations
import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:  # direct execution places scripts/, not the repository root, on sys.path
    from validation_paths import PathTranslationError, resolve_root_argument

MIN_FREE_BYTES = 2 * 1024 * 1024 * 1024
DEFAULT_BUDGET_SECONDS = 900


class CleanSourceIdentityError(RuntimeError):
    """The runner could not establish or preserve the source it is about to test."""


def classify_execution_uid(uid: int | None) -> str:
    if uid == 0:
        return "root_diagnostic_only"
    if uid is None:
        return "platform_default"
    return "unprivileged"


def require_unchanged_source_identity(before: dict[str, str], after: dict[str, str]) -> None:
    if before != after:
        raise CleanSourceIdentityError(
            f"candidate identity changed while clean validation ran: before={before}, after={after}"
        )


def first_line(command: list[str], cwd: Path) -> str | None:
    try:
        result = subprocess.run(command, cwd=cwd, check=False, text=True,
                                encoding="utf-8", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.splitlines()[0] if result.stdout else None


def source_identity(root: Path) -> dict[str, str]:
    root = root.resolve()
    git_prefix = ["git", "-c", f"safe.directory={root}", "-C", str(root)]

    def git_identity(label: str, *arguments: str) -> str:
        try:
            result = subprocess.run(
                [*git_prefix, *arguments], check=True, text=True, encoding="utf-8",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
            )
        except (OSError, subprocess.SubprocessError) as error:
            detail = ""
            if isinstance(error, subprocess.CalledProcessError):
                detail = (error.stderr or error.stdout or "").strip()
            raise CleanSourceIdentityError(
                f"could not establish {label} identity at {root}: "
                f"{detail or error}"
            ) from error
        value = result.stdout.strip()
        if not value:
            raise CleanSourceIdentityError(
                f"could not establish {label} identity at {root}: Git returned no value"
            )
        return value

    top_level = Path(git_identity("Git repository-root", "rev-parse", "--show-toplevel")).resolve()
    if top_level != root:
        raise CleanSourceIdentityError(
            f"candidate path identity mismatch: requested {root}, Git selected {top_level}"
        )
    head = git_identity("Git HEAD", "rev-parse", "HEAD")
    head_tree = git_identity("Git HEAD tree", "rev-parse", "HEAD^{tree}")
    index_tree = git_identity("Git index tree", "write-tree")
    try:
        sys.path.insert(0, str(root / "scripts"))
        import validate_evidence
        ledger = json.loads((root / "design/cgx1_validation_evidence.json").read_text(encoding="utf-8"))
        fingerprint = validate_evidence.source_fingerprint(
            root, excluded_paths=ledger.get("fingerprint_excluded_paths", []))
    except Exception as error:
        detail = ""
        if isinstance(error, subprocess.CalledProcessError):
            stderr = error.stderr.decode("utf-8", errors="replace") if isinstance(error.stderr, bytes) else error.stderr
            detail = (stderr or error.stdout or "").strip()
        raise CleanSourceIdentityError(
            f"could not establish source fingerprint at {root}: {detail or error}"
        ) from error
    if not fingerprint:
        raise CleanSourceIdentityError(f"could not establish source fingerprint at {root}: empty fingerprint")
    return {
        "candidate_path": str(root),
        "git_head": head,
        "head_tree": head_tree,
        "index_tree": index_tree,
        "source_fingerprint": fingerprint,
    }


def tree_bytes(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        if item.is_file():
            try:
                total += item.stat().st_size
            except OSError:
                pass
    return total


def run(command: list[str], cwd: Path, started: float, budget_seconds: int) -> float:
    elapsed = time.monotonic() - started
    remaining = budget_seconds - elapsed
    if remaining <= 0:
        raise TimeoutError(f"clean validation exceeded its {budget_seconds}-second budget")
    print(f"[{elapsed:8.1f}s] + {' '.join(command)}", flush=True)
    stage = time.monotonic()
    try:
        result = subprocess.run(command, cwd=cwd, check=False, timeout=remaining)
    except subprocess.TimeoutExpired as error:
        raise TimeoutError(f"command exceeded remaining {remaining:.1f}s validation budget: {command}") from error
    duration = time.monotonic() - stage
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, command)
    return duration


def read_cache(build: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    cache = build / "CMakeCache.txt"
    if not cache.is_file():
        return result
    for line in cache.read_text(encoding="utf-8", errors="replace").splitlines():
        if ":" not in line or line.startswith("//") or line.startswith("#"):
            continue
        name, value = line.split("=", 1)
        key = name.split(":", 1)[0]
        if key in {"CMAKE_C_COMPILER", "CMAKE_C_COMPILER_ID", "CMAKE_C_COMPILER_VERSION",
                   "CMAKE_CXX_COMPILER", "CMAKE_CXX_COMPILER_ID", "CMAKE_CXX_COMPILER_VERSION",
                   "CMAKE_BUILD_TYPE"}:
            result[key] = value
    return result


def write_summary(path: Path | None, summary: dict[str, Any]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    parser.add_argument("--config", choices=("Debug", "Release", "both"), default="both")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--budget-seconds", type=int, default=DEFAULT_BUDGET_SECONDS)
    parser.add_argument("--cmake-arg", action="append", default=[], help="extra configure argument, repeatable")
    parser.add_argument("--summary-json", type=Path, help="write exact candidate/toolchain/resource result JSON")
    parser.add_argument("--keep-build", action="store_true", help="retain the empty-start build trees after completion")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if args.budget_seconds < 1:
        parser.error("--budget-seconds must be positive")
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    if not (root / "CMakeLists.txt").is_file():
        parser.error(f"no CMakeLists.txt at {root}")

    started = time.monotonic()
    configs = ("Debug", "Release") if args.config == "both" else (args.config,)
    runner_uid = os.geteuid() if hasattr(os, "geteuid") else None
    privilege_class = classify_execution_uid(runner_uid)
    try:
        identity_before = source_identity(root)
    except CleanSourceIdentityError as error:
        summary = {
            "schema_version": 1, "root": root.name, "candidate_path": str(root),
            "git_head": None, "head_tree": None, "index_tree": None,
            "source_fingerprint": None, "configuration_set": list(configs),
            "runner_uid": runner_uid, "privilege_class": privilege_class,
            "status": "identity_unavailable", "exit_code": 2,
            "failure": {"message": str(error)}, "budget_seconds": args.budget_seconds,
            "parallel_jobs": args.jobs, "host": platform.platform(), "python": sys.version,
            "configurations": [], "total_elapsed_seconds": time.monotonic() - started,
        }
        print(str(error), file=sys.stderr)
        write_summary(args.summary_json, summary)
        print(json.dumps(summary, indent=2, sort_keys=True), flush=True)
        return 2

    required_tools = ("cmake", "ctest", "cc", "c++", "git")
    missing_tools = [name for name in required_tools if shutil.which(name) is None]
    if missing_tools:
        message = "required tools are missing from this runner's PATH: " + ", ".join(missing_tools)
        print(message, file=sys.stderr)
        summary = {
            "schema_version": 1, "root": root.name, **identity_before,
            "configuration_set": list(configs), "status": "tool_unavailable", "exit_code": 2,
            "runner_uid": runner_uid, "privilege_class": privilege_class,
            "failure": {"message": message}, "budget_seconds": args.budget_seconds,
            "parallel_jobs": args.jobs, "host": platform.platform(), "python": sys.version,
            "configurations": [], "total_elapsed_seconds": time.monotonic() - started,
        }
        write_summary(args.summary_json, summary)
        print(json.dumps(summary, indent=2, sort_keys=True), flush=True)
        return 2

    build_root = root / "build" / "clean-validation"
    build_root.mkdir(parents=True, exist_ok=True)
    base = Path(tempfile.mkdtemp(prefix="cgx1-clean-cmake-", dir=build_root))
    summary: dict[str, Any] = {
        "schema_version": 1, "root": root.name, **identity_before,
        "configuration_set": list(configs),
        "runner_uid": runner_uid, "privilege_class": privilege_class,
        "status": "in_progress", "exit_code": None, "budget_seconds": args.budget_seconds,
        "parallel_jobs": args.jobs, "host": platform.platform(), "python": sys.version,
        "cmake": first_line(["cmake", "--version"], root),
        "c_banner": first_line(["cc", "--version"], root),
        "cxx_banner": first_line(["c++", "--version"], root),
        "free_bytes_before": shutil.disk_usage(base.parent).free,
        "minimum_free_bytes": MIN_FREE_BYTES, "build_tree_bytes": None,
        "configurations": [], "total_elapsed_seconds": None,
    }
    if summary["free_bytes_before"] < MIN_FREE_BYTES:
        print(f"Less than {MIN_FREE_BYTES} bytes free before clean validation.", file=sys.stderr)
        summary["status"] = "insufficient_space"
        summary["exit_code"] = 2
        summary["total_elapsed_seconds"] = time.monotonic() - started
        write_summary(args.summary_json, summary)
        print(json.dumps(summary, indent=2, sort_keys=True), flush=True)
        if not args.keep_build:
            shutil.rmtree(base, ignore_errors=True)
        return 2

    exit_code = 0
    try:
        for config in configs:
            config_started = time.monotonic()
            build = base / config.lower()
            stages: dict[str, float] = {}
            configure = ["cmake", "-S", str(root), "-B", str(build), f"-DCMAKE_BUILD_TYPE={config}", *args.cmake_arg]
            stages["configure_seconds"] = run(configure, root, started, args.budget_seconds)
            toolchain = read_cache(build)
            inventory_started = time.monotonic()
            tests_json = subprocess.run(["ctest", "--test-dir", str(build), "--show-only=json-v1"],
                cwd=root, check=True, text=True, encoding="utf-8", stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=30)
            test_count = len(json.loads(tests_json.stdout).get("tests", []))
            if test_count < 1:
                raise RuntimeError("fresh CMake configuration exposes no CTest tests")
            stages["ctest_inventory_seconds"] = time.monotonic() - inventory_started
            stages["build_seconds"] = run(["cmake", "--build", str(build), "--config", config,
                "--parallel", str(args.jobs)], root, started, args.budget_seconds)
            stages["ctest_seconds"] = run(["ctest", "--test-dir", str(build), "-C", config,
                "--output-on-failure"], root, started, args.budget_seconds)
            summary["configurations"].append({"name": config, "status": "passed", "test_count": test_count,
                "toolchain": toolchain, **stages,
                "elapsed_seconds": time.monotonic() - config_started})
        identity_after = source_identity(root)
        require_unchanged_source_identity(identity_before, identity_after)
        if privilege_class == "root_diagnostic_only":
            summary["status"] = "passed_diagnostic_root_only"
            print(
                f"Diagnostic root-only {', '.join(configs)} configure/build/CTest passed in "
                f"{time.monotonic() - started:.1f}s; this is not contributor-grade clean-candidate evidence."
            )
        else:
            summary["status"] = "passed"
            print(f"Clean {', '.join(configs)} configure/build/CTest passed in {time.monotonic() - started:.1f}s.")
    except subprocess.CalledProcessError as error:
        exit_code = error.returncode or 1
        summary["status"] = "failed"
        summary["failure"] = {"command": error.cmd, "exit_code": error.returncode}
        print(f"Clean CMake validation failed with exit code {error.returncode}: {error.cmd}", file=sys.stderr)
    except TimeoutError as error:
        exit_code = 124
        summary["status"] = "timeout"
        summary["failure"] = {"message": str(error)}
        print(str(error), file=sys.stderr)
    except CleanSourceIdentityError as error:
        exit_code = 1
        summary["status"] = "identity_changed"
        summary["failure"] = {"message": str(error)}
        print(str(error), file=sys.stderr)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError) as error:
        exit_code = 1
        summary["status"] = "failed"
        summary["failure"] = {"message": str(error)}
        print(f"Clean CMake validation infrastructure failed: {error}", file=sys.stderr)
    finally:
        summary["exit_code"] = exit_code
        summary["total_elapsed_seconds"] = time.monotonic() - started
        summary["build_tree_bytes"] = tree_bytes(base)
        summary["free_bytes_after"] = shutil.disk_usage(base.parent).free
        summary["build_tree_path"] = str(base) if args.keep_build else None
        try:
            write_summary(args.summary_json, summary)
        finally:
            if args.keep_build:
                print(f"Retained fresh build trees: {base}")
            else:
                shutil.rmtree(base, ignore_errors=True)
        print(json.dumps(summary, indent=2, sort_keys=True), flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
