# SmartCart × Solari

An isolated native SmartCart experiment that asks:

> Can Solari turn SmartCart’s retailer handoff into a useful agentic shopping workflow without violating user trust?

SmartCart already turns reviewed recipes into pantry-aware shopping quantities, aggregates lists, computes conservative package counts when compatible package evidence exists, and opens retailer pages under user control. Its limitation is not package math; it is the absence of a current retailer-observation trail and an evidence-backed comparison across candidate baskets.

This fork adds one optional action to the normal iOS flow. After recipe review, pantry exclusion, and SmartCart’s existing matching work, the shopper taps **Research current options**. A native review sheet explains an evidence-backed low-surplus comparison. The shopper can refresh, edit, stop, or continue with the **unchanged original SmartCart retailer list**. Demo Grocer IDs and prices never enter a retailer queue, cart, or checkout.

## Exact end-to-end demo

The bounded use case is **Chicken Parmesan Pasta**:

1. SmartCart extracts the recipe and the user reviews it in Recipe Ready.
2. Pantry allocation excludes olive oil and garlic.
3. The remaining need is 1.5 lb chicken, 12 oz penne, and 3 oz Parmesan.
4. SmartCart runs its normal product preparation; the user explicitly taps **Research current options**.
5. The signed beta design binds the exact V3 research payload to a one-use Apple App Attest challenge. The transport envelope remains `solari-app-attest-research-envelope-v1`; that envelope version does not make the product “V1” or “V2.”
6. Solari Browser loads six JavaScript-rendered pages on the owned Demo Grocer and observes product identity, package size, visible synthetic price, source, time, and the required `current-v3` / `syntheticPrice` markers.
7. Solari Sandbox evaluates every cross-line combination and selects the lowest-surplus adequate basket whose subtotal is no more than `$0.75` above the cheapest adequate basket.
8. SmartCart verifies schema and request identity, exact sources, freshness, coverage, package arithmetic, cheapest reference, comparison arithmetic, and premium cap. It deliberately does **not** re-run the global argmin; that necessary computation remains Sandbox’s job.
9. The native sheet shows sources, timestamps, confidence, ambiguity, package counts, subtotal, cheapest comparison, premium, and surplus avoided.
10. **Continue with original SmartCart list** revalidates and finalizes only the original retailer matches. The final retailer handoff remains explicit and user controlled.

The credentialed V3 receipt records this synthetic decision:

| Need | Sandbox selection | Package decision | Observed synthetic line total |
| --- | --- | --- | ---: |
| Chicken, 1.5 lb | `dg-chicken-rightsize-1lb` | 2 × 1 lb | $10.00 |
| Penne, 12 oz | `dg-penne-value-16oz` | 1 × 16 oz | $1.24 |
| Parmesan, 3 oz | `dg-parmesan-value-6oz` | 1 × 6 oz | $2.08 |

Selected subtotal is `$13.32`. The cheapest adequate basket is `$12.79`; the selected basket spends `$0.53` more while reducing package surplus from 31 oz to 15 oz, avoiding 16 oz of overage. These are timestamped synthetic observations, not consumer-retailer prices, inventory, checkout quotes, or market-value evidence.

## Why Solari has a necessary job

**Solari Browser** does the interaction work that seeded records and static links cannot: it renders the admitted owned product pages and extracts only structured product evidence. V3 requires exact product/source identity plus page-provided `current-v3` and `syntheticPrice=true` markers. A static fixture cannot establish that a remote JavaScript page was rendered now.

**Solari Sandbox** is the global optimization authority. It normalizes pounds/ounces/counts, computes adequate package counts for each candidate, enumerates cross-line baskets, finds the cheapest adequate reference, applies the `$0.75` premium cap, and minimizes total surplus with deterministic tie-breaks. SmartCart checks safety and arithmetic invariants around that answer without duplicating the global optimizer locally.

**Solari Desktop is not used.** There is no legitimate desktop-only task.

The implementation uses fresh logged-out Browser sessions and an ephemeral Sandbox. Browser pages/session/client close and the Sandbox is killed before success. [Solari documents Browser sessions](https://docs.getsolari.com/sessions), [Browser control](https://docs.getsolari.com/browser-api), and [`sandbox.kill()` teardown](https://docs.getsolari.com/sandboxes).

Persistent Browser profiles are intentionally not used. Solari profiles contain Playwright storage state—cookies and per-origin localStorage—and can represent a real login. Enabling one would require a new consent, retention, access-control, deletion, and retailer-authorization design. See [Solari profiles](https://docs.getsolari.com/profiles).

## Evidence status

- **Credentialed V3 Browser + Sandbox:** GitHub Actions run [`33533170189`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189) passed against qualified runtime SHA `772e65bac5cabfba8b5e8b6a9482191a715c616a`. The [V3 qualification receipt](evidence/live/smartcart-solari-v3-qualification-33533170189.json) records six fresh Browser observations, freshness recomputed at result completion, the Sandbox optimizer result, internally computed result digest, and cleanup. Its access boundary was server-side operator qualification, not a signed iPhone request.
- **Owned pages:** Pages runtime deployment [`33533099042`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533099042) published the six `dg-*` Browser targets used by runtime qualification. Publication-only Pages run [`33534199401`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33534199401) later published the corrected explanatory copy at public head `bc083d6`; it is not a second runtime qualification.
- **Beta backend:** Vercel production deployment `dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r` is READY at alias `https://smartcart-solari-beta.vercel.app`. The immutable host `https://smartcart-solari-beta-iifvcowlq-blake23.vercel.app` was deployment-protected (302/401), while the public alias returned health 200 and challenge 201. The [deployment receipt](evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json) records those outcomes, App Attest/Upstash configuration, and fail-closed V1/live coexistence policy; it does not claim provider execution through the smoke request.
- **Signed native flow:** **PENDING.** Three Apple Development identities are visible, but archive signing failed: the personal team does not support Associated Domains and App Attest for `com.blakestudio.smartcart.solari-beta`, no matching iOS App Development provisioning profile exists, and the Share Extension profile has an application-groups mismatch. The physical iPhone is offline. There is no signed App Attest request, TestFlight build, App Store build, or downloadable-app claim.
- **Historical V1 proof:** run [`33519606791`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33519606791) and its `$12.79` receipt remain prior integration evidence only. They do not prove the V3 catalog or optimizer policy.
- **Walmart:** replay only. The dated Walmart fixture was observed `2026-07-16T12:00:00Z`; it is not current, location-specific, guaranteed, or proof of a Solari run.

The [public web artifact](https://exo-robotics.github.io/smartcart-solari/website/solari-demo/) explains the flow and hosts the owned product surfaces. It is supporting evidence, not the product. The product integration is the native post-pantry/pre-handoff action, and public native use is not claimed without a signed build.

## Architecture and SmartCart boundary

```text
SmartCart Recipe Ready
  -> existing ingredient review
  -> existing pantry allocation and list aggregation
  -> existing product preparation
  -> user taps Research current options
  -> App Attest v1 envelope around exact V3 payload
  -> beta admission: kill switch, one-use challenge, replay/idempotency,
     quotas, concurrency lease, bounds, cancellation, aggregate deadline
  -> Solari Browser: six owned current-v3 synthetic observations
  -> Solari Sandbox: global surplus-within-price-cap optimization
  -> backend schema + invariant validation and resource cleanup
  -> native evidence validation and two-minute in-memory cache
  -> native comparison sheet
  -> explicit continuation with unchanged original SmartCart retailer list
```

SmartCart’s parser, ingredient identity, pantry allocation, Meal Prep aggregation, quantity engine, product matching, `AppModel` state, Safari queue, and user-confirmed pantry reconciliation remain authoritative. The experiment creates no parallel recipe parser, pantry, retailer account, cart, order, checkout, or purchase-history model.

Production SmartCart remains untouched. `Config/Release.xcconfig` contains no Solari endpoint. Only the separate `SmartCart-SolariBeta` scheme / `Release-SolariBeta` configuration points to the beta host and uses bundle ID `com.blakestudio.smartcart.solari-beta`.

## Versioned evidence and provenance

The current research payload and response use V3 contracts:

- [`basket-research-request.schema.json`](contracts/v3/solari/basket-research-request.schema.json) — exactly three canonical requirements, two admitted candidates each, and the low-surplus policy.
- [`retailer-observation.schema.json`](contracts/v3/solari/retailer-observation.schema.json) — source, time, price/package fields, confidence/ambiguity, freshness, controlled location, `current-v3`, and `syntheticPrice`.
- [`basket-decision.schema.json`](contracts/v3/solari/basket-decision.schema.json) — required/covered quantity, package count, surplus, line total, evidence reference, and rationale.
- [`basket-research-result.schema.json`](contracts/v3/solari/basket-research-result.schema.json) — selected basket, cheapest reference comparison, optimizer authority, cleanup provenance, and trust assertions.

Apple challenge, registration, and `solari-app-attest-research-envelope-v1` schemas remain under [`contracts/v2/solari/`](contracts/v2/solari/). The envelope carries the exact base64-encoded V3 request bytes; changing those bytes invalidates the assertion binding.

Unknown versions, non-UUID or duplicate identities, unadmitted products/sources, missing or false current/synthetic markers, stale/future observations, incompatible units, invalid coverage/math, cheapest-reference or premium-cap mismatch, arbitrary substitution text, or missing Browser/Sandbox/App Attest/cleanup provenance fail closed. Missing price is nullable and partial totals stay nullable; missing data is never treated as `$0.00`. Protein-per-dollar is absent without separately attributable nutrition evidence.

## Trust boundaries and intentionally absent automation

- Visible prices are timestamped observations, not live/guaranteed pricing, inventory, tax, fees, fulfillment, or checkout totals.
- Demo Grocer is owned and synthetic. It proves the integration, not value against a real retailer.
- No profiles, recording, screenshots, raw HTML in the current V3 structured path, proxy, stealth, captcha solving, login, retailer account, cookies/localStorage, cart/list/order mutation, payment, or checkout.
- The retailer handoff is explicit. Research never silently changes original retailer matches; a visited page is not purchase evidence.
- `SOLARI_API_KEY`, Upstash credentials, and control-plane secrets are server only. Signed capability URLs are treated as secrets and never returned in evidence. [Solari API authentication and capability URLs](https://docs.getsolari.com/api-reference) document why.
- Release-SolariBeta has no fixture bypass. Debug replay is clearly labeled and never claimed as Browser, Sandbox, or App Attest execution.
- Runtime kill switch, per-key/global quotas, concurrency lease, bounded request/body/candidate sizes, one aggregate deadline, client-cancellation propagation, 75-second native request / 90-second resource timeouts, and a two-minute/maximum-eight-entry memory cache limit spend and stale reuse. Explicit refresh creates a fresh request identity and evicts the prior plan entry before refetching.
- Cleanup failure suppresses success. Sandbox receives structured public evidence, not credentials, raw pages, cookies, or capability URLs; no claim is made that Sandbox egress is blocked.

Live Walmart research is disabled without documented written authorization. Walmart’s [Terms of Use](https://www.walmart.com/help/article/walmart-com-terms-of-use/3b75080af40340d6bbd596f116fae5a0) restrict automated retrieval; Target’s [Terms & Conditions](https://www.target.com/c/terms-conditions/-/N-4sr7l) restrict unauthorized agents and extraction. V1 fails closed unless retailer authorization gates are explicitly configured, and the beta configuration rejects co-deployment with the operator-live route.

See the [experiment design](Docs/SOLARI_EXPERIMENT.md), [threat model](Docs/SOLARI_THREAT_MODEL.md), [qualification](Docs/SOLARI_QUALIFICATION.md), [runbook](Docs/SOLARI_DEMO_RUNBOOK.md), and [internal red-team log](Docs/SOLARI_RED_TEAM.md).

## Setup and tests

Use a clean isolated submission checkout; never deploy from production SmartCart or a dirty worktree. From the monorepo root:

```sh
git switch feat/native-solari-beta
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
python3 -m unittest discover -s website/solari-demo/tests -v
```

Focused native tests:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:SmartCartTests/SolariEvidenceContractTests
```

Unsigned generic beta build:

```sh
xcodebuild build \
  -project SmartCart.xcodeproj \
  -scheme SmartCart-SolariBeta \
  -configuration Release-SolariBeta \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Current evidence for qualified runtime `772e65b`: focused Solari backend 72/72, full backend 202/202, focused native 22/22 on iPhone 17 Pro / iOS 26.5 Simulator, web 7/7, generic unsigned Release-SolariBeta build PASS, and `npm audit` 0 vulnerabilities.

## Deployment

The linked Vercel project Root Directory is `backend/`, but CLI commands run from the clean monorepo root so `backend/` and shared `contracts/` are available. `backend/vercel.json` packages shared contracts with `includeFiles`.

```sh
git status --short
git rev-parse HEAD
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
vercel link
vercel deploy --prod
```

Do not `cd backend`, use `--cwd backend`, or change the configured Root Directory. Configure environment **names**, never values, in Vercel: `SOLARI_API_KEY`, `SOLARI_DEMO_RETAILER_BASE_URL`, `SOLARI_BETA_ENABLED`, `KV_REST_API_URL`, `KV_REST_API_TOKEN`, `SOLARI_BETA_RUNTIME_KEY`, `SOLARI_APP_ATTEST_TEAM_ID`, `SOLARI_APP_ATTEST_BUNDLE_ID`, `SOLARI_APP_ATTEST_ALLOWED_BUILDS`, the `SOLARI_APP_ATTEST_*` / `SOLARI_BETA_*` controls in [`backend/.env.example`](backend/.env.example), `SOLARI_BROWSER_BASE_URL`, `SOLARI_SANDBOX_BASE_URL`, `SOLARI_BROWSER_TIMEOUT_MS`, `SOLARI_SANDBOX_TIMEOUT_MS`, `SOLARI_REQUEST_TIMEOUT_MS`, `SOLARI_MAX_BODY_BYTES`, `SOLARI_RATE_LIMIT_PER_MINUTE`, and `SOLARI_TRUST_FORWARDED_FOR`.

`SOLARI_OPERATOR_TOKEN` and `SOLARI_LIVE_EXECUTION_ENABLED` belong only to operator qualification and must not be compiled into iOS/web. Production beta configuration fails closed if the V1 operator-live surface can coexist. Walmart authorization variables remain unset/false without actual written permission.

## Qualification summary

| Evidence | Result |
| --- | --- |
| Qualified runtime | `772e65bac5cabfba8b5e8b6a9482191a715c616a` |
| Focused / full backend | 72/72; 202/202 |
| Native / web | 22/22; 7/7 |
| npm audit | 0 vulnerabilities |
| Generic unsigned Release-SolariBeta build | PASS |
| Owned product Pages at runtime qualification | run `33533099042` |
| Credentialed V3 Browser + Sandbox | run `33533170189`; PASS |
| Vercel production | `dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r`; READY |
| Physical signed archive / signed App Attest | **PENDING — entitlement/profile blockers; phone offline** |
| TestFlight / App Store / downloadable app | **PENDING** |

## Repository provenance

This public submission is [`EXO-Robotics/smartcart-solari`](https://github.com/EXO-Robotics/smartcart-solari), isolated from production [`EXO-Robotics/smartcart-ios`](https://github.com/EXO-Robotics/smartcart-ios). It started from clean upstream commit [`fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9). Production SmartCart was not redirected or modified by deployment work.

Runtime provenance is pinned to `772e65bac5cabfba8b5e8b6a9482191a715c616a` by the credentialed qualification and Vercel receipts. Documentation, evidence publication, and supporting-site copy may be committed later; those publication-only changes do not retroactively become the runtime SHA. This README intentionally does not invent a self-referential “final publication commit.”

For upstream SmartCart context, see [Roadmap Status](Docs/ROADMAP_STATUS.md), [Trip Intelligence](Docs/TRIP_INTELLIGENCE_MCP.md), and the [backend README](backend/README.md).

## License

See [LICENSE](LICENSE). Public visibility does not alter its terms.
