# Solari threat model

## Protected assets and trust boundaries

```text
Release-SolariBeta app
  -> Apple App Attest + exact V3 request bytes
  -> Vercel beta API
       Upstash challenges / keys / counters / quotas / leases / kill switch
       server-only Solari credential
  -> Solari Browser -> exact owned public product URLs
  -> structured observations only
  -> Solari Sandbox -> bounded optimizer
  -> validated V3 result
  -> native evidence sheet
  -> unchanged original SmartCart retailer handoff
```

Protected assets include the Solari key, App Attest/Upstash control state, signed capability URLs, provider spend, evidence integrity, the shopper’s reviewed requirements, original SmartCart matches, and final handoff authority. The owned Demo Grocer contains synthetic public data; it does not justify relaxing the same boundaries needed for a future authorized source.

## Threat register

| Threat | Failure mode | Current control | Residual / required production work |
| --- | --- | --- | --- |
| Unbounded SSRF | Caller turns Browser into a network pivot | V3 admits one owned retailer, exact HTTPS root, exact six IDs/paths, no credentials/query/fragment; public-address DNS preflight; URL checked before and after render; product ID checked | Remote Browser DNS cannot be pinned, leaving DNS TOCTOU. Keep the owned host and exact-path policy; require controlled egress for any consumer source. |
| Redirect / JavaScript navigation | Page escapes after initial admission | Final `page.url()` must equal the exact candidate URL both before and after evaluation; mismatches fail closed | Provider/network compromise still warrants controlled egress and allowlisted DNS in production. |
| Page-content or prompt injection | Retailer text manipulates an agent/evaluator | No LLM prompt is built from page prose. V3 reads bounded structured DOM/JSON-LD fields; raw text is not passed to current result/Sandbox; product/current/synthetic markers must match | Treat every rendered field as untrusted input; retain schema and semantic bounds. Historical V1 raw-text code is not the current path and should not expand. |
| Retailer scraping / ToS violation | Unauthorized automation or fragile integration | Live source is owned Demo Grocer only. Walmart is replay-only; live Walmart requires explicit written-authorization gates. Target unsupported. Beta rejects coexistence with V1 operator-live mode | Before a real source, use an authorized API/feed or documented permission and review robots/terms/rate requirements. |
| Retailer layout fragility | Selector changes produce false product/price | Exact marker, product ID, URL, package/price parsing, current/synthetic markers, freshness, and complete six-candidate set all required; ambiguity preserved | Source changes should fail closed and alert; add source-specific monitoring only after authorization. |
| Misleading price/current claim | Shopper treats observation as guaranteed checkout price | Each observation has exact source/time/location, `syntheticPrice`, freshness, confidence/ambiguity; copy says observed/not guaranteed; tax, fees, inventory, fulfillment, checkout excluded | Demo Grocer offers no real-retailer value. Future retailer UI must carry store/location and expiry semantics backed by evidence. |
| Stale/future evidence | Old price appears current | Backend and native verify actual age, maximum age, future tolerance, and original timestamp; refresh bypasses two-minute cache | Never retimestamp cached evidence. Revisit TTL per authorized source and location behavior. |
| Incomplete total laundering | Missing line price becomes `$0` or a complete subtotal | General evidence model keeps price/total nullable; incomplete cannot claim complete. Fixed V3 qualification requires all three priced lines | Tax/fees/checkout total remain unknown even when the observed product subtotal is complete. |
| Unsupported match/substitution | Decision points to wrong product or arbitrary advice | Exact requirement/product/source membership, unique UUIDs, canonical ingredient/quantity/unit semantics, observation references, and substitution membership are validated | V3 is intentionally fixed. Broader matching requires a reviewed taxonomy and explicit ambiguity UX. |
| Optimizer overclaim or tampering | Sandbox returns attractive but invalid basket | SmartCart recomputes coverage, package count, line totals, stable cheapest reference, comparison arithmetic, and `$0.75` cap; internally computed receipt digest binds accepted result | Sandbox is intentionally the global argmin authority; SmartCart does not independently prove global optimality. State this boundary instead of claiming independent verification. |
| Secret exposure | Solari/Redis/operator credentials leak to client or artifacts | Secrets are environment-only; no client token; sanitized errors/receipts; capability/control URLs omitted; repository scans | Restrict deployment/provider access, rotate keys, and monitor logs/artifacts. Solari says bearer keys and signed capability URLs must be treated as secrets. |
| App impersonation / request alteration | Untrusted caller spends Solari or swaps requirements | Beta default-off; one-use App Attest challenge; assertion binds exact request bytes; backend checks app identity/build/key/counter/signature before provider work; no client bearer fallback | Real signed vector is pending. Current personal-team/provisioning blockers must be fixed without weakening entitlements. |
| Challenge replay / concurrency abuse | Repeated spend using valid device | Upstash challenge burn, monotonic counters, idempotency, per-key/global quotas, concurrency lease, body/candidate bounds | Configure alerts/budgets and named operator before testers. State-store outage fails closed. |
| V1 operator-live bypass | Public/operator route coexists with protected beta | Configuration rejects V1 operator-live when App Attest beta is enabled | Maintain deployment separation and regression tests. Operator qualification remains server-side only. |
| Kill-switch lag | Disabled feature continues provider work | Feature/runtime flags checked before admission; runtime key monitored during work; missing/store error aborts | Polling has finite delay; drill ownership and reconcile provider usage after infrastructure failure. |
| Cancellation/resource leak | User leaves but remote work continues | Native task cancellation; HTTP abort propagation; one aggregate deadline raced around provider calls/evaluation; page/session/client close and Sandbox kill in `finally`; cleanup failure suppresses success | A response-socket hangup after complete request body may run until deadline. Provider/infrastructure failure can outlive local cleanup; reconcile usage operationally. |
| Browser profile/session privacy | Cookies or login authority persist | Fresh logged-out session; no profile/login/storage save; no recording/proxy/stealth/captcha; close before success | If profiles are ever enabled, they store Playwright cookies/localStorage and represent a real account. Require consent, access, retention, deletion, and retailer authorization first. |
| Raw HTML/screenshot/log retention | Personalization or third-party content leaks | No screenshots/recording; current V3 path emits bounded structured fields; receipts omit raw HTML, page text, provider IDs, and capability URLs | Review provider retention, region, DPA, and log drains before consumer use. Remove historical V1 raw-text support if no longer needed. |
| Excess app data | Recipe/pantry habits leak | Sends only three reviewed requirements and six admitted IDs; no name, address, account, full pantry, source image/text, retailer session, or payment data | Ingredient choices can be personal. Establish retention/deletion if server logging expands. |
| Sandbox exfiltration | Optimizer leaks structured data or secrets | Sandbox receives no secrets, auth, capability URLs, cookies, or raw page content; fixed code/payload; output schema and invariants checked; Sandbox killed | No claim of blocked egress. Configure and prove no-egress if required. |
| Native cache confusion | Result is reused for changed recipe/list | Cache fingerprint binds plan/servings/mode, holds max eight results for two minutes in memory, refresh bypasses, continuation revalidates original matches | Never persist or retimestamp. App suspension timing remains a test concern. |
| Demo-to-retailer contamination | Synthetic IDs/prices enter Walmart/retailer handoff | Native success copy and continuation explicitly preserve the unchanged original SmartCart list; Demo IDs/prices are not transferred | Continue negative regression tests as UI evolves. |
| Autonomous purchase escalation | Research becomes commerce authority | No account/cart/order/payment/checkout capability. Explicit user continuation only; `visited` is not purchase evidence; pantry update remains explicit | Retailer actions remain under user and retailer controls. |

## App Attest state and privacy

The app stores its App Attest key identifier and accepted state; the Apple private key remains device-controlled. The backend stores public verification record, revocation/counter state, one-use challenges, bounded idempotency results, quotas, and short concurrency leases in Upstash. It does not store an Apple private key.

The transport envelope remains `solari-app-attest-research-envelope-v1` while `payloadBase64` contains exact `solari-shopping-research-request-v3` bytes. The server parses and validates V3 only after request binding and admission. A 401/403 clears the app’s local accepted-key reference and requires an explicit retry; there is no fallback bearer or Release fixture mode.

The protected Vercel deployment has smoke evidence for health/challenge and fail-closed malformed V3 rejection. No successful physical-device attestation/assertion/research exists. Three signing identities are present, but the archive is blocked by unsupported Associated Domains/App Attest on the personal team, missing matching app profile, Share Extension app-group profile mismatch, and an offline physical phone.

## Data minimization and retention

Retain only version, request/observation IDs, exact source, original timestamps, package/price fields, confidence/ambiguity, decisions/comparison, provenance/trust, cleanup, and sanitized qualification identity.

Do not retain Solari/Redis/operator secrets, auth headers, App Attest blobs beyond verification need, signed session/control/file URLs, cookies/localStorage, raw HTML/screenshots/recordings, retailer accounts, addresses, payment, carts, orders, or checkout data.

Persistent Solari profiles are deliberately unused. [Solari profiles](https://docs.getsolari.com/profiles) use Playwright storage state containing cookies and per-origin localStorage and should be treated like login credentials. [Solari API docs](https://docs.getsolari.com/api-reference) describe bearer authentication and signed capability URLs. [Solari Sandbox docs](https://docs.getsolari.com/sandboxes) specify `kill()` teardown.

## Operational release gate

Before any signed native beta or real-retailer claim:

- obtain correct team capabilities and matching main-app/Share Extension provisioning profiles;
- produce and install an allowlisted signed `Release-SolariBeta` build on a physical iPhone;
- complete Apple initial attestation and an assertion bound to exact V3 bytes;
- verify replay, quota, cancellation, kill-switch, and cleanup behavior on that path;
- configure budgets/alerts and named kill-switch ownership;
- scan client, deployment, logs, receipts, and artifacts for secrets/capability URLs;
- inspect source/time/mode/ambiguity/overage and unchanged-handoff UX with Dynamic Type/VoiceOver;
- obtain authorized retailer data access before replacing the owned synthetic source;
- separately qualify TestFlight, App Store, and downloadable-app claims.

Those gates are PENDING. The current evidence supports the protected backend, native code/simulator behavior, owned Browser targets, and operator-qualified Browser/Sandbox run—not a signed consumer-native or real-retailer release.
