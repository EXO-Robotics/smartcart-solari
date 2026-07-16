# SmartCart for iOS

SmartCart converts a recipe into a persisted, retailer-aware shopping manifest. It applies saved shopping rules, resolves canonical Walmart products when available, labels retailer-search fallbacks, and guides the shopper into retailer checkout.

![SmartCart home screen](SmartCart-Beta2-Simulator.png)

## Beta 2 critical path

Import recipe → review ingredients → adjust servings → check pantry → apply preferences → select one store → resolve products → confirm manifest → open retailer handoff.

The app currently supports:

- Camera, photo-library, pasted-text, sample, and schema.org recipe imports.
- On-device Vision text recognition for recipe images.
- Ingredient editing, fractions, units, optional-item handling, and serving scaling.
- Persisted pantry decisions, recipes, preferences, store choices, product matches, replacements, manifests, and guided-handoff progress.
- Executable organic, dietary, budget, and store-brand matching rules.
- Canonical `RetailerProductRecord` values with retailer/store identity, item IDs, URLs, package data, observed prices, availability, fulfillment eligibility, source, and observation timestamp.
- Exact Walmart product links where a seeded retailer record exists.
- Explicit, unpriced Walmart-search fallbacks where no eligible exact record exists.
- Single-store pickup planning in the public-beta flow.
- Saved manifests, sharing, and guided product-by-product handoff.

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

See [CHANGELOG.md](CHANGELOG.md) for the Beta 2 milestone and its known limitations.

## Build and test

Open `SmartCart.xcodeproj`, select the `SmartCart` scheme, choose an iOS 17 or newer simulator, and run.

From Terminal:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The regression suite covers parsing, package conversion, preference constraints, ranking and fallback behavior, product encoding and staleness, persistence/relaunch/migration/corruption, manifests, replacement persistence, and handoff capabilities.

## License

SmartCart is private proprietary software. See [LICENSE](LICENSE).
