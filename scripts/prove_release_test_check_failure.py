#!/usr/bin/env python3
"""Build and run the opt-in false-check fixture in Release and require CTest failure."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(command), flush=True)
    return subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    parser.add_argument("--keep-build", action="store_true", help="retain the temporary Release build directory")
    args = parser.parse_args()
    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    temporary = Path(tempfile.mkdtemp(prefix="cgx1-release-check-probe-"))
    build = temporary / "build"
    try:
        configure = run(
            ["cmake", "-S", str(root), "-B", str(build), "-DCMAKE_BUILD_TYPE=Release", "-DCGX1_ENABLE_TEST_FAILURE_PROBE=ON"],
            root,
        )
        print(configure.stdout, end="")
        if configure.returncode:
            return configure.returncode
        compile_result = run(
            ["cmake", "--build", str(build), "--config", "Release", "--target", "cgx1_test_check_failure_probe"], root
        )
        print(compile_result.stdout, end="")
        if compile_result.returncode:
            return compile_result.returncode
        test = run(
            ["ctest", "--test-dir", str(build), "-C", "Release", "--output-on-failure", "-R", "^cgx1_test_check_failure_probe$"], root
        )
        print(test.stdout, end="")
        expected = "CGX1_TEST_CHECK failed: false && \"intentional Release/NDEBUG failure probe\""
        if test.returncode == 0 or expected not in test.stdout:
            print("Release/NDEBUG failure probe did not produce the expected failing CTest diagnostic.", file=sys.stderr)
            return 1
        print("Confirmed: Release/NDEBUG CTest observes the intentional always-on check failure.")
        return 0
    finally:
        if args.keep_build:
            print(f"Retained probe build: {build}")
        else:
            shutil.rmtree(temporary, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
