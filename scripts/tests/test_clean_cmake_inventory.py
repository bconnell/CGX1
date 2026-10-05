from __future__ import annotations

import unittest

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


if __name__ == "__main__":
    unittest.main()
