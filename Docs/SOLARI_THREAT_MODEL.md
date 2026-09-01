# Solari native-beta threat model

## Assets and trust zones

Protected assets include the server-side Solari API key; Upstash REST credentials and beta control state; Apple App Attest key records/counters; signed Solari session/control URLs; reviewed recipe/pantry needs; normalized evidence; cost budget; SmartCart historical state; and the user’s retailer/account/cart/checkout authority.

```text
Release-SolariBeta app
  -> Apple App Attest key + one-use challenge/assertion
  -> deployed SmartCart beta API
       V2 schema + identity/request verification
       Upstash replay/idempotency/quota/concurrency/kill switch
       owned-source admission
  -> Solari Browser (untrusted owned page content)
  -> normalized observation only
  -> Solari Sandbox (fixed evaluator)
  -> validated V2 evidence/decision
  -> native independent validation + memory-only cache
user -> existing retailer handoff
```

Client input, page content, redirects, DNS, Solari output, fixtures, and cached records are untrusted. App Attest establishes an app/device/request boundary; it does not make page data true, authorize a retailer, or prove a purchase.

## Threats and controls

| Threat | Impact | Current controls | Residual / release requirement |
| --- | --- | --- | --- |
| Unauthorized retailer automation | Policy/legal breach and trust loss | Live Browser scope is owned Demo Grocer only. Walmart is replay-only; live Walmart requires separate written-authorization gates. Target is unsupported. No evasion capabilities. | A consumer trial needs an authorized retailer API/feed or written permission and renewed terms review. |
| Synthetic demo overstated as retailer value | Misleading submission/product claim | UI/docs/receipts label Demo Grocer owned and synthetic. Walmart replay and Solari live proof remain separate. | Do not claim real prices, inventory, market value, or public shopping utility from the synthetic catalog. |
| Arbitrary client URLs / SSRF | Access to localhost, metadata, private networks, or unexpected hosts | V2 client sends product IDs, not URLs. Backend derives an exact HTTPS owned URL; rejects credentials, IP literals, ports/query/fragment, private/non-public DNS, redirects, product-ID swaps, and post-render URL changes. | Remote Browser DNS cannot be pinned through the SDK. Public-DNS preflight plus exact URL checks leave DNS TOCTOU; production needs locked owned DNS and a trusted egress boundary. |
| Page/prompt injection | Page content drives navigation, secret disclosure, or commerce actions | Fixed navigation/extraction; page text is data. No LLM/tool-choice loop. Sandbox receives structured JSON, not HTML/instructions. No shell interpolation. | Page fields can still lie; source/product/package/price corroboration and native validation remain required. |
| Markup fragility | Wrong or unavailable observations | Fixed owned pages, bounded extraction, exact product identity, package validation, confidence/ambiguity, strict unavailable path. | Any future authorized retailer connector needs monitoring, fixtures, and graceful fallback. |
| Misleading price/location | User relies on a stale/default-market value | Source, `observedAt`, freshness, mode, confidence, synthetic location, and non-guaranteed copy stay near the recommendation. Live evidence older than 24 hours is rejected. | User/retailer confirms current local price, availability, tax, fees, promotions, and fulfillment. |
| Incomplete total shown as complete | Basket cost understated | Price/line/subtotal nullable. Complete requires every selected line to have valid package math, price, and one currency. Native/backend recompute. | Taxes, fees, deposits, memberships, promotions, fulfillment, substitutions, and later changes remain excluded. |
| Unsupported match/package math | Wrong product or quantity | One-to-three reviewed requirements; unique IDs; semantic product group/unit checks; exact candidate allowlist; source derivation; bounded finite numbers; independent package/subtotal verification. | Allergies/dietary label claims still need user label review and separate evidence. |
| App impersonation or altered request | Unauthorized caller spends Solari or substitutes a plan | Release-SolariBeta uses Apple App Attest. One-use challenge binds operation/key; assertion binds challenge, method/path, and exact request-body digest. Backend verifies app identity, allowlisted TestFlight category/build, key/counter, and signature before provider work. | No real signed native vector yet. Signing/TestFlight qualification is a hard release gate. A sideloaded development build is not accepted. |
| Challenge/assertion replay | Repeated spend or stale authorization | Upstash `GETDEL` consumes challenges; short TTL; key-bound operation; monotonic App Attest counter; atomic counter advance. Deployment smoke observed invalid 403 and consumed-challenge replay 403. | Monitor replay errors and revoke suspicious keys. Smoke used invalid material, not a successful Apple vector. |
| Request duplication/idempotency abuse | Duplicate spend or mixed results | Per-key + request-ID + exact-body digest reservation. Identical completed requests may replay the committed result; conflicting/pending duplicates fail. TTL bounds retained results. | Treat cached/idempotent results as prior observed evidence with original timestamps; never refresh timestamps on replay. |
| Secret leakage | Solari/Redis compromise and spend | `SOLARI_API_KEY`, `KV_REST_API_TOKEN`, and control secrets are Vercel/server-only. No client bearer/API key. Redacted logs/errors; no secrets in result/receipt/Sandbox. | Restrict environment/admin access, rotate secrets, scan artifacts/logs, and separate environments. |
| Signed capability URL leakage | Session/file control theft | CDP/WebSocket/control/file/preview URLs are never returned or logged and are excluded from receipts. | Restrict Solari organization access and provider logs. Treat capability URLs as secrets per [Solari API docs](https://docs.getsolari.com/api-reference). |
| Browser profile/session privacy | Retained cookies/login impersonation | Fresh logged-out Browser; no profile/login/storage save. Page/session/client close before success. | Any profile would require a separate consent/retention/deletion/retailer-authorization design. [Solari profiles](https://docs.getsolari.com/profiles) store cookies/localStorage. |
| Raw HTML/screenshot/recording retention | Personalization and third-party content leakage | Recording/screenshots/replay/raw HTML persistence disabled. V2 returns bounded structured fields only; sanitized receipts omit raw page text and resource IDs. | Review provider operational retention/region/DPA before a consumer beta. |
| Excess app data | Recipe/pantry habits leak | Client sends only one-to-three reviewed requirements and approved candidate IDs. No name, address, account, full pantry, source image/text, or retailer session. | Ingredient choices can still be personal; document retention/deletion if server logging expands. |
| Public spend / denial of service | Solari cost or capacity exhaustion | Beta disabled by default; runtime key must be exactly enabled. App Attest admission; per-key hourly/daily and global daily quotas; concurrency lease; body/time/candidate bounds; no broad retry loop. | Configure budgets/alerts and operator ownership before inviting testers. Rate/limit values are deployment configuration, not client promises. |
| Kill-switch delay/failure | Work continues after operator disable | Runtime key checked before challenge, attestation, and research and polled during live work. Disabled/missing/store-error aborts monitored providers. | Poll interval is finite; drill kill-switch ownership and verify alerts. Provider/backend crashes still need operational reconciliation. |
| Cancellation/resource leak | Cost persists after user leaves or request ends | Native tasks cancel with sheet lifecycle. Backend aborted/incomplete requests propagate to Browser/Sandbox; shared aggregate deadline; runtime kill monitor; page/session/client close and Sandbox kill in `finally`; cleanup failure suppresses success. | A response-socket hangup after a complete request body may not be observed and can run until the deadline/kill switch. Infrastructure can terminate before local `finally`; reconcile orphan resources/provider usage. |
| Sandbox egress assumption | Structured data or secret exfiltration | No claim of blocked egress. Sandbox receives no secrets/capability URLs and needs no network. Fixed evaluator output is schema-checked and independently recomputed. | Configure/prove no-egress separately if required. Isolation alone is not proof. |
| Native cache confusion | Stale/mismatched evidence shown for a new plan | Cache key is a deterministic fingerprint of reviewed plan/servings/mode; TTL two minutes; maximum eight; refresh bypass; current plan rechecked before handoff; memory only. | App suspension clock behavior and 24-hour observation policy remain separately validated. Never persist/retimestamp cache entries. |
| Evidence tampering/mix-and-match | Decision uses altered observations | Versioned V2 schemas; request, requirement, product, source, and observation references; duplicate rejection; exact source derivation; package/subtotal recomputation; Browser/Sandbox/App Attest/cleanup provenance required. | V1 public receipt is first-party evidence, not a cryptographically signed external attestation. |
| Unsafe handoff escalation | Recommendation becomes purchase authority | Research result has no commerce write capability. Explicit user continuation invokes existing queue. `visited` is not cart/order/purchase; pantry update remains explicit. | Retailer actions remain the user’s responsibility under retailer controls. |

## App Attest state and privacy

The app stores only its public App Attest key identifier and a local accepted flag. The backend stores the corresponding public verification record, revocation state, monotonic counter, one-use challenges, bounded idempotency results, quota counters, and short concurrency leases in Upstash. It does not store an Apple private key; the device Secure Enclave/App Attest service retains that authority.

On a 401/403 authorization rejection, the app clears its local key reference and requires an explicit user retry to perform fresh registration. There is no fallback bearer token and Release-SolariBeta cannot switch to fixture replay.

No successful physical-device attestation/assertion exists yet. The production smoke proves only challenge lifecycle and fail-closed invalid/replay handling.

## Evidence retention and expiry

Retain only normalized fields needed for reproducibility: versions, request/observation IDs, product/source, timestamps, package/price values, decisions, provenance, trust assertions, and sanitized qualification identity.

Do not retain Solari/Redis credentials, auth headers, App Attest assertion/attestation blobs beyond verification needs, session/control/capability URLs, cookies/localStorage, raw HTML/screenshots/recordings, retailer accounts, addresses, payment, carts, orders, or checkout data.

Live consumers reject observations outside the 24-hour policy or in the future. The native two-minute cache and server idempotency result preserve the original observation time. Walmart fixture replay retains July 16, 2026 and is always labeled historical.

## Operational gate

Before signed beta distribution, require all of:

- a valid signing identity and allowlisted TestFlight Release-SolariBeta build installed on a physical iPhone;
- successful Apple initial attestation and assertion bound to the exact V2 request;
- allowed build identity verified in deployed configuration;
- runtime kill-switch drill and named operator;
- quota/concurrency/budget alerts;
- secret/log/receipt scan;
- live Browser/Sandbox cleanup receipt;
- source/time/mode/ambiguity/partial-total UI review on device;
- Dynamic Type and VoiceOver checks;
- explicit user-controlled handoff;
- documented synthetic-source limitation and no real-retailer claim.

Physical signing, real signed App Attest, TestFlight, and App Store are currently PENDING with zero valid code-signing identities.

Solari lifecycle references: [sessions](https://docs.getsolari.com/sessions), [profiles](https://docs.getsolari.com/profiles), [Sandboxes](https://docs.getsolari.com/sandboxes), and [API capabilities](https://docs.getsolari.com/api-reference).
