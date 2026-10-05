#!/usr/bin/env python3
"""Validate local Markdown paths and generated heading anchors."""

from __future__ import annotations

import argparse
import html
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable
from urllib.parse import unquote, urlsplit

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument


LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)(?:\s+[^)]*)?\)")
ATX_HEADING_RE = re.compile(r"^ {0,3}(#{1,6})(?:[ \t]+|$)(.*?)\s*$")
SETEXT_HEADING_RE = re.compile(r"^ {0,3}(=+|-+)\s*$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")


@dataclass(frozen=True)
class LinkIssue:
    path: str
    line: int
    kind: str
    message: str


def validate_markdown_links(
    root: Path, markdown_paths: Iterable[Path] | None = None
) -> list[LinkIssue]:
    root = root.resolve()
    if markdown_paths is None:
        result = subprocess.run(
            ["git", "-c", f"safe.directory={root}", "-C", str(root),
             "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        markdown_paths = [
            Path(raw.decode("utf-8", errors="surrogateescape"))
            for raw in result.stdout.split(b"\0")
            if raw and Path(raw.decode("utf-8", errors="surrogateescape")).suffix.lower() == ".md"
        ]

    issues: list[LinkIssue] = []
    for relative_path in markdown_paths:
        relative_path = Path(relative_path)
        source_path = (root / relative_path).resolve()
        try:
            source_path.relative_to(root)
        except ValueError:
            issues.append(LinkIssue(relative_path.as_posix(), 1, "path_escape", "Markdown source escapes repository root"))
            continue
        if not source_path.is_file():
            issues.append(LinkIssue(relative_path.as_posix(), 1, "missing_source", "Markdown source file does not exist"))
            continue
        try:
            text = source_path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as error:
            issues.append(LinkIssue(relative_path.as_posix(), 1, "unreadable_source", str(error)))
            continue

        visible_text = _mask_fenced_code(text)
        source_slugs = _heading_slugs(visible_text)
        for match in LINK_RE.finditer(visible_text):
            destination = match.group(1)
            if destination.startswith("<") and destination.endswith(">"):
                destination = destination[1:-1]
            parsed = urlsplit(destination)
            if parsed.scheme or parsed.netloc or destination.startswith("//"):
                continue

            target_path = unquote(parsed.path)
            if not target_path:
                if not parsed.fragment:
                    continue
                resolved_target = source_path
                target_relative = relative_path.as_posix()
                target_slugs = source_slugs
            else:
                path_parts = [
                    part for part in PurePosixPath(target_path.replace("\\", "/")).parts
                    if part != "/"
                ]
                if target_path.startswith(("/", "\\")):
                    candidate = root.joinpath(*path_parts)
                else:
                    candidate = source_path.parent.joinpath(*path_parts)
                resolved_target = candidate.resolve()
                try:
                    target_relative = resolved_target.relative_to(root).as_posix()
                except ValueError:
                    line = text.count("\n", 0, match.start()) + 1
                    issues.append(LinkIssue(relative_path.as_posix(), line, "path_escape", f"local link escapes repository: {destination}"))
                    continue
                if not resolved_target.exists():
                    line = text.count("\n", 0, match.start()) + 1
                    issues.append(LinkIssue(relative_path.as_posix(), line, "missing_file", f"local file does not exist: {destination}"))
                    continue
                if resolved_target.is_dir() and parsed.fragment:
                    index_candidates = [resolved_target / "README.md", resolved_target / "index.md"]
                    index_path = next((path for path in index_candidates if path.is_file()), None)
                    if index_path is not None:
                        resolved_target = index_path
                        target_relative = resolved_target.relative_to(root).as_posix()
                target_slugs = _heading_slugs(resolved_target.read_text(encoding="utf-8-sig")) if resolved_target.is_file() and parsed.fragment else set()

            if parsed.fragment:
                anchor = unquote(parsed.fragment)
                if anchor not in target_slugs:
                    line = text.count("\n", 0, match.start()) + 1
                    issues.append(
                        LinkIssue(
                            relative_path.as_posix(),
                            line,
                            "missing_anchor",
                            f"heading anchor {anchor!r} does not exist in {target_relative}",
                        )
                    )
    return issues


def _mask_fenced_code(text: str) -> str:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    fence_char: str | None = None
    fence_length = 0
    for line in lines:
        match = FENCE_RE.match(line)
        if fence_char is None and match:
            fence_char = match.group(1)[0]
            fence_length = len(match.group(1))
            output.append("".join("\n" if character == "\n" else " " for character in line))
            continue
        if fence_char is not None:
            if match and match.group(1)[0] == fence_char and len(match.group(1)) >= fence_length:
                fence_char = None
                fence_length = 0
            output.append("".join("\n" if character == "\n" else " " for character in line))
            continue
        output.append(line)
    return "".join(output)


def _heading_slugs(markdown: str) -> set[str]:
    lines = markdown.splitlines()
    slugs: set[str] = set()
    base_counts: dict[str, int] = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        atx = ATX_HEADING_RE.match(line)
        heading_text: str | None = None
        if atx:
            heading_text = re.sub(r"[ \t]+#+[ \t]*$", "", atx.group(2)).strip()
        elif line.strip() and index + 1 < len(lines) and SETEXT_HEADING_RE.match(lines[index + 1]):
            heading_text = line.strip()
            index += 1
        if heading_text is not None:
            base = _slug(heading_text)
            if base:
                suffix = base_counts.get(base, 0)
                candidate = base if suffix == 0 else f"{base}-{suffix}"
                while candidate in slugs:
                    suffix += 1
                    candidate = f"{base}-{suffix}"
                base_counts[base] = suffix + 1
                slugs.add(candidate)
        index += 1
    return slugs


def _slug(heading: str) -> str:
    plain = html.unescape(heading)
    plain = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", plain)
    plain = re.sub(r"<[^>]*>", "", plain)
    plain = re.sub(r"[`*_~]", "", plain)
    plain = unicodedata.normalize("NFKC", plain).lower()
    normalized: list[str] = []
    for character in plain:
        if character.isspace():
            normalized.append("-")
        elif character.isalnum() or character == "-":
            normalized.append(character)
    return re.sub(r"-{2,}", "-", "".join(normalized)).strip("-")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    args = parser.parse_args(argv)
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
        issues = validate_markdown_links(root)
    except PathTranslationError as error:
        parser.error(str(error))
    except (OSError, subprocess.SubprocessError) as error:
        print(f"[fail] Markdown link check could not run: {error}", file=sys.stderr)
        return 1
    if issues:
        for issue in issues:
            print(f"[fail] {issue.path}:{issue.line}: {issue.message}", file=sys.stderr)
        return 1
    print("[pass] Local Markdown paths and heading anchors passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
