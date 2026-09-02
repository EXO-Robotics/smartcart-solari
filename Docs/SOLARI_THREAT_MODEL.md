# Solari V4 threat model

## Boundaries and protected assets

~~~text
Release-SolariBeta
  -> App Attest envelope binding exact V4 request bytes
  -> protected beta API / Upstash controls / server-only Solari key
  -> Browser exact owned V4 URLs
  -> bounded structured observations
  -> Sandbox relative-surplus DP
  -> independently checked policy invariants
  -> native researched-X-of-Y review
  -> unchanged original SmartCart handoff
~~~

Protected assets include provider credentials/spend, App Attest challenge/key/counter state, shopper requirements, skipped-line integrity, original SmartCart selections, evidence provenance, and user handoff authority.

## Threat register

| Threat | Failure mode | V4 control | Residual / release work |
| --- | --- | --- | --- |
| SSRF / navigation escape | Browser becomes a network pivot | One owned HTTPS root; 19 exact IDs/paths; no credentials/query/fragment; public-address DNS preflight; exact URL checked after navigation/render | Remote-browser DNS is not pinned, leaving DNS TOCTOU. Controlled egress is required before consumer use. |
| Page/prompt injection | Hostile prose manipulates research | No LLM prompt from page prose; only bounded structured fields; exact product/current/synthetic markers; raw text never enters Sandbox | Continue treating every rendered field as untrusted input. |
| Unauthorized retailer automation | Research violates terms or authorization | V4 targets owned Demo Grocer only. Walmart is replay-only; Target unsupported; real sources fail closed absent documented authorization | Qualify an authorized API/feed or explicit permission separately. |
| Layout/evidence fragility | Missing or changed field becomes a false claim | Exact source/product/marker/unit parsing, freshness, cardinality, and complete admitted-subset validation | Monitor owned pages; any future source needs source-specific failure telemetry. |
| Misleading price | Synthetic subtotal appears like checkout price | Source/time/location/freshness/confidence/ambiguity and synthetic marker; UI says observed comparison, not checkout quote | Tax, fees, discounts, inventory, fulfillment, and location remain unknown. |
| Partial-coverage laundering | Complete result implies every trip line was researched | Native plan binds total waiting count, admitted requirements, and explicit skipped lines; UI says Researched X of Y; skipped lines continue unchanged | Keep skip reasons visible and accessible as UI evolves. |
| Unsupported semantic match | Wrong ingredient enters research | Exact SmartCart product link, seeded alias group, canonical dimension, allowlisted candidate membership, unique IDs | Eight groups are not arbitrary coverage; broader taxonomy requires review and ambiguity UX. |
| Unbounded cost | Large trip multiplies provider spend | 1–12 requirements, 1–3 candidates each, <=24 observations; request/body bounds; quotas, concurrency lease, cache, cancellation, aggregate deadline, kill switch | Set budgets/alerts and named operator before testers. |
| Optimizer tampering/overclaim | Sandbox emits attractive invalid basket | Backend recomputes coverage, packages, line totals, cheapest reference, comparison, and $0.75 cap | Sandbox is global DP authority; SmartCart does not prove the global argmin. Preserve that wording. |
| App impersonation / body swap | Caller spends provider key or changes requirements | Default-off Release route; one-use App Attest challenge; assertion binds exact V4 bytes; app/build/key/counter/signature checks; no client bearer fallback | Signed physical-device vector remains PENDING. |
| Challenge replay / race | Valid device repeats spend | Challenge burn, monotonic counter, idempotency, per-key/global quotas, concurrency lease, request identity refresh | State-store outage fails closed; drill replay and lease recovery on device. |
| Secret/capability leakage | Key or signed URL reaches client/log | Environment-only secrets; sanitized errors/receipts; no provider/control URL in result; repository scans | Audit provider and deployment logs, rotate keys, restrict operators. |
| Session/profile privacy | Cookies/login authority persist | Fresh logged-out Browser session; no persistent profile, login, proxy, stealth, CAPTCHA, or storage save. App/TestFlight lanes do not record. The separate rate-limited public-demo lane records only the owned synthetic catalog. | A future profile would contain cookies/localStorage and requires consent, authorization, retention and deletion controls. |
| Raw-content retention | HTML/screenshots expose third-party or personal data | Immutable receipts keep bounded structured evidence only. The fresh public-demo response may expose one short-lived HTTPS replay URL after cleanup; it never stores the Browser session ID and cached responses never return the replay capability. | Replay retention is provider-plan dependent; keep the recorded surface owned, logged out, synthetic, and disclosure-visible. |
| Excess trip data | Recipe/pantry habits leak | Send only admitted line names, canonical quantities, exact candidate IDs; skipped lines/full pantry/account/address/payment stay client-side | Ingredient selections may still be personal; define retention/deletion before beta. |
| Sandbox exfiltration | Structured inputs or secret leaks | Sandbox receives no secrets/auth/cookies/raw pages; fixed optimizer/payload; output validation; teardown in finally | No claim of blocked egress. Configure/prove no-egress if required. |
| Cancellation/resource leak | User leaves while remote work continues | Native cancellation and 75/90-second timeouts; backend abort/deadline; Browser page/session/client close and Sandbox kill in finally; cleanup failure suppresses success | Socket hangup after body receipt may run to deadline; reconcile provider usage. |
| Refresh/cache confusion | Old evidence is retimestamped or wrong plan reused | Fingerprint binds plan/selections/servings/mode; bounded short memory cache; refresh evicts and creates new UUID/time; freshness uses original observedAt | Retest suspension and concurrent refresh on signed device. |
| Demo contamination | Synthetic selection reaches retailer | Continuation revalidates all original waiting selections and rejects Demo Grocer IDs/prices | Maintain negative regression tests. |
| Autonomous commerce | Research gains purchase authority | No account, cart, order, payment, or checkout capability; explicit user action before and after research | Retailer action remains entirely under user/retailer controls. |

## App Attest state

The transport envelope remains **solari-app-attest-research-envelope-v1** while its payload is **solari-shopping-research-request-v4**. The app stores only its key identifier/accepted state; Apple's private key remains device-controlled. Backend state includes public verification data, counter/revocation state, one-use challenges, bounded idempotency results, quotas, and short leases.

Release-SolariBeta has no fixture or bearer fallback. A 401/403 clears the local accepted-key reference and requires an explicit retry. Provider work is rejected before Browser/Sandbox unless the live beta path, App Attest identity/build, state store, quotas, lease, and kill switch all admit it.

No signed V4 App Attest request has run. A physical phone is connected, but its installed build predates the development lane and targets the strict distribution route. Installing the new development-lane build remains blocked by unsupported personal-team capabilities, a missing matching app profile, and a Share Extension application-groups mismatch.

## Data minimization and retention

Retain only the versioned request/result IDs, admitted canonical requirements, exact sources, original observation timestamps, package/price/confidence/ambiguity fields, decisions/comparison, provider provenance, cleanup, and sanitized qualification identity.

Do not retain secrets, auth headers, attestation blobs beyond verification need, signed control URLs, Browser session IDs, cookies/localStorage, raw HTML, screenshots, accounts, address, payment, cart, order, checkout, full pantry, or skipped trip lines. Public-demo recordings are provider-hosted, short-lived, and limited to the owned logged-out synthetic catalog; they are not copied into receipts or application storage.

Official references: [Solari profiles](https://docs.getsolari.com/profiles) describe Playwright storage state; [API docs](https://docs.getsolari.com/api-reference) describe bearer credentials and signed capability URLs; [Sandbox docs](https://docs.getsolari.com/sandboxes) describe teardown.

## Evidence and release gates

V4 run [33546912947](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546912947) at runtime **2dd4e6f30be8286a3a8f465c92a56427828a60e2** qualified the owned-source Browser/Sandbox path for eight requirements, 16 observations, mass/volume/count decisions, a real $0.63 bounded tradeoff that avoids about 680 g / 1.5 lb of excess chicken, and cleanup. Its [provider receipt](../evidence/live/smartcart-solari-v4-qualification-33546912947.json) is operator qualification, not signed App Attest/device proof.

Historical V3 [provider](../evidence/live/smartcart-solari-v3-qualification-33533170189.json) and [deployment](../evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json) receipts remain scoped to the narrower predecessor.

Before a V4 release claim, preserve the completed provider checks and finish the remaining product gates:

- preserve runtime `2dd4e6f` and its credentialed Browser+Sandbox receipt;
- keep contract/backend/native/web/build/audit checks green;
- keep all owned V4 pages published and verified;
- deploy that exact runtime and record a separate smoke receipt;
- produce/install a correctly signed Release-SolariBeta build;
- complete real App Attest registration/assertion/replay testing on iPhone;
- test accessibility, cancellation, quotas, kill switch, coverage/skips, evidence, and unchanged handoff;
- obtain documented retailer authorization before any non-owned source;
- separately qualify TestFlight/App Store/downloadable availability.

V4 credentialed provider execution and exact backend deployment identity are complete. Signed-device App Attest, distribution, and authorized-retailer gates remain **PENDING**.
