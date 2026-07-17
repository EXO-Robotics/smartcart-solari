# SmartCart for iOS

SmartCart converts a recipe into a persisted, retailer-aware shopping manifest. It applies saved shopping rules, resolves canonical Walmart products when available, labels retailer-search fallbacks, and guides the shopper into a retailer-owned shopping flow.

![SmartCart home screen](SmartCart-Beta2-Simulator.png)

## Beta 3 validation candidate

Import recipe → review ingredients → adjust servings → check pantry → apply preferences → choose a shopping route → confirm the normalized manifest → open the provider handoff.

The app currently supports:

- Camera, photo-library, pasted-text, sample, and backend-mediated recipe-page imports.
- Multi-page Vision OCR with bounding-box reading order, multi-column reconstruction, instruction boundaries, retry, and separate OCR/layout/parser confidence.
- Ingredient editing, sections, fractions, metric/common/count units, compound and equivalent measurements, preparation/brand notes, alternatives, optional-item handling, and serving scaling.
- Persisted pantry decisions, recipes, preferences, store choices, product matches, replacements, manifests, and guided-handoff progress.
- Executable organic, dietary, budget, and store-brand matching rules.
- Canonical `RetailerProductRecord` values with retailer/store identity, item IDs, URLs, package data, observed prices, availability, fulfillment eligibility, source, and observation timestamp.
- Exact Walmart product links where a seeded retailer record exists.
- Explicit, unpriced Walmart-search fallbacks where no eligible exact record exists.
- Single-store pickup planning in the public-beta flow.
- Saved manifests, sharing, and guided product-by-product handoff.
- Pantry-first import review with separate package count, package size/unit, and remaining amount/unit; full/partial/possible coverage now uses remaining stock, with buy-remainder math and an always-available buy-full override.
- Persistent barcode/manual pantry inventory with checksum-valid UPC/EAN/GTIN handling, leading-zero preservation, offline fixtures, required naming for unknown products, and explicit duplicate actions.
- Privacy-limited on-device funnel instrumentation and an internal tester dashboard.
- Credential-free connector contracts for six retailer/affiliate integration shapes.
- A capability-driven Instacart shopping-list route with advisory retailer and fulfillment preferences, manifest safety gates, backend URL caching, in-app Safari presentation, and explicitly self-reported return feedback.
- A guided Walmart Wishlist route with secure Walmart-owned sign-in, exact-product Safari handoff, self-reported per-item outcomes, persistent resume, and an optional validated shared-Wishlist reference.
- A low-friction post-shopping check-in that defaults purchased items from `all available`, `most`, `few`, or `did not shop`, lets excluded items be recovered as elsewhere/substituted purchases, updates pantry stock atomically, records substitutions, and learns a replacement only after explicit opt-in.

The repository also includes a local reference backend in `backend/`, a local deploy-ready business website in `website/`, and explicit human handoff gates in `Docs/`.

## Capability boundary

The demo Walmart adapter supports catalog search, exact product links, pickup and delivery eligibility metadata, and user-driven guided Wishlist handoff. SmartCart can remember a shared Wishlist URL, but it cannot inspect or modify the list.

The Instacart route is wired to the backend-only Developer Platform adapter. Without an approved server-side `INSTACART_API_KEY`, it remains development-ready rather than live. SmartCart never embeds the provider key and never infers that an order was placed merely because the handoff page opened.

It does **not** claim to:

- Programmatically create, modify, or inspect a Walmart cart or Wishlist.
- Link to a Walmart account or verify Walmart sign-in.
- Reserve a pickup window.
- Refresh live prices or inventory.
- Transfer a basket to a delivery provider.
- Submit substitutions, payment, or checkout.

Advanced testing tools can reveal experimental multi-stop, generic delivery-provider, and creator surfaces. These are intentionally outside the public-beta critical path.

## Persistence

State is stored as versioned JSON in Application Support. Schema-v5 adds durable, idempotent shopping sessions, deterministic shopping-state fingerprints, and pantry reconciliation while preserving the schema-v4 Walmart shared-Wishlist reference and earlier shopping, pantry, and analytics state. Existing pantry records derive explicit package and remaining fields during decode. A state file written by a newer app is preserved rather than quarantined or overwritten.

## Release notes and limitations

Photo-import safety thresholds and the required human corpus are documented in
[`Docs/PHOTO_PARSER_RELEASE_GATES.md`](Docs/PHOTO_PARSER_RELEASE_GATES.md).
The executable 25-recipe closed-beta walkthrough and acceptance thresholds are documented in
[`Docs/OCR_PARSER_HUMAN_TEST_PLAN.md`](Docs/OCR_PARSER_HUMAN_TEST_PLAN.md).
Instacart configuration, ownership boundaries, and validation steps are documented in
[`Docs/INSTACART_HANDOFF.md`](Docs/INSTACART_HANDOFF.md).
The guided Walmart setup, data boundary, analytics, and human test matrix are documented in
[`Docs/WALMART_WISHLIST_GUIDE.md`](Docs/WALMART_WISHLIST_GUIDE.md).

See [CHANGELOG.md](CHANGELOG.md) for release history and [Docs/ROADMAP_STATUS.md](Docs/ROADMAP_STATUS.md) for the engineering/human boundary.

## Build and test

Open `SmartCart.xcodeproj`, select the `SmartCart` scheme, choose an iOS 17 or newer simulator, and run.

From Terminal:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The regression suite covers parsing and golden recipes, package conversion, preference constraints, ranking and fallback behavior, barcode lookup, connector truthfulness, product encoding and staleness, persistence/relaunch/migration/corruption, pantry state, local analytics, manifests, replacement persistence, and handoff capabilities.

Before human beta work, follow [Docs/CLOSED_BETA_TEST_PLAN.md](Docs/CLOSED_BETA_TEST_PLAN.md). Partner and public launch work is gated by [Docs/PARTNER_INTEGRATION_CHECKLIST.md](Docs/PARTNER_INTEGRATION_CHECKLIST.md) and [Docs/APP_STORE_RELEASE_CHECKLIST.md](Docs/APP_STORE_RELEASE_CHECKLIST.md).

## License

SmartCart is private proprietary software. See [LICENSE](LICENSE).
