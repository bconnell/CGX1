import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "validate_rtl_warnings.py"
SPEC = importlib.util.spec_from_file_location("validate_rtl_warnings", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RtlWarningTests(unittest.TestCase):
    def test_log_without_warnings_passes_empty_allowlist(self):
        self.assertEqual(MODULE.classify_warnings("Icarus Verilog version 14.0\n", {"schema_version": 1, "rules": []}), [])

    def test_explicit_pattern_and_reason_classify_warning(self):
        document = {"schema_version": 1, "rules": [{"pattern": r"warning: deprecated", "reason": "Legacy testbench syntax pending migration."}]}
        self.assertEqual(MODULE.classify_warnings("warning: deprecated construct\n", document), [])

    def test_icarus_array_sensitivity_notice_is_classified(self):
        document = {
            "schema_version": 1,
            "rules": [{
                "pattern": r"warning: @\* is sensitive to all [0-9]+ words in array '[^']+'",
                "reason": "Icarus conservatively includes unpacked arrays in @* sensitivity.",
            }],
        }
        warning = "source.sv:10: warning: @* is sensitive to all 4 words in array 'pc_q'."
        self.assertEqual(MODULE.classify_warnings(warning, document), [])

    def test_unclassified_warning_fails(self):
        self.assertIn("unclassified RTL compiler diagnostic", MODULE.classify_warnings("warning: unknown construct", {"schema_version": 1, "rules": []})[0])

    def test_allowlist_without_reason_fails(self):
        errors = MODULE.validate_allowlist({"schema_version": 1, "rules": [{"pattern": "warning"}]})
        self.assertTrue(any("reason" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
