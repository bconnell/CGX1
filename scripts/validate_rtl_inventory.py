#!/usr/bin/env python3
"""Inventory every Icarus compile/run and first-party RTL source."""
from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from pathlib import Path

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument
from typing import Any

DEFAULT_COMPILE_TIMEOUT = 180
COMPLEX_COMPILE_TIMEOUT = 300
COMPILE_ONLY_REASONS = {
    "cgx1_matrix_int8_pooled_resident_engine_tb": (
        "The pooled resident INT8 plus ordinary-vector composition is intentionally compile-only; "
        "the complete mixed composition has not yet been bounded and simulated."
    )
}
IMPORTANT_TOP_MODES = {
    "cgx1_top_tb": "simulated",
    "cgx1_compute_workgroup_execution_frontend_tb": "simulated",
    "cgx1_compute_workgroup_lsu_tb": "simulated",
    "cgx1_matrix_int8_pooled_resident_engine_tb": "compile_only",
}


def _logical_lines(script_text: str) -> list[str]:
    folded = re.sub(r"\\\r?\n", " ", script_text)
    return folded.splitlines()


def _compile_timeout(top: str, source_count: int) -> int:
    if (top == "cgx1_resident_wave_vgpr_file_tb" or top.endswith("integration_tb")
            or top.endswith("execution_frontend_tb") or source_count >= 12):
        return COMPLEX_COMPILE_TIMEOUT
    return DEFAULT_COMPILE_TIMEOUT


def parse_script(script_text: str, root: Path) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    lines = _logical_lines(script_text)
    simulation_by_artifact: dict[str, dict[str, Any]] = {}
    for line in lines:
        stripped = line.strip()
        if not re.match(r"^(?:if\s+)?(?:!\s+)?timeout\b|^timeout\b", stripped):
            continue
        if re.search(r"\bvvp\b", stripped):
            match = re.search(r"\btimeout\s+(\d+)s\s+vvp\s+(\S+)", stripped)
            if not match:
                errors.append(f"unbounded simulation command: {stripped}")
                continue
            artifact = match.group(2)
            simulation_by_artifact[artifact] = {
                "timeout_seconds": int(match.group(1)),
                "expected_failure": bool(re.match(r"^if\s+timeout\b", stripped)),
            }
    # Catch any direct vvp command not seen by the timeout parser, including a command
    # line whose first token is wrapped in an if/unless conditional.
    for line in lines:
        stripped = line.strip()
        if re.match(r"^(?:if\s+)?(?:!\s+)?vvp\b", stripped):
            errors.append(f"unbounded simulation command: {stripped}")

    invocations: list[dict[str, Any]] = []
    seen_artifacts: set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not re.match(r"^(?:if\s+)?(?:!\s+)?iverilog(?:\s|$)", stripped):
            continue
        try:
            tokens = shlex.split(stripped, comments=True, posix=True)
        except ValueError as error:
            errors.append(f"cannot parse Icarus command {stripped!r}: {error}")
            continue
        try:
            compiler_index = tokens.index("iverilog")
        except ValueError:
            continue
        args = tokens[compiler_index + 1:]
        if "-s" not in args:
            # The bounded -V compiler provenance command is not a test top.
            if "-V" not in args or not stripped.startswith("timeout 10s"):
                errors.append(f"unrecognized Icarus invocation is not a test top or bounded version query: {stripped}")
            continue
        try:
            top = args[args.index("-s") + 1]
            artifact = args[args.index("-o") + 1]
        except (ValueError, IndexError):
            errors.append(f"Icarus compile requires -s top and -o artifact: {stripped}")
            continue
        if artifact in seen_artifacts:
            errors.append(f"duplicate Icarus artifact {artifact}")
        seen_artifacts.add(artifact)
        sources = [token for token in args if token.startswith("source/rtl/") and token.endswith(".sv")]
        tb = next((source for source in sources if source.startswith("source/rtl/tests/")), None)
        if tb is None:
            errors.append(f"compile top {top} has no first-party testbench source")
        if not sources:
            errors.append(f"compile top {top} has no RTL source files")
        run = simulation_by_artifact.get(artifact)
        if run is None:
            mode = "compile_only"
            reason = COMPILE_ONLY_REASONS.get(top)
            if reason is None:
                errors.append(f"compiled artifact has no bounded simulation and no approved compile-only reason: {top}")
        else:
            mode = "simulation_expected_failure" if run["expected_failure"] else "simulated"
            reason = None
            if run["timeout_seconds"] <= 0:
                errors.append(f"simulation timeout is not positive for {top}")
        entry: dict[str, Any] = {
            "top": top,
            "artifact": artifact,
            "testbench": tb,
            "mode": mode,
            "compile_timeout_seconds": _compile_timeout(top, len(sources)),
            "simulation_timeout_seconds": run["timeout_seconds"] if run else None,
            "production_sources": [source for source in sources if not source.startswith("source/rtl/tests/")],
        }
        if reason is not None:
            entry["reason"] = reason
        invocations.append(entry)
    if not invocations:
        errors.append("no bounded Icarus test tops were found")
    return invocations, errors


def _module_inventory(root: Path, invocations: list[dict[str, Any]]) -> list[dict[str, Any]]:
    source_to_artifacts: dict[str, list[str]] = {}
    for invocation in invocations:
        for source in invocation["production_sources"]:
            source_to_artifacts.setdefault(source, []).append(invocation["artifact"])
    result: list[dict[str, Any]] = []
    for path in sorted((root / "source/rtl").glob("*.sv")):
        relative = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        names = re.findall(r"\bmodule\s+(\w+)", text)
        for name in names:
            result.append({"module": name, "path": relative,
                           "validated_by_artifacts": sorted(source_to_artifacts.get(relative, []))})
    return result


def build_document(script_text: str, root: Path) -> dict[str, Any]:
    invocations, errors = parse_script(script_text, root)
    if errors:
        raise ValueError("; ".join(errors))
    modes = {entry["top"]: entry["mode"] for entry in invocations}
    return {
        "schema_version": 1,
        "compiler_timeout_policy_seconds": {"default": DEFAULT_COMPILE_TIMEOUT, "complex": COMPLEX_COMPILE_TIMEOUT},
        "warning_policy": "captured bounded compiler output classified by design/cgx1_rtl_warning_allowlist.json",
        "invocations": invocations,
        "modules": _module_inventory(root, invocations),
        "important_composed_tops": [
            {"top": top, "required_mode": mode} for top, mode in IMPORTANT_TOP_MODES.items()
        ],
    }


def validate_document(document: Any, script_text: str, root: Path) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        return ["RTL validation inventory must be a schema_version 1 object"]
    wrapper_match = re.search(r"^iverilog\(\)\s*\{(.*?)^\}", script_text, re.M | re.S)
    wrapper = wrapper_match.group(1) if wrapper_match else ""
    if (not wrapper or "timeout --signal=TERM --kill-after=5s" not in wrapper
            or '"$iverilog_bin" "$@" >"$compile_log" 2>&1' not in wrapper):
        errors.append("compiler timeout/captured-log wrapper is missing or unbounded")
    if not re.search(r"^timeout 10s \"\$iverilog_bin\" -V$", script_text, re.M):
        errors.append("Icarus compiler-version query is not bounded")
    if "scripts/validate_rtl_warnings.py --log build/rtl/compiler-warnings.log" not in script_text:
        errors.append("captured RTL compiler diagnostics are not classified by the warning gate")
    try:
        expected, parse_errors = parse_script(script_text, root)
        errors.extend(parse_errors)
    except (OSError, ValueError) as error:
        errors.append(f"RTL inventory parse failed: {error}")
        return errors
    recorded = document.get("invocations")
    if not isinstance(recorded, list):
        errors.append("RTL inventory invocations must be an array")
        recorded = []
    if recorded != expected:
        expected_by_artifact = {item["artifact"]: item for item in expected}
        recorded_by_artifact = {item.get("artifact"): item for item in recorded if isinstance(item, dict)}
        missing = sorted(set(expected_by_artifact) - set(recorded_by_artifact))
        extra = sorted(set(recorded_by_artifact) - set(expected_by_artifact))
        if missing:
            errors.append(f"RTL inventory is missing compile/run artifact(s): {', '.join(missing)}")
        if extra:
            errors.append(f"RTL inventory lists artifact(s) not built by the script: {', '.join(extra)}")
        for artifact in sorted(set(expected_by_artifact) & set(recorded_by_artifact)):
            if expected_by_artifact[artifact] != recorded_by_artifact[artifact]:
                errors.append(f"RTL mode mismatch or metadata drift for {artifact}")
    for item in recorded:
        if isinstance(item, dict) and item.get("mode") == "compile_only" and not item.get("reason", "").strip():
            errors.append(f"compile-only reason is missing for {item.get('top', 'unknown')}")
    for item in expected:
        if item["mode"] == "compile_only" and not item.get("reason", "").strip():
            errors.append(f"compile-only reason is missing for {item['top']}")
    expected_modules = _module_inventory(root, expected)
    modules = document.get("modules")
    if modules != expected_modules:
        errors.append("module inventory mismatch: every first-party RTL module and exact validation artifact must be listed")
    for module in expected_modules:
        if not module["validated_by_artifacts"]:
            errors.append(f"first-party RTL module is not compiled by any inventory entry: {module['path']}")
    tops = {item.get("top"): item.get("mode") for item in expected}
    for required in document.get("important_composed_tops", []):
        if not isinstance(required, dict):
            errors.append("important composed-top record must be an object")
            continue
        top = required.get("top")
        expected_mode = required.get("required_mode")
        if tops.get(top) != expected_mode:
            errors.append(f"important top {top} requires mode {expected_mode}; actual mode is {tops.get(top)}")
    if document.get("important_composed_tops") != [
        {"top": top, "required_mode": mode} for top, mode in IMPORTANT_TOP_MODES.items()
    ]:
        errors.append("important composed-top obligations were removed or changed")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    parser.add_argument("--write-inventory", action="store_true", help="regenerate the inventory from the current RTL validation script")
    args = parser.parse_args()
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    script_path = root / "scripts/validate_rtl.sh"
    inventory_path = root / "design/cgx1_rtl_validation_inventory.json"
    try:
        script_text = script_path.read_text(encoding="utf-8")
        if args.write_inventory:
            document = build_document(script_text, root)
            inventory_path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8", newline="\n")
            print(f"Wrote RTL inventory: {len(document['invocations'])} compile invocations, {len(document['modules'])} first-party modules")
            return 0
        document = json.loads(inventory_path.read_text(encoding="utf-8"))
        errors = validate_document(document, script_text, root)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"RTL inventory validation error: {error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    simulated = sum(item["mode"] in {"simulated", "simulation_expected_failure"} for item in document["invocations"])
    compile_only = sum(item["mode"] == "compile_only" for item in document["invocations"])
    print(f"RTL inventory passed: {len(document['invocations'])} compile invocations, {simulated} bounded runs, {compile_only} compile-only top, {len(document['modules'])} first-party modules.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
