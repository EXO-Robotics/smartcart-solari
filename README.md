# SmartCart for iOS

SmartCart converts a recipe into a persisted, retailer-aware shopping manifest. It applies saved shopping rules, resolves seeded Walmart or Target products when available, labels retailer-search fallbacks, and guides the shopper into a retailer-owned shopping flow.

![SmartCart home screen](SmartCart-Beta2-Simulator.png)

## Retailer guide branch

Import recipe → review ingredients → adjust servings → check pantry → apply preferences → choose Walmart or Target → review exact products → open the retailer in Safari → confirm purchases → update pantry.

The app currently supports:

- Camera, photo-library, pasted-text, sample, and backend-mediated recipe-page imports.
- Multi-page Vision OCR with bounding-box reading order, multi-column reconstruction, instruction boundaries, retry, and separate OCR/layout/parser confidence.
- Ingredient editing, sections, fractions, metric/common/count units, compound and equivalent measurements, preparation/brand notes, alternatives, optional-item handling, and serving scaling.
- Persisted pantry decisions, recipes, preferences, store choices, product matches, replacements, manifests, and guided-handoff progress.
- Executable organic, dietary, budget, and store-brand matching rules.
- Canonical `RetailerProductRecord` values with retailer/store identity, item IDs, URLs, package data, observed prices, availability, fulfillment eligibility, source, and observation timestamp.
- Exact Walmart and Target product links where a seeded retailer record exists.
- Explicit, unpriced retailer-search fallbacks where no eligible exact record exists.
- One Walmart location used as matching context; Target owns local-store selection after handoff.
- Saved manifests, sharing, and guided product-by-product handoff.
- Pantry-first import review with separate package count, package size/unit, and remaining amount/unit; full/partial/possible coverage now uses remaining stock, with buy-remainder math and an always-available buy-full override.
- Persistent barcode/manual pantry inventory with checksum-valid UPC/EAN/GTIN handling, leading-zero preservation, offline fixtures, required naming for unknown products, and explicit duplicate actions.
- Privacy-limited on-device funnel instrumentation and an internal tester dashboard.
- Dedicated Walmart and Target cards backed by one seeded retailer-guide engine, with Kroger and additional retailers clearly marked Coming Soon.
- Retailer-specific Safari handoffs, clearly labeled search fallbacks, self-reported per-item outcomes, and persistent resume.
- A low-friction post-shopping check-in that defaults purchased items from `all available`, `most`, `few`, or `did not shop`, lets excluded items be recovered as elsewhere/substituted purchases, updates pantry stock atomically, records substitutions, and learns a replacement only after explicit opt-in.

The repository also includes a local reference backend in `backend/`, a local deploy-ready business website in `website/`, and explicit human handoff gates in `Docs/`.

## Capability boundary

The active app path supports bounded seeded Walmart and Target catalog matching, exact public product links, clearly labeled searches, and user-driven Safari handoffs. SmartCart does not expose delivery providers, pickup scheduling, multiple-store planning, account linking, list automation, or native cart routes in this branch. Kroger is presentation-only and clearly labeled Coming Soon. Deeper integrations remain deferred until approved retailer interfaces are available.

It does **not** claim to:

- Programmatically create, modify, or inspect a retailer cart, Wishlist, Shopping List, or favorites collection.
- Link to a retailer account or verify retailer sign-in.
- Reserve a pickup window.
- Refresh live prices or inventory.
- Choose or schedule fulfillment.
- Transfer a basket to a retailer or another provider.
- Submit substitutions, payment, or checkout.

The selected retailer owns live location confirmation, product availability, final price, substitutions, list and cart state, fulfillment, payment, checkout, and order status.

## Persistence

State is stored as versioned JSON in Application Support. Schema-v5 adds durable, idempotent shopping sessions, deterministic shopping-state fingerprints, and pantry reconciliation while preserving the schema-v4 Walmart shared-Wishlist reference and earlier shopping, pantry, and analytics state. Existing pantry records derive explicit package and remaining fields during decode. A state file written by a newer app is preserved rather than quarantined or overwritten.

## Release notes and limitations

Photo-import safety thresholds and the required human corpus are documented in
[`Docs/PHOTO_PARSER_RELEASE_GATES.md`](Docs/PHOTO_PARSER_RELEASE_GATES.md).
The executable 25-recipe closed-beta walkthrough and acceptance thresholds are documented in
[`Docs/OCR_PARSER_HUMAN_TEST_PLAN.md`](Docs/OCR_PARSER_HUMAN_TEST_PLAN.md).
The earlier guided Walmart setup, data boundary, analytics, and human test matrix are documented in
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

The regression suite covers parsing and golden recipes, package conversion, preference constraints, cross-retailer isolation, Walmart and Target adapter contracts, ranking and truthful fallback behavior, barcode lookup, connector truthfulness, product encoding and staleness, persistence/relaunch/migration/corruption, pantry state, local analytics, manifests, replacement persistence, and handoff capabilities.

Before human beta work, follow [Docs/CLOSED_BETA_TEST_PLAN.md](Docs/CLOSED_BETA_TEST_PLAN.md). Partner and public launch work is gated by [Docs/PARTNER_INTEGRATION_CHECKLIST.md](Docs/PARTNER_INTEGRATION_CHECKLIST.md) and [Docs/APP_STORE_RELEASE_CHECKLIST.md](Docs/APP_STORE_RELEASE_CHECKLIST.md).

## License

SmartCart is private proprietary software. See [LICENSE](LICENSE).
