import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve().parents[1] / "validate_hardening_ledgers.py"
SPEC = importlib.util.spec_from_file_location("validate_hardening_ledgers", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class HardeningLedgerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.escaped = json.loads((ROOT / "design/cgx1_escaped_defects.json").read_text(encoding="utf-8"))
        cls.fault = json.loads((ROOT / "design/cgx1_fault_injection_matrix.json").read_text(encoding="utf-8"))
        cls.inventory = json.loads((ROOT / "design/cgx1_rtl_validation_inventory.json").read_text(encoding="utf-8"))

    def test_repository_ledgers_are_complete_and_executable(self):
        self.assertEqual(MODULE.validate_escaped_defects(self.escaped, ROOT), [])
        self.assertEqual(MODULE.validate_fault_matrix(self.fault, self.inventory, ROOT), [])

    def test_escaped_defect_requires_permanent_regression(self):
        changed = json.loads(json.dumps(self.escaped))
        changed["records"][0]["regressions"] = []
        self.assertTrue(any("permanent regressions" in error for error in MODULE.validate_escaped_defects(changed, ROOT)))

    def test_missing_regression_location_is_rejected(self):
        changed = json.loads(json.dumps(self.escaped))
        changed["records"][0]["regressions"][0]["needle"] = "missing regression needle"
        self.assertTrue(any("location was not found" in error for error in MODULE.validate_escaped_defects(changed, ROOT)))

    def test_required_lifecycle_pair_must_have_executable_test(self):
        changed = json.loads(json.dumps(self.fault))
        changed["cases"] = [case for case in changed["cases"] if case["id"] != "fault-with-sibling-barrier-wait"]
        errors = MODULE.validate_fault_matrix(changed, self.inventory, ROOT)
        self.assertTrue(any("fault x sibling_barrier_wait" in error for error in errors))

    def test_compile_only_top_cannot_back_fault_matrix_claim(self):
        changed = json.loads(json.dumps(self.fault))
        changed["cases"][0]["test_id"] = "rtl:cgx1_matrix_int8_pooled_resident_engine_tb"
        self.assertTrue(any("actually simulated RTL top" in error for error in MODULE.validate_fault_matrix(changed, self.inventory, ROOT)))


if __name__ == "__main__":
    unittest.main()
