#!/usr/bin/env python3
"""Classify warnings from bounded Verilator and Yosys logs."""
from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

WARNING_LINE = re.compile(r"(?:%Warning-[A-Za-z0-9_]+:|^\s*[Ww]arning:)")


def validate_allowlist(document: Any) -> list[str]:
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        return ["RTL tool warning allowlist must be a schema_version 1 object"]
    rules = document.get("rules")
    if not isinstance(rules, list):
        return ["RTL tool warning rules must be an array"]
    errors: list[str] = []
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict) or rule.get("tool") not in {"verilator", "yosys"}:
            errors.append(f"rules[{index}] requires tool=verilator or tool=yosys")
            continue
        if not isinstance(rule.get("pattern"), str) or not rule["pattern"]:
            errors.append(f"rules[{index}] requires a nonempty pattern")
            continue
        if not isinstance(rule.get("reason"), str) or not rule["reason"].strip():
            errors.append(f"rules[{index}] requires an explicit classification reason")
            continue
        try:
            re.compile(rule["pattern"])
        except re.error as error:
            errors.append(f"rules[{index}] has an invalid regex: {error}")
    return errors


def classify_logs(logs: list[tuple[str, str]], document: Any) -> list[str]:
    errors = validate_allowlist(document)
    if errors:
        return errors
    for tool, text in logs:
        for line_number, line in enumerate(text.splitlines(), 1):
            if not WARNING_LINE.search(line):
                continue
            if not any(rule["tool"] == tool and re.search(rule["pattern"], line)
                       for rule in document["rules"]):
                errors.append(f"unclassified {tool} warning at line {line_number}: {line.strip()}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verilator-log", type=Path, action="append", default=[])
    parser.add_argument("--yosys-log", type=Path, action="append", default=[])
    parser.add_argument("--allowlist", type=Path, default=Path(__file__).resolve().parents[1] / "design/cgx1_rtl_tool_warning_allowlist.json")
    args = parser.parse_args()
    try:
        document = json.loads(args.allowlist.read_text(encoding="utf-8"))
        logs = [("verilator", path.read_text(encoding="utf-8", errors="replace")) for path in args.verilator_log]
        logs.extend(("yosys", path.read_text(encoding="utf-8", errors="replace")) for path in args.yosys_log)
        errors = classify_logs(logs, document)
    except (OSError, json.JSONDecodeError) as error:
        print(f"RTL tool warning validation error: {error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("Verilator/Yosys warning classification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
