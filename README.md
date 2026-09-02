# SmartCart × Solari

> SmartCart could build the shopping list, but it could not tell a shopper which packages made a sensible basket. Solari closes that gap.

[![SmartCart x Solari: from recipe to a priced demo basket](website/solari-case-study/assets/social-preview.jpg)](https://exo-robotics.github.io/smartcart-solari/)

**[Research the meal and watch the before/after case study](https://exo-robotics.github.io/smartcart-solari/)** · **[Read the verified Solari run](https://exo-robotics.github.io/smartcart-solari/verified-run.html)** · [Run the small Cookbook example](https://github.com/EXO-Robotics/solari-cookbook/tree/main/examples/smartcart-basket-research-ts) · [Raw receipt](evidence/live/smartcart-solari-v4-qualification-33546912947.json) · [Source](https://github.com/EXO-Robotics/smartcart-solari)

SmartCart remains the product. The Solari integration has two necessary jobs:

- **Solari Browser** observes owned Demo Grocer products, package sizes, visible synthetic prices, sources, and timestamps.
- **Solari Sandbox** compares complete baskets for cost and leftovers instead of blindly selecting the cheapest package on each line.
- **SmartCart** owns the recipe, pantry, required quantities, verification, presentation, and final shopper-controlled handoff.

In the verified run, Sandbox chose a synthetic **$24.20** basket instead of the **$23.57** cheapest adequate basket. Spending **$0.63** more avoided about **680 g / 1.5 lb of excess chicken**.

**Trust boundary:** owned synthetic retailer only. No retailer login, cart change, purchase, or checkout. Commercial-retailer pricing and App Store distribution are not claimed.

**User evidence:** the public flow is self-serve; independent household feedback is still **PENDING** and is not replaced by internal review scores.

| Before Solari | After Solari |
| --- | --- |
| SmartCart extracts the recipe, applies pantry exclusions, aggregates the list, and opens a retailer. The shopper still has to search and compare packages. | The shopper requests research. Browser observes the approved demo products, Sandbox compares the basket, SmartCart checks the answer, and the shopper keeps the final handoff. |

## Why Solari is necessary

Normal SmartCart already extracts ingredients, excludes pantry items, aggregates quantities, matches seeded products, and calculates conservative package counts when compatible package evidence exists. Its limitation is that seeded or last-known records do not refresh a retailer observation or provide an evidence-backed comparison across candidate baskets.

**Solari Browser** renders only exact allowlisted pages on the repository-owned Demo Grocer. It observes product identity, package quantity/unit, visible synthetic price, source URL, timestamp, and required V4 provenance markers. Static links or replay data cannot prove that a JavaScript-rendered page was observed during a provider run.

**Solari Sandbox** receives only bounded structured requirements and Browser observations. It runs the **relative-surplus-premium-dp-v1** dynamic program: establish the cheapest adequate basket, then minimize aggregate relative surplus among baskets no more than $0.75 above that baseline. The UI calls this dimensionless sum of each line's `(covered - required) / required` ratio the **package-overage score**; it is not presented as a percentage. Sandbox is the global-selection authority. SmartCart independently verifies evidence membership, coverage, package and price arithmetic, cheapest reference, and premium cap, but does not recompute the global argmin.

Desktop is intentionally absent; it has no necessary job.

## Native end-to-end flow

1. The user reviews a recipe or trip and controls pantry exclusions.
2. SmartCart prepares its normal waiting shopping list and original retailer matches.
3. The user explicitly taps **Research current options**.
4. SmartCart normalizes eligible quantities to grams, milliliters, or count and admits only supported exact seeded matches.
5. Ineligible or over-limit lines are recorded as skipped; they are never silently dropped.
6. Solari Browser observes up to 24 exact owned product pages in a fresh logged-out session.
7. Solari Sandbox selects a low-relative-surplus basket within the $0.75 premium cap.
8. The native sheet shows researched coverage, skipped lines, package counts, observed synthetic subtotal, cheapest reference, premium, surplus, source, time, confidence, ambiguity, and cleanup provenance.
9. The user may refresh, edit, stop, or **Continue with original SmartCart list**.
10. Continuation revalidates the original list. Demo Grocer IDs and prices never enter the retailer handoff.

## Architecture

~~~text
Recipe / trip
  -> ingredient extraction -> pantry exclusion -> aggregation
  -> SmartCart exact product preparation
  -> V4 admission: eligible subset + explicit skipped lines
  -> Release-SolariBeta App Attest envelope
  -> protected beta API
  -> Solari Browser: exact owned V4 pages
  -> structured retailer-observation-v4 evidence
  -> Solari Sandbox: relative-surplus premium-cap DP
  -> validated basket-research-result-v4
  -> native comparison
  -> unchanged user-controlled SmartCart retailer handoff
~~~

Production SmartCart is untouched. This public submission was forked from upstream SmartCart commit [fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9). Only the separate Solari schemes point at the protected path. **SmartCart-SolariDevelopment** runs local Apple-development builds through the default-off `/dev` lane (App Attest category 3); **SmartCart-SolariBeta** remains the Release/TestFlight lane (category 2). Normal Release configuration has no Solari endpoint. See the [development-lane boundary](Docs/SOLARI_DEVELOPMENT_LANE.md).

The App Attest transport remains **solari-app-attest-research-envelope-v1**; its signed payload contains exact V4 request bytes. That transport version is not the retailer-evidence version.

## Versioned evidence contract

V4 contracts live in [contracts/v4/solari/](contracts/v4/solari/):

- [request](contracts/v4/solari/basket-research-request.schema.json): 1–12 canonical requirements, 1–3 allowlisted candidates per line, 24-observation ceiling, and fixed optimization policy.
- [observation](contracts/v4/solari/retailer-observation.schema.json): exact requirement/product/source membership, package data, nullable visible price, timestamp, confidence, ambiguity, freshness, controlled location, **current-v4**, and **syntheticPrice: true**.
- [decision](contracts/v4/solari/basket-decision.schema.json): required and covered quantity, package count, surplus, relative surplus, observed line total, evidence reference, and rationale.
- [result](contracts/v4/solari/basket-research-result.schema.json): complete admitted subset, cheapest comparison, Sandbox authority, Browser/Sandbox cleanup, and trust assertions.

Observed product subtotals exclude tax, fees, fulfillment, inventory, discounts, and checkout totals. They are not live or guaranteed retailer prices. Missing evidence cannot become zero; a complete V4 result requires a valid decision for every admitted requirement. Skipped SmartCart lines sit outside that admitted subset and are called out separately in native UI.

## Trust boundaries

- Owned synthetic Demo Grocer only for V4; no authorized real-retailer coverage is claimed.
- Walmart exists only as historical recorded-fixture replay. It is not a current Solari run or current-price evidence.
- No retailer login, account, persistent Browser profile, proxy, stealth, CAPTCHA bypass, cart mutation, order, payment, or checkout. The app/TestFlight lanes do not record Browser sessions. The separate public-demo lane records only the owned, logged-out synthetic catalog so a reviewer can watch the Solari run.
- Browser sessions are fresh and logged out. Persistent profiles are intentionally unused; if enabled, Playwright storage state would contain cookies and per-origin localStorage and must be treated as account authority.
- Solari, App Attest/Redis, and operator credentials remain server-side. No provider or operator bearer secret ships to iOS or web.
- The protected live route is default-off and bound to App Attest, allowlisted app identity/build, one-use challenges, counters, quotas, leases, cancellation, and a runtime kill switch.
- Local-device testing uses a distinct default-off route and Redis namespace. It accepts category 3 only; the existing TestFlight endpoint remains category 2 only. Neither lane accepts a client bearer or fixture fallback.
- Raw HTML, screenshots, recordings, cookies, and signed capability URLs are not retained in immutable result evidence. A fresh public-demo response may include a short-lived HTTPS replay link; the Browser session ID is never stored, and cached responses drop expired replay links.
- Browser/session/client cleanup and Sandbox teardown run on success and failure paths; cleanup failure suppresses success.
- The user always controls final handoff.

Official provider references: [Solari SDK](https://docs.getsolari.com/sdk), [sessions](https://docs.getsolari.com/sessions), [profiles](https://docs.getsolari.com/profiles), [sandboxes](https://docs.getsolari.com/sandboxes), and [API authentication](https://docs.getsolari.com/api-reference).

## Evidence status

V4 is frozen and credential-qualified at runtime **2dd4e6f30be8286a3a8f465c92a56427828a60e2**. [GitHub Actions run 33546912947](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546912947) executed the real Solari Browser and Sandbox providers against an eight-line mass/volume/count trip: 16 fresh observations, eight decisions, and confirmed cleanup. Sandbox selected the 1.5 lb chicken package instead of the cheaper 3 lb bag: a complete synthetic **$24.20** basket versus the **$23.57** cheapest adequate basket, spending **$0.63** within the user's $0.75 cap while avoiding about **680 g / 1.5 lb of excess chicken**. The [sanitized V4 receipt](evidence/live/smartcart-solari-v4-qualification-33546912947.json) binds the request/result digests and exact runtime commit.

That provider receipt is server-side operator qualification. It is not signed native App Attest, real-retailer, device, TestFlight, App Store, or downloadable-app proof. Those gates remain **PENDING**.

Publication commit **8f749e33808119ee403142929da5b757ed934e35** is deployed to the protected beta alias. Vercel deployment **dpl_AkwuZcEt7N6WdFmR6Tye4BrqasbR** reached READY; `/health` returned 200 and the App Attest challenge route returned 201. The [deployment receipt](evidence/live/smartcart-solari-v4-deployment-8f749e3-20260901.json) intentionally does not call that smoke a signed native or provider execution.

Development-lane commit **ad0ba7f97d2a9775349635640e48e677ec5e85be** is deployed at the same alias through Vercel deployment **dpl_DzZH4Bj52xbsAE2Tu6aBMWSCmKER**. Distribution `/v1` remains App Attest category-2-only; the separately namespaced `/dev/v1` lane is category-3-only and accepts the same exact allowlisted beta identity/build. Health returned 200 and both challenge routes returned 201. The [development-lane receipt](evidence/live/smartcart-solari-development-lane-ad0ba7f-20260901.json) records those boundaries without claiming a signed assertion or provider run.

Historical V3 evidence is preserved because it proves the narrower predecessor actually ran:

- Credentialed Browser+Sandbox run [33533170189](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189) at runtime **772e65bac5cabfba8b5e8b6a9482191a715c616a**.
- [V3 qualification receipt](evidence/live/smartcart-solari-v3-qualification-33533170189.json): six fresh owned synthetic observations and a $13.32 selected basket versus $12.79 cheapest, spending $0.53 to avoid 16 oz of surplus.
- Historical V3 deployment **dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r** and [deployment receipt](evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json).

Those receipts do not qualify V4's variable subset, larger catalog, mass/volume/count admission, or DP result.

Signed archive remains **PENDING**: a paired physical iPhone is now connected and already has beta build 4 installed, but that installed build predates the development-lane configuration and still targets the strict distribution route. The available personal team lacks the needed Associated Domains/App Attest capability for the beta bundle, no matching app profile exists, and the Share Extension profile has an application-groups mismatch. Consequently the new `SmartCart-SolariDevelopment` build could not be signed and installed. There is no successful signed-App-Attest, TestFlight, App Store, or downloadable-app claim.

## Setup and targeted validation

Requirements: Xcode, Node.js, npm, Python 3, and—only for an authorized provider qualification—server-side Solari credentials.

~~~bash
git clone https://github.com/EXO-Robotics/smartcart-solari.git
cd smartcart-solari
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
python3 website/solari-demo/validate.py
~~~

### Run the native replay

The fastest reviewer path requires no Solari credential and makes no live-provider claim:

1. Open `SmartCart.xcodeproj` in Xcode.
2. Select the `SmartCart` scheme and an iPhone Simulator.
3. Run the Debug configuration.
4. On Home, tap **Open Solari Demo Meal**.
5. Continue through **Recipe Review** and tap **Research current options**.
6. Inspect the eight-item price check, then choose **Looks good — continue shopping** or **Edit my list**.

The screen is labeled **DEBUG RECORDED REPLAY · NOT LIVE**. Real credentialed Browser + Sandbox execution is proven separately by the immutable V4 receipt linked above.

Exercise focused native contract tests with the SmartCart scheme, then build the beta configuration without implying signing:

~~~bash
xcodebuild \
  -project SmartCart.xcodeproj \
  -scheme SmartCart-SolariBeta \
  -configuration Release-SolariBeta \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
~~~

For a real Xcode-installed development-device run, select `SmartCart-SolariDevelopment`. Its Run action points at `/dev`; its Archive action intentionally uses `Release-SolariBeta` so a distribution archive cannot inherit the development endpoint.

At the presentation release gate: Solari-focused backend **98/98**, full backend **228/228**, focused native **29/29** on iPhone 17 Pro / iOS 26.5 Simulator, case-study **6/6**, replay/owned-catalog **7/7**, dependency audit **0 vulnerabilities**, and unsigned **Release-SolariBeta BUILD SUCCEEDED**. The complete native demo route also passed a fresh UI exercise from Home through the eight-of-eight price check and back into SmartCart's original in-app retailer setup. See [qualification](Docs/SOLARI_QUALIFICATION.md) and the [demo runbook](Docs/SOLARI_DEMO_RUNBOOK.md) for claim boundaries.

## Deployment

Deploy from a clean worktree of the intended immutable submission commit. Run the Vercel CLI from the monorepo root; configure the Vercel project's **Root Directory** as **backend** so shared contracts are packaged through the backend include rules. Configure environment-variable names without committing values; the required names and admission checks are documented in [backend/.env.example](backend/.env.example) and [the runbook](Docs/SOLARI_DEMO_RUNBOOK.md).

The public case study calls a separate default-off route that accepts only one fixed owned eight-item meal. It is isolated from both App Attest routes and is bounded by exact-origin checks, HMAC-pseudonymous per-visitor limits, global quotas, a concurrency lease, a conservative run-unit allowance, cancellation, a runtime kill switch, and a validated cached fallback. It cannot accept arbitrary retailer URLs. A one-time atomic bootstrap may initialize a missing runtime key for a new deployment; a durable marker prevents deletion from silently re-enabling a killed lane. A fresh response may include a short-lived Solari Browser replay; cached responses never expose an expired replay capability.

A successful health/challenge smoke does not prove a provider run. A provider receipt does not prove signed native App Attest. A simulator build does not prove physical-device, TestFlight, App Store, or real-retailer value.

## What differs from normal SmartCart

Normal SmartCart stops at its seeded matching/package math and user-controlled retailer handoff. This fork adds an optional evidence-refresh and bounded basket-comparison step immediately before that same handoff. It does not replace SmartCart's recipe, pantry, list, state, retailer, cart, or checkout contracts.

More detail: [experiment](Docs/SOLARI_EXPERIMENT.md), [threat model](Docs/SOLARI_THREAT_MODEL.md), [qualification](Docs/SOLARI_QUALIFICATION.md), [demo runbook](Docs/SOLARI_DEMO_RUNBOOK.md), and [historical/internal red-team record](Docs/SOLARI_RED_TEAM.md).
