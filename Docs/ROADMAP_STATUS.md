# SmartCart roadmap execution status

This document separates implemented product foundations from work that legally or operationally requires a person, partner approval, or production credentials.

| Milestone | Engineering state | Ready human step |
| --- | --- | --- |
| 1. Foundation | Complete in Beta 2 | Continue regression testing |
| 2. OCR and recipe engine | Multi-column OCR reconstruction, retry quality selection, source-aware confidence/evidence, conservative corrected-text alignment, sections, package/range/compound measurements, deterministic fixtures, and backend-mediated URL extraction | Complete the 25-recipe acceptance run, then the promotion corpus |
| 3. Product matching | Hard dietary/organic rules, package sizing, deterministic ranking, match reasons, confidence, fallbacks, preferred replacements | Review poor matches from beta sessions |
| 4. Barcode and pantry | VisionKit scanner, validated EAN-8/UPC-A/EAN-13/GTIN-14 resolution, durable user-named mappings, backend-cached Open Food Facts identity with truthful manual fallback, explicit package count/size/unit and remaining amount/unit, conservative identity merging, pantry-first suggestions, remainder math, overrides, fingerprinted shopping sessions, four-way reconciliation, explicit substitution learning, and idempotent schema-v5 persistence | Test camera debounce, catalog/manual fallback, remaining-stock edits, substitution feedback, and relaunch idempotency on a physical iPhone |
| 5. Analytics and testing | Privacy-limited on-device funnel, feature flags, internal tester dashboard, OCR duration/retry metrics | Recruit 20–50 testers and export aggregate observations manually |
| 6. Retail connectors | Shared Shopping Trip experience; bounded credential-free Walmart and Target trips with retailer-scoped setup, explicit Next Item advancement, interruption-safe pause/resume, truthful completion summaries, and optional pantry update; durable state remains in the internal `ShoppingSession`; Kroger and other adapters stay truthfully gated | Human-test Walmart and Target setup, interruption/resume, Next Item, final list opening, and pantry reconciliation, then validate desired partners and request access |
| 6A. Meal Prep Mode | Beta-scoped shared `ShoppingScope`; 1–5 saved recipes, independent servings, conservative aggregation, pantry subtraction, frozen provenance, combined internal `ShoppingManifest`, and the shared Recipe Ready/Shopping Trip/pantry loop | Human-test diverse five-recipe plans, uncertain merges, relaunch recovery, Dynamic Type, and VoiceOver before broadening scope |
| 7. Backend and security | Local reference service plus bounded recipe-page fetch/extraction, cached food-identity lookup, mock sessions, OAuth PKCE primitives, manifest sync, analytics ingestion, cache, affiliate abstraction, rate limiting, and redacted logs | Validate publisher/catalog compatibility, then select hosting/database/auth vendors and supply secrets through a secure channel |
| 8. Website and business assets | Local deploy-ready website, policies, support, FAQ, disclosures, architecture docs, and press kit | Legal review, buy domain, create support email, and deploy |
| 9. Partner integrations | Adapter slots and capability boundaries are ready | Obtain partner approvals, client IDs, redirect URIs, and affiliate IDs |
| 10. Public launch | Version 0.3.0 candidate, privacy manifest, test plan, partner checklist, and release checklist | Apple Developer/TestFlight/App Store Connect, final legal/privacy review, production services, and launch approval |

## Product truth boundary

- Walmart product records, prices, availability, stores, and pickup windows remain seeded demo data. Target product records and prices are bounded last-known demo data; Target confirms the store and live state.
- No connector programmatically creates a cart, modifies a Wishlist or Shopping List, places a delivery order, reserves pickup, submits a substitution, processes payment, or completes checkout. Walmart and Target are explicitly user-guided; Kroger remains Coming Soon.
- The backend is a local reference implementation with in-memory/demo persistence, not a production service.
- Website files are local and unpublished. Placeholder contact and legal details must be replaced before deployment.
- Production analytics, crash reporting, accounts, cloud sync, and retailer credentials remain disabled.

## Release candidate definition

The repository is ready to enter human validation when the iOS tests, backend tests, website validation, clean secret scan, simulator launch, and saved-flow relaunch all pass on the same candidate commit. The first hands-on gate is `OCR_PARSER_HUMAN_TEST_PLAN.md`; public launch remains blocked until the larger photo corpus and every human gate in `APP_STORE_RELEASE_CHECKLIST.md` pass.
