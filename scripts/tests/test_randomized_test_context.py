import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "validate_randomized_tests.py"
SPEC = importlib.util.spec_from_file_location("validate_randomized_tests", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RandomizedTestContextTests(unittest.TestCase):
    def test_fixed_seed_context_is_accepted(self):
        source = """
#include <cstdint>
constexpr std::uint32_t seed = 0x1234U;
std::mt19937 random(seed);
SetRandomTestFailureContext("case", seed, step, state);
WriteRandomTestFailureContext(std::cerr);
"""
        self.assertEqual(MODULE.validate_cpp_random_source(source), [])

    def test_missing_failure_context_is_rejected(self):
        source = "constexpr std::uint32_t seed = 1U; std::mt19937 rng(seed);"
        errors = MODULE.validate_cpp_random_source(source)
        self.assertTrue(any("set and print" in error for error in errors))

    def test_nondeterministic_device_is_rejected(self):
        source = "constexpr std::uint32_t seed = 1U; std::mt19937 rng(seed); std::random_device rd;"
        self.assertTrue(any("random_device" in error for error in MODULE.validate_cpp_random_source(source)))

    def test_comments_and_strings_do_not_create_random_source(self):
        source = '// std::mt19937 rng;\nconst char* note = "std::mt19937";'
        self.assertEqual(MODULE.validate_cpp_random_source(source), [])

    def test_sv_global_random_is_rejected(self):
        self.assertTrue(any("simulator-global" in error for error in MODULE.validate_sv_random_source("case ($urandom_range(0, 5))")))

    def test_sv_fixed_seed_and_failure_context_are_accepted(self):
        source = """localparam logic [31:0] RANDOM_SEED = 32'h1234; logic [31:0] randomized_state; $fatal(1, "seed=%08x iteration=%0d state=%08x", RANDOM_SEED, i, randomized_state);"""
        self.assertEqual(MODULE.validate_sv_random_source(source), [])


if __name__ == "__main__":
    unittest.main()
