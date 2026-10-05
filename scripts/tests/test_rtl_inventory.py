import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve().parents[1] / "validate_rtl_inventory.py"
SPEC = importlib.util.spec_from_file_location("validate_rtl_inventory", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RtlInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script_text = (ROOT / "scripts/validate_rtl.sh").read_text(encoding="utf-8")
        cls.inventory = json.loads((ROOT / "design/cgx1_rtl_validation_inventory.json").read_text(encoding="utf-8"))

    def test_current_compile_and_simulation_inventory_matches(self):
        self.assertEqual(MODULE.validate_document(self.inventory, self.script_text, ROOT), [])

    def test_simulated_top_without_bounded_run_is_rejected(self):
        changed = self.script_text.replace("timeout 30s vvp build/rtl/cgx1_top_tb.vvp", "vvp build/rtl/cgx1_top_tb.vvp", 1)
        errors = MODULE.validate_document(self.inventory, changed, ROOT)
        self.assertTrue(any("unbounded simulation" in error for error in errors))

    def test_compile_only_composition_cannot_be_claimed_simulated(self):
        changed = json.loads(json.dumps(self.inventory))
        target = next(item for item in changed["invocations"] if item["top"] == "cgx1_matrix_int8_pooled_resident_engine_tb")
        target["mode"] = "simulated"
        errors = MODULE.validate_document(changed, self.script_text, ROOT)
        self.assertTrue(any("mode mismatch" in error for error in errors))

    def test_unbounded_iverilog_compiler_is_rejected(self):
        changed = self.script_text.replace('timeout --signal=TERM --kill-after=5s "${selected_timeout}s" "$iverilog_bin"', '"$iverilog_bin"', 1)
        errors = MODULE.validate_document(self.inventory, changed, ROOT)
        self.assertTrue(any("compiler timeout" in error for error in errors))

    def test_inventory_must_cover_every_production_module_source(self):
        changed = json.loads(json.dumps(self.inventory))
        changed["modules"] = changed["modules"][:-1]
        errors = MODULE.validate_document(changed, self.script_text, ROOT)
        self.assertTrue(any("module inventory mismatch" in error for error in errors))

    def test_compile_only_entry_requires_partial_reason(self):
        changed = json.loads(json.dumps(self.inventory))
        target = next(item for item in changed["invocations"] if item["mode"] == "compile_only")
        target.pop("reason", None)
        errors = MODULE.validate_document(changed, self.script_text, ROOT)
        self.assertTrue(any("compile-only reason" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
