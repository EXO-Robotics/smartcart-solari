# Solari submission qualification receipt

## Exact identities

- Public repository: `https://github.com/EXO-Robotics/smartcart-solari`
- Branch: `feat/native-solari-beta`
- Current qualified implementation: `eee8c840b59def4428548c66203304193fa93520`
- Native integration sequence: `9369d70` → `2516414` → `eee8c84`
- Clean upstream base: `fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`
- Credentialed Solari run: [`33519606791`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33519606791), successful at exact commit `eee8c84`
- Solari execution receipt: [`smartcart-solari-live-proof-33519606791.json`](../evidence/live/smartcart-solari-live-proof-33519606791.json)
- Vercel production deployment: `dpl_FD8iBpRhvmEckcUm7oo7v5tMoxdh`, READY
- API base: `https://smartcart-solari-beta.vercel.app` ([health](https://smartcart-solari-beta.vercel.app/health))
- Deployment/smoke receipt: [`smartcart-solari-beta-deployment-20260901.json`](../evidence/live/smartcart-solari-beta-deployment-20260901.json)
- Public replay/demo: `https://exo-robotics.github.io/smartcart-solari/website/solari-demo/`

Production SmartCart is not redirected or modified. The normal Release configuration still contains no Solari endpoint. The beta uses a separate scheme, build configuration, bundle identity, endpoint, entitlements file, and public submission repository.

## What is implemented in the native product flow

Commit `9369d70` adds an optional **Research current options** action to Recipe Ready. It follows the normal path through reviewed recipe state, pantry exclusion, shopping-list aggregation, and product matching. Instead of immediately finalizing the Safari queue, the explicit research intent evaluates the current waiting items and opens the native Solari Basket Review sheet.

The admitted plan is deliberately narrow:

- one to three waiting shopping items;
- positive reviewed quantities in pounds, ounces, or count;
- unique requirement, ingredient, and candidate identities;
- exact candidates from the owned Demo Grocer set;
- no source URLs, retailer credentials, account data, or Solari secret supplied by the app.

The sheet shows package count/size, coverage and surplus, visible line price, observed subtotal or incomplete state, source, timestamp, confidence, ambiguity, provenance, and limitations. The user can refresh, edit, fall back to normal SmartCart, or explicitly continue to the existing retailer queue. A changed plan invalidates the result before handoff.

Commit `2516414` adds the productionized V2 boundary: Apple App Attest challenge/attestation/assertion verification, exact request-byte binding, replay counters, idempotency, Upstash quotas/concurrency leases, runtime kill switch, V2 schemas, and server-side Solari admission. Commit `eee8c84` packages the contracts and Browser runtime assets needed by the Vercel function.

## Actual credentialed Browser + Sandbox evidence

Actions run `33519606791` is the current Solari execution proof. The [receipt](../evidence/live/smartcart-solari-live-proof-33519606791.json) binds the run to commit `eee8c84` and records:

- six fresh Browser observations from `2026-09-01T14:27:48.423Z` through `2026-09-01T14:27:55.394Z`;
- the exact six owned Demo Grocer product URLs and product IDs;
- three selected packages: 3 lb chicken, 16 oz penne, and 6 oz finely shredded Parmesan;
- one package per requirement and a complete synthetic subtotal of `$12.79`;
- three Sandbox decisions using `smallest-sufficient-package-v1`;
- independent SmartCart arithmetic verification;
- Browser page/session/client and Sandbox cleanup enforced before success;
- no fixture replay, account, cart, or checkout action.

This proves actual Solari Browser and Sandbox execution against SmartCart’s owned synthetic catalog. It does not prove a real retailer’s price, availability, or consumer value, and it does not prove that an Apple-signed native V2 request reached the deployed backend.

## Deployed App Attest/Upstash boundary

The [deployment receipt](../evidence/live/smartcart-solari-beta-deployment-20260901.json) is the authority for deployment identity and smoke results. It records production READY state and:

| Smoke check | Result | Meaning |
| --- | --- | --- |
| `GET /health` | `200` | deployed service route is reachable |
| challenge issuance | `201` | enabled runtime and Upstash one-use challenge write are reachable |
| malformed attestation | `403` | invalid Apple evidence fails closed |
| replay of consumed challenge | `403` | the one-use challenge was burned and could not be reused |

The smoke deliberately used invalid attestation material. It proves routing, state-store integration, challenge consumption, and the reject path. It is not a successful Apple attestation or assertion. No signed native research request is claimed.

## Fresh qualification matrix

| Qualification | Result |
| --- | --- |
| `npm run test:solari` | 55 passed, 0 failed |
| full backend `npm test` | 185 passed, 0 failed |
| focused native Solari tests | 13 passed, 0 failed |
| `Release-SolariBeta` simulator build | PASS |
| separate Debug simulator install and launch | PASS |
| Vercel production deployment | READY |
| deployed App Attest/Upstash smoke | health 200; challenge 201; invalid 403; replay 403 |
| credentialed Solari Browser + Sandbox workflow | PASS, run `33519606791`, commit `eee8c84` |
| physical iPhone code signing identities | **PENDING — 0 valid identities** |
| valid signed App Attest attestation/assertion/research vector | **PENDING** |
| TestFlight and App Store | **PENDING** |

The Release-SolariBeta simulator build proves compilation and packaging for that configuration. The Debug simulator launch proves the app can install and reach the local replay UI. Simulator App Attest is not accepted as physical-device/TestFlight proof. Neither result makes the native beta publicly usable.

## V2 evidence and admission contract

The native path accepts only:

- `solari-shopping-research-request-v2`
- `retailer-observation-v2`
- `basket-decision-v2`
- `solari-shopping-research-result-v2`
- `solari-app-attest-research-envelope-v1`

Challenge and initial-attestation schemas are versioned separately under [`contracts/v2/solari/`](../contracts/v2/solari/). The App Attest assertion hash binds the one-use server challenge, HTTP method/path, and SHA-256 digest of the exact encoded research body. The backend checks the Apple certificate chain/receipt/nonce/app identity, allowed build, registered key, monotonic assertion counter, one-use challenge, request schema, and owned-catalog policy before provider work.

After admission, Upstash atomically enforces request idempotency, per-key hourly/daily quotas, a global daily quota, and a concurrency lease. The runtime key is checked before challenge, attestation, and research and is polled during provider work; disabling it cancels live work. Aborted/incomplete incoming requests propagate cancellation. Browser and Sandbox providers share a bounded request deadline and clean up before success. A response-socket hangup after a complete request body may run until that deadline or kill-switch observation.

The native app independently checks request/result identity, exact derived source URL, product allowlist, freshness, package and subtotal math, completeness, Browser/Sandbox provenance, enforced cleanup, App Attest access boundary, and user-controlled handoff. Validated results are cached in memory for two minutes with at most eight entries; refresh bypasses the cache and nothing is persisted.

## Trust claims supported

- Solari Browser and Sandbox materially perform distinct jobs in the owned-catalog workflow.
- Observations include source and timestamps; visible prices are explicitly non-guaranteed.
- Missing/ambiguous evidence stays visible and cannot become a complete total silently.
- Solari, Redis, and control credentials stay server-side.
- Browser profiles/login state and retailer account/cart/checkout authority are absent.
- Runtime disablement, quotas, idempotency, cancellation, and cleanup bound spend and resource lifetime.
- The normal SmartCart handoff and pantry-confirmation boundaries remain user controlled.

## Not demonstrated / remaining gates

1. **Signed native path:** the host has zero valid signing identities, so no physical iPhone build, initial Apple attestation, assertion, or end-to-end V2 native research call has run. The verifier intentionally accepts only an allowlisted TestFlight validation category/build, so a locally sideloaded development build is not a substitute.
2. **Distribution:** there is no TestFlight build, App Store build, or public native beta.
3. **Retailer value:** Demo Grocer is owned and synthetic. Walmart remains fixture replay only; Target live research is unsupported. A real consumer trial needs an authorized retailer source.
4. **Remote DNS TOCTOU:** the server performs fail-closed public-DNS preflight and exact pre/post-render URL checks, but the remote Browser SDK does not provide DNS pinning. An authorized production source needs locked owned DNS and a trusted egress boundary.
5. **Operational rollout:** secrets, allowed-build changes, kill-switch ownership, quota alerts, retention review, incident response, and physical-device accessibility checks require an operator runbook before inviting testers.

These are explicit release gates, not failed Browser/Sandbox proof. Do not describe the native beta as shipped or publicly usable until the signed App Attest vector and distribution evidence exist.
