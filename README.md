# SmartCart × Solari

An isolated SmartCart experiment that asks:

> Can Solari turn SmartCart’s retailer handoff into a useful agentic shopping workflow without violating user trust?

SmartCart already converts a reviewed recipe into pantry-aware shopping quantities, computes conservative package counts when exact compatible package evidence exists, and opens retailer-owned pages under user control. Its original limitation is evidence freshness and comparison: seeded or last-known product records do not provide a current observation trail or an evidence-backed comparison across candidates.

This fork adds one optional step in the normal Recipe Ready flow: after pantry exclusion and product preparation, the shopper can tap **Research current options**. SmartCart then requests a bounded product comparison, presents the evidence in a native basket-review sheet, and still requires the shopper to choose **Continue to retailer**. It never buys anything.

## Current evidence status

Three claims are deliberately separate:

1. **Walmart replay:** the public interactive demo replays dated upstream Walmart observations. It does not invoke Solari and is not current retailer evidence.
2. **Credentialed Solari proof:** GitHub Actions run [`33519606791`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33519606791) successfully ran Solari Browser and Solari Sandbox against the owned synthetic Demo Grocer at exact commit `eee8c840b59def4428548c66203304193fa93520`. The sanitized [live receipt](evidence/live/smartcart-solari-live-proof-33519606791.json) records six Browser observations, three Sandbox decisions, cleanup, and a synthetic `$12.79` subtotal.
3. **Native beta productization:** commits `9369d70`, `2516414`, and `eee8c84` add the normal post-pantry/pre-handoff UI, V2 evidence contracts, Apple App Attest request binding, Upstash-backed replay protection/quotas, and the dedicated `Release-SolariBeta` deployment configuration. The backend is deployed, but public native use remains **PENDING** until an allowlisted TestFlight build on a physical iPhone produces a real App Attest vector.

The deployed beta API base is `https://smartcart-solari-beta.vercel.app` ([health](https://smartcart-solari-beta.vercel.app/health); Vercel production deployment `dpl_FD8iBpRhvmEckcUm7oo7v5tMoxdh`). Its versioned [deployment receipt](evidence/live/smartcart-solari-beta-deployment-20260901.json) records READY status and smoke evidence: health `200`, challenge issuance `201`, invalid attestation `403`, and consumed-challenge replay `403`. These checks prove deployed routing, Upstash challenge lifecycle, and fail-closed rejection—not a valid Apple-signed attestation.

Commit `c11d8c7` publishes the two immutable receipts and this native-product evidence narrative. The runtime and deployment receipts remain pinned to implementation commit `eee8c84`; documentation publication does not relabel that execution identity.

## End-to-end use case

The bounded demo is **Chicken Parmesan Pasta**:

1. SmartCart extracts the recipe and the user reviews it in Recipe Ready.
2. Pantry allocation excludes olive oil and garlic.
3. The remaining need is 1.5 lb chicken, 12 oz penne, and 3 oz Parmesan.
4. SmartCart performs its normal product preparation, then the user explicitly selects **Research current options**.
5. The beta admits one to three waiting items with reviewed quantities and exact candidates from the owned Demo Grocer catalog.
6. On a signed beta build, Apple App Attest binds a one-use challenge to the exact V2 request bytes before backend admission.
7. Solari Browser reads the admitted JavaScript-rendered product pages and produces structured, timestamped observations.
8. Solari Sandbox normalizes compatible units, computes required package counts, and selects the smallest sufficient observed basket.
9. SmartCart validates versions, request/product/source identity, freshness, package arithmetic, subtotal completeness, provenance, and trust assertions before showing anything.
10. The shopper reviews source, timestamp, confidence, ambiguity, package count, observed subtotal, and limitations, then either edits, refreshes, falls back to normal SmartCart, or continues to the existing retailer handoff.

The canonical historical Walmart replay remains:

| Need | Walmart fixture product | Package decision | Historical fixture price |
| --- | --- | --- | ---: |
| Chicken, 1.5 lb | `10414680` | 1 × 3 lb | $9.47 |
| Penne, 12 oz | `10534084` | 1 × 16 oz | $1.24 |
| Parmesan, 3 oz | `10452414` | 1 × 6 oz | $2.08 |

Its observation time is `2026-07-16T12:00:00Z`; its `$12.79` estimate is historical seeded data, not current or guaranteed pricing, location-specific availability, or proof of a Solari run.

## Why Solari is necessary

**Solari Browser** performs the interaction job that static catalog records cannot: load an admitted JavaScript-rendered product page and record the identity, package, visible price, exact source URL, timestamp, confidence, and ambiguity actually observed. The only live target is SmartCart’s owned synthetic Demo Grocer. Browser sessions are fresh and logged out; profiles, recording, proxies, stealth, captcha solving, account access, cart actions, and checkout are disabled.

**Solari Sandbox** performs a separate isolated computation job: normalize pounds/ounces/counts, compare admitted candidates, calculate package counts and surplus, choose the smallest sufficient priced basket, and return a versioned decision. It receives structured public observations and quantities—not raw HTML, credentials, signed capability URLs, cookies, or account data. SmartCart independently verifies the resulting arithmetic before accepting it.

**Solari Desktop is not used.** There is no legitimate desktop-only task in this workflow.

The owned Demo Grocer proves the integration and safety architecture; it is synthetic and does not establish real-retailer usefulness, inventory, pricing, or market value. A consumer rollout requires an authorized retailer API/feed or written automation permission.

Official Solari references: [Quickstart](https://docs.getsolari.com/quickstart), [Browser sessions](https://docs.getsolari.com/sessions), [profiles](https://docs.getsolari.com/profiles), [Sandboxes](https://docs.getsolari.com/sandboxes), and [API authentication/capabilities](https://docs.getsolari.com/api-reference).

## Architecture

```text
Recipe / reviewed Meal Prep
  -> existing extraction and correction
  -> existing pantry allocation and shopping-list aggregation
  -> existing product preparation
  -> user taps Research current options
  -> App Attest one-use challenge + assertion over exact V2 request bytes
  -> SmartCart beta backend admission
       runtime kill switch
       build/device/request verification
       replay protection + idempotency
       per-key/global quotas + concurrency lease
       owned-source and request bounds
  -> Solari Browser structured observations
  -> Solari Sandbox basket decision
  -> backend schema validation + cleanup before response
  -> native independent validation + two-minute in-memory cache
  -> evidence-backed basket review
  -> user chooses normal retailer handoff
```

The original parser, ingredient identity, pantry allocation, Meal Prep aggregation, quantity engine, product matching, `AppModel` state, Safari shopping queue, and user-confirmed pantry reconciliation remain authoritative. The Solari path does not create another recipe parser, pantry, retailer account, cart, order, checkout, or purchase-history model.

Production SmartCart remains unchanged. `Config/Release.xcconfig` has no Solari endpoint; only the separate `SmartCart-SolariBeta` scheme and `Release-SolariBeta` configuration use `https://smartcart-solari-beta.vercel.app` and the distinct `com.blakestudio.smartcart.solari-beta` identity.

See [the experiment design](Docs/SOLARI_EXPERIMENT.md) and [threat model](Docs/SOLARI_THREAT_MODEL.md).

## V1 proof and V2 native evidence contracts

The Actions receipt is the immutable V1 execution proof for commit `eee8c84`: it records the actual Browser/Sandbox run against the owned catalog. It does not claim that the native V2/App Attest path ran.

The productized native boundary uses V2 basket contracts:

- [`basket-research-request.schema.json`](contracts/v2/solari/basket-research-request.schema.json): `solari-shopping-research-request-v2`
- [`retailer-observation.schema.json`](contracts/v2/solari/retailer-observation.schema.json): `retailer-observation-v2`
- [`basket-decision.schema.json`](contracts/v2/solari/basket-decision.schema.json): `basket-decision-v2`
- [`basket-research-result.schema.json`](contracts/v2/solari/basket-research-result.schema.json): `solari-shopping-research-result-v2`
- [`app-attest-research-envelope.schema.json`](contracts/v2/solari/app-attest-research-envelope.schema.json): one-use challenge, key ID, assertion, and exact payload bytes

Challenge and initial-attestation contracts live beside them under [`contracts/v2/solari/`](contracts/v2/solari/). Unknown versions, replayed challenges/counters, altered payload bytes, unsupported products, duplicate identities, mismatched URLs, stale/future observations, incompatible units, invalid math, incomplete totals presented as complete, or missing Browser/Sandbox/App Attest provenance fail closed.

Missing price stays `null`, never `$0.00`. A complete subtotal exists only when every selected line has compatible package evidence and a visible same-currency price. Protein-per-dollar remains absent without separate attributable nutrition evidence.

## Trust and operational boundaries

- Observed prices are timestamped evidence, not guarantees, inventory claims, or checkout quotes.
- Walmart is replay-only. Walmart live automation additionally requires explicit written-authorization gates; none are present. Target live research is unsupported.
- No retailer account, persistent Browser profile, login, cookies/localStorage, cart/list/order, fulfillment, payment, checkout, or purchase verification is used.
- `SOLARI_API_KEY`, Upstash credentials, and all control-plane secrets remain server-side. No Solari/operator secret is compiled into iOS or browser code.
- Release-SolariBeta has no fixture bypass. Debug replay is explicitly labeled and does not use App Attest, Browser, or Sandbox.
- The Upstash runtime key is a fail-closed kill switch checked before challenge/attestation/research and polled during live work.
- Admission includes one-use challenges, attested-key/counter verification, request-body binding, idempotency, configurable per-key/global quotas, a concurrency lease, size/time bounds, request-abort propagation, and an aggregate deadline.
- The native cache holds at most eight validated results in memory for two minutes; refresh bypasses it. It is not persisted.
- Browser pages/session/client close and Sandbox is killed before a success response. Cleanup failure suppresses success.
- The final retailer open remains explicit user authority; `visited` is not purchase evidence and pantry changes still require confirmation.

Walmart’s [Terms of Use](https://www.walmart.com/help/article/walmart-com-terms-of-use/3b75080af40340d6bbd596f116fae5a0) prohibit automated retrieval/scraping without express prior written consent. Target’s [Terms & Conditions](https://www.target.com/c/terms-conditions/-/N-4sr7l) prohibit unauthorized agentic tools and data extraction. Respecting those limits is part of the product design.

Persistent Solari profiles are intentionally unused. Solari profiles contain Playwright `storageState`—cookies and per-origin localStorage—and represent a real login. Enabling one would require a new consent, retention, access-control, deletion, and retailer-policy design.

## Setup

Use a clean checkout of the submission branch; do not deploy from the production SmartCart checkout or from a dirty worktree.

From the monorepo root:

```sh
git switch feat/native-solari-beta
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
```

For local fixture replay, start the backend with `npm --prefix backend start`, open `SmartCart.xcodeproj`, and use the normal `SmartCart` Debug scheme. Debug uses the local backend and a clearly labeled recorded replay.

For simulator compilation of the productized configuration:

```sh
xcodebuild build \
  -project SmartCart.xcodeproj \
  -scheme SmartCart-SolariBeta \
  -configuration Release-SolariBeta \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The current focused evidence is 55/55 Solari backend tests, 185/185 full backend tests, 13/13 focused native tests, a passing Release-SolariBeta simulator build, and a separate Debug simulator install/launch. These do not substitute for a signed physical-device run.

## Deployment

The Vercel project’s configured Root Directory must be `backend/`, while the CLI upload/deploy runs from the clean monorepo root so `backend/` and the shared `contracts/` tree are both available to the function packager. Deploy only from a clean worktree at the intended commit:

```sh
git status --short
npm --prefix backend ci
npm --prefix backend run test:solari
vercel link
vercel deploy --prod
```

Configure these names in the Vercel project without placing values in source or documentation:

- `SOLARI_API_KEY`
- `SOLARI_DEMO_RETAILER_BASE_URL`
- `SOLARI_BETA_ENABLED`
- `KV_REST_API_URL`
- `KV_REST_API_TOKEN`
- `SOLARI_BETA_RUNTIME_KEY`
- `SOLARI_APP_ATTEST_TEAM_ID`
- `SOLARI_APP_ATTEST_BUNDLE_ID`
- `SOLARI_APP_ATTEST_ALLOWED_BUILDS`
- the `SOLARI_APP_ATTEST_CHALLENGE_TTL_SECONDS` and `SOLARI_BETA_*_LIMIT`, `*_TTL_SECONDS`, `*_MAX_BODY_BYTES`, and `*_KILL_POLL_MS` controls documented in [`backend/.env.example`](backend/.env.example)
- `SOLARI_BROWSER_BASE_URL` and `SOLARI_SANDBOX_BASE_URL`
- `SOLARI_BROWSER_TIMEOUT_MS`, `SOLARI_SANDBOX_TIMEOUT_MS`, and `SOLARI_REQUEST_TIMEOUT_MS`
- `SOLARI_MAX_BODY_BYTES`, `SOLARI_RATE_LIMIT_PER_MINUTE`, and `SOLARI_TRUST_FORWARDED_FOR`

Do not change the linked project Root Directory from `backend/`, and do not `cd backend` or use `--cwd backend` for this monorepo deployment. `backend/vercel.json` and the root `.vercelignore` package the V2 contracts and Browser runtime assets while excluding native/docs artifacts.

Do not configure `SOLARI_OPERATOR_TOKEN` for the native V2 path; that token belongs to the separate operator/V1 qualification route. Never ship any server secret in `Release-SolariBeta.xcconfig`, an app plist, source, fixture, screenshot, or client log.

The exact procedure and evidence checks are in [the demo runbook](Docs/SOLARI_DEMO_RUNBOOK.md). Exact qualification identities and remaining gates are in [the qualification receipt](Docs/SOLARI_QUALIFICATION.md).

## Qualification summary

| Evidence | Result |
| --- | --- |
| Solari focused backend suite | 55 passed |
| Full backend suite | 185 passed |
| Focused native suite | 13 passed |
| Release-SolariBeta simulator build | PASS |
| Debug simulator installation/launch | PASS |
| Vercel production deployment | `dpl_FD8iBpRhvmEckcUm7oo7v5tMoxdh` — READY |
| Deployed smoke | health 200; challenge 201; invalid 403; replay 403 |
| Credentialed Browser + Sandbox proof | run `33519606791`, commit `eee8c84`, PASS |
| Physical iPhone signing and real signed App Attest vector | **PENDING — 0 valid signing identities** |
| TestFlight/App Store | **PENDING** |

Do not describe the native beta as publicly usable until an allowlisted TestFlight build on a physical iPhone completes the real App Attest registration/assertion/research flow. The owned Demo Grocer remains synthetic; no real-retailer price or market-value claim is supported.

## Provenance

This public submission repository is `EXO-Robotics/smartcart-solari`, isolated from the production `EXO-Robotics/smartcart-ios` remote. It started from clean upstream commit [`fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9).

Native beta implementation sequence:

- `9369d70` — native Recipe Ready research flow and App Attest client
- `2516414` — V2 backend admission, Upstash state/quotas, and App Attest verification
- `eee8c84` — deployable Solari runtime asset packaging

Original SmartCart documentation remains available through [the upstream status index](Docs/ROADMAP_STATUS.md), [trip-intelligence design](Docs/TRIP_INTELLIGENCE_MCP.md), and [backend README](backend/README.md).

## License

See [LICENSE](LICENSE). Public repository visibility does not alter its terms.
