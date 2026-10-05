import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import check_markdown_links
from scripts.check_markdown_links import validate_markdown_links


class MarkdownLinkTests(unittest.TestCase):
    def test_git_file_discovery_uses_candidate_scoped_safe_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text("# clean\n", encoding="utf-8")
            completed = check_markdown_links.subprocess.CompletedProcess(
                args=[], returncode=0, stdout=b"README.md\0", stderr=b""
            )

            with patch.object(check_markdown_links.subprocess, "run", return_value=completed) as run:
                self.assertEqual(validate_markdown_links(root), [])

            command = run.call_args.args[0]
            self.assertEqual(
                ["git", "-c", f"safe.directory={root.resolve()}", "-C", str(root.resolve())],
                command[:5],
            )

    def test_encoded_local_path_and_heading_anchor_are_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs").mkdir()
            (root / "README.md").write_text(
                "[guide](docs/release%20guide.md#release-guide)\n", encoding="utf-8"
            )
            (root / "docs/release guide.md").write_text(
                "# Release guide\n", encoding="utf-8"
            )

            self.assertEqual(validate_markdown_links(root, [Path("README.md")]), [])

    def test_duplicate_heading_slugs_get_numeric_suffixes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text(
                "[first](guide.md#configuration)\n"
                "[second](guide.md#configuration-1)\n",
                encoding="utf-8",
            )
            (root / "guide.md").write_text(
                "## Configuration\n\n## Configuration\n", encoding="utf-8"
            )

            self.assertEqual(validate_markdown_links(root, [Path("README.md")]), [])

    def test_missing_file_and_missing_heading_report_distinct_reasons(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text(
                "[missing file](absent.md#nowhere)\n"
                "[missing heading](existing.md#nowhere)\n",
                encoding="utf-8",
            )
            (root / "existing.md").write_text("# Present\n", encoding="utf-8")

            issues = validate_markdown_links(root, [Path("README.md")])

            self.assertEqual([issue.kind for issue in issues], ["missing_file", "missing_anchor"])
            self.assertEqual([issue.line for issue in issues], [1, 2])

    def test_fragment_only_link_checks_the_current_document(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text(
                "[here](#valid-heading)\n[missing](#not-here)\n"
                "## Valid heading\n",
                encoding="utf-8",
            )

            issues = validate_markdown_links(root, [Path("README.md")])

            self.assertEqual([(issue.kind, issue.line) for issue in issues], [("missing_anchor", 2)])

    def test_links_inside_fenced_code_are_not_navigation_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text(
                "```md\n[example](not-a-real-file.md#nope)\n```\n", encoding="utf-8"
            )

            self.assertEqual(validate_markdown_links(root, [Path("README.md")]), [])


if __name__ == "__main__":
    unittest.main()
