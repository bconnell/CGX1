#!/usr/bin/env python3
"""Reject runtime assert use in C/C++ translation units used by CTest."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument
from typing import Iterable

SOURCE_SUFFIXES = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx"}
PRODUCTION_ALLOWLIST = Path("scripts/test_source_assertions_allowlist.json")
STATE_CHANGING_TEST_CALLS = frozenset({
    "activate", "admit", "advanceacceptedinstruction", "applycontrolevent",
    "arriveatbarrier", "beginwaveexecution", "collectcompletions", "completelaunch",
    "completewaveexecution", "enqueueworkgroup", "faultwave", "faultworkgroup",
    "killworkgroup", "processonecommand", "registerqueuecontext", "release",
    "reserve", "restorevgpr", "restorewrite", "retireonewave", "scheduleonecycle",
    "selectissuablewave", "servicesharedlocalmemorycycle", "setqueuefaulted",
    "submitbytes", "submitsharedlocalmemoryrequest", "takesharedlocalmemoryresponse",
    "terminatewave", "unregisterqueuecontext",
    "testfaultedcontextanddeterministicrandomizedprogress",
    "testpermanentresourcefailureisreportedandremoved", "testqueueidentityandbounds",
    "testresetreportspendingandresidentdispatchcancellation",
    "testtemporarypressuredoesnotloseorpinothercontexts",
    "testtileeligibilityandquiescentcompletion", "testweightedshareandaging",
})
TEST_CHECK_MACRO = re.compile(r"\b(?:CGX1_TEST_CHECK|CHECK)\s*\(")
C_CALL = re.compile(
    r"(?:(?:\b[A-Za-z_][A-Za-z_0-9]*\s*(?:::|->|\.)\s*)*)"
    r"([A-Za-z_][A-Za-z_0-9]*)\s*\("
)
IGNORED_CMAKE_ARGUMENTS = {
    "WIN32", "MACOSX_BUNDLE", "EXCLUDE_FROM_ALL", "IMPORTED", "ALIAS",
    "OBJECT", "STATIC", "SHARED", "MODULE", "UNKNOWN", "INTERFACE",
}


@dataclass(frozen=True)
class CMakeCommand:
    name: str
    arguments: tuple[str, ...]
    line: int


def _skip_cmake_comment(source: str, index: int) -> int:
    end = source.find("\n", index)
    return len(source) if end < 0 else end + 1


def parse_cmake_commands(source: str) -> list[CMakeCommand]:
    """Read CMake command calls while respecting comments, quotes, and nesting."""
    commands: list[CMakeCommand] = []
    index = 0
    while index < len(source):
        if source[index] == "#":
            index = _skip_cmake_comment(source, index)
            continue
        match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", source[index:])
        if match is None:
            index += 1
            continue
        name = match.group(0)
        cursor = index + len(name)
        while cursor < len(source) and source[cursor].isspace():
            cursor += 1
        if cursor >= len(source) or source[cursor] != "(":
            index += len(name)
            continue

        start_line = source.count("\n", 0, index) + 1
        cursor += 1
        content_start = cursor
        depth = 1
        quote = False
        escaped = False
        while cursor < len(source) and depth:
            char = source[cursor]
            if quote:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    quote = False
            elif char == '"':
                quote = True
            elif char == "#":
                cursor = _skip_cmake_comment(source, cursor)
                continue
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            cursor += 1
        if depth:
            raise ValueError(f"unterminated CMake command {name} at line {start_line}")
        content = source[content_start : cursor - 1]
        commands.append(CMakeCommand(name.lower(), tuple(_split_cmake_arguments(content)), start_line))
        index = cursor
    return commands


def _split_cmake_arguments(content: str) -> list[str]:
    arguments: list[str] = []
    current: list[str] = []
    quote = False
    escaped = False
    index = 0
    while index < len(content):
        char = content[index]
        if quote:
            if escaped:
                current.append(char)
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = False
            else:
                current.append(char)
        elif char == '"':
            quote = True
        elif char == "#":
            index = _skip_cmake_comment(content, index) - 1
        elif char.isspace() or char == ";":
            if current:
                arguments.append("".join(current))
                current.clear()
        else:
            current.append(char)
        index += 1
    if quote:
        raise ValueError("unterminated quoted CMake argument")
    if current:
        arguments.append("".join(current))
    return arguments


def _cmake_path(token: str, cmake_dir: Path, root: Path) -> Path | None:
    token = token.replace("${CMAKE_CURRENT_SOURCE_DIR}", str(cmake_dir))
    token = token.replace("${PROJECT_SOURCE_DIR}", str(root))
    if "${" in token or "$<" in token or token.startswith("-"):
        return None
    path = Path(token)
    if not path.is_absolute():
        path = cmake_dir / path
    return path.resolve()


def discover_test_sources(root: Path) -> tuple[dict[str, set[Path]], list[str]]:
    targets: dict[str, set[Path]] = {}
    tests: list[tuple[Path, CMakeCommand]] = []
    for cmake_file in sorted(root.rglob("CMakeLists.txt")):
        relative_parts = cmake_file.relative_to(root).parts
        if any(part in {".git", "build", "out", "third_party", "vendor"} for part in relative_parts[:-1]):
            continue
        commands = parse_cmake_commands(cmake_file.read_text(encoding="utf-8"))
        cmake_dir = cmake_file.parent
        for command in commands:
            if command.name == "add_executable" and command.arguments:
                target = command.arguments[0]
                sources: set[Path] = set()
                for argument in command.arguments[1:]:
                    if argument.upper() in IGNORED_CMAKE_ARGUMENTS:
                        continue
                    path = _cmake_path(argument, cmake_dir, root)
                    if path is not None and path.suffix.lower() in SOURCE_SUFFIXES and path.exists():
                        sources.add(path)
                targets[target] = sources
            elif command.name == "add_test":
                tests.append((cmake_dir, command))

    selected: dict[str, set[Path]] = {}
    diagnostics: list[str] = []
    for cmake_dir, command in tests:
        args = list(command.arguments)
        try:
            command_index = next(i for i, arg in enumerate(args) if arg.upper() == "COMMAND")
        except StopIteration:
            if len(args) < 2:  # CONFIGURATIONS and generated tests are not C/C++ targets.
                continue
            executable = args[1]
        else:
            if command_index + 1 >= len(args):
                diagnostics.append(f"CMakeLists.txt:{command.line}: add_test has no COMMAND")
                continue
            executable = args[command_index + 1]
            target_match = re.fullmatch(r"\$<TARGET_FILE:([^>]+)>", executable, re.IGNORECASE)
            if target_match:
                executable = target_match.group(1)
        if executable in targets:
            selected[executable] = targets[executable]
        elif executable.startswith("$<TARGET_FILE:"):
            diagnostics.append(f"CMakeLists.txt:{command.line}: cannot resolve test executable {executable}")
    if not selected:
        diagnostics.append("no CTest executable sources could be resolved for the runtime assertion scan")
    return selected, diagnostics


def _mask_comments_and_literals(source: str) -> str:
    """Replace comments and literals with spaces, preserving source offsets/newlines."""
    chars = list(source)
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            end = source.find("\n", index)
            end = len(source) if end < 0 else end
            for pos in range(index, end):
                chars[pos] = " "
            index = end
        elif source.startswith("/*", index):
            end = source.find("*/", index + 2)
            end = len(source) if end < 0 else end + 2
            for pos in range(index, end):
                if source[pos] != "\n":
                    chars[pos] = " "
            index = end
        else:
            raw_start = re.match(r'(?:u8|u|U|L)?R"([^ ()\\\t\r\n]{0,16})\(', source[index:])
            if raw_start:
                delimiter = raw_start.group(1)
                end_token = ")" + delimiter + '"'
                end = source.find(end_token, index + raw_start.end())
                end = len(source) if end < 0 else end + len(end_token)
                for pos in range(index, end):
                    if source[pos] != "\n":
                        chars[pos] = " "
                index = end
            elif source[index] in {'"', "'"}:
                quote = source[index]
                start = index
                index += 1
                escaped = False
                while index < len(source):
                    char = source[index]
                    if escaped:
                        escaped = False
                    elif char == "\\":
                        escaped = True
                    elif char == quote:
                        index += 1
                        break
                    index += 1
                for pos in range(start, index):
                    if source[pos] != "\n":
                        chars[pos] = " "
            else:
                index += 1
    return "".join(chars)


def runtime_assert_locations(source: str) -> list[tuple[int, int]]:
    masked = _mask_comments_and_literals(source)
    locations: list[tuple[int, int]] = []
    for match in re.finditer(r"\bassert\b", masked):
        if match.start() > 0 and (masked[match.start() - 1].isalnum() or masked[match.start() - 1] == "_"):
            continue
        cursor = match.end()
        while cursor < len(masked) and masked[cursor].isspace():
            cursor += 1
        if cursor < len(masked) and masked[cursor] == "(":
            line = masked.count("\n", 0, match.start()) + 1
            column = match.start() - masked.rfind("\n", 0, match.start())
            locations.append((line, column))
    return locations


def state_changing_test_call_locations(source: str) -> list[tuple[int, int, str]]:
    """Find repository-owned mutating operations evaluated inside test checks."""
    masked = _mask_comments_and_literals(source)
    locations: list[tuple[int, int, str]] = []
    for check in TEST_CHECK_MACRO.finditer(masked):
        opening = check.end() - 1
        cursor = opening + 1
        depth = 1
        while cursor < len(masked) and depth:
            if masked[cursor] == "(":
                depth += 1
            elif masked[cursor] == ")":
                depth -= 1
            cursor += 1
        if depth:
            continue
        expression = masked[opening + 1 : cursor - 1]
        for call in C_CALL.finditer(expression):
            name = call.group(1)
            if name.lower() not in STATE_CHANGING_TEST_CALLS:
                continue
            offset = opening + 1 + call.start(1)
            line = masked.count("\n", 0, offset) + 1
            column = offset - masked.rfind("\n", 0, offset)
            locations.append((line, column, name))
    return locations


def _load_allowlist(root: Path) -> dict[str, str]:
    path = root / PRODUCTION_ALLOWLIST
    if not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or not isinstance(payload.get("files"), list):
        raise ValueError(f"invalid production assertion allowlist: {path}")
    result: dict[str, str] = {}
    for entry in payload["files"]:
        rel = entry.get("path")
        reason = entry.get("reason")
        if not isinstance(rel, str) or not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"allowlist entries require path and reason: {path}")
        result[rel.replace("\\", "/")] = reason
    return result


def check_root(root: Path) -> list[str]:
    root = root.resolve()
    test_targets, diagnostics = discover_test_sources(root)
    allowlist = _load_allowlist(root)
    visited: set[Path] = set()
    for target, sources in sorted(test_targets.items()):
        if not sources:
            diagnostics.append(f"CTest executable {target} has no resolvable C/C++ sources")
            continue
        for source_path in sorted(sources):
            if source_path in visited:
                continue
            visited.add(source_path)
            relative = source_path.relative_to(root).as_posix()
            if relative in allowlist:
                continue
            content = source_path.read_text(encoding="utf-8")
            for line, column in runtime_assert_locations(content):
                diagnostics.append(
                    f"{relative}:{line}:{column}: runtime assert(...) in CTest source; use CGX1_TEST_CHECK(...)"
                )
            for line, column, name in state_changing_test_call_locations(content):
                diagnostics.append(
                    f"{relative}:{line}:{column}: state-changing operation {name}(...) inside a test check; "
                    "execute it before the check and check the captured result"
                )
    return diagnostics


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    args = parser.parse_args(argv)
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
        diagnostics = check_root(root)
    except PathTranslationError as error:
        parser.error(str(error))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"release test check gate error: {error}", file=sys.stderr)
        return 2
    if diagnostics:
        for diagnostic in diagnostics:
            print(diagnostic, file=sys.stderr)
        return 1
    targets, _ = discover_test_sources(root)
    source_count = len({path for paths in targets.values() for path in paths})
    print(f"Release test check gate passed: {len(targets)} CTest executables, {source_count} C/C++ sources scanned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
