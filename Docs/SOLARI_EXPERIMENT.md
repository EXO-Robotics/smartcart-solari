# Solari experiment design

## Research question and success condition

Can retailer-page research plus isolated basket computation improve SmartCart’s existing retailer handoff without taking authority away from the shopper?

Success is not “the agent bought groceries.” It is an auditable recommendation that starts from SmartCart’s reviewed recipe and pantry-derived need, ties every retailer claim to dated source evidence, makes package math reproducible, keeps missing/ambiguous evidence visible, and leaves the final handoff to the user. No retailer account, cart, checkout, or payment authority is acquired.

## Existing SmartCart boundary

SmartCart’s established flow is recipe import/extraction → Recipe Ready correction → pantry allocation → shopping-list/Meal Prep aggregation → product matching/exceptions → user-driven Safari Shopping Trip → optional user-confirmed pantry reconciliation.

- `RecipeParser` and ingredient identity remain authoritative; the contextual classifier is shadow-only.
- `PantryMatchingService` conservatively determines full, partial, or possible coverage and does not treat uncertain cross-unit stock as exact coverage.
- `MealPrepAggregationService` combines reviewed recipes while retaining uncertain/incompatible lines for review.
- `RetailerCatalogService` provides bounded seeded matches and explicit search fallbacks; it does not refresh live prices.
- `AppModel` owns UI/state and versioned persistence. Existing shopping sessions are frozen historical records.

The experiment must not silently mutate prepared trips, purchase state, pantry, or retailer account state.

At the upstream baseline, the Release app points only selected capabilities such as barcode identity and Weekly Meals at the deployed service, while recipe-page import is unconfigured/hidden. The wider Node application is explicitly local/demo and the deployed surface has no retailer research/scraping route. `/v1/solari/research` is additive in this isolated fork; it does not alter the production SmartCart remote or make the local/demo account and retailer handoff routes production-ready.

## Chosen V1

The fixed product demo is Chicken Parmesan Pasta. After pantry allocation, olive oil and garlic are excluded and the remaining need is chicken 1.5 lb, penne 12 oz, and Parmesan 3 oz.

There are two clearly separate evidence modes:

1. **Walmart fixture replay.** Dated upstream SmartCart observations (`2026-07-16T12:00:00Z`) for products `10414680`, `10534084`, and `10452414` produce one package each and a historical fixture estimate of $12.79. This is the realistic retailer recommendation demo, but it is not live research.
2. **Owned Demo Grocer live path.** Solari Browser may load only repository-controlled Demo Grocer product pages, and Solari Sandbox evaluates the resulting structured observations. This is the executable proof of necessary Browser + Sandbox usage without scraping a third-party retailer.

Live Walmart research is disabled and fails closed without documented written authorization. Walmart’s current [Terms of Use](https://www.walmart.com/help/article/walmart-com-terms-of-use/3b75080af40340d6bbd596f116fae5a0) prohibit automated retrieval/scraping without express prior written consent. Target’s [Terms & Conditions](https://www.target.com/c/terms-conditions/-/N-4sr7l) restrict automated agents and extraction and recognize only Target-approved Agentic Commerce Agents. This is an explicit product/security control.

## Responsibilities

### SmartCart iOS

- Supplies reviewed, post-pantry ingredient needs.
- Requests research through the SmartCart backend, never Solari directly.
- Decodes only supported evidence versions.
- Shows evidence mode, source, observation timestamp, confidence/ambiguity, package decision, and total completeness.
- Keeps retailer handoff an explicit user action.
- Does not treat a visited page as purchase evidence or update pantry without existing confirmation.

### SmartCart backend

- Keeps `SOLARI_API_KEY` server-side.
- Leaves live execution off by default and requires a separate server/operator Bearer token before any live provider work. Fixture replay remains public and rate-limited; iOS/web never receive the operator token.
- Validates request size, quantities, source identifiers/URLs, evidence mode, and retailer authorization policy.
- Permits the usable live demo only on the owned Demo Grocer allowlist; rejects Target, and rejects Walmart unless both written-authorization gates are present; revalidates every redirect/final URL.
- Starts short-lived Browser/Sandbox resources with bounded timeouts and concurrency/rate controls.
- Converts page output to a retailer observation before Sandbox evaluation.
- Validates all outputs and fails closed.
- Closes the Browser session and Solari Browser client, and kills Sandbox, in `finally` paths.
- Returns explicit fixture/live/unavailable mode without upgrading labels.

The live admission sequence is strict: `executionMode: "live"` → `SOLARI_LIVE_EXECUTION_ENABLED=true` → configured 32–256 character `SOLARI_OPERATOR_TOKEN` → exact constant-time Bearer-token match → retailer/source policy → Browser/Sandbox. A failure returns 403 before the service/provider. Recorded fixture mode bypasses live credentials because it invokes neither Browser nor Sandbox.

### Solari Browser

- Opens an allowlisted owned Demo Grocer product page in a fresh logged-out browser.
- Reads visible identity, package, price, source URL, and context needed to assess ambiguity.
- Emits structured data only.
- Does not sign in, search broadly, click purchase controls, attach a profile, record, proxy, use stealth, solve captchas, or retain raw pages.

Solari’s [session documentation](https://docs.getsolari.com/sessions) says defaults are headless with no profile, recording, proxy, or stealth and documents explicit closure. These optional capabilities stay off.

### Solari Sandbox

- Receives required quantities plus validated structured observations—not raw HTML, cookies, signed endpoints, the Solari key, or user account data.
- Runs deterministic unit normalization, required-package count, candidate evaluation, total calculation, and completeness checks.
- Produces a versioned basket decision referencing exact observation IDs.
- Is killed after the run.

Solari documents [Sandbox](https://docs.getsolari.com/sandboxes) as headless compute with commands/code/files and explicit `kill()`. The experiment does not assume network isolation merely because compute is sandboxed; the job needs no outbound network and receives no reusable secret.

## Evidence model

Two contract layers separate fact from inference:

1. **Retailer observation:** what one permitted product page or dated fixture appeared to show at a specific time.
2. **Basket decision:** what deterministic package/basket logic concluded from a named set of observations and SmartCart needs.

Observation semantics include `retailer-observation-v1`, observation/requirement IDs, collection method, source/retailer product ID, canonical URL, title, package quantity/unit, nullable price/currency, `observedAt`, confidence, ambiguity, location/freshness labels, and a bounded extracted plain-text evidence field. `rawText` is not HTML, a screenshot, or a recording; it is bounded to 12 KB, treated as untrusted, and not logged or stored as session/account state.

Decision semantics include `basket-decision-v1`, exact requirement/observation references, selected package count, normalized coverage/surplus and protein economics where defensible, substitution/ambiguity notes, nullable line totals/currency, and confidence/rationale. The `solari-shopping-research-result-v1` envelope adds nullable subtotal/completeness counts, `smallest-sufficient-package-v1` optimizer provenance, Browser/Sandbox execution provenance, and trust assertions.

Rules:

- Unknown versions, absent/mismatched references, non-finite/negative numbers, unsupported currencies, incompatible units, or disallowed URLs fail closed.
- Replaying a fixture preserves `observedAt`; a separate replay time cannot make it fresh.
- A fixture cannot carry live-Solari mode.
- Missing price remains `null`, never zero.
- A complete total exists only when every included selected line has a validated package count and same-currency price. Otherwise total is `null`; any priced subtotal is separately labeled.
- Protein-per-dollar is omitted unless independently attributable nutrition evidence is present.

Contract authority:

- [`contracts/v1/solari/basket-research-request.schema.json`](../contracts/v1/solari/basket-research-request.schema.json)
- [`contracts/v1/solari/retailer-observation.schema.json`](../contracts/v1/solari/retailer-observation.schema.json)
- [`contracts/v1/solari/basket-decision.schema.json`](../contracts/v1/solari/basket-decision.schema.json)
- [`contracts/v1/solari/basket-research-result.schema.json`](../contracts/v1/solari/basket-research-result.schema.json)
- Authoritative request/result fixtures: [`contracts/fixtures/v1/solari/`](../contracts/fixtures/v1/solari/)
- Submission UI: [`website/solari-demo/`](../website/solari-demo/), which loads the authoritative result fixture rather than maintaining an independent price contract

## Failure behavior

Retailer authorization absence, markup changes, login/consent/captcha walls, redirects outside the allowlist, private-network resolution, timeouts, missing selectors, title/package mismatch, or location ambiguity do not trigger broader browsing. The request is rejected or downgraded with a reason. SmartCart shows research unavailable/partial and preserves its normal handoff/search behavior.

Browser success plus Sandbox failure is not a basket recommendation. Sandbox success against a fixture is not live retailer evidence. UI success is not availability, cart, purchase, device, deployment, or App Store proof.

## Intentionally excluded

- Live Walmart/Target automation without documented authorization.
- Broad retailer coverage or arbitrary web search/candidate discovery.
- Profiles, cookie/localStorage reuse, login, replay, screenshots/raw HTML retention.
- Proxy, stealth, captcha solving, or bypass attempts.
- Cart/list writes, fulfillment, payment, checkout, orders, or purchase verification.
- Solari Desktop.
- Nutrition/protein economics without separate evidence.

Solari [profiles](https://docs.getsolari.com/profiles) store login-bearing Playwright `storageState`, including cookies and origin localStorage. They are excluded because logged-out research does not justify that privacy/authority increase.

## Provenance and qualification

The submission fork begins at clean `upstream/main` commit `fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`. Historical Walmart observations originate from that baseline and retain their historical timestamp. The fixture’s freshness is explicitly stale under the 24-hour live policy; recorded mode admits it only as clearly labeled historical replay, never as refreshed evidence. A fixture receipt identifies submission commit, contract version, fixture ID, command, result, and replay time.

Live qualification additionally requires a server-side `SOLARI_API_KEY`, explicit `SOLARI_LIVE_EXECUTION_ENABLED=true`, a valid server/operator `SOLARI_OPERATOR_TOKEN` supplied as Bearer auth, owned Demo Grocer source, live evidence mode, observation IDs/timestamps/sources, and Browser/Sandbox cleanup proof. Neither credential is shipped to iOS/web. The current construction environment has no key, so no live Solari run is claimed.

See [the demo runbook](SOLARI_DEMO_RUNBOOK.md) and [threat model](SOLARI_THREAT_MODEL.md).
