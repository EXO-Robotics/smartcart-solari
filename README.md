# SmartCart × Solari

An experimental SmartCart fork that asks one bounded question:

> Can Solari turn SmartCart’s retailer handoff into a useful agentic shopping workflow without violating user trust?

SmartCart already turns a reviewed recipe into pantry-aware quantities, computes conservative package counts when it has exact compatible package evidence, and then opens retailer-owned pages for the shopper. Its limitation is evidence freshness and comparison: package math relies on seeded or last-known product records, with no current retailer observation refresh and no evidence-backed checkout comparison across candidates. This fork adds that bounded comparison before the existing user-controlled handoff. It does not add autonomous purchasing.

## The smallest legitimate experiment

The product demo is **Chicken Parmesan Pasta**:

1. SmartCart extracts and reviews the recipe ingredients.
2. Pantry allocation excludes olive oil and garlic.
3. The remaining need is 1.5 lb chicken, 12 oz penne, and 3 oz Parmesan.
4. A Browser adapter turns allowed product pages into structured candidate/product/package/price observations.
5. Solari Sandbox receives only structured observations and required quantities, then runs deterministic unit normalization, package math, and basket evaluation.
6. SmartCart validates the versioned evidence and presents product, package count, observed price, source, timestamp, confidence, ambiguity, and total completeness.
7. The shopper chooses whether to continue to the retailer. The retailer remains authoritative for location, availability, final price, cart, fulfillment, payment, and checkout.

The Walmart path is intentionally a **fixture replay**, not a live scrape. It preserves public exact-product source URLs for user handoff and provenance, but the experiment does not fetch those URLs automatically. Its observations were seeded in upstream SmartCart on `2026-07-16T12:00:00Z`:

| Need | Walmart fixture product | Package decision | Historical fixture price |
| --- | --- | --- | ---: |
| Chicken, 1.5 lb | `10414680` | 1 × 3 lb | $9.47 |
| Penne, 12 oz | `10534084` | 1 × 16 oz | $1.24 |
| Parmesan, 3 oz | `10452414` | 1 × 6 oz | $2.08 |

The fixture checkout estimate is **$12.79**. It is a replay of dated upstream seeded observations: it is not current or guaranteed pricing, not availability evidence, and not proof of a Solari Browser or Sandbox run.

## Why Solari has a necessary job

**Solari Browser** is the live research boundary: it loads JavaScript-rendered product pages and captures the page that was actually seen as a structured observation. In this public build, the usable live demo is the repository’s owned/controlled **Demo Grocer** surface. Live Walmart fails closed unless both written-authorization gates are set; no such authorization is present. Live Target is not supported at all. The implementation does not enable profiles, recording, proxy routing, stealth, captcha solving, account access, cart control, or checkout.

That policy is deliberate. Walmart’s current [Terms of Use](https://www.walmart.com/help/article/walmart-com-terms-of-use/3b75080af40340d6bbd596f116fae5a0) (last updated June 23, 2026) prohibit automated retrieval/scraping without express prior written consent. Target’s [Terms & Conditions](https://www.target.com/c/terms-conditions/-/N-4sr7l) restrict automated agents and data extraction and recognize only Target-approved Agentic Commerce Agents. Respecting those boundaries is part of the trust experiment, not a hidden demo limitation.

**Solari Sandbox** does a distinct computation job: normalize compatible units, calculate required package counts, evaluate candidates, and return a deterministic decision plus completeness and ambiguity. Browser output—not browser control or raw HTML—is the Sandbox input. Sandbox network egress is not assumed to be blocked; the job is designed not to require network access or secrets, and the Sandbox is killed after use.

**Solari Desktop is not used.** No GUI-only desktop application is necessary for controlled-page research or deterministic basket math.

Official Solari references: [Quickstart](https://docs.getsolari.com/quickstart), [browser sessions and lifecycle](https://docs.getsolari.com/sessions), [profiles and stored login state](https://docs.getsolari.com/profiles), [sandboxes and teardown](https://docs.getsolari.com/sandboxes), and [API authentication/capability URLs](https://docs.getsolari.com/api-reference).

## Trust boundary

- **Observed, not promised.** A price appears only with retailer/source, observation timestamp, evidence mode, and confidence. “Observed” never means live, guaranteed, location-correct, or checkout-final.
- **Walmart is replay-only in this submission.** Its evidence is a dated deterministic fixture. The backend rejects live Walmart unless both authorization gates are present; this submission has neither authorization nor a live receipt. Target live research is outside the contract.
- **Location is unresolved unless evidenced.** Walmart fixture data is not tied to the user’s current store or ZIP. Taxes, fees, promotions, memberships, inventory, and checkout total can differ.
- **Partial stays partial.** A basket total is nullable when any included line lacks a trustworthy price or compatible package decision. A priced subtotal is never relabeled as a complete total.
- **No account or purchase authority.** The experiment does not sign in, attach a retailer profile, read cookies, inspect/write a cart or order, choose fulfillment, submit payment, or check out.
- **Server-only credentials.** `SOLARI_API_KEY` and the separate live `SOLARI_OPERATOR_TOKEN` belong only in the backend runtime/operator channel. Neither is compiled into the iOS app or web demo, returned by an API, committed, logged, or sent to a Sandbox job.
- **Live is default-off and operator-gated.** Public, rate-limited `recorded_fixture` requests never invoke Solari. Every `live` request is rejected before provider work unless `SOLARI_LIVE_EXECUTION_ENABLED=true`, a 32–256 character operator token is configured, and the same token arrives as a Bearer credential.
- **Minimal retention.** The durable artifact is normalized evidence/decision JSON. Raw HTML, screenshots, recordings, signed control URLs, cookies, and browser storage are not required or retained.
- **Short-lived compute.** The Browser session closes and the Solari Browser client closes in `finally`; the Sandbox is killed in `finally`. Failure returns unavailable/partial, never invented evidence.
- **User-controlled handoff.** The final action remains an explicit open of a retailer-owned page. “Visited” is not cart/order/purchase proof, and pantry updates remain explicit.

Persistent Solari profiles are intentionally not used. Solari documents a profile as Playwright `storageState` containing cookies and per-origin localStorage and warns that it represents a real login. Enabling one would create account authority and sensitive retained state without a legitimate need. Any future profile use requires new consent, retention, access-control, deletion, and retailer-policy design; it is not a configuration toggle for this experiment.

See [the threat model](Docs/SOLARI_THREAT_MODEL.md) for SSRF, page-content injection, retailer policy/fragility, secrets, cost, retention, evidence expiry, and handoff controls.

## Architecture and product boundaries

```text
Recipe / reviewed Meal Prep
  -> existing extraction and user correction
  -> existing pantry allocation and shopping-list aggregation
  -> SmartCart backend request with required quantities + server-approved sources
  -> Browser observation
       live Solari: owned Demo Grocer only
       Walmart: dated fixture replay only
  -> versioned retailer-observation evidence
  -> Solari Sandbox (live) or deterministic local evaluator (fixture replay)
  -> versioned basket decision
  -> backend validation and evidence receipt
  -> SmartCart comparison UI
  -> user chooses retailer-owned handoff
```

The original SmartCart parser, ingredient identity, pantry allocation, Meal Prep aggregation, quantity engine, retailer matching, and Safari Shopping Trip remain authoritative for their existing responsibilities. The Solari path is an additive research/recommendation seam; it does not create a second recipe parser, pantry, cart, checkout, or purchase-history model. `AppModel` remains the native state owner, versioned persistence remains authoritative for historical trips, and the iOS client receives structured evidence only—it never talks to Solari directly.

The backend is the only live Solari integration boundary. In the upstream baseline, the Release app’s configured remote services are limited and the wider Node application is explicitly local/demo; there is no production retailer-research route. This fork adds `/v1/solari/research` without redirecting production SmartCart. The new boundary applies default-off live admission/operator authentication, request/body/rate/candidate limits, an owned-host allowlist, redirect revalidation, timeouts, schema validation, and cleanup. Untrusted page text is data, never an instruction. The evaluator accepts a narrow JSON payload and fixed deterministic program, not raw HTML or free-form page instructions.

More detail is in [the experiment design](Docs/SOLARI_EXPERIMENT.md). Original SmartCart material remains available in [the upstream documentation index](Docs/ROADMAP_STATUS.md), [trip-intelligence design](Docs/TRIP_INTELLIGENCE_MCP.md), and [backend README](backend/README.md).

## Versioned evidence and provenance

The fork separates two immutable, schema-validated concepts:

- A **retailer observation** binds candidate identity, package, and visible price claims to an observation ID, source URL, observation timestamp, evidence mode, confidence, and ambiguity.
- A **basket decision** binds recipe needs and exact observation IDs to package counts, line economics, substitutions/ambiguities, a nullable subtotal, and completeness.

Unknown versions fail closed. Fixture replay and live Solari are separate evidence modes. Fixture replay retains the original observation time; replay time cannot refresh it. Missing price stays `null`, never `$0.00`. Protein-per-dollar is omitted unless separate attributable nutrition evidence exists. Contract paths and executable fixtures are listed in [the experiment design](Docs/SOLARI_EXPERIMENT.md).

The wire authorities are [`basket-research-request.schema.json`](contracts/v1/solari/basket-research-request.schema.json) (`solari-shopping-research-request-v1`), [`retailer-observation.schema.json`](contracts/v1/solari/retailer-observation.schema.json) (`retailer-observation-v1`), [`basket-decision.schema.json`](contracts/v1/solari/basket-decision.schema.json) (`basket-decision-v1`), and [`basket-research-result.schema.json`](contracts/v1/solari/basket-research-result.schema.json) (`solari-shopping-research-result-v1`). The result also states optimizer method/version, whether Browser/Sandbox actually ran, fixture status, and fixed trust assertions such as no account/cart/checkout access.

## What differs from normal SmartCart

Normal SmartCart uses bounded seeded Walmart/Target matches or explicit unpriced search fallbacks, then moves the user through retailer pages. This fork adds a pre-handoff evidence and basket-decision layer. Its public V1 implements the full Solari Browser path for owned Demo Grocer pages and replays the Walmart product experience with dated fixtures. A credentialed receipt is still required to prove that path ran live. Target and broader real-retailer automation are intentionally outside V1.

This experiment intentionally does **not** automate:

- live Walmart without written authorization, and any live Target retrieval in V1;
- retailer login, accounts, profiles, cookies/localStorage, carts, lists, orders, checkout, payment, fulfillment, or purchase verification;
- arbitrary web search, nationwide/local inventory claims, or broad retailer coverage;
- proxy, stealth, captcha solving, recording/replay, raw-page retention, or Desktop control;
- nutrition inference or protein-per-dollar without separate evidence.

## Setup

Requirements: Node.js 20+, Xcode with an iOS 17+ simulator, and a Solari API key for a credentialed live Demo Grocer run only.

```sh
cd backend
npm install
cp .env.example .env
npm start
```

Fixture replay needs neither Solari nor operator credentials. For an authorized live Demo Grocer operator run, set `SOLARI_API_KEY`, `SOLARI_LIVE_EXECUTION_ENABLED=true`, a random 32–256 character `SOLARI_OPERATOR_TOKEN`, and `SOLARI_DEMO_RETAILER_BASE_URL` to an owned, credential-free public HTTPS `/solari-demo` root. `backend/.env.example` documents the optional Browser base URL, Sandbox base URL, 6-second Browser/10-second Sandbox timeouts, 32 KB request limit, and five-request-per-minute limit. Never add either secret to Xcode, the iOS app, web demo, fixture, snapshot, GitHub commit, or logged command. Open `SmartCart.xcodeproj`, select `SmartCart`, choose an iOS 17+ simulator, and run. Follow [the demo runbook](Docs/SOLARI_DEMO_RUNBOOK.md) for fixture replay and the separately gated live Demo Grocer mode.

### Current evidence status

This construction environment does **not** have `SOLARI_API_KEY`. The bundled fixture replay can prove contracts, validation, basket math, API/UI integration, and truthful labels, but it cannot prove a live Solari Browser/Sandbox run. No live Walmart run should occur even if a key is later set; retailer authorization is a separate required gate.

## Deployment

Deploy only the backend with `SOLARI_API_KEY` and `SOLARI_OPERATOR_TOKEN` in a server-side secret store; live execution remains disabled by default. Keep allowed origins, source hosts, and public endpoint rate limits narrow. Do not expose either credential, session WebSocket/CDP endpoints, profile IDs, Sandbox control URLs, signed upload/download URLs, or preview URLs to the iOS client/frontend. Live Browser targets remain owned Demo Grocer until a retailer-specific authorization record and allowlist change are reviewed. Even an operator-authenticated live Walmart request additionally requires both `SOLARI_RETAILER_RESEARCH_AUTHORIZED=true` and a nontrivial `SOLARI_WALMART_WRITTEN_AUTHORIZATION_REFERENCE`; never set those merely to make a demo pass.

Production readiness additionally requires TLS, secret rotation, log/retention review, retailer-policy review, live cleanup receipts, cost controls, and existing SmartCart device/release gates. A local server, simulator build, public repository, or dated fixture is not production/App Store/live-retailer proof.

## Test and evidence checks

From `backend/`:

```sh
npm run test:solari
npm test
```

Run the focused contract/API/Demo Grocer/fixture commands and repository claim/secret checks listed in [the demo runbook](Docs/SOLARI_DEMO_RUNBOOK.md), then the targeted native tests/build for the recommendation UI seam. The dependency-free submission UI can be served from the repository root at [`/website/solari-demo/`](website/solari-demo/README.md). Preserve test output separately from live evidence: deterministic fixtures prove replay behavior only.

The skeptical-review method, accepted fixes, residual Low findings, and justified SDK-specific rejection are recorded in [the Solari red-team record](Docs/SOLARI_RED_TEAM.md). A score is attributable only to the exact commit named in its review receipt.

## Submission provenance

This is the separate submission repository `EXO-Robotics/smartcart-solari`; it does not redirect or modify the production SmartCart remote. The fork started from clean `upstream/main` commit [`fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9). `upstream` remains `EXO-Robotics/smartcart-ios`; `origin` is the submission repository.

### Internship-brief mapping

The source for this mapping is the internship brief supplied with the submission, summarized here rather than presented as a canonical public rubric. It asks for a real use case, legitimate Solari product usage, and a public GitHub build. This fork maps those to pantry-aware basket comparison; Browser evidence plus Sandbox optimization, each with a distinct necessary job; and this isolated submission repository. No canonical social-post URL, numeric score, or additional rubric is asserted.

## License

See [LICENSE](LICENSE). Public repository visibility does not alter its terms.
