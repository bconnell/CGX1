import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_release_test_checks as gate


class ReleaseTestCheckGateTests(unittest.TestCase):
    def test_scanner_accepts_check_and_static_assert_but_ignores_comments_and_literals(self):
        source = r'''
            // assert(comment_only);
            const char* text = "assert(string_only);";
            static_assert(sizeof(int) >= 2, "static assertion is allowed");
            CGX1_TEST_CHECK(value == expected);
        '''
        self.assertEqual(gate.runtime_assert_locations(source), [])

    def test_scanner_rejects_runtime_assert_condition(self):
        self.assertEqual(gate.runtime_assert_locations("assert(condition);"), [(1, 1)])

    def test_scanner_accepts_assert_identifier_without_call_and_static_assert(self):
        self.assertEqual(
            gate.runtime_assert_locations("int assert_value = 0; static_assert(true);") ,
            [],
        )

    def test_cmake_target_mapping_finds_runtime_assert_in_ctest_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text(
                "add_executable(sample tests.cpp)\nadd_test(NAME sample_test COMMAND sample)\n",
                encoding="utf-8",
            )
            (root / "tests.cpp").write_text("assert(false);\n", encoding="utf-8")
            diagnostics = gate.check_root(root)
            self.assertEqual(len(diagnostics), 1)
            self.assertIn("tests.cpp:1:1", diagnostics[0])

    def test_scanner_fails_closed_when_no_ctest_executable_is_resolved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text("project(empty)\n", encoding="utf-8")
            diagnostics = gate.check_root(root)
            self.assertEqual(len(diagnostics), 1)
            self.assertIn("no CTest executable sources", diagnostics[0])

    def test_scanner_finds_targets_when_candidate_path_contains_build_segment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "build" / "candidate"
            root.mkdir(parents=True)
            (root / "CMakeLists.txt").write_text(
                "add_executable(sample tests.cpp)\nadd_test(NAME sample_test COMMAND sample)\n",
                encoding="utf-8",
            )
            (root / "tests.cpp").write_text("CGX1_TEST_CHECK(true);\n", encoding="utf-8")
            self.assertEqual(gate.check_root(root), [])

    def test_positive_control_ignores_static_assert_and_always_on_check_in_ctest_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text(
                "add_executable(sample tests.cpp)\nadd_test(NAME sample_test COMMAND sample)\n",
                encoding="utf-8",
            )
            (root / "tests.cpp").write_text(
                "static_assert(sizeof(int) >= 2);\nCGX1_TEST_CHECK(1 == 1);\n",
                encoding="utf-8",
            )
            self.assertEqual(gate.check_root(root), [])

    def test_negative_control_rejects_state_change_inside_always_on_check(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text(
                "add_executable(sample tests.cpp)\nadd_test(NAME sample_test COMMAND sample)\n",
                encoding="utf-8",
            )
            (root / "tests.cpp").write_text(
                "void test() { CGX1_TEST_CHECK(scheduler.Admit(demand) == expected); }\n",
                encoding="utf-8",
            )
            diagnostics = gate.check_root(root)
            self.assertEqual(len(diagnostics), 1)
            self.assertIn("state-changing operation Admit", diagnostics[0])

    def test_negative_control_rejects_state_change_inside_check_callback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text(
                "add_executable(sample tests.cpp)\nadd_test(NAME sample_test COMMAND sample)\n",
                encoding="utf-8",
            )
            (root / "tests.cpp").write_text(
                "void test() { CGX1_TEST_CHECK(Throws([&] { scheduler.Admit(demand); })); }\n",
                encoding="utf-8",
            )
            diagnostics = gate.check_root(root)
            self.assertEqual(len(diagnostics), 1)
            self.assertIn("state-changing operation Admit", diagnostics[0])

    def test_positive_control_accepts_action_captured_before_always_on_check(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "CMakeLists.txt").write_text(
                "add_executable(sample tests.cpp)\nadd_test(NAME sample_test COMMAND sample)\n",
                encoding="utf-8",
            )
            (root / "tests.cpp").write_text(
                "void test() { const auto result = scheduler.Admit(demand); "
                "CGX1_TEST_CHECK(result == expected); }\n",
                encoding="utf-8",
            )
            self.assertEqual(gate.check_root(root), [])

    def test_cmake_parser_respects_comments_quoted_paths_and_multiline_calls(self):
        parsed = gate.parse_cmake_commands(
            'add_executable(sample\n "dir with space/test.cpp" # ignored.cpp\n other.cpp)\n'
            'add_test(NAME unit COMMAND sample)\n'
        )
        self.assertEqual([command.name for command in parsed], ["add_executable", "add_test"])
        self.assertIn("dir with space/test.cpp", parsed[0].arguments)


if __name__ == "__main__":
    unittest.main()
