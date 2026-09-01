from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE = Path(__file__).resolve().parents[1] / "validate.py"
SPEC = importlib.util.spec_from_file_location("solari_demo_validate", MODULE)
assert SPEC and SPEC.loader
validate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate)


class ReplayFixtureValidationTests(unittest.TestCase):
    def write_fixture(self, value: str) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "fixture.json"
        path.write_text(value, encoding="utf-8")
        return path

    def test_rejects_independent_ui_contract(self) -> None:
        path = self.write_fixture('{"schemaVersion":"smartcart.solari.demo-replay.v1"}')
        errors = validate.validate_replay_fixture(path)
        self.assertIn("fixture must use canonical solari-shopping-research-result-v1", errors)

    def test_rejects_live_claim_for_replay(self) -> None:
        path = self.write_fixture("""{
          "schemaVersion":"solari-shopping-research-result-v1",
          "executionMode":"recorded_fixture",
          "retailerID":"walmart",
          "trust":{
            "priceClaim":"observed-visible-price-not-guaranteed",
            "accountAccessed":false,"cartModified":false,"checkoutAutomated":false,"userControlsHandoff":true
          },
          "observations":[]
        }""")
        errors = validate.validate_replay_fixture(path)
        self.assertTrue(any("trust.priceClaim" in error for error in errors))

    def test_rejects_catalog_not_marked_synthetic(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "catalog.json").write_text('{"synthetic":false,"products":[]}', encoding="utf-8")
        errors = []
        catalog = __import__("json").loads((root / "catalog.json").read_text(encoding="utf-8"))
        if catalog.get("synthetic") is not True:
            errors.append("controlled catalog must be marked synthetic")
        self.assertIn("controlled catalog must be marked synthetic", errors)

    def test_public_demo_has_no_numeric_confidence_or_selection_reset(self) -> None:
        errors = validate.inspect_demo()
        self.assertNotIn("main replay must not invent numeric decision confidence", errors)
        self.assertNotIn("stage navigation must not discard selected product alternatives", errors)
        self.assertNotIn("what-if preview must keep incomplete totals nullable", errors)
        self.assertNotIn("what-if preview must normalize compatible weight units", errors)


if __name__ == "__main__":
    unittest.main()
