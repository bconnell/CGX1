#!/usr/bin/env python3
"""Preflight the output filesystem and bound generated validation artifacts."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import sys
from pathlib import Path, PureWindowsPath
from typing import Any, Mapping


DEFAULT_ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = Path("design/cgx1_validation_resource_budget.json")
WAVEFORM_SUFFIXES = {".vcd", ".fst", ".lxt", ".lxt2", ".ghw"}
GIB = 1024**3


class DiskBudgetError(RuntimeError):
    """The output volume or its configured budget could not be established."""


def select_profile(requested: str, environ: Mapping[str, str] | None = None) -> str:
    environ = os.environ if environ is None else environ
    if requested == "auto":
        return "hosted" if environ.get("GITHUB_ACTIONS", "").lower() == "true" else "developer"
    if requested not in {"developer", "hosted"}:
        raise DiskBudgetError(f"unknown disk-budget profile: {requested}")
    return requested


def _native_path(path: str | os.PathLike[str]) -> Path:
    raw = os.fspath(path)
    if not raw.strip():
        raise DiskBudgetError("output path is empty; disk usage cannot be measured")
    if os.name != "nt" and PureWindowsPath(raw).is_absolute():
        raise DiskBudgetError(
            f"Windows-style output path cannot be measured on Linux: {raw!r}; "
            "translate it to a native Linux path such as /mnt/c/... first"
        )
    return Path(raw).expanduser()


def nearest_existing_path(path: str | os.PathLike[str]) -> Path:
    """Return the resolved existing ancestor whose filesystem will receive output."""
    candidate = _native_path(path)
    try:
        resolved = candidate.resolve(strict=False)
    except (OSError, RuntimeError) as error:
        raise DiskBudgetError(f"cannot resolve output path {candidate}: {error}") from error
    while not resolved.exists():
        parent = resolved.parent
        if parent == resolved:
            raise DiskBudgetError(f"no existing filesystem ancestor for output path {candidate}")
        resolved = parent
    try:
        return resolved.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise DiskBudgetError(f"cannot resolve existing output volume for {candidate}: {error}") from error


def measure_output_volume(
    output_path: str | os.PathLike[str],
    *,
    disk_usage=None,
) -> dict[str, Any]:
    probe = nearest_existing_path(output_path)
    disk_usage = shutil.disk_usage if disk_usage is None else disk_usage
    try:
        usage = disk_usage(probe)
    except OSError as error:
        raise DiskBudgetError(
            f"cannot measure the filesystem that will receive {output_path}: {error}"
        ) from error
    return {
        "probe_path": str(probe),
        "total_bytes": int(usage.total),
        "used_bytes": int(usage.used),
        "free_bytes": int(usage.free),
    }


def evaluate_budget(
    profile: Mapping[str, Any],
    free_bytes: int,
    estimate_bytes: int | None,
    *,
    block_when_warning: bool = False,
) -> dict[str, Any]:
    minimum = profile.get("minimum_free_bytes")
    warning = profile.get("warning_free_bytes")
    if not isinstance(minimum, int) or isinstance(minimum, bool) or minimum < 0:
        raise DiskBudgetError("disk-budget profile needs a non-negative minimum_free_bytes")
    if warning is not None and (
        not isinstance(warning, int) or isinstance(warning, bool) or warning < minimum
    ):
        raise DiskBudgetError("warning_free_bytes must be null or at least minimum_free_bytes")
    if not isinstance(free_bytes, int) or isinstance(free_bytes, bool) or free_bytes < 0:
        raise DiskBudgetError("measured free space must be a non-negative integer")
    if estimate_bytes is not None and (
        not isinstance(estimate_bytes, int) or isinstance(estimate_bytes, bool) or estimate_bytes < 0
    ):
        raise DiskBudgetError("estimated output bytes must be a non-negative integer")

    projected = None if estimate_bytes is None else free_bytes - estimate_bytes
    reasons: list[str] = []
    unsafe = free_bytes < minimum
    if unsafe:
        reasons.append(f"current free space is below the {minimum}-byte minimum reserve")
    if projected is not None and projected < minimum:
        unsafe = True
        reasons.append(f"estimated output would leave less than the {minimum}-byte minimum reserve")

    warning_state = (warning is not None and free_bytes < warning) or (
        warning is not None and projected is not None and projected < warning
    )
    if unsafe:
        status = "unsafe"
    elif warning_state:
        status = "warning"
        reasons.append("free space is below the configured warning threshold")
    else:
        status = "info"
        reasons.append("free space meets the configured reserve")

    if estimate_bytes is None:
        estimate_status = "unmeasured"
        reasons.append("job-size estimate is unmeasured; preflight applied the free-space reserve only")
    else:
        estimate_status = "provided"

    if block_when_warning and status == "warning":
        status = "unsafe"
        reasons.append("optional artifact-heavy work is blocked while the developer profile warns")

    return {
        "status": status,
        "free_bytes": free_bytes,
        "warning_free_bytes": warning,
        "minimum_free_bytes": minimum,
        "estimate_bytes": estimate_bytes,
        "estimate_status": estimate_status,
        "projected_free_bytes": projected,
        "reason": "; ".join(reasons),
    }


def load_disk_policy(root: Path) -> dict[str, Any]:
    path = root / POLICY_PATH
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise DiskBudgetError(f"cannot read disk-budget policy {path}: {error}") from error
    if not isinstance(document, dict):
        raise DiskBudgetError(f"disk-budget policy root must be an object: {path}")
    return validate_disk_policy(document)


def validate_disk_policy(document: Mapping[str, Any]) -> dict[str, Any]:
    budget = document.get("disk_budget")
    if not isinstance(budget, dict):
        raise DiskBudgetError("disk-budget policy is missing")
    if not isinstance(budget.get("profiles"), dict) or not isinstance(budget.get("operations"), dict):
        raise DiskBudgetError("disk-budget profiles or operations are missing")
    for name in ("developer", "hosted"):
        profile = budget["profiles"].get(name)
        if not isinstance(profile, dict):
            raise DiskBudgetError(f"disk-budget profile {name!r} is missing")
        evaluate_budget(profile, 0, None)
    required_operations = {
        "clean-candidate", "clean-cmake", "wsl-candidate", "gcc-debug", "gcc-release",
        "clang-debug", "clang-release", "sanitizer-build", "hosted-tool-install", "icarus",
        "verilator-toolchain-build", "rtl-tools", "synthesis-smoke", "formal",
    }
    missing = sorted(required_operations - set(budget["operations"]))
    if missing:
        raise DiskBudgetError("disk-budget operation classes are missing: " + ", ".join(missing))
    for name, operation in budget["operations"].items():
        if not isinstance(operation, dict):
            raise DiskBudgetError(f"disk-budget operation {name!r} must be an object")
        estimate = operation.get("estimated_peak_bytes")
        status = operation.get("measurement_status")
        if estimate is None and status != "unmeasured":
            raise DiskBudgetError(f"unmeasured operation {name!r} must be labeled unmeasured")
        if estimate is not None and (
            not isinstance(estimate, int) or isinstance(estimate, bool) or estimate < 0
            or status not in {"measured", "estimate"}
            or not isinstance(operation.get("measurement_source"), str)
            or not operation["measurement_source"].strip()
        ):
            raise DiskBudgetError(f"operation {name!r} has an invalid estimate or measurement status")
        tree_limit = operation.get("maximum_output_tree_bytes")
        if tree_limit is not None and (
            not isinstance(tree_limit, int) or isinstance(tree_limit, bool) or tree_limit <= 0
        ):
            raise DiskBudgetError(f"operation {name!r} has an invalid maximum_output_tree_bytes")
        test_output_limit = operation.get("maximum_test_output_file_bytes")
        if test_output_limit is not None and (
            not isinstance(test_output_limit, int) or isinstance(test_output_limit, bool)
            or test_output_limit <= 0
        ):
            raise DiskBudgetError(f"operation {name!r} has an invalid maximum_test_output_file_bytes")
        if not isinstance(operation.get("block_when_warning"), bool):
            raise DiskBudgetError(f"operation {name!r} needs a boolean block_when_warning field")
    limits = budget.get("artifact_limits")
    if not isinstance(limits, dict):
        raise DiskBudgetError("disk-budget artifact limits are missing")
    for key in ("maximum_waveform_file_bytes", "maximum_test_output_file_bytes"):
        value = limits.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise DiskBudgetError(f"disk-budget artifact limit {key!r} must be a positive integer")
    return budget


def artifact_limits_for_operation(
    budget: Mapping[str, Any], operation: str,
) -> dict[str, int]:
    """Return global artifact limits with any explicitly scoped operation override."""
    operations = budget.get("operations")
    limits = budget.get("artifact_limits")
    if not isinstance(operations, dict) or operation not in operations:
        raise DiskBudgetError(f"operation {operation!r} has no artifact-scan policy")
    if not isinstance(limits, dict):
        raise DiskBudgetError("disk-budget artifact limits are missing")
    operation_limit = operations[operation].get("maximum_test_output_file_bytes")
    return {
        "maximum_waveform_file_bytes": limits["maximum_waveform_file_bytes"],
        "maximum_test_output_file_bytes": (
            operation_limit if operation_limit is not None
            else limits["maximum_test_output_file_bytes"]
        ),
    }


def _profile_with_overrides(profile: Mapping[str, Any], environ: Mapping[str, str]) -> dict[str, Any]:
    result = dict(profile)
    for key, variable in (
        ("warning_free_bytes", "CGX1_DISK_WARNING_FREE_BYTES"),
        ("minimum_free_bytes", "CGX1_DISK_MINIMUM_FREE_BYTES"),
    ):
        raw = environ.get(variable)
        if raw is not None:
            try:
                result[key] = int(raw)
            except ValueError as error:
                raise DiskBudgetError(f"{variable} must be a non-negative integer") from error
    return result


def preflight_disk_budget(
    root: Path,
    operation: str,
    output_path: str | os.PathLike[str],
    *,
    profile_name: str = "auto",
    estimate_bytes: int | None = None,
    environ: Mapping[str, str] | None = None,
    disk_usage=None,
) -> dict[str, Any]:
    environ = os.environ if environ is None else environ
    budget = load_disk_policy(root.resolve())
    operations = budget["operations"]
    if operation not in operations:
        raise DiskBudgetError(f"operation {operation!r} has no registered disk-budget policy")
    selected = select_profile(profile_name, environ)
    profiles = budget["profiles"]
    if selected not in profiles:
        raise DiskBudgetError(f"disk-budget profile {selected!r} is not configured")
    operation_policy = operations[operation]
    configured_estimate = operation_policy.get("estimated_peak_bytes")
    if estimate_bytes is None:
        estimate_bytes = configured_estimate
    profile = _profile_with_overrides(profiles[selected], environ)
    volume = measure_output_volume(output_path, disk_usage=disk_usage)
    result = evaluate_budget(
        profile,
        volume["free_bytes"],
        estimate_bytes,
        block_when_warning=(selected == "developer" and operation_policy.get("block_when_warning", False)),
    )
    result.update({
        "operation": operation,
        "profile": selected,
        "output_path": os.fspath(output_path),
        "filesystem_probe_path": volume["probe_path"],
        "filesystem_total_bytes": volume["total_bytes"],
        "filesystem_used_bytes": volume["used_bytes"],
    })
    return result


def is_redirected_path(path: Path, metadata: os.stat_result | None = None) -> bool:
    if path.is_symlink():
        return True
    if metadata is None:
        try:
            metadata = path.lstat()
        except OSError:
            return False
    reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    attributes = getattr(metadata, "st_file_attributes", 0)
    return bool(attributes & reparse_flag)


def scan_generated_artifacts(
    root: str | os.PathLike[str],
    *,
    max_waveform_bytes: int,
    max_test_output_bytes: int,
    max_tree_bytes: int | None = None,
) -> dict[str, Any]:
    output_root = _native_path(root)
    if not output_root.exists():
        return {"passed": True, "root": str(output_root), "files_scanned": 0,
                "total_bytes": 0, "largest_files": [], "oversized": [], "skipped_redirected": 0}
    if is_redirected_path(output_root):
        return {"passed": False, "root": str(output_root), "files_scanned": 0,
                "total_bytes": 0, "largest_files": [], "oversized": [],
                "error": "refusing to scan a redirected output root", "skipped_redirected": 0}
    if not output_root.is_dir():
        return {"passed": False, "root": str(output_root), "files_scanned": 0,
                "total_bytes": 0, "largest_files": [], "oversized": [],
                "error": "generated output root is not a directory", "skipped_redirected": 0}

    file_rows: list[dict[str, Any]] = []
    oversized: list[dict[str, Any]] = []
    skipped_redirected = 0
    try:
        for directory, child_directories, file_names in os.walk(output_root, topdown=True, followlinks=False):
            current = Path(directory)
            retained_directories = []
            for name in child_directories:
                child = current / name
                if is_redirected_path(child):
                    skipped_redirected += 1
                else:
                    retained_directories.append(name)
            child_directories[:] = retained_directories
            for name in file_names:
                item = current / name
                metadata = item.lstat()
                if is_redirected_path(item, metadata):
                    skipped_redirected += 1
                    continue
                if not stat.S_ISREG(metadata.st_mode):
                    continue
                size = int(metadata.st_size)
                relative = item.relative_to(output_root).as_posix()
                kind = "waveform" if item.suffix.lower() in WAVEFORM_SUFFIXES else "test_output"
                limit = max_waveform_bytes if kind == "waveform" else max_test_output_bytes
                row = {"path": str(item), "relative_path": relative, "bytes": size, "kind": kind}
                file_rows.append(row)
                if size > limit:
                    oversized.append({**row, "limit_bytes": limit})
    except OSError as error:
        return {"passed": False, "root": str(output_root), "files_scanned": len(file_rows),
                "total_bytes": sum(row["bytes"] for row in file_rows), "largest_files": [],
                "oversized": oversized, "error": f"could not scan generated output: {error}",
                "skipped_redirected": skipped_redirected}

    total_bytes = sum(row["bytes"] for row in file_rows)
    if max_tree_bytes is not None and total_bytes > max_tree_bytes:
        oversized.append({
            "path": str(output_root), "relative_path": ".", "bytes": total_bytes,
            "kind": "output_tree", "limit_bytes": max_tree_bytes,
        })
    file_rows.sort(key=lambda row: (-row["bytes"], row["relative_path"]))
    return {
        "passed": not oversized,
        "root": str(output_root),
        "files_scanned": len(file_rows),
        "total_bytes": total_bytes,
        "largest_files": file_rows[:5],
        "oversized": oversized,
        "skipped_redirected": skipped_redirected,
    }


def scan_generated_artifact_roots(
    roots: list[str | os.PathLike[str]],
    *,
    max_waveform_bytes: int,
    max_test_output_bytes: int,
    max_tree_bytes: int | None = None,
) -> dict[str, Any]:
    """Scan disjoint output roots and apply a single aggregate tree limit."""
    native_roots = [_native_path(root) for root in roots]
    if not native_roots:
        raise DiskBudgetError("at least one artifact scan root is required")
    resolved_roots: list[Path] = []
    for root in native_roots:
        if is_redirected_path(root):
            raise DiskBudgetError(f"refusing to scan a redirected output root: {root}")
        resolved = root.resolve(strict=False)
        if any(
            resolved == existing or resolved.is_relative_to(existing) or existing.is_relative_to(resolved)
            for existing in resolved_roots
        ):
            raise DiskBudgetError(f"artifact scan roots overlap: {root}")
        resolved_roots.append(resolved)

    reports = [
        scan_generated_artifacts(
            root,
            max_waveform_bytes=max_waveform_bytes,
            max_test_output_bytes=max_test_output_bytes,
        )
        for root in native_roots
    ]
    total_bytes = sum(report["total_bytes"] for report in reports)
    oversized = [issue for report in reports for issue in report.get("oversized", [])]
    if max_tree_bytes is not None and total_bytes > max_tree_bytes:
        oversized.append({
            "path": ", ".join(str(root) for root in native_roots),
            "relative_path": ".",
            "bytes": total_bytes,
            "kind": "output_tree",
            "limit_bytes": max_tree_bytes,
        })
    errors = [f"{report['root']}: {report['error']}" for report in reports if report.get("error")]
    largest_files = sorted(
        (row for report in reports for row in report.get("largest_files", [])),
        key=lambda row: (-row["bytes"], row["path"]),
    )[:5]
    return {
        "passed": not oversized and not errors,
        "roots": [report["root"] for report in reports],
        "files_scanned": sum(report["files_scanned"] for report in reports),
        "total_bytes": total_bytes,
        "largest_files": largest_files,
        "oversized": oversized,
        "errors": errors,
        "skipped_redirected": sum(report["skipped_redirected"] for report in reports),
    }


def format_size(byte_count: int | None) -> str:
    if byte_count is None:
        return "unmeasured"
    if byte_count >= GIB:
        return f"{byte_count / GIB:.2f} GiB"
    return f"{byte_count / (1024**2):.2f} MiB"


def format_preflight_report(report: Mapping[str, Any]) -> str:
    return (
        f"[disk-budget] {report['status']}: profile={report['profile']} "
        f"operation={report['operation']} output={report['output_path']} "
        f"filesystem={report['filesystem_probe_path']} "
        f"free={format_size(report['free_bytes'])} "
        f"estimate={format_size(report['estimate_bytes'])} "
        f"projected_free={format_size(report['projected_free_bytes'])}; {report['reason']}"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT,
                        help="repository root containing the disk-budget policy")
    parser.add_argument("--operation", required=True)
    parser.add_argument("--output-path", required=True,
                        help="directory or file path that will receive generated output")
    parser.add_argument("--profile", choices=("auto", "developer", "hosted"), default="auto")
    parser.add_argument("--estimate-bytes", type=int,
                        help="explicit peak-size estimate when the policy has no measurement")
    parser.add_argument("--scan-root", type=Path, action="append",
                        help="also check generated files under this root; repeat to aggregate disjoint roots")
    args = parser.parse_args(argv)
    try:
        report = preflight_disk_budget(
            args.root, args.operation, args.output_path,
            profile_name=args.profile, estimate_bytes=args.estimate_bytes,
        )
        print(format_preflight_report(report),
              file=sys.stderr if report["status"] == "unsafe" else sys.stdout, flush=True)
        if args.scan_root is not None:
            budget = load_disk_policy(args.root.resolve())
            limits = artifact_limits_for_operation(budget, args.operation)
            scan = scan_generated_artifact_roots(
                args.scan_root,
                max_waveform_bytes=limits["maximum_waveform_file_bytes"],
                max_test_output_bytes=limits["maximum_test_output_file_bytes"],
                max_tree_bytes=budget["operations"][args.operation].get("maximum_output_tree_bytes"),
            )
            print("[disk-budget] artifact scan: " + json.dumps(scan, sort_keys=True), flush=True)
            if not scan["passed"]:
                for issue in scan.get("oversized", []):
                    print(
                        f"[disk-budget] oversized {issue['kind']} output: {issue['path']} "
                        f"{issue['bytes']} bytes exceeds {issue['limit_bytes']} bytes",
                        file=sys.stderr,
                    )
                for error in scan.get("errors", []):
                    print(f"[disk-budget] {error}", file=sys.stderr)
                return 2
        return 2 if report["status"] == "unsafe" else 0
    except (DiskBudgetError, OSError, KeyError, ValueError) as error:
        print(f"[disk-budget] unsafe: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
