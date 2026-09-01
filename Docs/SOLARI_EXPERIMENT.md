# Solari experiment design

## Research question

Can retailer-page research plus isolated basket computation improve SmartCart’s existing handoff without taking authority away from the shopper?

A successful result begins with SmartCart’s reviewed post-pantry need, ties each package/price claim to source and time, makes basket math reproducible, exposes ambiguity, and leaves the original retailer handoff under explicit user control. An agent buying groceries is outside the experiment.

## Existing SmartCart boundary

The established product flow is recipe import/extraction → Recipe Ready correction → pantry allocation → shopping-list or Meal Prep aggregation → product matching/exceptions → user-controlled Safari Shopping Trip → optional user-confirmed pantry reconciliation.

- `RecipeParser` and SmartCart ingredient identity remain authoritative.
- `PantryMatchingService` owns conservative full/partial/possible coverage.
- `MealPrepAggregationService` combines reviewed recipes without silently merging uncertain identities or units.
- SmartCart already computes conservative package counts when exact compatible package evidence exists.
- `AppModel` owns UI state, the retailer queue, and durable trip history.
- A visited retailer page is not purchase evidence. Retailer cart, fulfillment, payment, checkout, and final price remain outside SmartCart’s authority.

The experiment inserts one optional research action after existing preparation and before finalizing the existing retailer queue. It does not change the recipe, pantry, original retailer matches, purchase state, or retailer account.

## Native product flow

The `SmartCart-SolariBeta` flow is user triggered:

1. Recipe Ready presents normal **Shop This Recipe** and, when the beta endpoint is configured, **Research current options**.
2. Both start with SmartCart’s existing preparation path.
3. Research accepts only the canonical three post-pantry Chicken Parmesan Pasta requirements and two owned Demo Grocer candidates per requirement.
4. Apple App Attest is designed to bind a one-use challenge to the exact V3 request bytes. The transport schema remains `solari-app-attest-research-envelope-v1`; V3 identifies the current research product contract.
5. The native review sheet validates and displays the evidence; it never silently replaces the shopping plan.
6. Refresh bypasses a two-minute in-memory cache. Edit/done leaves the retailer list unchanged.
7. **Continue with original SmartCart list** recomputes plan identity and finalizes only the original retailer matches. Demo product IDs, package selections, and synthetic prices are never transferred.
8. Failure offers retry or the normal SmartCart path. No failure authorizes automatic fallback commerce.

Debug can replay a clearly labeled synthetic result without Browser, Sandbox, or App Attest. `Release-SolariBeta` has no replay bypass.

## Supported source and fixed use case

The only current Browser target is the repository-controlled **SmartCart Demo Grocer**. It exposes six JavaScript-rendered `dg-*` product pages:

- chicken: 3 lb / `$9.47`, or 1 lb / `$5.00`;
- penne: 16 oz / `$1.24`, or 12 oz / `$1.65`;
- Parmesan: 6 oz / `$2.08`, or 3 oz / `$2.42`.

Every visible price is synthetic. Each rendered product root must explicitly provide `catalogEra=current-v3` and `syntheticPrice=true`; the Browser provider extracts those fields, and the backend rejects missing, false, or wrong-era markers.

The fixed post-pantry requirement is chicken 1.5 lb, penne 12 oz, and Parmesan 3 oz. The credentialed run selected two 1 lb chicken packages, one 16 oz penne, and one 6 oz Parmesan: `$13.32`, 15 oz aggregate surplus. The cheapest adequate `$12.79` basket has 31 oz surplus, so the policy spends `$0.53`—within a `$0.75` cap—to avoid 16 oz.

The owned source legitimately demonstrates dynamic-page observation, contracts, cleanup, and native UX. It does not establish real-retailer prices, availability, location behavior, consumer savings, or market value.

The Walmart path is historical replay only. Its observations are dated `2026-07-16T12:00:00Z`, and the `$12.79` subtotal is not current/guaranteed. Live Walmart Browser research remains disabled without documented written authorization. Target is unsupported.

## Necessary Solari roles

### Browser: evidence acquisition

For each exact admitted URL, Browser:

1. starts a fresh logged-out session with profiles, recording, captcha, proxy, stealth, and retries disabled;
2. opens the exact owned HTTPS product page;
3. waits for the rendered `[data-solari-product="true"]` marker;
4. reads product identity, package quantity/unit, visible price/currency, title, `current-v3`, and `syntheticPrice` from structured rendered fields;
5. verifies the final URL both before and after page evaluation and verifies the expected product ID;
6. emits a structured, timestamped observation with freshness, source, confidence, ambiguity, controlled location, and no raw HTML;
7. closes each page, then session/client, before success.

Browser is necessary because the evidence is absent from the product page’s initial static HTML and becomes available after JavaScript renders. A fixture or ordinary static link cannot prove that remote rendered state was observed.

### Sandbox: global basket optimization

Sandbox receives only bounded structured requirements, observation/package/price fields, and the fixed policy. It:

1. normalizes pounds and ounces;
2. computes each candidate’s sufficient package count, line total, and surplus;
3. enumerates all cross-line candidate combinations;
4. selects the deterministic cheapest adequate reference;
5. limits eligible baskets to at most `$0.75` above that reference;
6. selects the globally lowest-surplus eligible basket, then subtotal and product ID tie-breaks;
7. returns selected/reference identities and comparison arithmetic.

This is Sandbox’s necessary authority. SmartCart checks that all selected/reference evidence is admitted, covers the need, has valid package/price arithmetic, uses the stable cheapest reference, and respects the premium cap. It does not recompute the global minimum-surplus argmin, so the Sandbox is not decorative duplicated computation.

The Sandbox uses an ephemeral base template, receives no Solari/retailer/App Attest credentials or capability URLs, and is killed in `finally`. No volume, snapshot, profile, browser state, or account data is attached. No claim is made that egress is disabled.

### Why no Desktop

The task requires rendered web observation and headless computation. Desktop would add a larger capability surface without a distinct job, so it is intentionally absent.

Solari references: [Quickstart](https://docs.getsolari.com/quickstart), [Browser sessions](https://docs.getsolari.com/sessions), [Browser API](https://docs.getsolari.com/browser-api), [profiles](https://docs.getsolari.com/profiles), [Sandboxes](https://docs.getsolari.com/sandboxes), and [API authentication/capabilities](https://docs.getsolari.com/api-reference).

## Architecture and admission

```text
Release-SolariBeta app
  -> reviewed SmartCart requirement fingerprint
  -> one-use App Attest challenge
  -> solari-app-attest-research-envelope-v1
       payloadBase64 = exact solari-shopping-research-request-v3 bytes
  -> beta API admission
       feature/runtime kill switches
       app/build/key/counter/signature/request binding
       one-use challenge + idempotency
       per-key/global quotas + concurrency lease
       exact owned source/candidate/policy bounds
       request cancellation + aggregate deadline
  -> Solari Browser observations v3
  -> Solari Sandbox decision/result v3
  -> backend contract and policy-invariant verification
  -> cleanup before response
  -> native validation and native review
  -> unchanged original SmartCart retailer handoff
```

The beta endpoint is `https://smartcart-solari-beta.vercel.app`. Deployment is live and protected; a valid signed App Attest/native request has not yet run. The credentialed V3 proof used the same Browser/Sandbox service through an operator-only server-side qualification boundary. Those are separate evidence claims.

## V3 evidence contract

The research evidence is versioned under [`contracts/v3/solari/`](../contracts/v3/solari/):

| Contract | Purpose |
| --- | --- |
| `solari-shopping-research-request-v3` | exact demo, canonical quantities, six candidate IDs, source policy, fixed optimization policy |
| `retailer-observation-v3` | product/source/time/package/price, confidence/ambiguity, freshness, controlled location, current/synthetic markers |
| `basket-decision-v3` | observation reference, package count, coverage, surplus, line total, rationale |
| `solari-shopping-research-result-v3` | selected basket, cheapest comparison, optimizer authority, cleanup and trust provenance |

The App Attest transport remains under [`contracts/v2/solari/`](../contracts/v2/solari/) and uses `solari-app-attest-research-envelope-v1`. Transport envelope and research payload versions are intentionally independent.

Validation fails closed on altered request bytes; duplicate/non-UUID IDs; unknown candidates; wrong source; stale/future/mismatched freshness; wrong `catalogEra` or `syntheticPrice`; missing package/price evidence; incompatible units; invalid coverage or subtotal; incorrect cheapest reference; premium above `$0.75`; unadmitted substitution text; missing cleanup/provenance; or any account/cart/checkout assertion.

Missing prices remain `null`; a partial result cannot masquerade as a complete total. The current fixed V3 qualification requires a fully priced complete three-line basket. Protein-per-dollar remains `null` because the pages provide no separately attributable protein evidence.

## Trust and operational boundary

- No live/guaranteed retailer price or availability claim.
- No profile, recording, screenshot, raw HTML in the current structured path, proxy, stealth, captcha, login, cookies/localStorage, retailer session, cart/list/order, payment, or checkout.
- `SOLARI_API_KEY`, Upstash credentials, operator tokens, and signed provider capability URLs are server-only.
- Persistent profiles are not used; if enabled they would retain cookies/localStorage and real login authority.
- The beta feature and runtime kill switch fail closed. Quotas, concurrency lease, body/candidate limits, aggregate deadline, cancellation, and cleanup constrain spend.
- Native cache is memory-only, maximum eight entries, two-minute TTL, request/plan keyed, and bypassed by refresh.
- Resource cleanup is part of success: Browser page/session/client close and Sandbox kill are confirmed before response/receipt.
- SmartCart’s original retailer handoff and pantry reconciliation remain explicit user decisions.

## Deliberate limits

- One fixed recipe and owned synthetic catalog, not broad retailer support.
- No real retailer value claim until an authorized API/feed or written automation permission exists.
- No nutrition economics without attributable evidence.
- No tax, fees, inventory, substitution availability, fulfillment, or checkout estimate.
- No signed physical-device App Attest proof yet; archive, TestFlight, App Store, and downloadable native build remain pending.
- No autonomous purchase and no claim that a visited link means bought.

## Current evidence

- code: `ced1154e76a376a7d630900f7c5f4b4317a3932d`;
- Pages: run `33528975472`, six current `dg-*` pages HTTP 200;
- V3 Browser/Sandbox: run `33529059284`, [receipt](../evidence/live/smartcart-solari-v3-qualification-33529059284.json);
- production backend: `dpl_6DgqhKjWN4fm1CHpL6cWcZnWks2x`, [deployment receipt](../evidence/live/smartcart-solari-v3-deployment-20260901.json);
- tests: 71/71 focused backend, 201/201 full backend, 20/20 focused native, 6/6 web, `npm audit` 0;
- generic unsigned Release-SolariBeta build: PASS;
- signed iPhone/App Attest/TestFlight/App Store: PENDING.
