from __future__ import annotations

import unittest
from pathlib import Path
import tempfile
from unittest.mock import patch

from scripts import run_clean_cmake_tests


class CleanCMakeInventoryTests(unittest.TestCase):
    def test_human_inventory_fallback_recovers_registered_tests(self) -> None:
        inventory = getattr(run_clean_cmake_tests, "ctest_inventory_count", None)
        self.assertIsNotNone(inventory, "clean runner must provide a tested CTest inventory parser")
        count, source = inventory(
            '{"kind":"ctestInfo","tests":[]}',
            "Test project C:/build\n  Test #1: first_check\n  Test #2: second_check\n",
        )
        self.assertEqual((2, "human"), (count, source))

    def test_empty_json_and_human_inventories_stay_empty(self) -> None:
        inventory = getattr(run_clean_cmake_tests, "ctest_inventory_count", None)
        self.assertIsNotNone(inventory, "clean runner must provide a tested CTest inventory parser")
        self.assertEqual(
            (0, "empty"),
            inventory('{"kind":"ctestInfo","tests":[]}', "Test project C:/build\nNo tests were found!!!\n"),
        )

    def test_json_inventory_remains_preferred_when_present(self) -> None:
        inventory = getattr(run_clean_cmake_tests, "ctest_inventory_count", None)
        self.assertIsNotNone(inventory, "clean runner must provide a tested CTest inventory parser")
        self.assertEqual(
            (2, "json"),
            inventory('{"kind":"ctestInfo","tests":[{},{}]}', "No tests were found!!!\n"),
        )

    def test_old_temporary_build_is_reported_before_new_candidate_is_created(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-stale-clean-build-") as temporary:
            root = Path(temporary)
            stale = root / "cgx1-clean-cmake-interrupted"
            stale.mkdir()

            with self.assertRaisesRegex(RuntimeError, "determine whether it is active"):
                run_clean_cmake_tests.require_no_stale_clean_builds(root)

            self.assertTrue(stale.is_dir(), "the stale-output guard must not delete unknown build data")

    def test_clean_build_root_must_remain_under_the_build_directory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-build-root-") as temporary:
            root = Path(temporary)
            build_root = root / "other-output"
            with self.assertRaisesRegex(run_clean_cmake_tests.DiskBudgetError, "build directory"):
                run_clean_cmake_tests.require_build_root_inside_repo(root, build_root)

    def test_clean_build_root_rejects_a_redirected_path_inside_the_repository(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-build-link-") as temporary:
            root = Path(temporary)
            build_directory = root / "build"
            build_directory.mkdir()
            target = root / "docs"
            target.mkdir()
            build_root = build_directory / "clean-validation"
            with patch(
                "scripts.run_clean_cmake_tests.is_redirected_path",
                side_effect=lambda path, *_args: Path(path) == build_root,
            ):
                with self.assertRaisesRegex(run_clean_cmake_tests.DiskBudgetError, "redirected"):
                    run_clean_cmake_tests.require_build_root_inside_repo(root, build_root)

    def test_output_size_measurement_fails_closed_when_a_file_cannot_be_read(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-clean-size-read-") as temporary:
            root = Path(temporary)
            (root / "unreadable.bin").write_bytes(b"output")
            with patch.object(Path, "lstat", side_effect=PermissionError("denied")):
                with self.assertRaisesRegex(run_clean_cmake_tests.DiskBudgetError, "cannot measure"):
                    run_clean_cmake_tests.tree_bytes(root)

    def test_cleanup_guard_refuses_a_symlink_inside_its_owned_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cgx1-cleanup-redirection-") as temporary:
            root = Path(temporary)
            parent = root / "parent"
            owned = parent / "cgx1-clean-cmake-test"
            outside = root / "outside"
            parent.mkdir()
            owned.mkdir()
            outside.mkdir()
            link = owned / "redirect"
            try:
                link.symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation is unavailable: {error}")

            with self.assertRaisesRegex(RuntimeError, "redirected path"):
                run_clean_cmake_tests.require_safe_owned_tree(owned, parent, "cgx1-clean-cmake-")

            self.assertTrue(outside.is_dir(), "cleanup preflight must not traverse the redirection")


if __name__ == "__main__":
    unittest.main()
