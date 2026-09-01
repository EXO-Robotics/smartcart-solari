#!/usr/bin/env python3
"""Validate the dependency-free SmartCart × Solari replay and controlled catalog."""

from __future__ import annotations

import json
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parent
CANONICAL_FIXTURE = ROOT.parents[1] / "contracts" / "fixtures" / "v1" / "solari" / "chicken-parmesan-walmart-result.json"
PRODUCT_IDS = {"10414680", "10534084", "623835750", "10452414", "10307238", "47088917"}
ALLOWED_REMOTE_HOSTS = {"www.walmart.com"}


class ReplayHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.lang = ""
        self.title = 0
        self.main = 0
        self.h1 = 0
        self.remote_assets: list[str] = []
        self.remote_links: list[str] = []
        self.local_refs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        if tag == "html":
            self.lang = values.get("lang", "")
        elif tag == "title":
            self.title += 1
        elif tag == "main":
            self.main += 1
        elif tag == "h1":
            self.h1 += 1

        reference = ""
        if tag in {"script", "img"}:
            reference = values.get("src", "")
        elif tag == "link":
            reference = values.get("href", "")
        elif tag == "a":
            reference = values.get("href", "")

        if not reference or reference.startswith("#"):
            return
        parsed = urlsplit(reference)
        if parsed.scheme or parsed.netloc:
            if tag in {"script", "img", "link"}:
                self.remote_assets.append(reference)
            else:
                self.remote_links.append(reference)
        else:
            self.local_refs.append(reference)


def validate_html(path: Path) -> list[str]:
    errors: list[str] = []
    parser = ReplayHTMLParser()
    parser.feed(path.read_text(encoding="utf-8"))
    relative = path.relative_to(ROOT).as_posix()
    if parser.lang != "en":
        errors.append(f"{relative}: html lang must be en")
    if parser.title != 1:
        errors.append(f"{relative}: expected one title")
    if parser.main != 1:
        errors.append(f"{relative}: expected one main")
    if parser.h1 != 1:
        errors.append(f"{relative}: expected one h1")
    if parser.remote_assets:
        errors.append(f"{relative}: remote assets are forbidden: {parser.remote_assets}")
    for link in parser.remote_links:
        if urlsplit(link).hostname not in ALLOWED_REMOTE_HOSTS:
            errors.append(f"{relative}: unapproved remote link: {link}")
    for reference in parser.local_refs:
        target = (path.parent / urlsplit(reference).path).resolve()
        if path == ROOT / "index.html" and reference == "../index.html":
            continue
        try:
            target.relative_to(ROOT)
        except ValueError:
            errors.append(f"{relative}: reference escapes demo root: {reference}")
            continue
        if not target.exists():
            errors.append(f"{relative}: broken local reference: {reference}")
    return errors


def validate_replay_fixture(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        fixture = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"fixture unreadable: {error}"]

    # This temporary validator accepts only the canonical result once the shared
    # contract fixture lands; a stale independent UI contract must fail closed.
    if fixture.get("schemaVersion") != "solari-shopping-research-result-v1":
        errors.append("fixture must use canonical solari-shopping-research-result-v1")
        return errors
    if fixture.get("executionMode") != "recorded_fixture":
        errors.append("website replay fixture must remain recorded_fixture")
    if fixture.get("retailerID") != "walmart":
        errors.append("website replay fixture retailer must remain walmart")
    trust = fixture.get("trust", {})
    expected_trust = {
        "priceClaim": "recorded-fixture-not-live",
        "accountAccessed": False,
        "cartModified": False,
        "checkoutAutomated": False,
        "userControlsHandoff": True,
    }
    for key, value in expected_trust.items():
        if trust.get(key) != value:
            errors.append(f"fixture trust.{key} must equal {value!r}")
    observations = fixture.get("observations", [])
    if {item.get("retailerProductID") for item in observations} != PRODUCT_IDS:
        errors.append("fixture must contain exactly the six reviewed product IDs")
    for item in observations:
        if item.get("collectionMethod") != "smartcart-seeded-fixture-replay":
            errors.append(f"{item.get('observationID')}: invalid replay collection method")
        if not item.get("observedAt") or not item.get("sourceURL"):
            errors.append(f"{item.get('observationID')}: missing timestamp or source URL")
        if item.get("proteinGramsPerPackage") is not None:
            errors.append(f"{item.get('observationID')}: unsupported nutrition evidence must remain null")
    return errors


def validate_catalog(path: Path) -> list[str]:
    catalog = json.loads(path.read_text(encoding="utf-8"))
    errors: list[str] = []
    if catalog.get("synthetic") is not True:
        errors.append("controlled catalog must be marked synthetic")
    if {item.get("id") for item in catalog.get("products", [])} != PRODUCT_IDS:
        errors.append("controlled catalog must contain exactly the six demo IDs")
    script = (ROOT / "retailer" / "retailer.js").read_text(encoding="utf-8")
    for attribute in (
        "solariProduct", "productId", "productName", "packageValue",
        "packageUnit", "priceCents", "currency",
    ):
        if f"dataset.{attribute}" not in script:
            errors.append(f"controlled catalog renderer missing dataset.{attribute}")
    return errors


def inspect_demo(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    required = [
        "index.html", "styles.css", "app.js", "README.md", "validate.py",
        "retailer/index.html", "retailer/styles.css", "retailer/retailer.js", "retailer/catalog.json",
    ]
    required.extend(f"retailer/product/{product_id}.html" for product_id in sorted(PRODUCT_IDS))
    for relative in required:
        if not (root / relative).is_file():
            errors.append(f"missing required file: {relative}")
    if errors:
        return errors

    for html in sorted(root.rglob("*.html")):
        errors.extend(validate_html(html))
    errors.extend(validate_replay_fixture(CANONICAL_FIXTURE))
    errors.extend(validate_catalog(root / "retailer" / "catalog.json"))

    main_text = (root / "index.html").read_text(encoding="utf-8")
    required_markers = [
        "Recorded demo evidence · not live",
        "not a Solari live run",
        "Live Walmart Browser execution is disabled",
        "user-controlled retailer handoff",
        "protein/$ is omitted",
    ]
    for marker in required_markers:
        if marker.casefold() not in main_text.casefold():
            errors.append(f"main replay missing trust marker: {marker}")
    if "96%" in main_text:
        errors.append("main replay must not invent numeric decision confidence")
    for marker in ("data-decision-confidence", "data-package-count", "data-receipt-fine"):
        if marker not in main_text:
            errors.append(f"main replay missing derived decision marker: {marker}")

    app_text = (root / "app.js").read_text(encoding="utf-8")
    if "selectedByRequirement.clear()" in app_text:
        errors.append("stage navigation must not discard selected product alternatives")
    if "checkoutEstimate: complete" not in app_text:
        errors.append("what-if preview must keep incomplete totals nullable")
    if "weightScale" not in app_text:
        errors.append("what-if preview must normalize compatible weight units")
    return sorted(set(errors))


def main() -> int:
    errors = inspect_demo()
    if errors:
        print(f"Solari demo validation failed ({len(errors)} issue(s)):")
        for error in errors:
            print(f"- {error}")
        return 1
    print("Solari demo validation passed: canonical replay, controlled catalog, local assets, links, and trust markers checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
