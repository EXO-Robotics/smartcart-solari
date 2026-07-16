# Changelog

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
