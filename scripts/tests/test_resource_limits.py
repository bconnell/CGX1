import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import validate_resource_limits as validator


class ResourceLimitRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "source").mkdir()
        (self.root / "source/limit.hpp").write_text("limit = 8;\n", encoding="utf-8")
        (self.root / "source/test.cpp").write_text(
            "CHECK(value == 8); CHECK(value == 9);\n", encoding="utf-8"
        )
        self.document = {
            "schema_version": 1,
            "limits": [{
                "id": "example",
                "classification": "parameterized_implementation",
                "value": "8 units",
                "rationale": "bounded test fixture",
                "source": {"path": "source/limit.hpp", "needle": "limit = 8"},
                "requires_over_boundary": True,
                "test_refs": [
                    {"path": "source/test.cpp", "needle": "value == 8", "kind": "exact"},
                    {"path": "source/test.cpp", "needle": "value == 9", "kind": "over"},
                ],
            }],
        }

    def tearDown(self):
        self.temporary.cleanup()

    def test_valid_exact_and_over_boundary_records_pass(self):
        self.assertEqual(validator.validate_document(self.document, self.root), [])

    def test_missing_classification_is_rejected(self):
        del self.document["limits"][0]["classification"]
        self.assertTrue(any("classification" in error
            for error in validator.validate_document(self.document, self.root)))

    def test_missing_boundary_reference_is_rejected(self):
        self.document["limits"][0]["test_refs"].pop()
        errors = validator.validate_document(self.document, self.root)
        self.assertTrue(any("just-over/just-below" in error for error in errors))

    def test_missing_reference_needle_is_rejected(self):
        self.document["limits"][0]["test_refs"][0]["needle"] = "not a test"
        self.assertTrue(any("needle is missing" in error
            for error in validator.validate_document(self.document, self.root)))

    def test_invalid_classification_is_rejected(self):
        self.document["limits"][0]["classification"] = "architecture_by_test"
        self.assertTrue(any("classification" in error
            for error in validator.validate_document(self.document, self.root)))


if __name__ == "__main__":
    unittest.main()
