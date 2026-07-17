# SmartCart for iOS

SmartCart converts a recipe into a persisted, retailer-aware shopping manifest. It applies saved shopping rules, resolves canonical Walmart products when available, labels retailer-search fallbacks, and guides the shopper into retailer checkout.

![SmartCart home screen](SmartCart-Beta2-Simulator.png)

## Beta 3 validation candidate

Import recipe → review ingredients → adjust servings → check pantry → apply preferences → select one store → resolve products → confirm manifest → open retailer handoff.

The app currently supports:

- Camera, photo-library, pasted-text, sample, and schema.org recipe imports.
- Multi-page on-device Vision text recognition with retry and confidence diagnostics.
- Ingredient editing, fractions, units, optional-item handling, and serving scaling.
- Persisted pantry decisions, recipes, preferences, store choices, product matches, replacements, manifests, and guided-handoff progress.
- Executable organic, dietary, budget, and store-brand matching rules.
- Canonical `RetailerProductRecord` values with retailer/store identity, item IDs, URLs, package data, observed prices, availability, fulfillment eligibility, source, and observation timestamp.
- Exact Walmart product links where a seeded retailer record exists.
- Explicit, unpriced Walmart-search fallbacks where no eligible exact record exists.
- Single-store pickup planning in the public-beta flow.
- Saved manifests, sharing, and guided product-by-product handoff.
- Persistent barcode/manual pantry inventory with an offline demo UPC cache.
- Privacy-limited on-device funnel instrumentation and an internal tester dashboard.
- Credential-free connector contracts for six retailer/affiliate integration shapes.

The repository also includes a local reference backend in `backend/`, a local deploy-ready business website in `website/`, and explicit human handoff gates in `Docs/`.

## Capability boundary

The demo Walmart adapter supports catalog search, exact product links, pickup and delivery eligibility metadata, and guided product handoff.

It does **not** claim to:

- Create or modify a Walmart cart.
- Save a Walmart wishlist.
- Reserve a pickup window.
- Refresh live prices or inventory.
- Transfer a basket to a delivery provider.
- Submit substitutions, payment, or checkout.

Advanced testing tools can reveal experimental multi-stop, generic delivery-provider, and creator surfaces. These are intentionally outside the public-beta critical path.

## Persistence

State is stored as versioned JSON in Application Support. Schema migration and corrupt-state quarantine are covered by tests.

## Release notes and limitations

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
