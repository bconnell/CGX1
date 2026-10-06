#!/usr/bin/env python3
"""Configure from empty build trees, build every target, and run CTest."""
from __future__ import annotations
import argparse
import json
import os
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
    from scripts.check_disk_budget import (
        DiskBudgetError, artifact_limits_for_operation, format_preflight_report,
        is_redirected_path, load_disk_policy,
        preflight_disk_budget, scan_generated_artifacts,
    )
except ModuleNotFoundError:  # direct execution places scripts/, not the repository root, on sys.path
    from validation_paths import PathTranslationError, resolve_root_argument
    from check_disk_budget import (
        DiskBudgetError, artifact_limits_for_operation, format_preflight_report,
        is_redirected_path, load_disk_policy,
        preflight_disk_budget, scan_generated_artifacts,
    )

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

    def fail_on_walk_error(error: OSError) -> None:
        raise error

    for directory, child_directories, file_names in os.walk(
        path, topdown=True, followlinks=False, onerror=fail_on_walk_error,
    ):
        current = Path(directory)
        retained_directories = []
        for name in child_directories:
            child = current / name
            try:
                metadata = child.lstat()
            except OSError as error:
                raise DiskBudgetError(f"cannot inspect generated output directory {child}: {error}") from error
            if not is_redirected_path(child, metadata) and stat.S_ISDIR(metadata.st_mode):
                retained_directories.append(name)
        child_directories[:] = retained_directories
        for name in file_names:
            item = current / name
            try:
                metadata = item.lstat()
            except OSError as error:
                raise DiskBudgetError(f"cannot measure generated output {item}: {error}") from error
            if not is_redirected_path(item, metadata) and stat.S_ISREG(metadata.st_mode):
                total += metadata.st_size
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
                   "CMAKE_BUILD_TYPE", "CMAKE_GENERATOR", "CMAKE_GENERATOR_PLATFORM"}:
            result[key] = value
    return result


def ctest_inventory_count(json_output: str, human_output: str = "") -> tuple[int, str]:
    """Count registered tests, retaining a human-list fallback for CTest builds."""
    try:
        parsed = json.loads(json_output)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, dict) and isinstance(parsed.get("tests"), list):
        json_count = len(parsed["tests"])
        if json_count:
            return json_count, "json"

    human_count = len(re.findall(r"^\s*Test\s+#\d+:", human_output, re.MULTILINE))
    if human_count:
        return human_count, "human"
    return 0, "empty"


def describe_empty_ctest_inventory(
    build: Path,
    json_result: subprocess.CompletedProcess[str],
    human_result: subprocess.CompletedProcess[str],
    ctest_path: str | None,
    ctest_version: str | None,
) -> str:
    generated_files = sorted(build.rglob("CTestTestfile.cmake"))
    file_details: list[str] = []
    for path in generated_files[:16]:
        try:
            content = path.read_text(encoding="utf-8", errors="replace")[:3000]
        except OSError as error:
            content = f"<read failed: {error}>"
        file_details.append(f"{path.relative_to(build).as_posix()}: {content!r}")
    if len(generated_files) > 16:
        file_details.append(f"... {len(generated_files) - 16} additional CTestTestfile.cmake files omitted")
    return (
        "fresh CMake configuration exposes no CTest tests after JSON and human inventory checks; "
        f"ctest_path={ctest_path!r}; ctest_version={ctest_version!r}; "
        f"json_exit={json_result.returncode}; json_stdout={json_result.stdout[:4000]!r}; "
        f"json_stderr={json_result.stderr[:2000]!r}; "
        f"human_exit={human_result.returncode}; human_stdout={human_result.stdout[:4000]!r}; "
        f"human_stderr={human_result.stderr[:2000]!r}; "
        f"generated_test_files={file_details!r}"
    )


def write_summary(path: Path | None, summary: dict[str, Any]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")


def require_no_stale_clean_builds(build_root: Path) -> None:
    if not build_root.is_dir():
        return
    existing = sorted(
        child for child in build_root.iterdir()
        if child.name.startswith("cgx1-clean-cmake-")
    )
    if existing:
        paths = ", ".join(str(path) for path in existing)
        raise RuntimeError(
            "an earlier CGX1 clean CMake output is still present; determine whether it is active "
            f"before cleanup or starting another build: {paths}"
        )


def require_build_root_inside_repo(root: Path, build_root: Path) -> None:
    root_resolved = root.resolve()
    build_directory = root_resolved / "build"
    try:
        resolved_build_directory = build_directory.resolve(strict=False)
        resolved_output = build_root.resolve(strict=False)
    except (OSError, RuntimeError) as error:
        raise DiskBudgetError(f"cannot resolve clean build output path {build_root}: {error}") from error
    if is_redirected_path(build_directory) or os.path.ismount(build_directory):
        raise DiskBudgetError(f"clean build directory is redirected or mounted: {build_directory}")
    if is_redirected_path(build_root) or os.path.ismount(build_root):
        raise DiskBudgetError(f"clean build output is redirected or mounted: {build_root}")
    if (not resolved_build_directory.is_relative_to(root_resolved)
            or resolved_build_directory == root_resolved):
        raise DiskBudgetError(f"clean build directory resolves outside the repository: {build_directory}")
    if (not resolved_output.is_relative_to(resolved_build_directory)
            or resolved_output == resolved_build_directory):
        raise DiskBudgetError(
            f"clean build output must remain under the repository build directory: {build_root}"
        )


def require_safe_owned_tree(path: Path, expected_parent: Path, prefix: str) -> None:
    if not path.exists():
        return
    if not path.name.startswith(prefix):
        raise RuntimeError(f"refusing to remove output without the CGX1 owner prefix: {path}")
    if is_redirected_path(path) or os.path.ismount(path):
        raise RuntimeError(f"refusing to remove a symlink or mount point: {path}")
    if is_redirected_path(expected_parent) or os.path.ismount(expected_parent):
        raise RuntimeError(f"refusing cleanup through a redirected or mounted parent: {expected_parent}")
    if not path.is_dir():
        raise RuntimeError(f"refusing to recursively remove a non-directory output: {path}")
    if path.resolve(strict=True).parent != expected_parent.resolve(strict=True):
        raise RuntimeError(f"refusing to remove output outside its owned parent: {path}")

    def fail_on_walk_error(error: OSError) -> None:
        raise RuntimeError(f"cannot inspect generated output before cleanup {path}: {error}") from error

    for directory, child_directories, file_names in os.walk(
        path, topdown=True, followlinks=False, onerror=fail_on_walk_error,
    ):
        current = Path(directory)
        for name in child_directories + file_names:
            child = current / name
            try:
                metadata = child.lstat()
            except OSError as error:
                raise RuntimeError(f"cannot inspect generated output before cleanup {child}: {error}") from error
            if is_redirected_path(child, metadata) or os.path.ismount(child):
                raise RuntimeError(f"refusing recursive cleanup through redirected path: {child}")


def compiler_operation(root: Path, config: str) -> str:
    if os.name == "nt":
        return "clean-cmake"
    compiler = shlex.split(os.environ.get("CC") or shutil.which("cc") or "cc")
    description = first_line([*compiler, "--version"], root) or ""
    family = "clang" if "clang" in description.lower() else "gcc"
    operation = f"{family}-{config.lower()}"
    try:
        budget = json.loads((root / "design/cgx1_validation_resource_budget.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "clean-cmake"
    if operation not in budget.get("disk_budget", {}).get("operations", {}):
        return "clean-cmake"
    return operation


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
    build_root_existed = build_root.exists()
    build_parent_existed = (root / "build").exists()
    try:
        require_build_root_inside_repo(root, build_root)
        disk_report = preflight_disk_budget(root, "clean-cmake", build_root)
        print(format_preflight_report(disk_report), flush=True)
        if disk_report["status"] == "unsafe":
            raise DiskBudgetError(disk_report["reason"])
        require_no_stale_clean_builds(build_root)
    except (DiskBudgetError, OSError, RuntimeError) as error:
        message = str(error)
        summary = {
            "schema_version": 1, "root": root.name, **identity_before,
            "configuration_set": list(configs), "status": "preflight_failed", "exit_code": 2,
            "runner_uid": runner_uid, "privilege_class": privilege_class,
            "failure": {"message": message}, "budget_seconds": args.budget_seconds,
            "parallel_jobs": args.jobs, "host": platform.platform(), "python": sys.version,
            "configurations": [], "disk_budget_preflight": locals().get("disk_report"),
            "total_elapsed_seconds": time.monotonic() - started,
        }
        print(f"Clean CMake preflight failed: {message}", file=sys.stderr)
        write_summary(args.summary_json, summary)
        print(json.dumps(summary, indent=2, sort_keys=True), flush=True)
        return 2

    build_root.mkdir(parents=True, exist_ok=True)
    base = Path(tempfile.mkdtemp(prefix="cgx1-clean-cmake-", dir=build_root))
    if args.summary_json is not None and args.summary_json.resolve(strict=False).is_relative_to(base.resolve()):
        shutil.rmtree(base)
        raise ValueError("--summary-json must not be placed inside the disposable clean build tree")
    summary: dict[str, Any] = {
        "schema_version": 1, "root": root.name, **identity_before,
        "configuration_set": list(configs),
        "runner_uid": runner_uid, "privilege_class": privilege_class,
        "status": "in_progress", "exit_code": None, "budget_seconds": args.budget_seconds,
        "parallel_jobs": args.jobs, "host": platform.platform(), "python": sys.version,
        "cmake": first_line(["cmake", "--version"], root),
        "ctest": first_line(["ctest", "--version"], root),
        "ctest_executable": shutil.which("ctest"),
        "free_bytes_before": disk_report["free_bytes"],
        "minimum_free_bytes": disk_report["minimum_free_bytes"],
        "disk_budget_preflight": disk_report,
        "build_tree_bytes": None, "peak_configuration_tree_bytes": 0,
        "configurations": [], "total_elapsed_seconds": None,
    }

    exit_code = 0
    active_configuration: dict[str, Any] | None = None
    try:
        for config in configs:
            config_started = time.monotonic()
            build = base / config.lower()
            stages: dict[str, float] = {}
            active_configuration = {"name": config, "build": build, "stages": stages}
            operation = compiler_operation(root, config)
            stage_disk_report = preflight_disk_budget(
                root, operation, build,
            )
            print(format_preflight_report(stage_disk_report), flush=True)
            if stage_disk_report["status"] == "unsafe":
                raise DiskBudgetError(stage_disk_report["reason"])
            configure = ["cmake", "-S", str(root), "-B", str(build), f"-DCMAKE_BUILD_TYPE={config}", *args.cmake_arg]
            stages["configure_seconds"] = run(configure, root, started, args.budget_seconds)
            toolchain = read_cache(build)
            inventory_started = time.monotonic()
            tests_json = subprocess.run(["ctest", "--test-dir", str(build), "--show-only=json-v1"],
                cwd=root, check=False, text=True, encoding="utf-8", stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=30)
            if tests_json.returncode:
                raise RuntimeError(
                    "CTest JSON inventory command failed: "
                    f"exit={tests_json.returncode}; stdout={tests_json.stdout[:4000]!r}; "
                    f"stderr={tests_json.stderr[:2000]!r}"
                )
            test_count, inventory_method = ctest_inventory_count(tests_json.stdout)
            if test_count < 1:
                tests_human = subprocess.run(["ctest", "--test-dir", str(build), "--show-only"],
                    cwd=root, check=False, text=True, encoding="utf-8", stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, timeout=30)
                test_count, inventory_method = ctest_inventory_count(
                    tests_json.stdout, tests_human.stdout + "\n" + tests_human.stderr)
                if tests_human.returncode:
                    raise RuntimeError(
                        "CTest human inventory command failed: "
                        f"exit={tests_human.returncode}; stdout={tests_human.stdout[:4000]!r}; "
                        f"stderr={tests_human.stderr[:2000]!r}"
                    )
                if test_count < 1:
                    raise RuntimeError(describe_empty_ctest_inventory(
                        build, tests_json, tests_human, shutil.which("ctest"),
                        first_line(["ctest", "--version"], root)))
            stages["ctest_inventory_seconds"] = time.monotonic() - inventory_started
            build_command = ["cmake", "--build", str(build), "--config", config,
                "--parallel", str(args.jobs)]
            if os.name == "nt":
                build_command.append("--verbose")
            stages["build_seconds"] = run(build_command, root, started, args.budget_seconds)
            stages["ctest_seconds"] = run(["ctest", "--test-dir", str(build), "-C", config,
                "--output-on-failure"], root, started, args.budget_seconds)
            disk_policy = load_disk_policy(root)
            limits = artifact_limits_for_operation(disk_policy, operation)
            artifact_scan = scan_generated_artifacts(
                build,
                max_waveform_bytes=limits["maximum_waveform_file_bytes"],
                max_test_output_bytes=limits["maximum_test_output_file_bytes"],
                max_tree_bytes=disk_policy["operations"][operation].get("maximum_output_tree_bytes"),
            )
            if not artifact_scan["passed"]:
                summary["artifact_scan_failure"] = artifact_scan
                raise RuntimeError(
                    "clean CMake output exceeded its configured per-file size limit: "
                    + json.dumps(artifact_scan.get("oversized", []), sort_keys=True)
                )
            config_bytes = tree_bytes(build)
            summary["peak_configuration_tree_bytes"] = max(
                summary["peak_configuration_tree_bytes"], config_bytes,
            )
            summary["configurations"].append({"name": config, "status": "passed", "test_count": test_count,
                "test_inventory_method": inventory_method,
                "disk_budget_preflight": stage_disk_report,
                "artifact_scan": artifact_scan,
                "build_tree_bytes": config_bytes,
                "free_bytes_after": shutil.disk_usage(base.parent).free,
                "toolchain": toolchain, **stages,
                "elapsed_seconds": time.monotonic() - config_started})
            if not args.keep_build:
                require_safe_owned_tree(build, base, config.lower())
                shutil.rmtree(build)
            active_configuration = None
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
    except (DiskBudgetError, OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError) as error:
        exit_code = 1
        summary["status"] = "failed"
        summary["failure"] = {"message": str(error)}
        print(f"Clean CMake validation infrastructure failed: {error}", file=sys.stderr)
    finally:
        summary["exit_code"] = exit_code
        summary["total_elapsed_seconds"] = time.monotonic() - started
        if exit_code != 0 and active_configuration is not None:
            failed_build = active_configuration["build"]
            try:
                failed_build_bytes = tree_bytes(failed_build) if failed_build.exists() else 0
                summary["failed_configuration"] = {
                    "name": active_configuration["name"],
                    "build_tree_bytes": failed_build_bytes,
                    "completed_stages": dict(active_configuration["stages"]),
                }
                summary["peak_configuration_tree_bytes"] = max(
                    summary["peak_configuration_tree_bytes"], failed_build_bytes,
                )
            except (DiskBudgetError, OSError) as error:
                summary["failed_configuration"] = {
                    "name": active_configuration["name"],
                    "build_tree_bytes": None,
                    "measurement_failure": str(error),
                    "completed_stages": dict(active_configuration["stages"]),
                }
                summary["artifact_size_measurement_failure"] = str(error)
        try:
            summary["build_tree_bytes"] = (
                tree_bytes(base) if args.keep_build else summary["peak_configuration_tree_bytes"]
            )
        except (DiskBudgetError, OSError) as error:
            summary["build_tree_bytes"] = None
            summary["artifact_size_measurement_failure"] = str(error)
            if exit_code == 0:
                exit_code = 1
                summary["status"] = "failed"
                summary["failure"] = {"message": str(error)}
        summary["build_tree_path"] = str(base) if args.keep_build else None
        if args.keep_build:
            print(f"Retained fresh build trees: {base}")
        else:
            try:
                require_safe_owned_tree(base, build_root, "cgx1-clean-cmake-")
                if base.exists():
                    shutil.rmtree(base)
                if not build_root_existed:
                    try:
                        build_root.rmdir()
                    except OSError:
                        pass
                if not build_parent_existed:
                    try:
                        (root / "build").rmdir()
                    except OSError:
                        pass
            except (OSError, RuntimeError) as error:
                exit_code = 1
                summary["exit_code"] = exit_code
                summary["status"] = "cleanup_failed"
                summary["failure"] = {"message": str(error)}
                print(f"Clean CMake output cleanup failed: {error}", file=sys.stderr)
        try:
            summary["free_bytes_after"] = shutil.disk_usage(disk_report["filesystem_probe_path"]).free
        except (OSError, KeyError):
            summary["free_bytes_after"] = None
        summary["free_bytes_after_cleanup"] = summary["free_bytes_after"]
        if summary["free_bytes_after_cleanup"] is None and exit_code == 0:
            exit_code = 1
            summary["status"] = "failed"
            summary["failure"] = {"message": "post-cleanup filesystem free space could not be measured"}
        summary["exit_code"] = exit_code
        write_summary(args.summary_json, summary)
        print(json.dumps(summary, indent=2, sort_keys=True), flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
