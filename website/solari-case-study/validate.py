#!/usr/bin/env python3
"""Validate the SmartCart × Solari GitHub Pages case study and its receipt-bound claims."""

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
RECEIPT = REPO_ROOT / "evidence" / "live" / "smartcart-solari-v4-qualification-33546912947.json"
VIDEO_SHA256 = {
    "smartcart-before-solari.mp4": "f1864b2566b8ab9e25e80eb55b9d6ac41722f1f8a1e390c24188e28f8f2a71b7",
    "smartcart-after-solari.mp4": "dd2209feb93d442774c1f51ac70c8be3264094cd10b77ff049e8fa8abeebc3b3",
}
ALLOWED_REMOTE_HOSTS = {"github.com", "docs.getsolari.com"}
REQUIRED_PHRASES = {
    "SmartCart already planned the meal",
    "Solari helps price the basket",
    "Solari Browser",
    "Solari Sandbox",
    "What Solari added",
    "owned demo retailer",
    "Solari never touches your Walmart account",
    "You decide what to buy",
}
REQUIRED_LIVE_DEMO_MARKERS = {
    "Research this meal",
    "Public research path",
    "Bounded request in progress",
    "smartcart-solari-public-demo-request-v1",
    "chicken-pasta-eight-item-v1",
    "smartcart-solari-public-demo-response-v1",
    "Telemetry unavailable",
    "Last verified result",
    "owned synthetic Demo Grocer",
    "No purchase action occurred",
}
REQUIRED_RECEIPT_PHRASES = {
    "What the Solari run",
    "$24.20",
    "$23.57",
    "Spend $0.63 more",
    "1.5 lb of extra chicken",
    "Solari Browser found the choices",
    "Solari Sandbox compared whole baskets",
    "SmartCart checked the result",
    "owned Demo Grocer",
    "No retailer account was accessed",
    "No purchase or checkout was automated",
    "33546912947",
    "View raw JSON",
}
FORBIDDEN_SECTION_MARKERS = (
    'class="hero-proof-line',
    'class="frontend-selector',
    'data-frontend=',
    'class="transformation section"',
    'class="execution section"',
    'class="proof section"',
    'data-comparison-state=',
    'data-process=',
    'data-panel=',
)
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
        elif tag == "video":
            for attribute in ("poster", "src"):
                reference = values.get(attribute, "")
                if reference:
                    self.references.append((tag, reference))
        elif tag == "source":
            src = values.get("src", "")
            if src:
                self.references.append((tag, src))


def inspect_case_study(root: Path = ROOT, receipt_path: Path = RECEIPT) -> list[str]:
    errors: list[str] = []
    index = root / "index.html"
    readable_receipt = root / "verified-run.html"
    styles = root / "styles.css"
    script = root / "script.js"
    for path in (
        index,
        readable_receipt,
        styles,
        script,
        root / "assets" / "smartcart-food-stage.jpg",
        root / "assets" / "social-preview.jpg",
        root / "assets" / "favicon.svg",
        root / "assets" / "smartcart-before-solari.mp4",
        root / "assets" / "smartcart-before-solari-poster.jpg",
        root / "assets" / "smartcart-after-solari.mp4",
        root / "assets" / "smartcart-after-solari-poster.jpg",
    ):
        if not path.is_file():
            errors.append(f"missing required case-study file: {path.relative_to(root)}")
    if errors:
        return errors

    source = index.read_text(encoding="utf-8")
    receipt_source = readable_receipt.read_text(encoding="utf-8")
    javascript = script.read_text(encoding="utf-8")
    dynamic_source = source + "\n" + javascript
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

    receipt_parser = LandingParser()
    receipt_parser.feed(receipt_source)
    if receipt_parser.lang != "en" or not receipt_parser.viewport:
        errors.append("verified-run.html: language and viewport metadata are required")
    if receipt_parser.main_count != 1 or receipt_parser.h1_count != 1 or not receipt_parser.skip_link:
        errors.append("verified-run.html: expected one main, one h1, and an accessible skip link")
    for phrase in REQUIRED_RECEIPT_PHRASES:
        if phrase.casefold() not in receipt_source.casefold():
            errors.append(f"verified-run.html: missing readable receipt marker {phrase!r}")
    if "verified-run.html" not in source:
        errors.append("index.html: primary evidence links must lead to the readable verified run")
    if source.count("evidence/live/smartcart-solari-v4-qualification-33546912947.json"):
        errors.append("index.html: raw JSON must be secondary to the readable verified run")

    for phrase in REQUIRED_PHRASES:
        if phrase.casefold() not in source.casefold():
            errors.append(f"index.html: missing required product marker {phrase!r}")
    for marker in REQUIRED_LIVE_DEMO_MARKERS:
        if marker.casefold() not in dynamic_source.casefold():
            errors.append(f"case study: missing public live-demo marker {marker!r}")
    for social_marker in ("og:title", "og:description", "og:image", "twitter:card"):
        if social_marker not in source:
            errors.append(f"index.html: missing social preview marker {social_marker}")
    if 'aria-label="Case study navigation"' in source:
        errors.append("index.html: retired top-center case-study navigation must stay removed")
    for comparison_marker in (
        'aria-selected="true" tabindex="0" data-video-mode="after"',
        'data-hero-video',
        'assets/smartcart-before-solari.mp4',
        'assets/smartcart-after-solari.mp4',
    ):
        if comparison_marker not in dynamic_source:
            errors.append(f"index.html: missing accessible comparison state marker {comparison_marker!r}")
    for forbidden_marker in FORBIDDEN_SECTION_MARKERS:
        if forbidden_marker in dynamic_source:
            errors.append(f"case study: retired post-video section marker returned: {forbidden_marker!r}")
    for replay_marker in (
        "DEBUG RECORDED REPLAY · NOT LIVE",
        "Solari does not run inside the video",
        "BEFORE SOLARI · RECORDED APP FLOW · NOT LIVE",
        "AFTER SOLARI · DEBUG RECORDED REPLAY · NOT LIVE",
        "The retailer screen is recorded context, not a current price or availability claim",
        "the separate receipt proves the real eight-item Browser and Sandbox run",
    ):
        if replay_marker.casefold() not in dynamic_source.casefold():
            errors.append(f"index.html: missing native/provider separation marker {replay_marker!r}")
    for implementation_marker in (
        'https://smartcart-solari-beta.vercel.app/public-demo/v1/solari/research',
        'method: "POST"',
        "AbortController",
        "PUBLIC_DEMO_TIMEOUT_MS",
        "credentials: \"omit\"",
        "textContent",
        "replaceChildren",
        "approvedReplayURL",
        'parsed.protocol === "https:"',
        'host.endsWith(".getsolari.com")',
        'host === "pinetree-browser-replays.s3.us-west-1.amazonaws.com"',
    ):
        if implementation_marker not in javascript:
            errors.append(f"script.js: missing bounded live-demo behavior {implementation_marker!r}")
    for unsafe_dynamic_html in (".innerHTML", "insertAdjacentHTML", "document.write"):
        if unsafe_dynamic_html in javascript:
            errors.append(f"script.js: public result rendering must not use {unsafe_dynamic_html}")
    if "<iframe" in source.casefold():
        errors.append("index.html: Browser replay must remain a validated outbound link, never an iframe")
    video_tag = re.search(r"<video\b[^>]*>", source, flags=re.IGNORECASE)
    if (
        video_tag is None
        or "playsinline" not in video_tag.group(0).casefold()
        or "controls" in video_tag.group(0).casefold()
        or "data-video-play" not in source
        or "autoplay" in source.casefold()
    ):
        errors.append("index.html: native replay must use the authored play control, remain inline, and never autoplay")
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
            if tag in {"link", "script", "video", "source"}:
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

    for tag, reference in receipt_parser.references:
        parsed = urlsplit(reference)
        if parsed.scheme or parsed.netloc:
            if tag in {"link", "script", "video", "source"}:
                errors.append(f"verified-run.html: remote assets are forbidden: {reference}")
            elif parsed.hostname not in ALLOWED_REMOTE_HOSTS:
                errors.append(f"verified-run.html: unapproved remote link: {reference}")
            continue
        if reference.startswith("#"):
            if reference[1:] not in receipt_parser.ids:
                errors.append(f"verified-run.html: missing fragment target: {reference}")
            continue
        target = deploy_mapped.get(parsed.path, (root / parsed.path).resolve())
        if not target.exists():
            errors.append(f"verified-run.html: broken local/deployment reference: {reference}")

    for accessibility_key in ('"ArrowRight"', '"ArrowLeft"', "setHeroVideoMode", "heroVideo.load()"):
        if accessibility_key not in javascript:
            errors.append(f"script.js: missing accessible comparison behavior {accessibility_key}")
    if "prefers-reduced-motion" not in javascript or "prefers-reduced-motion" not in styles.read_text(encoding="utf-8"):
        errors.append("case study must honor prefers-reduced-motion in CSS and JavaScript")

    for filename, expected_hash in VIDEO_SHA256.items():
        video_path = root / "assets" / filename
        if video_path.is_file():
            video_hash = hashlib.sha256(video_path.read_bytes()).hexdigest()
            if video_hash != expected_hash:
                errors.append(f"case-study video bytes drifted for {filename}: {video_hash}")

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
