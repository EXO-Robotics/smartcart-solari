#!/usr/bin/env python3
"""Validate the SmartCart × Solari GitHub Pages case study and its receipt-bound claims."""

from __future__ import annotations

import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[1]
RECEIPT = REPO_ROOT / "evidence" / "live" / "smartcart-solari-v4-qualification-33546912947.json"
ALLOWED_REMOTE_HOSTS = {"github.com", "docs.getsolari.com"}
REQUIRED_PHRASES = {
    "The frontend is replaceable",
    "Solari is the capability",
    "owned, synthetic retailer",
    "$24.20",
    "$0.63",
    "1.5 lb",
    "No retailer login",
    "User-controlled handoff",
}
FORBIDDEN_CLAIMS = (
    r"\blive retailer prices?\b",
    r"(?<!no )\bguaranteed prices?\b",
    r"\bavailable on TestFlight\b",
    r"\bApp Store download\b",
    r"\bcommercial retailer coverage\b(?![^.]{0,35}\bnot\b)",
)


class LandingParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.lang = ""
        self.viewport = False
        self.main_count = 0
        self.h1_count = 0
        self.skip_link = False
        self.ids: set[str] = set()
        self.references: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {name: value or "" for name, value in attrs}
        if values.get("id"):
            self.ids.add(values["id"])
        if tag == "html":
            self.lang = values.get("lang", "")
        elif tag == "meta" and values.get("name", "").lower() == "viewport":
            self.viewport = bool(values.get("content"))
        elif tag == "main":
            self.main_count += 1
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "a":
            href = values.get("href", "")
            if href:
                self.references.append((tag, href))
                if href == "#main" and "skip-link" in values.get("class", "").split():
                    self.skip_link = True
        elif tag == "link":
            href = values.get("href", "")
            if href:
                self.references.append((tag, href))
        elif tag == "script":
            src = values.get("src", "")
            if src:
                self.references.append((tag, src))


def inspect_case_study(root: Path = ROOT, receipt_path: Path = RECEIPT) -> list[str]:
    errors: list[str] = []
    index = root / "index.html"
    styles = root / "styles.css"
    script = root / "script.js"
    for path in (index, styles, script, root / "assets" / "smartcart-food-stage.jpg"):
        if not path.is_file():
            errors.append(f"missing required case-study file: {path.relative_to(root)}")
    if errors:
        return errors

    source = index.read_text(encoding="utf-8")
    parser = LandingParser()
    parser.feed(source)
    if parser.lang != "en":
        errors.append("index.html: html lang must be en")
    if not parser.viewport:
        errors.append("index.html: viewport metadata is required")
    if parser.main_count != 1:
        errors.append(f"index.html: expected one main element, found {parser.main_count}")
    if parser.h1_count != 1:
        errors.append(f"index.html: expected one h1, found {parser.h1_count}")
    if not parser.skip_link:
        errors.append("index.html: accessible skip link is required")

    for phrase in REQUIRED_PHRASES:
        if phrase.casefold() not in source.casefold():
            errors.append(f"index.html: missing required product marker {phrase!r}")
    for pattern in FORBIDDEN_CLAIMS:
        if re.search(pattern, source, flags=re.IGNORECASE):
            errors.append(f"index.html: forbidden overclaim matched {pattern!r}")

    deploy_mapped = {
        "evidence/live/smartcart-solari-v4-qualification-33546912947.json": receipt_path,
        "website/solari-demo/": REPO_ROOT / "website" / "solari-demo" / "index.html",
    }
    for tag, reference in parser.references:
        parsed = urlsplit(reference)
        if parsed.scheme or parsed.netloc:
            if tag in {"link", "script"}:
                errors.append(f"index.html: remote assets are forbidden: {reference}")
            elif parsed.hostname not in ALLOWED_REMOTE_HOSTS:
                errors.append(f"index.html: unapproved remote link: {reference}")
            continue
        if reference.startswith("#"):
            if reference[1:] not in parser.ids:
                errors.append(f"index.html: missing fragment target: {reference}")
            continue
        target = deploy_mapped.get(parsed.path, (root / parsed.path).resolve())
        if not target.exists():
            errors.append(f"index.html: broken local/deployment reference: {reference}")

    javascript = script.read_text(encoding="utf-8")
    for key in ("smartcart", "procurement", "travel", '"field-service"'):
        if key not in javascript:
            errors.append(f"script.js: missing replaceable frontend model {key}")
    if "prefers-reduced-motion" not in javascript or "prefers-reduced-motion" not in styles.read_text(encoding="utf-8"):
        errors.append("case study must honor prefers-reduced-motion in CSS and JavaScript")

    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"qualification receipt unreadable: {error}")
        return sorted(set(errors))
    coverage = receipt.get("coverage", {})
    basket = receipt.get("basket", {})
    comparison = receipt.get("comparison", {})
    expected = {
        "requirements": coverage.get("researchedRequirementCount"),
        "observations": coverage.get("observationCount"),
        "selected": basket.get("observedSubtotal"),
        "cheapest": comparison.get("cheapestAdequateSubtotal"),
        "premium": comparison.get("premiumOverCheapest"),
        "cap": comparison.get("maxPremiumOverCheapest"),
    }
    if expected != {"requirements": 8, "observations": 16, "selected": 24.2, "cheapest": 23.57, "premium": 0.63, "cap": 0.75}:
        errors.append(f"qualification receipt economics drifted: {expected}")
    if receipt.get("execution", {}).get("browser") != "solari-browser-provider-completed":
        errors.append("receipt does not prove completed Solari Browser execution")
    if receipt.get("execution", {}).get("sandbox") != "solari-sandbox-provider-completed":
        errors.append("receipt does not prove completed Solari Sandbox execution")
    return sorted(set(errors))


def main() -> int:
    errors = inspect_case_study()
    if errors:
        print(f"SmartCart × Solari case-study validation failed ({len(errors)} issue(s)):")
        for error in errors:
            print(f"- {error}")
        return 1
    print("SmartCart × Solari case-study validation passed: presentation, portability, accessibility, and receipt-bound claims checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
