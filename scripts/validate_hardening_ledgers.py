#!/usr/bin/env python3
"""Validate permanent regressions and high-risk RTL lifecycle fault pairs."""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument
from typing import Any


def _check_ref(reference: Any, label: str, root: Path, errors: list[str]) -> None:
    if not isinstance(reference, dict):
        errors.append(f"{label}: reference must be an object")
        return
    relative, needle = reference.get("path"), reference.get("needle")
    if not isinstance(relative, str) or not isinstance(needle, str) or not needle:
        errors.append(f"{label}: path and nonempty needle are required")
        return
    target = (root / relative).resolve()
    if root.resolve() not in target.parents:
        errors.append(f"{label}: path escapes repository: {relative}")
        return
    if not target.is_file():
        errors.append(f"{label}: referenced file is missing: {relative}")
        return
    if needle not in target.read_text(encoding="utf-8", errors="replace"):
        errors.append(f"{label}: regression/gate location was not found in {relative}: {needle}")


def validate_escaped_defects(document: Any, root: Path) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        return ["escaped-defect ledger must be a schema_version 1 object"]
    records = document.get("records")
    if not isinstance(records, list) or not records:
        return ["escaped-defect ledger requires records"]
    ids: set[str] = set()
    for index, item in enumerate(records):
        label = f"records[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{label}: record must be an object")
            continue
        ident = item.get("id")
        if not isinstance(ident, str) or not ident or ident in ids:
            errors.append(f"{label}: id is missing or duplicated")
        else:
            ids.add(ident)
        for field in ("origin", "failure_mode"):
            if not isinstance(item.get(field), str) or not item[field].strip():
                errors.append(f"{label}: {field} is required")
        for field in ("regressions", "gates"):
            refs = item.get(field)
            if not isinstance(refs, list) or not refs:
                errors.append(f"{label}: at least one permanent {field} reference is required")
                continue
            for ref_index, reference in enumerate(refs):
                _check_ref(reference, f"{label}.{field}[{ref_index}]", root, errors)
    return errors


def validate_fault_matrix(document: Any, inventory: Any, root: Path) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        return ["fault-injection matrix must be a schema_version 1 object"]
    if document.get("coverage_level") != "selected high-risk lifecycle/state pairs; not an exhaustive Cartesian product":
        errors.append("fault matrix must state its selected-pair coverage boundary")
    invocation_modes = {}
    if isinstance(inventory, dict):
        invocation_modes = {entry.get("top"): entry.get("mode") for entry in inventory.get("invocations", []) if isinstance(entry, dict)}
    cases = document.get("cases")
    required = document.get("required_pairs")
    if not isinstance(cases, list) or not cases:
        errors.append("fault-injection matrix requires cases")
        cases = []
    if not isinstance(required, list) or not required:
        errors.append("fault-injection matrix requires explicit required_pairs")
        required = []
    ids: set[str] = set()
    covered: set[tuple[str, str]] = set()
    for index, case in enumerate(cases):
        label = f"cases[{index}]"
        if not isinstance(case, dict):
            errors.append(f"{label}: case must be an object")
            continue
        ident = case.get("id")
        if not isinstance(ident, str) or not ident or ident in ids:
            errors.append(f"{label}: id is missing or duplicated")
        else:
            ids.add(ident)
        event, overlap = case.get("event"), case.get("overlap_state")
        if not isinstance(event, str) or not event or not isinstance(overlap, str) or not overlap:
            errors.append(f"{label}: event and overlap_state are required")
        else:
            covered.add((event, overlap))
        if not isinstance(case.get("ownership_invariant"), str) or not case["ownership_invariant"].strip():
            errors.append(f"{label}: ownership_invariant is required")
        test_id = case.get("test_id")
        prefix, _, top = test_id.partition(":") if isinstance(test_id, str) else ("", "", "")
        if prefix != "rtl" or invocation_modes.get(top) not in {"simulated", "simulation_expected_failure"}:
            errors.append(f"{label}: test_id must name an actually simulated RTL top")
        _check_ref(case.get("test_ref"), f"{label}.test_ref", root, errors)
    for index, pair in enumerate(required):
        if not isinstance(pair, dict):
            errors.append(f"required_pairs[{index}]: entry must be an object")
            continue
        event, overlap = pair.get("event"), pair.get("overlap_state")
        if (event, overlap) not in covered:
            errors.append(f"required lifecycle pair is not tied to an executable test: {event} x {overlap}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    args = parser.parse_args()
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    try:
        escaped = json.loads((root / "design/cgx1_escaped_defects.json").read_text(encoding="utf-8"))
        fault = json.loads((root / "design/cgx1_fault_injection_matrix.json").read_text(encoding="utf-8"))
        inventory = json.loads((root / "design/cgx1_rtl_validation_inventory.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"hardening ledger validation error: {error}", file=sys.stderr)
        return 2
    errors = validate_escaped_defects(escaped, root) + validate_fault_matrix(fault, inventory, root)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"Hardening ledgers passed: {len(escaped['records'])} escaped-defect classes and {len(fault['cases'])} high-risk lifecycle pairs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
