from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE = Path(__file__).resolve().parents[1] / "validate.py"
SPEC = importlib.util.spec_from_file_location("solari_case_study_validate", MODULE)
assert SPEC and SPEC.loader
validate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate)


class CaseStudyValidationTests(unittest.TestCase):
    def test_checked_in_case_study_is_receipt_bound(self) -> None:
        self.assertEqual(validate.inspect_case_study(), [])

    def test_rejects_live_retailer_price_claim(self) -> None:
        source = (validate.ROOT / "index.html").read_text(encoding="utf-8")
        self.assertTrue(any(__import__("re").search(pattern, source + " live retailer prices", flags=__import__("re").IGNORECASE) for pattern in validate.FORBIDDEN_CLAIMS))

    def test_rejects_receipt_economics_drift(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        receipt = Path(temporary.name) / "receipt.json"
        receipt.write_text('{"coverage":{"researchedRequirementCount":8,"observationCount":16},"basket":{"observedSubtotal":99},"comparison":{"cheapestAdequateSubtotal":23.57,"premiumOverCheapest":0.63,"maxPremiumOverCheapest":0.75},"execution":{"browser":"solari-browser-provider-completed","sandbox":"solari-sandbox-provider-completed"}}', encoding="utf-8")
        errors = validate.inspect_case_study(receipt_path=receipt)
        self.assertTrue(any("economics drifted" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
