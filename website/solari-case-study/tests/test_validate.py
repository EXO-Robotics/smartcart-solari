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

    def test_readable_receipt_keeps_raw_evidence_secondary(self) -> None:
        landing = (validate.ROOT / "index.html").read_text(encoding="utf-8")
        readable = (validate.ROOT / "verified-run.html").read_text(encoding="utf-8")
        self.assertIn("verified-run.html", landing)
        self.assertNotIn("evidence/live/smartcart-solari-v4-qualification-33546912947.json", landing)
        self.assertIn("View raw JSON", readable)

    def test_live_public_run_is_fixed_bounded_and_server_rate_limited(self) -> None:
        landing = (validate.ROOT / "index.html").read_text(encoding="utf-8")
        script = (validate.ROOT / "script.js").read_text(encoding="utf-8")
        self.assertIn("Research this meal", landing)
        self.assertIn('https://smartcart-solari-beta.vercel.app/public-demo/v1/solari/research', script)
        self.assertIn('schemaVersion: "smartcart-solari-public-demo-request-v1"', script)
        self.assertIn('mealID: "chicken-pasta-eight-item-v1"', script)
        self.assertNotIn("sessionStorage", script)
        self.assertNotIn("setTimeout(() => {\n        liveProgressSteps", script)
        self.assertIn('payload.deliveryMode === "cached-verified-run"', script)
        self.assertIn("AbortController", script)
        self.assertIn('credentials: "omit"', script)

    def test_provider_result_rendering_is_text_only_and_replay_is_link_only(self) -> None:
        landing = (validate.ROOT / "index.html").read_text(encoding="utf-8")
        script = (validate.ROOT / "script.js").read_text(encoding="utf-8")
        self.assertNotIn("<iframe", landing.casefold())
        self.assertNotIn(".innerHTML", script)
        self.assertNotIn("insertAdjacentHTML", script)
        self.assertIn("textContent", script)
        self.assertIn("replaceChildren", script)
        self.assertIn('parsed.protocol === "https:"', script)
        self.assertIn('host.endsWith(".getsolari.com")', script)
        self.assertIn('host === "pinetree-browser-replays.s3.us-west-1.amazonaws.com"', script)
        self.assertIn('payload.schemaVersion !== "smartcart-solari-public-demo-response-v1"', script)
        self.assertIn('payload.deliveryMode === "cached-verified-run"', script)
        self.assertIn('payload.deliveryMode === "live" ? approvedReplayURL', script)
        self.assertIn("runtimeStats.wallTimeMs", script)
        self.assertIn("provenance.resourceCleanup", script)

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
