# SmartCart roadmap execution status

This document separates implemented product foundations from work that legally or operationally requires a person, partner approval, or production credentials.

| Milestone | Engineering state | Ready human step |
| --- | --- | --- |
| 1. Foundation | Complete in Beta 2 | Continue regression testing |
| 2. OCR and recipe engine | Multi-image Vision OCR, retry path, expanded fractions/ranges, normalization, confidence report, golden corpus tests | Test real screenshots and cookbook photos |
| 3. Product matching | Hard dietary/organic rules, package sizing, deterministic ranking, match reasons, confidence, fallbacks, preferred replacements | Review poor matches from beta sessions |
| 4. Barcode and pantry | VisionKit scanner, Simulator UPC entry, offline lookup fixtures, persistent pantry inventory and preferred products | Test camera scanning on a physical iPhone |
| 5. Analytics and testing | Privacy-limited on-device funnel, feature flags, internal tester dashboard, OCR duration/retry metrics | Recruit 20–50 testers and export aggregate observations manually |
| 6. Retail connectors | Credential-free contracts for Walmart, Instacart, Kroger, Target, Amazon Fresh, and generic affiliate handoff | Validate desired partners and request access |
| 7. Backend and security | Local reference service, mock sessions, OAuth PKCE primitives, manifest sync, analytics ingestion, cache, affiliate abstraction, rate limiting, redacted logs | Select hosting/database/auth vendors and supply secrets through a secure channel |
| 8. Website and business assets | Local deploy-ready website, policies, support, FAQ, disclosures, architecture docs, and press kit | Legal review, buy domain, create support email, and deploy |
| 9. Partner integrations | Adapter slots and capability boundaries are ready | Obtain partner approvals, client IDs, redirect URIs, and affiliate IDs |
| 10. Public launch | Version 0.3.0 candidate, privacy manifest, test plan, partner checklist, and release checklist | Apple Developer/TestFlight/App Store Connect, final legal/privacy review, production services, and launch approval |

## Product truth boundary

- Walmart product records, prices, availability, stores, and pickup windows remain seeded demo data.
- No connector creates a cart, wishlist, delivery order, pickup reservation, substitution, payment, or checkout.
- The backend is a local reference implementation with in-memory/demo persistence, not a production service.
- Website files are local and unpublished. Placeholder contact and legal details must be replaced before deployment.
- Production analytics, crash reporting, accounts, cloud sync, and retailer credentials remain disabled.

## Release candidate definition

The repository is ready to enter human validation when the iOS tests, backend tests, website validation, clean secret scan, simulator launch, and saved-flow relaunch all pass. Public launch remains blocked until every human gate in `APP_STORE_RELEASE_CHECKLIST.md` is checked.
