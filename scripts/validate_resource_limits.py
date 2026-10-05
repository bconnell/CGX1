#!/usr/bin/env python3
"""Validate explicit classification and executable references for fixed limits."""

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

CLASSIFICATIONS = {
    "frozen_architecture",
    "parameterized_implementation",
    "physical_resource_candidate",
    "representation_bound",
    "safety_overflow_bound",
    "malformed_input_guard",
    "test_only_configuration",
}
BOUNDARY_KINDS = {"exact", "over", "below", "parameter_smoke"}


def validate_document(document: Any, root: Path) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        return ["resource limit registry must be a schema_version 1 object"]
    limits = document.get("limits")
    if not isinstance(limits, list) or not limits:
        return ["resource limit registry must contain a nonempty limits array"]
    seen: set[str] = set()
    root = root.resolve()

    def check_reference(reference: Any, label: str, require_test: bool = False) -> tuple[str | None, str | None]:
        if not isinstance(reference, dict):
            errors.append(f"{label}: reference must be an object")
            return None, None
        relative = reference.get("path")
        needle = reference.get("needle")
        if not isinstance(relative, str) or not isinstance(needle, str) or not needle:
            errors.append(f"{label}: reference requires path and nonempty needle")
            return None, None
        candidate = (root / relative).resolve()
        if root not in candidate.parents:
            errors.append(f"{label}: path escapes repository: {relative}")
            return relative, needle
        if not candidate.is_file():
            errors.append(f"{label}: referenced file is missing: {relative}")
            return relative, needle
        if needle not in candidate.read_text(encoding="utf-8"):
            errors.append(f"{label}: reference needle is missing from {relative}: {needle}")
        if require_test and not relative.startswith(("source/", "scripts/tests/")):
            errors.append(f"{label}: boundary reference must identify executable test source: {relative}")
        return relative, needle

    for index, item in enumerate(limits):
        label = f"limits[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{label}: entry must be an object")
            continue
        identifier = item.get("id")
        if not isinstance(identifier, str) or not identifier:
            errors.append(f"{label}: id is required")
        elif identifier in seen:
            errors.append(f"{label}: duplicate id {identifier}")
        else:
            seen.add(identifier)
        classification = item.get("classification")
        if classification not in CLASSIFICATIONS:
            errors.append(f"{label}: missing or invalid classification {classification!r}")
        if not isinstance(item.get("value"), str) or not item["value"].strip():
            errors.append(f"{label}: value description is required")
        if not isinstance(item.get("rationale"), str) or not item["rationale"].strip():
            errors.append(f"{label}: rationale is required")
        check_reference(item.get("source"), f"{label}.source")
        references = item.get("test_refs")
        if not isinstance(references, list) or not references:
            errors.append(f"{label}: at least one executable test reference is required")
            references = []
        kinds: set[str] = set()
        for ref_index, reference in enumerate(references):
            ref_label = f"{label}.test_refs[{ref_index}]"
            if isinstance(reference, dict):
                kind = reference.get("kind")
                if kind not in BOUNDARY_KINDS:
                    errors.append(f"{ref_label}: invalid boundary kind {kind!r}")
                else:
                    kinds.add(kind)
            check_reference(reference, ref_label, require_test=True)
        if item.get("requires_over_boundary") is True:
            if "exact" not in kinds:
                errors.append(f"{label}: consequential limit needs an exact-boundary test reference")
            if not ({"over", "below"} & kinds):
                errors.append(f"{label}: consequential limit needs a just-over/just-below test reference")
        if classification == "test_only_configuration" and "architecture_status" in item:
            errors.append(f"{label}: test-only configuration cannot set public architecture status")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    args = parser.parse_args()
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    path = root / "design/cgx1_resource_limits.json"
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
        errors = validate_document(document, root)
    except (OSError, json.JSONDecodeError) as error:
        print(f"resource limit validation error: {error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"Resource limit registry passed: {len(document['limits'])} classified limits with source and test references.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
