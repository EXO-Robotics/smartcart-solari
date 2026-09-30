#!/usr/bin/env python3
"""Check the video submission's assets, links, evidence labels, and frozen receipt."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[1]
RECEIPT = REPO_ROOT / "evidence/live/smartcart-solari-v4-qualification-33546912947.json"
VIDEO_SHA256 = {
    "smartcart-before-solari.mp4": "3f8f63014b18af2559c45d5c22e647df969046ff8d738bd4df5b507232242b9d",
    "smartcart-after-solari.mp4": "dd2209feb93d442774c1f51ac70c8be3264094cd10b77ff049e8fa8abeebc3b3",
}
PROJECT_URL = "https://github.com/EXO-Robotics/smartcart-solari#readme"
EVIDENCE_URL = "https://github.com/EXO-Robotics/smartcart-solari/blob/8f749e33808119ee403142929da5b757ed934e35/evidence/live/smartcart-solari-v4-qualification-33546912947.json"
EXAMPLE_URL = "https://github.com/EXO-Robotics/solari-cookbook/tree/main/examples/smartcart-basket-research-ts"
FORBIDDEN_CLAIMS = (
    r"\blive retailer prices?\b",
    r"(?<!no )\bguaranteed prices?\b",
    r"\bavailable on TestFlight\b",
    r"\bApp Store download\b",
)


class LandingParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tags: list[tuple[str, dict[str, str]]] = []
        self.ids: set[str] = set()
        self.duplicate_ids: set[str] = set()
        self.references: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        self.tags.append((tag, values))
        identity = values.get("id")
        if identity:
            if identity in self.ids:
                self.duplicate_ids.add(identity)
            self.ids.add(identity)
        for key in ("href", "src", "poster"):
            if values.get(key):
                self.references.append((tag, values[key]))


def inspect_case_study(root: Path = ROOT, receipt_path: Path = RECEIPT) -> list[str]:
    errors: list[str] = []
    required_files = (
        "index.html", "submission.css", "submission.js", "verified-run.html",
        "assets/social-preview.jpg", "assets/favicon.svg",
        "assets/smartcart-before-solari.mp4", "assets/smartcart-before-solari-poster.jpg",
        "assets/smartcart-after-solari.mp4", "assets/smartcart-after-solari-poster.jpg",
    )
    for relative in required_files:
        if not (root / relative).is_file():
            errors.append(f"missing required submission file: {relative}")
    if errors:
        return errors

    source = (root / "index.html").read_text(encoding="utf-8")
    script = (root / "submission.js").read_text(encoding="utf-8")
    parser = LandingParser()
    parser.feed(source)
    by_tag = lambda tag: [values for candidate, values in parser.tags if candidate == tag]
    if len(by_tag("main")) != 1 or len(by_tag("h1")) != 1:
        errors.append("submission must have one main and one h1")
    if not any(values.get("lang") == "en" for values in by_tag("html")):
        errors.append("html lang must be en")
    if not any(values.get("name") == "viewport" for values in by_tag("meta")):
        errors.append("viewport metadata is required")
    if not any(values.get("href") == "#main" and "skip-link" in values.get("class", "") for values in by_tag("a")):
        errors.append("accessible skip link is required")
    if not any(values.get("id") == "main" and values.get("tabindex") == "-1" for values in by_tag("main")):
        errors.append("skip-link target must accept focus")
    if parser.duplicate_ids:
        errors.append(f"duplicate ids: {sorted(parser.duplicate_ids)}")

    tabs = [values for _, values in parser.tags if values.get("role") == "tab"]
    selected = [tab for tab in tabs if tab.get("aria-selected") == "true"]
    if len(tabs) != 2 or len(selected) != 1 or selected[0].get("data-video-mode") != "after":
        errors.append("the Before/After tabs must open on After Solari")
    for _, values in parser.tags:
        for attribute in ("aria-controls", "aria-labelledby", "aria-describedby"):
            for identity in values.get(attribute, "").split():
                if identity not in parser.ids:
                    errors.append(f"missing accessibility target: {identity}")

    videos = by_tag("video")
    if len(videos) != 1 or "playsinline" not in videos[0] or "controls" not in videos[0] or "autoplay" in videos[0]:
        errors.append("video must play inline, have no autoplay, and retain controls without JavaScript")
    combined = source + script
    for phrase in ("DEBUG recorded replay", "Demo Grocer test data", "Not a live run", "not current prices or availability"):
        if phrase.casefold() not in combined.casefold():
            errors.append(f"missing footage evidence label: {phrase}")
    for filename in VIDEO_SHA256:
        if f"assets/{filename}" not in combined:
            errors.append(f"missing recording route: {filename}")
    for url in (PROJECT_URL, EVIDENCE_URL, EXAMPLE_URL):
        if url not in source:
            errors.append(f"missing direct review link: {url}")
    for marker in ("og:title", "og:description", "og:image", "twitter:card"):
        if marker not in source:
            errors.append(f"missing social metadata: {marker}")
    for pattern in FORBIDDEN_CLAIMS:
        if re.search(pattern, source, re.IGNORECASE):
            errors.append(f"forbidden overclaim: {pattern}")
    if re.search(r"\bfetch\s*\(|XMLHttpRequest|public-demo/v1/solari/research", script):
        errors.append("submission player must not start provider research")

    for tag, reference in parser.references:
        parsed = urlsplit(reference)
        if parsed.scheme or parsed.netloc:
            if tag != "a" or parsed.scheme != "https" or parsed.hostname != "github.com":
                errors.append(f"unapproved remote asset/link: {reference}")
        elif reference.startswith("#"):
            if reference[1:] not in parser.ids:
                errors.append(f"missing fragment target: {reference}")
        elif not (root / parsed.path).is_file():
            errors.append(f"broken local reference: {reference}")
    for filename, expected in VIDEO_SHA256.items():
        actual = hashlib.sha256((root / "assets" / filename).read_bytes()).hexdigest()
        if actual != expected:
            errors.append(f"recording bytes drifted: {filename}: {actual}")

    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return sorted(set(errors + [f"qualification receipt unreadable: {error}"]))
    coverage = receipt.get("coverage", {})
    basket = receipt.get("basket", {})
    comparison = receipt.get("comparison", {})
    economics = (
        coverage.get("researchedRequirementCount"), coverage.get("observationCount"),
        basket.get("observedSubtotal"), comparison.get("cheapestAdequateSubtotal"),
        comparison.get("premiumOverCheapest"), comparison.get("maxPremiumOverCheapest"),
    )
    if economics != (8, 16, 24.2, 23.57, 0.63, 0.75):
        errors.append(f"qualification receipt economics drifted: {economics}")
    for provider in ("browser", "sandbox"):
        if receipt.get("execution", {}).get(provider) != f"solari-{provider}-provider-completed":
            errors.append(f"receipt does not prove completed Solari {provider} execution")
    return sorted(set(errors))


def main() -> int:
    errors = inspect_case_study()
    if errors:
        print("SmartCart × Solari submission validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print("SmartCart × Solari submission validation passed: video assets, review links, accessibility, and frozen evidence.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
