# Solari experiment

## Question and product boundary

> Can Solari turn SmartCart's retailer handoff into a useful agentic shopping workflow without violating user trust?

V4 adds an optional research step to the normal native SmartCart flow. It does not replace recipe extraction, pantry exclusion, aggregation, existing product preparation, trip state, or retailer handoff. Any trip with waiting items may invoke the action, but only eligible exact seeded matches enter research. Unsupported lines are preserved and explained.

SmartCart already performs conservative package math when it has compatible package evidence. The missing capability is a current retailer observation plus a defensible cross-candidate basket comparison.

## V4 use case

1. The shopper prepares any normal trip or recipe.
2. Pantry exclusions and aggregation produce waiting lines.
3. The shopper taps **Research current options**.
4. SmartCart evaluates every waiting line:
   - normalize exact mass, volume, or count;
   - require an exact SmartCart product match;
   - map only to an owned seeded Demo Grocer group;
   - admit at most 12 requirements, three candidates per requirement, and 24 total observations.
5. The native plan records admitted and skipped lines. The UI says **Researched X of Y items** and shows why each skipped line remains on the normal list.
6. Browser observes the admitted exact owned pages.
7. Sandbox chooses the minimum aggregate relative-surplus basket within $0.75 of the cheapest adequate basket.
8. SmartCart validates the structured result and presents comparison/provenance.
9. The shopper edits, refreshes, stops, or continues with the unchanged original SmartCart list.

This is useful partial coverage, not broad matching. V4's fixed owned catalog contains 19 synthetic candidates across eight groups: chicken, pasta, olive oil, heavy cream, Parmesan, garlic, lemon, and parsley. Names, matched products, quantity dimensions, and candidate sets must agree. V4 does not claim arbitrary ingredients, nationwide stores, inventory, localization, or authorized real-retailer value.

## Browser's necessary job

Solari Browser is used because the owned product surfaces are JavaScript-rendered and a seeded record or static URL cannot prove the rendered product evidence observed in a particular run.

For each admitted candidate it:

1. opens the exact allowlisted HTTPS V4 URL in a fresh logged-out session;
2. waits for the bounded product surface;
3. verifies final URL and exact product identity;
4. reads bounded structured fields only: title, package quantity/unit, visible synthetic price/currency, product ID, **current-v4**, and **syntheticPrice=true**;
5. records source, observation time, confidence, ambiguity, and controlled-demo location;
6. closes the page, session, and client on all paths.

It does not ingest page prose into an LLM prompt or pass raw page text to Sandbox. It uses no retailer account, persistent profile, recording, proxy, stealth, CAPTCHA bypass, or purchase control.

## Sandbox's necessary job

Sandbox receives only canonical requirements and structured Browser observations. The **relative-surplus-premium-dp-v1** optimizer:

1. calculates adequate package counts per candidate;
2. calculates line price and relative surplus, (covered - required) / required;
3. establishes the cheapest adequate basket;
4. indexes dynamic-programming states by premium cents up to $0.75;
5. minimizes aggregate relative surplus, shown to users as a dimensionless package-overage score rather than a percentage;
6. breaks ties by observed subtotal and then retailer product ID;
7. emits decisions and comparison;
8. tears down the microVM on all paths.

SmartCart recomputes evidence membership, coverage, package count, line totals, cheapest reference, comparison arithmetic, and the premium cap. It intentionally does not recompute the global dynamic-program argmin; that is Solari Sandbox's necessary authority.

## Native and backend architecture

~~~text
normal waiting SmartCart trip
  -> V4 eligibility builder
       eligible requirements (1..12)
       candidates (1..3 each, <=24 total)
       explicit skipped lines
       unchanged original selections
  -> Release-SolariBeta App Attest envelope
  -> protected beta admission / quotas / lease / kill switch
  -> Browser owned-page observations
  -> Sandbox relative-surplus DP
  -> backend schema + policy validation
  -> native schema + provenance + freshness validation
  -> researched-X-of-Y review
  -> unchanged original SmartCart handoff
~~~

The signed transport schema is still **solari-app-attest-research-envelope-v1**, wrapped around exact **solari-shopping-research-request-v4** bytes. Release-SolariBeta has no fixture bypass. Debug replay, where enabled, is visibly labeled and invokes neither provider nor App Attest.

Refresh creates a new request UUID/timestamp and evicts the prior short-lived in-memory result. Native networking uses an ephemeral session with cookies/cache disabled and bounded timeouts. Backend deadlines, quotas, cancellation, and cleanup remain authoritative.

## Evidence and provenance

The V4 schemas are:

| Contract | Purpose |
| --- | --- |
| [solari-shopping-research-request-v4](../contracts/v4/solari/basket-research-request.schema.json) | canonical admitted subset, exact candidates, bounds, policy |
| [retailer-observation-v4](../contracts/v4/solari/retailer-observation.schema.json) | source/time/package/nullable price/current/synthetic/freshness evidence |
| [basket-decision-v4](../contracts/v4/solari/basket-decision.schema.json) | package count, coverage, surplus, relative surplus, line total, evidence reference |
| [solari-shopping-research-result-v4](../contracts/v4/solari/basket-research-result.schema.json) | complete admitted-subset decisions, comparison, optimizer authority, trust and cleanup |

The result covers only admitted requirements. The native plan separately preserves total waiting count and skipped lines, so a complete research result cannot imply that every trip line was researched.

Every amount is an observed synthetic product subtotal, never a checkout quote. Taxes, fees, discounts, inventory, fulfillment, account-specific pricing, and location-specific price are outside the contract. Nullable missing evidence never becomes zero.

## Trust boundary

- V4 is owned Demo Grocer only.
- Walmart is historical fixture replay only; live retailer automation remains fail-closed without documented authorization.
- No account, persistent profile, cart, order, payment, or checkout automation.
- No Solari credential in native or web artifacts.
- No raw HTML, screenshot, recording, cookie, localStorage, or signed capability URL in result evidence.
- Provider work is default-off behind App Attest and operator-controlled quotas/kill switch.
- Demo products/prices never enter SmartCart's original retailer list.
- User action remains required before and after research.

Persistent Browser profiles are deliberately unused. If enabled, they would store Playwright cookies and per-origin localStorage and therefore require explicit consent, retailer authorization, access controls, retention/deletion policy, and account-risk review.

## Evidence status

The V4 provider path is frozen and credential-qualified:

- runtime **2dd4e6f30be8286a3a8f465c92a56427828a60e2**;
- [run 33546912947](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546912947);
- [sanitized receipt](../evidence/live/smartcart-solari-v4-qualification-33546912947.json);
- eight researched requirements spanning mass, volume, and count;
- 16 fresh Browser observations and eight Sandbox decisions;
- complete $24.20 synthetic basket versus $23.57 cheapest, spending $0.63 to select 1.5 lb rather than 3 lb of chicken and avoid about 680 g / 1.5 lb of shopper-visible excess;
- Browser and Sandbox cleanup enforced before receipt;
- focused provider/qualification tests 21/21, full backend 214/214, focused native 28/28, web 7/7, npm audit 0, unsigned Release-SolariBeta build PASS;
- public V4 owned catalog and Pages deployment [33546848706](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546848706).

V4 beta deployment is also complete at publication commit **5164426**: deployment **dpl_2ucnyzesiFFFf7bU7bFraDaVerPh** is READY and the [sanitized deployment receipt](../evidence/live/smartcart-solari-v4-deployment-5164426-20260901.json) records health 200 and challenge 201 without claiming signed-device execution.

The following remain **PENDING**:

- signed Release-SolariBeta archive and physical-iPhone App Attest flow;
- TestFlight/App Store/downloadable app;
- any authorized real-retailer source.

Historical V3 run [33533170189](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189) and its [receipt](../evidence/live/smartcart-solari-v3-qualification-33533170189.json) prove real Browser/Sandbox execution for the narrower six-page Chicken Parmesan predecessor at runtime **772e65b**. The V3 [deployment receipt](../evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json) proves that predecessor's deployed beta boundary; it is not reused as V4 proof.

## Intentionally not automated

- ingredient extraction or pantry decisions without user review;
- fuzzy/arbitrary ingredient mapping;
- third-party retailer research without authorization;
- retailer login, location/profile personalization, inventory claims, or account pricing;
- cart mutation, purchase, payment, or checkout;
- substitution outside the admitted owned candidate set;
- transferring synthetic choices into retailer handoff;
- autonomous background research.

That narrowness is the experiment: Solari materially refreshes and evaluates evidence while SmartCart keeps meaning, trip state, and commerce authority.
