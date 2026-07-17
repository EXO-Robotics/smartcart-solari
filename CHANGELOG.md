# Changelog

## 0.3.0 — Human-validation candidate (unreleased)

- Reconstructs multi-column recipe photos from OCR bounding boxes, preserves bullet continuations, stops at instruction boundaries, and reports layout ambiguity separately from text confidence.
- Adds a permanent 20-ingredient, multi-section recipe fixture plus compound measurements, equivalents, preparation phrases, brand notes, alternatives, and explicit malformed-quantity review.
- Routes URL import through the local recipe-page backend, which enforces HTTPS/redirect/timeout/size/MIME rules, preserves original/final URL provenance, and uses inert JSON-LD or visible-page extraction.
- Adds pantry-first recipe review: imported ingredients are compared with saved inventory, but matches never silently skip a purchase. Testers can use pantry stock, buy only the remainder, or override and buy the full amount.
- Adds editable pantry package amounts and schema-v3 migration of legacy inferred barcode names to `Unknown Product` with required naming.
- Adds validated UPC-A/EAN-13/GTIN-14 resolution, leading-zero preservation, explicit duplicate actions, and no inferred product names, prices, or availability.
- Adds multi-image OCR import, retry diagnostics, expanded fraction/range parsing, ingredient aliases, confidence scoring, and golden recipe tests.
- Adds persistent pantry inventory, physical-device VisionKit barcode scanning, Simulator UPC entry, and a bundled offline demo UPC cache.
- Remembers manual product replacements as preferred matches for later runs.
- Adds privacy-limited on-device funnel events, feature flags, and an internal tester dashboard.
- Adds credential-honest connector profiles for Walmart, Instacart, Kroger, Target, Amazon Fresh, and generic affiliate handoff.
- Adds a local reference backend with mock auth/OAuth foundations, manifests, analytics ingestion, caching, affiliate abstraction, rate limits, and redacted logs.
- Adds an unpublished local business website, policy/support pages, developer docs, and media kit.
- Adds closed-beta, partner-integration, and App Store human handoff checklists.

### Known limitations

- Barcode camera scanning requires a supported physical iPhone; the Simulator uses manual UPC entry.
- Pantry quantity coverage is exact only when saved and recipe units are convertible. Name-only or cross-dimension matches are labeled as possible and require a user decision.
- Recipe URL import requires the local `backend/` service in this validation build; publisher blocks and unsupported pages fall back to pasted text or screenshots.
- Analytics remains local diagnostic state, not a production telemetry or crash-reporting service.
- Backend persistence and authentication are demo/local foundations, not production infrastructure.
- Website/legal text requires owner and legal review before deployment.
- Partner approval, credentials, live catalogs, production services, TestFlight, and App Store submission remain human-gated.

## 0.2.0-beta.1 — Beta 2

SmartCart Beta 2 establishes the first complete closed-beta shopping workflow:

- Imports recipes from photos, camera captures, pasted text, sample data, and supported recipe URLs.
- Reviews and edits parsed ingredients, scales servings, and excludes pantry items.
- Applies persistent organic, dietary, budget, and store-brand preferences.
- Selects a preferred Walmart store and pre-plans a pickup preference.
- Resolves seeded exact Walmart product records when eligible.
- Uses an explicit, unpriced Walmart search fallback when no eligible exact record exists.
- Persists recipes, preferences, pantry choices, store selection, pickup preference, product replacements, manifests, and guided-shopping progress.
- Opens exact retailer items or labeled searches through a guided handoff.
- Adds automated coverage for parsing, package math, matching constraints, retailer links, persistence, migration, corruption recovery, substitutions, manifests, and capability boundaries.

## Known limitations

- Walmart prices, availability, and fulfillment eligibility are seeded demo records, not live commerce data.
- Every seeded price is labeled as demo/last-known and not live; Walmart determines the final price.
- Search fallbacks are not exact products and do not include a SmartCart price.
- SmartCart does not create or modify a Walmart cart or wishlist.
- SmartCart does not reserve a pickup window, submit substitutions, transfer a delivery basket, process payment, or complete checkout.
- Generic delivery-provider and multi-stop surfaces remain experimental and are hidden behind advanced testing tools.
- Store names, distances, addresses, and pickup windows are prototype fixtures.
- Recipe URL import depends on publicly accessible schema.org recipe metadata and may fail on blocked or unsupported pages.
- Product imagery uses local symbols rather than a licensed live retailer image feed.
- Analytics, barcode scanning, live catalog refresh, authentication, and production retailer integrations are not included in this release.
