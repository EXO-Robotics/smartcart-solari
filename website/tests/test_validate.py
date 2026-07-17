from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "validate.py"
SPEC = importlib.util.spec_from_file_location("smartcart_site_validate", MODULE_PATH)
assert SPEC and SPEC.loader
validate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate)


VALID_PAGE = """<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width">
<title>Fixture</title></head><body><a class="skip-link" href="#main">Skip</a>
<main id="main"><h1>Fixture</h1>{body}</main></body></html>"""


class WebsiteValidationTests(unittest.TestCase):
    def make_site(self, body: str = "") -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "index.html").write_text(VALID_PAGE.format(body=body), encoding="utf-8")
        return root

    def test_accepts_minimal_accessible_local_page(self) -> None:
        root = self.make_site()
        errors = validate.inspect_site(root, required_pages={"index.html": "Fixture"})
        relevant = [error for error in errors if not error.startswith("missing required package file")]
        self.assertEqual(relevant, [])

    def test_reports_broken_local_link(self) -> None:
        root = self.make_site('<a href="missing.html">Missing</a>')
        errors = validate.inspect_site(root, required_pages={"index.html": "Fixture"})
        self.assertTrue(any("broken local reference" in error for error in errors))

    def test_rejects_remote_dependency(self) -> None:
        root = self.make_site('<script src="https://cdn.invalid/library.js"></script>')
        errors = validate.inspect_site(root, required_pages={"index.html": "Fixture"})
        self.assertTrue(any("remote or special reference" in error for error in errors))

    def test_reports_missing_fragment(self) -> None:
        root = self.make_site('<a href="#not-present">Nowhere</a>')
        errors = validate.inspect_site(root, required_pages={"index.html": "Fixture"})
        self.assertTrue(any("missing fragment target" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
