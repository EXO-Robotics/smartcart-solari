# Solari retailer-research threat model

## Assets and trust zones

Protected assets are the server-side Solari key and operator token, session/control endpoints and signed URLs, user recipe/pantry needs, normalized evidence, cost budget, SmartCart historical state, and the user’s retailer/account/cart authority.

```text
iOS client input
  -> SmartCart backend (policy + schema boundary)
     -> Solari Browser (untrusted permitted page)
     -> normalized observation (data only)
     -> Solari Sandbox (deterministic evaluator)
  <- validated evidence/decision
user -> retailer-owned handoff (user authority)
```

Pages, redirects, DOM text, Sandbox output, fixtures, and client requests are untrusted. Solari is a privileged external processor; isolation does not replace minimization, secret handling, cleanup, or validation.

## Threats and controls

| Threat | Impact | V1 controls | Residual/operational requirement |
| --- | --- | --- | --- |
| Unauthorized retailer automation | Policy/legal breach and trust loss | Usable live demo is owned Demo Grocer only. Walmart is fixture replay and live requests require both written-authorization gates; neither is present. Target is unsupported. No stealth/proxy/captcha/bypass. | Recheck current terms and obtain written/approved access before any retailer policy change. Walmart [Terms](https://www.walmart.com/help/article/walmart-com-terms-of-use/3b75080af40340d6bbd596f116fae5a0); Target [Terms](https://www.target.com/c/terms-conditions/-/N-4sr7l). |
| SSRF via URL or redirect | Access to localhost, metadata, private services, or unexpected hosts | Client cannot submit arbitrary target. Server-owned HTTPS allowlist; reject credentials, non-default ports, IP literals, encoded-host confusion, and non-public resolved addresses. Revalidate DNS, every redirect, and final URL. Bound redirects/bytes/time. | DNS rebinding and controlled-host changes require tested resolution policy. Fail closed. |
| Prompt/page-content injection | Page tells an agent to disclose, navigate, execute, or buy | Fixed navigation/extraction; DOM/JSON-LD is data. No instruction-following/tool-choice loop. Sandbox receives narrow normalized JSON, not HTML. No shell interpolation. | Misleading fields remain possible; identity/package/price corroboration and manual fixture review are required. |
| Markup fragility | Wrong match/price or broken demo | Controlled test surface; extractor version; selector/structured-data corroboration; confidence/ambiguity; fixture regression; explicit unavailable fallback. | A future authorized retailer integration still needs monitoring and policy review. |
| Misleading price/location | User relies on stale/default-market value | Show source, observed time, evidence mode; label non-guaranteed; fixture timestamp immutable; unknown location explicit; no availability claim. | User confirms final local price/availability. Enforce expiry policy before production. |
| Incomplete total shown complete | Basket cost understated | Price/total nullable. Total only when every included line has valid package count/price/currency. Missing lines carry reasons; priced subtotal is distinct. | Taxes, fees, deposits, memberships, promotions, fulfillment, substitutions, and later changes remain excluded. |
| Unsupported product match/math | Wrong item or quantity | Preserve SmartCart identity; validate product/source; compare title/package; reject incompatible units/blocking ambiguity; show confidence/substitution. | Dietary/allergy-sensitive matches need user review and package label confirmation. |
| Secret leakage | Solari compromise/spend/data exposure | Backend-only `SOLARI_API_KEY` and `SOLARI_OPERATOR_TOKEN`; never returned, sent to Sandbox/client, logged, committed, or put in errors. Redact auth. Secret scans and rotation. | Platform admins can access runtime secrets; separate environments and audit access. |
| Signed capability URL leakage | Third party controls session or accesses files | Treat WebSocket/CDP/control/file/preview URLs as secrets; never log/return; no replay/port preview; redact IDs. Solari [API docs](https://docs.getsolari.com/api-reference) describe signed endpoints as capabilities. | Restrict Solari organization membership. |
| Profile/session privacy | Retained cookies/localStorage enable impersonation | No profile/login/storage save. Fresh logged-out runs; Browser closes in `finally`. | Any future profile requires new consent/retention/deletion design. Solari [profiles](https://docs.getsolari.com/profiles) are login-bearing. |
| Raw HTML/screenshot/replay retention | Captures personalization/third-party content | Recording off; no persisted screenshots/raw HTML. Contract `rawText` is a bounded extracted plain-text evidence excerpt, treated as untrusted and excluded from logs/session state. Diagnostic capture is default-off, scrubbed, short-lived. | Verify provider operational retention/region/DPA before production and reassess whether an authorized retailer needs even bounded text. |
| Excess app data | Recipe/pantry habits leak | Send canonical needs and approved candidates only—no name, account, address, full pantry, source image/text, or app ID. | Ingredient choices may still be personal; define retention/deletion/access policy. |
| Cost/concurrency abuse | Spend or denial of service | Auth as appropriate, body/rate/candidate/concurrency limits, one aggregate deadline, in-flight operation cancellation, client-disconnect propagation, no retries on deterministic errors/429, cleanup, kill switch. | Add provider budgets/alerts before public live access. |
| Public endpoint spends configured Solari credit | An unauthenticated caller triggers Browser/Sandbox work | Live execution defaults off. It requires `SOLARI_LIVE_EXECUTION_ENABLED=true`, a configured 32–256 character `SOLARI_OPERATOR_TOKEN`, and an exact Bearer-token match checked in constant time before provider work. The token is operator/server-only and is not shipped to iOS/web. Public fixture replay stays rate-limited and never invokes Solari. | Rotate/restrict the token, keep the live flag off outside supervised runs, and add infrastructure-level quotas before wider access. |
| Resource leak | Spend/residual state/capacity loss | `try/finally`; close the Browser session, close the Solari Browser client, kill Sandbox, record sanitized cleanup status, and use TTL/orphan reconciliation. | Crashes can skip local `finally`; operational reconciliation remains necessary. |
| Sandbox egress assumption | Evaluator fetches/exfiltrates | Do not claim blocked egress. Job needs no network, gets no secrets/capability URLs, runs a fixed evaluator, then is killed. Validate its schema and recompute package/price invariants server-side. | Prove/configure no-egress separately if required. Isolation is not proof. |
| Sandbox command injection | Page strings become executable | Pass validated JSON/file to a fixed executable with argv; no composed shell; bound strings/control characters. | Pin/review evaluator/template dependencies. |
| Replay/live confusion | Fixture presented as current Solari output | Evidence mode is contract data; fixture `observedAt` immutable; replay time separate; tests reject relabeling. | Review screenshots/copy. Current no-key environment cannot support live claim. |
| Evidence tampering/mix-and-match | Decision uses altered observations | Versioned schemas, observation IDs, exact submitted-source and requirement references, duplicate/reference rejection, and server-side package/price subtotal recomputation. | Cryptographic signing is not part of V1; a future portable attestation would require separate key management. |
| Unsafe handoff escalation | Research becomes purchasing authority | Recommendation has no write capability. Only explicit user open/handoff. `visited` is not cart/order/purchase; pantry update remains explicit. | Retailer page actions are performed by the user under retailer controls. |

## Retention

Retain only normalized observation/decision fields needed for reproducibility: IDs, sources, dates, modes, versions, values, and ambiguity. Do not retain the Solari key, operator token, or auth headers; session/control/signed URLs; cookies/localStorage/profiles/accounts; raw HTML/screenshots/replay/captcha/proxy data; or address/payment/cart/order/checkout data.

Before production, define exact evidence retention/expiry/deletion, provider region/retention review, incident rotation, and log-scrubbing tests. “The app does not use it” is not proof a provider stores nothing.

## Evidence expiry and UX

Age is first-class. Live consumers compare `observedAt` with the 24-hour policy and reject stale evidence without rewriting time. Recorded fixture mode may admit the July 16 observations only as prominently labeled historical replay; replay time never changes freshness. Source/time/mode stay near price. A complete item subtotal is still labeled as excluding tax, fees, deposits, promotions, memberships, fulfillment, substitutions, and later changes.

If any required line is unpriced/unresolved, total is `null`. A priced subtotal must name exclusions. Placeholder `$0.00` is forbidden.

## Solari references and live gate

- [Sessions](https://docs.getsolari.com/sessions): defaults and close/release lifecycle.
- [Profiles](https://docs.getsolari.com/profiles): stored cookies/localStorage and login-equivalent sensitivity.
- [Sandboxes](https://docs.getsolari.com/sandboxes): headless compute and explicit `kill()`.
- [API reference](https://docs.getsolari.com/api-reference): bearer auth and signed capabilities.

Live admission fails with `403` before Solari/provider work unless the default-off `SOLARI_LIVE_EXECUTION_ENABLED` flag is explicitly enabled, the server has a valid `SOLARI_OPERATOR_TOKEN`, and an operator supplies its exact Bearer value. Neither `SOLARI_API_KEY` nor the operator token is shipped to iOS or web clients. Successful responses identify the exact execution mode in `x-smartcart-data-mode`; errors use `solari-error`.

Block live enablement if any is unproven: owned source/authorization policy; both server-only secrets; operator admission; SSRF/redirect tests; profile/recording/proxy/stealth/captcha disabled; no account/cart/checkout calls; schema/reference/math validation; nullable totals; source/time/mode UI; cleanup; rate/cost controls; log/secret scan; and explicit user handoff.
