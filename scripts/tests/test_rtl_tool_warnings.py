import importlib.util
import json
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "validate_rtl_tool_warnings.py"
SPEC = importlib.util.spec_from_file_location("validate_rtl_tool_warnings", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RtlToolWarningTests(unittest.TestCase):
    def test_timescalemod_allowlist_is_limited_to_two_reviewed_modules(self):
        allowlist_path = SCRIPT.parents[1] / "design" / "cgx1_rtl_tool_warning_allowlist.json"
        allowlist = json.loads(allowlist_path.read_text(encoding="utf-8"))
        approved_logs = [
            ("verilator", "%Warning-TIMESCALEMOD: source/rtl/cgx1_compute_int8_vector_execution_frontend.sv:1:1: mixed timescale"),
            ("verilator", "%Warning-TIMESCALEMOD: source/rtl/cgx1_compute_mixed_service_policy.sv:1:1: mixed timescale"),
        ]

        self.assertEqual([], MODULE.classify_logs(approved_logs, allowlist))

        unrelated_log = [
            ("verilator", "%Warning-TIMESCALEMOD: source/rtl/cgx1_unreviewed_module.sv:1:1: mixed timescale"),
        ]
        errors = MODULE.classify_logs(unrelated_log, allowlist)
        self.assertEqual(1, len(errors))
        self.assertIn("unclassified verilator warning", errors[0])

    def test_logs_without_warnings_pass(self):
        self.assertEqual(MODULE.classify_logs([("yosys", "2 cells\n")], {"schema_version": 1, "rules": []}), [])

    def test_unknown_warning_is_rejected(self):
        errors = MODULE.classify_logs([("verilator", "%Warning-WIDTH: file.sv:1:1: width mismatch")], {"schema_version": 1, "rules": []})
        self.assertTrue(any("unclassified verilator warning" in error for error in errors))

    def test_tool_specific_rule_requires_reason(self):
        errors = MODULE.validate_allowlist({"schema_version": 1, "rules": [{"tool": "yosys", "pattern": "Warning:"}]})
        self.assertTrue(any("reason" in error for error in errors))

    def test_explicit_reason_classifies_only_the_named_tool(self):
        allowlist = {"schema_version": 1, "rules": [{"tool": "yosys", "pattern": "Warning: expected", "reason": "Known parser notice in this bounded smoke."}]}
        self.assertEqual(MODULE.classify_logs([("yosys", "Warning: expected notice"), ("verilator", "")], allowlist), [])


if __name__ == "__main__":
    unittest.main()
