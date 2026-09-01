# SmartCart Solari

SmartCart Solari is an experimental, isolated fork of [SmartCart](https://github.com/EXO-Robotics/smartcart-ios) asking:

> Can Solari turn SmartCart's retailer handoff into a useful agentic shopping workflow without violating user trust?

The V4 product path starts inside native SmartCart. Any trip with waiting items may offer **Research current options** after recipe extraction, pantry exclusion, shopping-list aggregation, and SmartCart's existing product preparation. SmartCart admits only eligible exact matches from the owned Demo Grocer catalog, researches those lines, and reports **Researched X of Y items**. Every skipped line remains visible with a reason and continues unchanged through the normal SmartCart retailer handoff.

This is not arbitrary ingredient coverage. V4 supports 19 owned synthetic candidates in eight seeded groups: chicken, pasta, olive oil, heavy cream, Parmesan, garlic, lemon, and parsley. A request may contain 1–12 eligible requirements, at most three candidates per requirement, and at most 24 observations. Quantities are normalized as mass, volume, or count.

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

Production SmartCart is untouched. This public submission was forked from upstream SmartCart commit [fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9). Only the separate **SmartCart-SolariBeta** scheme / **Release-SolariBeta** configuration points at the beta path. Normal Release configuration has no Solari endpoint.

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
- No retailer login, account, persistent Browser profile, recording, proxy, stealth, CAPTCHA bypass, cart mutation, order, payment, or checkout.
- Browser sessions are fresh and logged out. Persistent profiles are intentionally unused; if enabled, Playwright storage state would contain cookies and per-origin localStorage and must be treated as account authority.
- Solari, App Attest/Redis, and operator credentials remain server-side. No provider or operator bearer secret ships to iOS or web.
- The protected live route is default-off and bound to App Attest, allowlisted app identity/build, one-use challenges, counters, quotas, leases, cancellation, and a runtime kill switch.
- Raw HTML, screenshots, recordings, cookies, and signed capability URLs are not retained in result evidence.
- Browser/session/client cleanup and Sandbox teardown run on success and failure paths; cleanup failure suppresses success.
- The user always controls final handoff.

Official provider references: [Solari SDK](https://docs.getsolari.com/sdk), [sessions](https://docs.getsolari.com/sessions), [profiles](https://docs.getsolari.com/profiles), [sandboxes](https://docs.getsolari.com/sandboxes), and [API authentication](https://docs.getsolari.com/api-reference).

## Evidence status

V4 is frozen and credential-qualified at runtime **2dd4e6f30be8286a3a8f465c92a56427828a60e2**. [GitHub Actions run 33546912947](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546912947) executed the real Solari Browser and Sandbox providers against an eight-line mass/volume/count trip: 16 fresh observations, eight decisions, and confirmed cleanup. Sandbox selected the 1.5 lb chicken package instead of the cheaper 3 lb bag: a complete synthetic **$24.20** basket versus the **$23.57** cheapest adequate basket, spending **$0.63** within the user's $0.75 cap while avoiding about **680 g / 1.5 lb of excess chicken**. The [sanitized V4 receipt](evidence/live/smartcart-solari-v4-qualification-33546912947.json) binds the request/result digests and exact runtime commit.

That provider receipt is server-side operator qualification. It is not signed native App Attest, real-retailer, device, TestFlight, App Store, or downloadable-app proof. Those gates remain **PENDING**.

Publication commit **5164426e39ec5c5524135e82e6689a9fce923387** is deployed to the protected beta alias. Vercel deployment **dpl_2ucnyzesiFFFf7bU7bFraDaVerPh** reached READY; `/health` returned 200 and the App Attest challenge route returned 201. The [deployment receipt](evidence/live/smartcart-solari-v4-deployment-5164426-20260901.json) intentionally does not call that smoke a signed native or provider execution.

Historical V3 evidence is preserved because it proves the narrower predecessor actually ran:

- Credentialed Browser+Sandbox run [33533170189](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189) at runtime **772e65bac5cabfba8b5e8b6a9482191a715c616a**.
- [V3 qualification receipt](evidence/live/smartcart-solari-v3-qualification-33533170189.json): six fresh owned synthetic observations and a $13.32 selected basket versus $12.79 cheapest, spending $0.53 to avoid 16 oz of surplus.
- Historical V3 deployment **dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r** and [deployment receipt](evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json).

Those receipts do not qualify V4's variable subset, larger catalog, mass/volume/count admission, or DP result.

Signed archive remains **PENDING**: three Apple Development identities are visible, but the personal team lacks the needed Associated Domains/App Attest capability for the beta bundle, no matching app profile exists, the Share Extension profile has an application-groups mismatch, and the physical iPhone is offline. There is no TestFlight, App Store, downloadable-app, or signed-native claim.

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

Exercise focused native contract tests with the SmartCart scheme, then build the beta configuration without implying signing:

~~~bash
xcodebuild \
  -project SmartCart.xcodeproj \
  -scheme SmartCart-SolariBeta \
  -configuration Release-SolariBeta \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
~~~

At qualified V4 source state: focused V3/V4 qualification tests **21/21**, full backend **214/214**, focused native **28/28** on iPhone 17 Pro / iOS 26.5 Simulator, web **7/7**, dependency audit **0 vulnerabilities**, and unsigned **Release-SolariBeta BUILD SUCCEEDED**. The broader native suite retains two pre-existing baseline-failing test methods; V4-focused tests are green. See [qualification](Docs/SOLARI_QUALIFICATION.md) and the [demo runbook](Docs/SOLARI_DEMO_RUNBOOK.md) for claim gates.

## Deployment

Deploy from a clean worktree of the intended immutable submission commit. Run the Vercel CLI from the monorepo root; configure the Vercel project's **Root Directory** as **backend** so shared contracts are packaged through the backend include rules. Configure environment-variable names without committing values; the required names and admission checks are documented in [the runbook](Docs/SOLARI_DEMO_RUNBOOK.md).

A successful health/challenge smoke does not prove a provider run. A provider receipt does not prove signed native App Attest. A simulator build does not prove physical-device, TestFlight, App Store, or real-retailer value.

## What differs from normal SmartCart

Normal SmartCart stops at its seeded matching/package math and user-controlled retailer handoff. This fork adds an optional evidence-refresh and bounded basket-comparison step immediately before that same handoff. It does not replace SmartCart's recipe, pantry, list, state, retailer, cart, or checkout contracts.

More detail: [experiment](Docs/SOLARI_EXPERIMENT.md), [threat model](Docs/SOLARI_THREAT_MODEL.md), [qualification](Docs/SOLARI_QUALIFICATION.md), [demo runbook](Docs/SOLARI_DEMO_RUNBOOK.md), and [historical/internal red-team record](Docs/SOLARI_RED_TEAM.md).
