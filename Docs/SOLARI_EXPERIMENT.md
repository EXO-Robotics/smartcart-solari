# Solari experiment design

## Research question

Can retailer-page research plus isolated basket computation improve SmartCart’s existing handoff without taking authority away from the shopper?

Success is an auditable recommendation: it starts from SmartCart’s reviewed post-pantry need, ties each product/price claim to source and time, makes package math reproducible, preserves ambiguity and missing evidence, and leaves the final retailer handoff to the user. Success is not an agent buying groceries.

## Existing SmartCart boundary

The established flow is recipe import/extraction → Recipe Ready correction → pantry allocation → shopping-list or Meal Prep aggregation → product matching/exceptions → user-controlled Safari Shopping Trip → optional user-confirmed pantry reconciliation.

- `RecipeParser` and ingredient identity remain authoritative.
- `PantryMatchingService` determines conservative full/partial/possible coverage.
- `MealPrepAggregationService` combines reviewed recipes without silently merging uncertain identities/units.
- SmartCart already computes conservative package counts when exact compatible package evidence exists.
- `AppModel` owns UI/state and durable trip history.
- A visited retailer page is not purchase evidence; cart, fulfillment, payment, checkout, and final price remain retailer/user authority.

The experiment inserts one optional research step after the existing matching work and before finalizing the existing retailer queue. It does not mutate a prepared trip, pantry, purchase state, or retailer account.

## Native product flow

The `SmartCart-SolariBeta` path is user triggered:

1. Recipe Ready shows the normal **Shop This Recipe** action and, only when the beta backend is configured, a separate **Research current options** action.
2. Both actions use SmartCart’s normal `beginShoppingFromRecipeReady()` and `startMatching()` path.
3. Normal shopping finalizes the retailer queue immediately.
4. Research evaluates the resulting waiting items. One to three exact owned-catalog items with reviewed positive pound/ounce/count quantities are admitted; unsupported or duplicate identities fail with an explicit reason.
5. A native review sheet loads and validates evidence. It never silently replaces the shopping plan.
6. The user can refresh, edit, continue with normal SmartCart after a failure, or explicitly continue to the retailer queue.
7. Before continuation, SmartCart recomputes the plan fingerprint. Any recipe, pantry, serving, product, or requirement change invalidates the evidence.

Debug may replay a clearly marked synthetic recorded result without Browser, Sandbox, or App Attest. `Release-SolariBeta` has no replay bypass.

## Supported source and demo

The only live Browser target is the repository-controlled **SmartCart Demo Grocer** catalog. The fixed Chicken Parmesan Pasta need is chicken 1.5 lb, penne 12 oz, and Parmesan 3 oz after olive oil and garlic are excluded by pantry allocation.

This owned source is appropriate for proving dynamic-page observation, schemas, admission, cleanup, and native UX without violating retailer terms. It is synthetic: it does not establish real-retailer prices, availability, location behavior, or consumer value.

The Walmart experience is a replay of upstream records observed `2026-07-16T12:00:00Z`. Live Walmart is blocked without documented written authorization. Target live research is unsupported. Walmart’s [Terms](https://www.walmart.com/help/article/walmart-com-terms-of-use/3b75080af40340d6bbd596f116fae5a0) and Target’s [Terms](https://www.target.com/c/terms-conditions/-/N-4sr7l) make those policy boundaries explicit.

## Solari Browser responsibility

Browser has one necessary job: observe an admitted JavaScript-rendered product page at a specific time.

- Start a fresh logged-out session with no profile, recording, proxy, stealth, or captcha capability.
- Navigate only to the server-derived exact Demo Grocer product URL.
- Extract visible identity, package, price, and ambiguity context as data.
- Recheck the exact page URL before and after rendering and verify the product ID.
- Emit a bounded structured observation; do not retain raw HTML/screenshots.
- Close each page, the Browser session, and the Browser client before success.

Page text is untrusted data, never an instruction. There is no search/tool-choice loop, login, account access, cart control, or checkout.

Solari’s [session documentation](https://docs.getsolari.com/sessions) documents the fresh default and close lifecycle. [Profiles](https://docs.getsolari.com/profiles) contain login-bearing cookies/localStorage, so they are intentionally excluded.

## Solari Sandbox responsibility

Sandbox receives only validated structured observations plus reviewed quantities. It:

- normalizes compatible pounds/ounces/counts;
- computes required package count, coverage, and surplus;
- compares admitted adequate candidates with visible prices;
- selects the smallest sufficient observed basket;
- returns versioned decisions and complete/partial totals.

Sandbox receives no Solari key, App Attest material, Upstash credential, cookies, capability URL, raw HTML, account data, or arbitrary executable page content. The evaluator is fixed; SmartCart independently recomputes its selections and arithmetic. Sandbox egress is not assumed to be blocked, so the job is designed not to need network access or secrets. The microVM is killed before success.

Solari documents Sandbox compute and explicit `kill()` in the [Sandbox guide](https://docs.getsolari.com/sandboxes).

## V1 execution proof versus V2 product contract

The immutable credentialed proof is Actions run [`33519606791`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33519606791) at commit `eee8c84`. Its [V1 receipt](../evidence/live/smartcart-solari-live-proof-33519606791.json) records six fresh Browser observations (14:27:48–55Z), three Sandbox decisions, cleanup, and the `$12.79` owned synthetic basket. It proves actual Solari execution, not the native App Attest transport.

The native/deployed path is V2:

- `solari-shopping-research-request-v2`
- `retailer-observation-v2`
- `basket-decision-v2`
- `solari-shopping-research-result-v2`
- `solari-app-attest-research-envelope-v1`

The contract files and examples are under [`contracts/v2/solari/`](../contracts/v2/solari/). V2 removes client-supplied source URLs: the app sends candidate product IDs; the backend derives exact URLs from its owned base. Result provenance requires Browser, Sandbox, enforced cleanup, `apple-app-attest`, and user-controlled handoff.

No signed physical-device V2 request has run. The V1 Browser/Sandbox receipt and deployed V2 smoke evidence must not be combined into a claim that the signed native path is complete.

## Apple App Attest and server admission

The native client keeps a public App Attest key identifier, obtains a one-use operation-specific challenge, and registers a new key when necessary. For research, it computes an assertion over:

- the challenge;
- `POST`;
- `/v1/solari/research`;
- the SHA-256 digest of the exact encoded V2 request body.

The request contains an envelope with the exact payload bytes, key ID, challenge ID, and assertion. There is no reusable bearer/API credential in iOS.

The backend verifies beta enablement, runtime switch, challenge expiry/operation/key binding, registered non-revoked key, Apple assertion signature and app identity, allowlisted TestFlight validation category/build, monotonic counter, exact payload binding, and V2 schema before Solari work. Initial attestation verifies Apple’s certificate/receipt/nonce/key/app identity and stores the public verification record server-side. A locally sideloaded development build is not accepted as TestFlight evidence.

The production smoke receipt proves challenge creation/consumption and invalid/replay rejection. A real signed attestation/assertion remains pending because the host has no valid signing identity.

## Spend, replay, and lifecycle controls

Upstash stores only bounded beta control state:

- one-use challenges with short TTL;
- attested public-key records and counters;
- request idempotency reservations/results;
- per-key hourly/daily and global daily counters;
- concurrency leases;
- the runtime kill-switch key.

Admission atomically rejects quota/concurrency overflow. Duplicate request IDs with identical bytes can return the committed result; a different body conflicts. The native app also keeps a nonpersistent two-minute, eight-entry validated-result cache; **Refresh current options** bypasses it.

The runtime switch is checked before challenge, attestation, and research, then polled during provider execution. Turning it off aborts in-flight work. An aborted/incomplete incoming request propagates cancellation through the backend and providers. Browser and Sandbox share an aggregate deadline. A response-socket hangup after a complete request body may not be observed by the handler, so that edge remains bounded by the aggregate deadline and runtime switch rather than immediate cancellation. Every success requires confirmed cleanup.

## Evidence semantics

A retailer observation is a fact claim about what an admitted page appeared to show at one timestamp. A basket decision is an inference from named requirements and observation IDs.

Rules:

- unknown versions, duplicate/mismatched identities, out-of-allowlist products/URLs, invalid timestamps, stale/future live observations, incompatible units, or invalid numeric values fail closed;
- visible price is nullable and never defaults to zero;
- a complete subtotal exists only if every selected line has a valid package count and visible same-currency price;
- replay timestamps never become fresh because they were replayed;
- confidence and ambiguity remain qualitative evidence, not a made-up percentage;
- protein-per-dollar is omitted without separately attributable nutrition evidence;
- Browser/Sandbox success is not inventory, checkout, purchase, App Store, or physical-device proof.

## Failure behavior

Missing signing/App Attest support, disabled runtime, exhausted quota, duplicate/replayed challenge/counter, invalid build, unsupported plan, source-policy failure, private DNS, unexpected redirect, product mismatch, timeout, page/captcha/login wall, incomplete observation, Sandbox error, native validation failure, or cleanup failure produces unavailable/error—not invented evidence.

The native UI offers retry, edit, or normal SmartCart fallback. No failure path silently enables broader browsing or commerce authority.

## Intentionally excluded

- live Walmart/Target automation without authorization;
- broad retailer discovery or arbitrary client URLs;
- Browser profiles, login, recording, raw HTML/screenshots, proxy, stealth, or captcha solving;
- retailer account/list/cart/order, fulfillment, payment, checkout, or purchase detection;
- persistent native evidence cache;
- Solari Desktop;
- nutrition/protein economics without separate evidence;
- public native-use claims before signing/TestFlight evidence.

## Qualification boundary

The current evidence is:

- 55/55 focused Solari backend tests;
- 185/185 full backend tests;
- 13/13 focused native tests;
- Release-SolariBeta simulator build PASS;
- separate Debug simulator install/launch PASS;
- Vercel deployment `dpl_FD8iBpRhvmEckcUm7oo7v5tMoxdh` READY with health 200, challenge 201, invalid 403, replay 403;
- credentialed Browser/Sandbox run `33519606791` PASS at `eee8c84`.

Physical iPhone signing, a real signed App Attest vector, TestFlight, and App Store remain PENDING with zero valid signing identities. See [qualification](SOLARI_QUALIFICATION.md), [threat model](SOLARI_THREAT_MODEL.md), and [runbook](SOLARI_DEMO_RUNBOOK.md).
