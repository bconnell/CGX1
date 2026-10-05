#!/usr/bin/env python3
"""Reject unclassified RTL compiler warnings from captured bounded runs."""
from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

DIAGNOSTIC_RE = re.compile(r"\b(?:warning|sorry)\b", re.IGNORECASE)


def validate_allowlist(document: Any) -> list[str]:
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        return ["warning allowlist must be a schema_version 1 object"]
    rules = document.get("rules")
    if not isinstance(rules, list):
        return ["warning allowlist rules must be an array"]
    errors: list[str] = []
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict) or not isinstance(rule.get("pattern"), str) or not rule["pattern"]:
            errors.append(f"rules[{index}] requires a nonempty regex pattern")
            continue
        if not isinstance(rule.get("reason"), str) or not rule["reason"].strip():
            errors.append(f"rules[{index}] requires an explicit classification reason")
            continue
        try:
            re.compile(rule["pattern"])
        except re.error as error:
            errors.append(f"rules[{index}] has an invalid regex: {error}")
    return errors


def classify_warnings(log_text: str, document: Any) -> list[str]:
    errors = validate_allowlist(document)
    if errors:
        return errors
    rules = document["rules"]
    for line_number, line in enumerate(log_text.splitlines(), 1):
        if not DIAGNOSTIC_RE.search(line):
            continue
        if not any(re.search(rule["pattern"], line) for rule in rules):
            errors.append(f"unclassified RTL compiler diagnostic at line {line_number}: {line.strip()}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--allowlist", type=Path, default=Path(__file__).resolve().parents[1] / "design/cgx1_rtl_warning_allowlist.json")
    args = parser.parse_args()
    try:
        document = json.loads(args.allowlist.read_text(encoding="utf-8"))
        errors = classify_warnings(args.log.read_text(encoding="utf-8", errors="replace"), document)
    except (OSError, json.JSONDecodeError) as error:
        print(f"RTL warning validation error: {error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("RTL compiler warning and tool-limitation classification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
