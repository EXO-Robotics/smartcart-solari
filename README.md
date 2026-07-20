# SmartCart for iOS

SmartCart turns a recipe or reviewed Meal Prep plan into a pantry-aware, retailer-matched Shopping Trip. **Recipe Ready** brings ingredient corrections, servings, pantry decisions, retailer settings, and shopping preferences onto one adaptive confirmation screen before opening retailer-owned pages in Safari.

## Current shopping flow

Import a recipe → confirm it in Recipe Ready → start shopping → review only product exceptions → move through retailer pages in one continuous Shopping Trip → optionally update the pantry afterward.

Meal Prep combines one to five reviewed saved recipes conservatively, keeps uncertain ingredients separate until resolved, and then converges into the same Recipe Ready, matching, Shopping Trip, and pantry-update flow as a single recipe.

Home renders, in order: the header, **Start New Recipe**, one conditional **Shopping Trips** section, an optional **Shop Again** card, the preferred-store card, and the checkout trust strip. At standard Dynamic Type sizes, **Take Photo** and **Choose Photo** share the first compact row of a two-column grid, **Paste Link** and **More** share the second compact row, and **Meal Prep Mode** is a full-width action below the grid. Accessibility Dynamic Type sizes stack the four import actions vertically before the same full-width Meal Prep action. This describes rendered order and adaptation, not a guarantee that every action fits in the first viewport on every device.

Recipes is a saved-recipe library with search and a pull-up **Recent Recipes** drawer. Only importing or intentionally opening a whole recipe adds or reorders drawer entries; retailer pages, Shopping Trip resume, replacements, and pantry reconciliation do not. Removing Saved Recipes membership prunes that recipe from recency, but retains the underlying record for historical Shopping Trips and frozen Meal Prep provenance.

The app currently supports:

- Camera, photo-library, pasted-text, sample, and backend-mediated recipe-page imports.
- Multi-page Vision OCR with reading-order reconstruction, instruction boundaries, retry, and separate OCR/layout/parser confidence. Raw observations retain page, normalized geometry, confidence, alternatives, and observation IDs independently from reconstructed layout text, accepted parser text, and ignored source lines.
- Confirmed ingredient edits and deletions are routed through the parent model by stable ingredient ID. Deletion drops only that ingredient's pre-trip match, preserves eligible unchanged waiting matches for selective reuse, rejects any in-flight result invalidated by the deletion, and leaves an existing session-owned Shopping Trip frozen.
- Inline Recipe Ready editing for ingredients, servings, optional items, alternatives, and uncertain quantities, plus compact pantry and trip-settings review.
- Persistent pantry decisions, recipes, preferences, store choices, product matches, replacements, and Shopping Trip progress.
- Organic and dietary preferences filter eligible matches; budget and store-brand preferences rank them.
- Seeded exact Walmart and Target product links when an eligible record exists, and explicit unpriced retailer-search fallbacks otherwise.
- Exception-only product review: high-confidence exact matches continue without another screen; fallbacks and lower-confidence choices require an explicit accept, replacement, manual search, or skip decision.
- A continuous in-app Safari Shopping Trip. **Next Item** becomes available only after the page loads and records only that the shopper chose to advance after viewing it (`visited`); it is not evidence of any retailer, order, or purchase action.
- Durable pause and resume at the current waiting item. Tapping **Pause** or dismissing the retailer page with native close pauses without advancing. A load failure keeps the item waiting and offers retry, external open, skip, or pause.
- A post-trip pantry check-in whose purchase selections remain user-controlled. Home exposes a pantry-update-pending card inside the single **Shopping Trips** section. Opening it reaches the completion surface, where **Yes, update pantry**, **Not yet**, and **Archive without pantry update** remain explicit; archiving hides only the pending card and does not change the pantry, record an outcome, or remove the completed trip.
- Pantry-first review with separate package count, package size/unit, and remaining amount/unit; full/partial/possible coverage uses remaining stock, with buy-remainder math and a buy-full override.
- Persistent barcode/manual pantry inventory with checksum-valid EAN-8/UPC-A/EAN-13/GTIN-14 handling, leading-zero preservation, saved user naming, bundled fixtures, backend-mediated Open Food Facts identity, and explicit duplicate handling. Catalog names remain editable and unverified; no price or availability is inferred.
- Privacy-limited on-device funnel instrumentation and an internal tester dashboard.
- Walmart and Target matching, with Kroger and additional retailers clearly marked Coming Soon.

The contextual ingredient classifier is a `DEBUG` shadow comparison only. The existing `RecipeParser` path remains authoritative for app output; the contextual result is not the production default and must not be described as one. Image-source shadow decisions require strict spatial provenance; structured URL/Pinterest/list sources may use declared ingredient rows; pasted text is handled conservatively. Contextual rescue cannot cross page, column, section, instruction, or metadata boundaries. The labeled evaluation inventory is 144 cases: 120 fixed-corpus cases plus 24 independent development spatial cases. Development-focused gates are green, but the separately run frozen held-out aggregate gate failed on the latest frozen code candidate, so the current closed-beta verdict is **NO-GO**.

This stabilization boundary does not change the documented Recipe Ready, product-exception, Safari Shopping Trip, or user-confirmed pantry-update flow.

The repository also includes a local reference backend in `backend/`, a local deploy-ready business website in `website/`, and explicit human validation gates in `Docs/`.

## Capability boundary

The active app path supports bounded seeded Walmart and Target catalog matching, exact public product links, clearly labeled searches, and user-driven Safari Shopping Trips. SmartCart does not expose delivery providers, pickup scheduling, multiple-store planning, account linkage, list automation, or native cart routes in this branch. Kroger is presentation-only and clearly labeled Coming Soon.

SmartCart does **not**:

- Programmatically create, modify, or inspect a retailer cart, Wishlist, Shopping List, favorites collection, order, or purchase.
- Link to a retailer account, read retailer cookies, or verify sign-in.
- Detect what the shopper did on a retailer page; **Next Item** means only “visited and advanced.”
- Reserve a pickup window, refresh live prices or inventory, or choose fulfillment.
- Transfer a basket, submit substitutions, payment, or checkout.

The selected retailer owns live location confirmation, product availability, final price, substitutions, list and cart state, fulfillment, payment, checkout, and order status.

## Persistence

State is stored as versioned JSON in Application Support. The current schema is v6. Its internal records preserve schema-v5 durable shopping trips and pantry reconciliation, the schema-v4 optional Walmart shared-Wishlist reference, and earlier shopping, pantry, and analytics state. Schema v6 adds Meal Prep scope/snapshots, the backward-compatible `visited` item status, an optional pantry-reminder archive timestamp, OCR source provenance, and optional `savedRecipeIDs` library membership.

For schema-v6 compatibility, an absent `savedRecipeIDs` field infers membership for valid retained non-sample recipes, while a present empty set means the library is intentionally empty; IDs that do not resolve to retained recipes are discarded. A newly imported non-sample recipe is saved by default. Samples remain in a dedicated catalog and are not auto-saved. Removing a recipe from Saved Recipes changes membership and prunes its Recent Recipes entry, while preserving retained recipe records, Shopping Trips, pantry, preferences, and frozen Meal Prep state. Missing optional fields otherwise decode to their prior behavior. A state file written by a newer app is preserved rather than quarantined or overwritten.

## Release notes and limitations

Photo-import safety thresholds and the required human corpus are documented in [`Docs/PHOTO_PARSER_RELEASE_GATES.md`](Docs/PHOTO_PARSER_RELEASE_GATES.md). The executable 25-recipe walkthrough is in [`Docs/OCR_PARSER_HUMAN_TEST_PLAN.md`](Docs/OCR_PARSER_HUMAN_TEST_PLAN.md). Automated development evidence does not replace that physical-device walkthrough, and neither can override a failed frozen held-out gate. The current Walmart Shopping Trip boundary and preserved legacy Wishlist details are in [`Docs/WALMART_WISHLIST_GUIDE.md`](Docs/WALMART_WISHLIST_GUIDE.md).

See [CHANGELOG.md](CHANGELOG.md) for release history and [Docs/ROADMAP_STATUS.md](Docs/ROADMAP_STATUS.md) for the engineering/human boundary.

## Build and test

Open `SmartCart.xcodeproj`, select the `SmartCart` scheme, choose an iOS 17 or newer simulator, and run.

From Terminal, run the eligible development suite while explicitly excluding the frozen held-out selector:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skip-testing:SmartCartTests/ContextualIngredientFilterTests/testFrozenHeldOutCorpusDoesNotRegressAgainstLegacy
```

Then run the frozen held-out aggregate gate separately against the same frozen candidate. Record only its aggregate receipt; do not copy case content into release documentation or tune the frozen candidate from case-level results.

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SmartCartTests/ContextualIngredientFilterTests/testFrozenHeldOutCorpusDoesNotRegressAgainstLegacy
```

The automated suite covers parsing, package conversion, preference constraints, retailer isolation, truthful fallbacks, persistence/relaunch/migration/corruption, Meal Prep, pantry state, product exceptions, Shopping Trip progress, and reconciliation. A closed-beta `GO` requires both automated invocations to pass on the same candidate plus the documented human and physical-device walkthrough. Dynamic Type and VoiceOver remain required human-validation gates; follow [Docs/CLOSED_BETA_TEST_PLAN.md](Docs/CLOSED_BETA_TEST_PLAN.md) before beta promotion. The current candidate remains **NO-GO** because its frozen held-out invocation failed.

Partner and public launch work is gated by [Docs/PARTNER_INTEGRATION_CHECKLIST.md](Docs/PARTNER_INTEGRATION_CHECKLIST.md) and [Docs/APP_STORE_RELEASE_CHECKLIST.md](Docs/APP_STORE_RELEASE_CHECKLIST.md).

## License

SmartCart is private proprietary software. See [LICENSE](LICENSE).
