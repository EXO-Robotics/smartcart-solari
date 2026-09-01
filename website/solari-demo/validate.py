#!/usr/bin/env python3
"""Validate the dependency-free SmartCart × Solari replay and controlled catalog."""

from __future__ import annotations

import json
import math
import re
import sys
from html.parser import HTMLParser
from itertools import product
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parent
CANONICAL_FIXTURE = ROOT.parents[1] / "contracts" / "fixtures" / "v1" / "solari" / "chicken-parmesan-walmart-result.json"
V1_RECEIPT = ROOT.parents[1] / "evidence" / "live" / "smartcart-solari-live-proof-33519606791.json"
V3_RECEIPT = ROOT.parents[1] / "evidence" / "live" / "smartcart-solari-v3-qualification-33533170189.json"
LEGACY_PRODUCT_IDS = {"10414680", "10534084", "623835750", "10452414", "10307238", "47088917"}
CURRENT_PRODUCT_SPECS = {
    "dg-chicken-value-3lb": (3, "lb", 947),
    "dg-chicken-rightsize-1lb": (1, "lb", 500),
    "dg-penne-value-16oz": (16, "oz", 124),
    "dg-penne-rightsize-12oz": (12, "oz", 165),
    "dg-parmesan-value-6oz": (6, "oz", 208),
    "dg-parmesan-rightsize-3oz": (3, "oz", 242),
}
V4_PRODUCT_SPECS = {
    "dg4-chicken-value-3lb": (3, "lb", 813), "dg4-chicken-organic-1-5lb": (1.5, "lb", 876), "dg4-chicken-free-range-3lb": (3, "lb", 1392),
    "dg4-penne-value-16oz": (16, "oz", 124), "dg4-penne-glutenfree-24oz": (24, "oz", 1198),
    "dg4-olive-oil-value-17floz": (17, "fl oz", 612), "dg4-olive-oil-organic-17floz": (17, "fl oz", 736), "dg4-olive-oil-smooth-16floz": (16, "fl oz", 675),
    "dg4-heavy-cream-value-16floz": (16, "fl oz", 296), "dg4-heavy-cream-organic-16floz": (16, "fl oz", 587),
    "dg4-parmesan-value-6oz": (6, "oz", 208), "dg4-parmesan-frigo-5oz": (5, "oz", 328), "dg4-parmesan-kraft-6oz": (6, "oz", 498),
    "dg4-garlic-bulb-8ct": (8, "count", 78), "dg4-garlic-peeled-6oz": (6, "oz", 307), "dg4-garlic-minced-8oz": (8, "oz", 312),
    "dg4-lemon-each-1ct": (1, "count", 64), "dg4-lemon-organic-2lb": (2, "lb", 392), "dg4-parsley-bunch-1ct": (1, "count", 98),
}
ALLOWED_REMOTE_HOSTS = {"www.walmart.com", "github.com", "exo-robotics.github.io"}
FORBIDDEN_STOCK_CLAIM_PATTERNS = (
    r"\bavailability\b",
    r"\bin\s*stock\b",
    r"\bout\s*of\s*stock\b",
    r"\bstock(?:ed|ing|level|status)?\b",
)


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
    if {item.get("retailerProductID") for item in observations} != LEGACY_PRODUCT_IDS:
        errors.append("fixture must contain exactly the six reviewed product IDs")
    for item in observations:
        if item.get("collectionMethod") != "smartcart-seeded-fixture-replay":
            errors.append(f"{item.get('observationID')}: invalid replay collection method")
        if not item.get("observedAt") or not item.get("sourceURL"):
            errors.append(f"{item.get('observationID')}: missing timestamp or source URL")
        if item.get("proteinGramsPerPackage") is not None:
            errors.append(f"{item.get('observationID')}: unsupported nutrition evidence must remain null")
    return errors


def validate_catalog(path: Path, *, historical: bool) -> list[str]:
    catalog = json.loads(path.read_text(encoding="utf-8"))
    errors: list[str] = []
    if catalog.get("synthetic") is not True:
        errors.append(f"{path.name}: controlled catalog must be marked synthetic")
    if catalog.get("historical") is not historical or catalog.get("current") is historical:
        errors.append(f"{path.name}: catalog era flags are inconsistent")

    products = catalog.get("products", [])
    product_ids = {item.get("id") for item in products}
    expected_ids = LEGACY_PRODUCT_IDS if historical else set(CURRENT_PRODUCT_SPECS)
    if product_ids != expected_ids:
        errors.append(f"{path.name}: catalog must contain exactly its six expected IDs")
    if not historical:
        serialized = json.dumps(catalog).casefold()
        if "walmart" in serialized or product_ids & LEGACY_PRODUCT_IDS:
            errors.append("current V3 catalog must not expose Walmart or legacy product identity")
        if catalog.get("priceProvenance") != "synthetic-test-data":
            errors.append("current V3 prices must be labeled synthetic test data")
        for product in products:
            expected = CURRENT_PRODUCT_SPECS.get(product.get("id"))
            actual = (product.get("packageValue"), product.get("packageUnit"), product.get("priceCents"))
            if expected != actual:
                errors.append(f"{product.get('id')}: current V3 package or price data drifted")
            if product.get("syntheticPrice") is not True:
                errors.append(f"{product.get('id')}: current V3 price must be explicitly synthetic")
    elif catalog.get("priceProvenance") != "historical-synthetic-test-data":
        errors.append("legacy V1 prices must be labeled historical synthetic test data")

    script = (ROOT / "retailer" / "retailer.js").read_text(encoding="utf-8")
    for attribute in (
        "solariProduct", "productId", "productName", "packageValue",
        "packageUnit", "priceCents", "currency", "catalogEra", "syntheticPrice",
    ):
        if f"dataset.{attribute}" not in script:
            errors.append(f"controlled catalog renderer missing dataset.{attribute}")
    if "legacy-catalog.json" not in script:
        errors.append("controlled catalog renderer must preserve historical V1 routing")
    return errors


def validate_current_product_output(renderer_path: Path, catalog_path: Path) -> list[str]:
    """Fail closed if the generated current product surface implies stock state."""
    renderer = renderer_path.read_text(encoding="utf-8")
    render_product = renderer.split("function renderProduct", 1)[-1].split("function renderCatalog", 1)[0]
    catalog = catalog_path.read_text(encoding="utf-8")
    errors: list[str] = []

    for label, source in (("renderer", render_product), ("current catalog", catalog)):
        for pattern in FORBIDDEN_STOCK_CLAIM_PATTERNS:
            if re.search(pattern, source, flags=re.IGNORECASE):
                errors.append(f"{label} must not generate availability or stock claims")
                break

    for attribute in ("catalogEra", "syntheticPrice"):
        if f"article.dataset.{attribute}" not in render_product:
            errors.append(f"current product output must preserve data-{re.sub(r'(?<!^)(?=[A-Z])', '-', attribute).lower()}")
    return errors


def validate_v4_catalog(path: Path, renderer_path: Path) -> list[str]:
    catalog = json.loads(path.read_text(encoding="utf-8"))
    errors: list[str] = []
    if catalog.get("catalogVersion") != "smartcart.demo-grocer.v4" or catalog.get("synthetic") is not True or catalog.get("current") is not True or catalog.get("historical") is not False:
        errors.append("V4 catalog identity and synthetic-current markers must remain explicit")
    products = catalog.get("products", [])
    if {item.get("id") for item in products} != set(V4_PRODUCT_SPECS):
        errors.append("V4 catalog must contain exactly the nineteen owned dg4 candidate IDs")
    serialized = json.dumps(catalog).casefold()
    if "walmart" in serialized or any(str(product_id) in serialized for product_id in LEGACY_PRODUCT_IDS):
        errors.append("V4 catalog must not expose retailer names or legacy retailer product IDs")
    for product in products:
        expected = V4_PRODUCT_SPECS.get(product.get("id"))
        actual = (product.get("packageValue"), product.get("packageUnit"), product.get("priceCents"))
        if expected != actual:
            errors.append(f"{product.get('id')}: V4 package or synthetic price data drifted")
        if product.get("syntheticPrice") is not True:
            errors.append(f"{product.get('id')}: V4 price must be explicitly synthetic")
    renderer = renderer_path.read_text(encoding="utf-8")
    for marker in ("solariProduct", "catalogEra", "productId", "packageValue", "packageUnit", "priceCents", "syntheticPrice", "current-v4"):
        if marker not in renderer:
            errors.append(f"V4 renderer missing required evidence marker {marker}")
    return errors


def validate_v3_policy_math(path: Path) -> list[str]:
    catalog = json.loads(path.read_text(encoding="utf-8"))
    grouped: dict[str, list[dict[str, object]]] = {"chicken": [], "penne": [], "parmesan": []}
    required_ounces = {"chicken": 24, "penne": 12, "parmesan": 3}
    for item in catalog.get("products", []):
        product_id = str(item.get("id", ""))
        group = next((name for name in grouped if product_id.startswith(f"dg-{name}-")), None)
        if group:
            package_ounces = float(item["packageValue"]) * (16 if item["packageUnit"] == "lb" else 1)
            count = math.ceil(required_ounces[group] / package_ounces)
            grouped[group].append({
                "id": product_id,
                "count": count,
                "lineCents": int(item["priceCents"]) * count,
                "overbuyOunces": package_ounces * count - required_ounces[group],
            })

    if any(len(options) != 2 for options in grouped.values()):
        return ["current V3 policy requires exactly two candidates per ingredient"]

    baskets = []
    for choices in product(*(grouped[name] for name in ("chicken", "penne", "parmesan"))):
        baskets.append({
            "ids": tuple(choice["id"] for choice in choices),
            "counts": tuple(choice["count"] for choice in choices),
            "cents": sum(choice["lineCents"] for choice in choices),
            "overbuy": sum(choice["overbuyOunces"] for choice in choices),
        })
    baseline = min(baskets, key=lambda basket: basket["cents"])
    eligible = [basket for basket in baskets if basket["cents"] <= baseline["cents"] + 75]
    winner = min(eligible, key=lambda basket: (basket["overbuy"], basket["cents"], basket["ids"]))
    expected_ids = (
        "dg-chicken-rightsize-1lb",
        "dg-penne-value-16oz",
        "dg-parmesan-value-6oz",
    )

    errors: list[str] = []
    if baseline["cents"] != 1279:
        errors.append("current V3 minimum-cost basket must remain $12.79")
    if winner["cents"] != 1332 or winner["ids"] != expected_ids or winner["counts"] != (2, 1, 1):
        errors.append("current V3 $0.75 premium policy must select the expected $13.32 basket")
    if baseline["overbuy"] - winner["overbuy"] != 16:
        errors.append("current V3 policy must avoid exactly 16 oz of overbuy")
    return errors


def validate_v1_receipt(path: Path) -> list[str]:
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"prior V1 live receipt unreadable: {error}"]

    errors: list[str] = []
    if receipt.get("workflow", {}).get("runID") != "33519606791":
        errors.append("prior V1 live receipt must bind run 33519606791")
    execution = receipt.get("execution", {})
    expected = {
        "assuranceScope": "first-party-execution-receipt",
        "browser": "solari-browser-provider-completed",
        "sandbox": "solari-sandbox-provider-completed",
        "fixtureReplay": False,
    }
    for key, value in expected.items():
        if execution.get(key) != value:
            errors.append(f"prior V1 live receipt execution.{key} must equal {value!r}")
    if receipt.get("useCase", {}).get("retailer") != "SmartCart Demo Grocer synthetic catalog":
        errors.append("prior V1 live receipt must remain scoped to the synthetic Demo Grocer")
    return errors


def validate_v3_receipt(path: Path) -> list[str]:
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"V3 qualification receipt unreadable: {error}"]

    errors: list[str] = []
    if receipt.get("receiptVersion") != "smartcart-solari-v3-qualification-v1":
        errors.append("V3 qualification receipt version drifted")
    if receipt.get("workflow", {}).get("runID") != "33533170189":
        errors.append("V3 qualification receipt must bind run 33533170189")

    execution = receipt.get("execution", {})
    expected_execution = {
        "assuranceScope": "server-side-direct-service-receipt",
        "accessBoundary": "operator-qualification",
        "browser": "solari-browser-provider-completed",
        "sandbox": "solari-sandbox-provider-completed",
    }
    for key, value in expected_execution.items():
        if execution.get(key) != value:
            errors.append(f"V3 qualification receipt execution.{key} must equal {value!r}")

    expected_products = {
        "dg-chicken-rightsize-1lb",
        "dg-penne-value-16oz",
        "dg-parmesan-value-6oz",
    }
    if set(receipt.get("selectedProductIDs", [])) != expected_products:
        errors.append("V3 qualification receipt selected products drifted")

    basket = receipt.get("basket", {})
    if basket.get("completeness") != "complete" or basket.get("observedSubtotal") != 13.32:
        errors.append("V3 qualification receipt must record the complete $13.32 selected basket")
    comparison = receipt.get("comparison", {})
    expected_comparison = {
        "cheapestAdequateSubtotal": 12.79,
        "selectedSubtotal": 13.32,
        "premiumOverCheapest": 0.53,
        "surplusAvoidedOunces": 16,
        "maxPremiumOverCheapest": 0.75,
    }
    for key, value in expected_comparison.items():
        if comparison.get(key) != value:
            errors.append(f"V3 qualification receipt comparison.{key} must equal {value!r}")
    optimizer = receipt.get("optimizer", {})
    if optimizer.get("authority") != "solari-sandbox" or optimizer.get("policyInvariantsVerified") is not True:
        errors.append("V3 qualification receipt must preserve Sandbox authority and verified policy invariants")
    return errors


def inspect_demo(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    required = [
        "index.html", "styles.css", "app.js", "README.md", "validate.py",
        "retailer/index.html", "retailer/styles.css", "retailer/retailer.js",
        "retailer/catalog.json", "retailer/legacy-catalog.json",
    ]
    required.extend(f"retailer/product/{product_id}.html" for product_id in sorted(LEGACY_PRODUCT_IDS | set(CURRENT_PRODUCT_SPECS)))
    required.extend([
        "retailer-v4/index.html", "retailer-v4/styles.css", "retailer-v4/retailer.js", "retailer-v4/catalog.json",
    ])
    required.extend(f"retailer-v4/product/{product_id}.html" for product_id in sorted(V4_PRODUCT_SPECS))
    for relative in required:
        if not (root / relative).is_file():
            errors.append(f"missing required file: {relative}")
    if errors:
        return errors

    for html in sorted(root.rglob("*.html")):
        errors.extend(validate_html(html))
    errors.extend(validate_replay_fixture(CANONICAL_FIXTURE))
    errors.extend(validate_catalog(root / "retailer" / "catalog.json", historical=False))
    errors.extend(validate_catalog(root / "retailer" / "legacy-catalog.json", historical=True))
    errors.extend(validate_current_product_output(
        root / "retailer" / "retailer.js",
        root / "retailer" / "catalog.json",
    ))
    errors.extend(validate_v3_policy_math(root / "retailer" / "catalog.json"))
    errors.extend(validate_v4_catalog(root / "retailer-v4" / "catalog.json", root / "retailer-v4" / "retailer.js"))
    errors.extend(validate_v1_receipt(V1_RECEIPT))
    errors.extend(validate_v3_receipt(V3_RECEIPT))

    for product_id in CURRENT_PRODUCT_SPECS:
        source = (root / "retailer" / "product" / f"{product_id}.html").read_text(encoding="utf-8")
        for marker in ("Current V3 synthetic", "no retailer affiliation", "no account, cart, fulfillment, payment, or checkout"):
            if marker.casefold() not in source.casefold():
                errors.append(f"{product_id}: current product page missing boundary label {marker!r}")
        if "walmart" in source.casefold() or any(legacy_id in source for legacy_id in LEGACY_PRODUCT_IDS):
            errors.append(f"{product_id}: current product page leaked legacy Walmart identity")
        if any(re.search(pattern, source, flags=re.IGNORECASE) for pattern in FORBIDDEN_STOCK_CLAIM_PATTERNS):
            errors.append(f"{product_id}: current product page must not claim availability or stock state")
    for product_id in LEGACY_PRODUCT_IDS:
        source = (root / "retailer" / "product" / f"{product_id}.html").read_text(encoding="utf-8")
        for marker in ("Historical V1 synthetic", "immutable evidence URLs", "no account, cart, fulfillment, payment, or checkout"):
            if marker.casefold() not in source.casefold():
                errors.append(f"{product_id}: legacy product page missing historical boundary label {marker!r}")

    current_index = (root / "retailer" / "index.html").read_text(encoding="utf-8")
    if any(product_id in current_index for product_id in LEGACY_PRODUCT_IDS) or "legacy-catalog" in current_index:
        errors.append("default Demo Grocer index must not expose historical V1 products")

    main_text = (root / "index.html").read_text(encoding="utf-8")
    required_markers = [
        "Research current options",
        "V3 Browser + Sandbox qualification complete",
        "33533170189",
        "smartcart-solari-v3-qualification-33533170189.json",
        "33519606791",
        "smartcart-solari-live-proof-33519606791.json",
        "Historical UI replay only",
        "V3 policy result · credentialed qualification",
        "$12.79 cheapest adequate",
        "$13.32 selected",
        "$0.53 premium",
        "16 oz of aggregate surplus avoided",
        "supporting evidence and the owned Browser surface",
        "not the product frontend",
        "does not prove signed native App Attest",
        "physical-device/TestFlight success",
        "Live Walmart Browser execution is disabled",
        "user-controlled retailer handoff",
        "protein/$ is omitted",
    ]
    for marker in required_markers:
        if marker.casefold() not in main_text.casefold():
            errors.append(f"main replay missing trust marker: {marker}")
    handoff_section = main_text.split('id="stage-handoff"', 1)[-1].split("</section>", 1)[0]
    if "walmart" in handoff_section.casefold() or any(product_id in handoff_section for product_id in LEGACY_PRODUCT_IDS):
        errors.append("current Demo handoff must not expose Walmart or legacy V1 identity")
    for marker in ("supporting V3 preview", "owned synthetic Demo Grocer candidates qualified by run 33533170189", "not the product frontend"):
        if marker.casefold() not in handoff_section.casefold():
            errors.append(f"current Demo handoff missing qualification marker: {marker}")
    stale_v3_copy = ("There is no credentialed V3 run yet", "qualification pending", "pending a new credentialed run")
    for marker in stale_v3_copy:
        if marker.casefold() in main_text.casefold():
            errors.append(f"main replay retains stale pre-qualification copy: {marker}")
    superseded_run = "".join(("33505", "918379"))
    superseded_receipt = f"smartcart-solari-live-proof-{superseded_run}.json"
    if superseded_run in main_text or superseded_receipt in main_text:
        errors.append("main replay references superseded credentialed proof")
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
    expected_handoff_ids = {
        "dg-chicken-rightsize-1lb",
        "dg-penne-value-16oz",
        "dg-parmesan-value-6oz",
    }
    handoff_spec = app_text.split("const v3ExpectedHandoff", 1)[-1].split("];", 1)[0]
    if set(re.findall(r'productID: "([^"]+)"', handoff_spec)) != expected_handoff_ids:
        errors.append("current Demo handoff must use only the expected V3 low-waste products")
    render_handoff = app_text.split("function renderHandoff", 1)[-1].split("function replayEvents", 1)[0]
    if "walmart" in render_handoff.casefold() or any(product_id in render_handoff for product_id in LEGACY_PRODUCT_IDS):
        errors.append("current Demo handoff renderer must not use Walmart or legacy V1 data")
    if "synthetic line total" not in render_handoff:
        errors.append("current Demo handoff prices must remain explicitly synthetic")
    if "V3 qualification run 33533170189" not in render_handoff:
        errors.append("current Demo handoff must cite the V3 qualification run")
    return sorted(set(errors))


def main() -> int:
    errors = inspect_demo()
    if errors:
        print(f"Solari demo validation failed ({len(errors)} issue(s)):")
        for error in errors:
            print(f"- {error}")
        return 1
    print("Solari demo validation passed: V3 qualification replay, V4 owned retailer catalog, historical V1 routing, links, and trust markers checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
