#!/usr/bin/env python3
"""Require deterministic seeds and failure context for randomized test sources."""
from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument


def _mask_cpp_comments_and_literals(source: str) -> str:
    pattern = re.compile(r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/)', re.DOTALL)
    return pattern.sub(lambda match: "\n" * match.group(0).count("\n") if match.group(0).startswith(("//", "/*")) else " " * len(match.group(0)), source)


def _mask_sv_comments_and_strings(source: str) -> str:
    pattern = re.compile(r'("(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/)', re.DOTALL)
    return pattern.sub(lambda match: "\n" * match.group(0).count("\n") if match.group(0).startswith(("//", "/*")) else " " * len(match.group(0)), source)


def validate_cpp_random_source(source: str, label: str = "<source>") -> list[str]:
    masked = _mask_cpp_comments_and_literals(source)
    if not re.search(r"std::mt19937(?:_64)?\b", masked):
        return []
    errors: list[str] = []
    if re.search(r"std::random_device\b", masked):
        errors.append(f"{label}: nondeterministic random_device is forbidden in randomized tests")
    if not re.search(r"\b(?:constexpr|const)\s+(?:std::)?uint(?:8|16|32|64)_t\s+seed\s*=", masked):
        errors.append(f"{label}: randomized C++ source must declare an explicit constant seed")
    if "SetRandomTestFailureContext" not in masked or "WriteRandomTestFailureContext" not in masked:
        errors.append(f"{label}: randomized C++ checks must set and print seed/iteration/state context")
    return errors


def validate_sv_random_source(source: str, label: str = "<source>") -> list[str]:
    masked = _mask_sv_comments_and_strings(source)
    errors: list[str] = []
    if re.search(r"\$(?:u?random)(?:_range)?\b", masked):
        errors.append(f"{label}: simulator-global $random/$urandom is not an explicit replayable seed")
    if re.search(r"\brandomized_state\b", masked):
        if not re.search(r"RANDOM_SEED\s*=\s*32'h[0-9a-fA-F_]+", source):
            errors.append(f"{label}: RTL PRNG state must start from an explicit fixed RANDOM_SEED")
        if not re.search(r"seed=%0\w+.*iteration=%0\w+.*state=%0\w+", source):
            errors.append(f"{label}: randomized RTL failure diagnostics must report seed, iteration, and state")
    return errors


def validate_repository(root: Path) -> list[str]:
    errors: list[str] = []
    for path in sorted((root / "source").rglob("*.cpp")):
        source = path.read_text(encoding="utf-8", errors="replace")
        errors.extend(validate_cpp_random_source(source, path.relative_to(root).as_posix()))
    for path in sorted((root / "source/rtl/tests").glob("*.sv")):
        source = path.read_text(encoding="utf-8", errors="replace")
        errors.extend(validate_sv_random_source(source, path.relative_to(root).as_posix()))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    args = parser.parse_args()
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    errors = validate_repository(root)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("Randomized test seed/context gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
