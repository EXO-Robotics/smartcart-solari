from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "validate.py"
SPEC = importlib.util.spec_from_file_location("submission_validate", MODULE)
assert SPEC and SPEC.loader
validate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate)


class SubmissionValidationTests(unittest.TestCase):
    def test_submission_is_valid(self) -> None:
        self.assertEqual(validate.inspect_case_study(), [])

    def copied_site(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        target = Path(temporary.name) / "site"
        shutil.copytree(validate.ROOT, target)
        return target

    def test_rejects_missing_replay_label(self) -> None:
        root = self.copied_site()
        for filename in ("index.html", "submission.js"):
            path = root / filename
            path.write_text(path.read_text().replace("DEBUG recorded replay", "Native recording"))
        self.assertTrue(any("footage evidence label" in error for error in validate.inspect_case_study(root=root)))

    def test_rejects_broken_media_reference(self) -> None:
        root = self.copied_site()
        path = root / "index.html"
        path.write_text(path.read_text().replace('src="assets/smartcart-after-solari.mp4"', 'src="assets/missing.mp4"'))
        self.assertTrue(any("broken local reference" in error for error in validate.inspect_case_study(root=root)))

    def test_rejects_recording_drift(self) -> None:
        root = self.copied_site()
        (root / "assets/smartcart-after-solari.mp4").write_bytes(b"different recording")
        self.assertTrue(any("recording bytes drifted" in error for error in validate.inspect_case_study(root=root)))

    def test_rejects_receipt_drift(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "receipt.json"
        receipt = json.loads(validate.RECEIPT.read_text())
        receipt["basket"]["observedSubtotal"] = 99
        path.write_text(json.dumps(receipt))
        self.assertTrue(any("economics drifted" in error for error in validate.inspect_case_study(receipt_path=path)))


if __name__ == "__main__":
    unittest.main()
