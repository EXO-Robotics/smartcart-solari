# Solari submission qualification receipt

## Exact identities

- Public repository: `https://github.com/EXO-Robotics/smartcart-solari`
- Live-qualified implementation commit: `8d592fa2d11efe1a3f0996274c14c00caae08148`
- Sanitized-receipt publication commit: `b7afbb96c567235cdebe3515ce32adea82c05570`
- Clean upstream base: `fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`
- Credentialed Solari run: [`33501521988`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33501521988) — successful
- Versioned live receipt: [`smartcart-solari-live-proof-33501521988.json`](../evidence/live/smartcart-solari-live-proof-33501521988.json)
- Public artifact: `https://exo-robotics.github.io/smartcart-solari/website/solari-demo/`
- Public receipt: `https://exo-robotics.github.io/smartcart-solari/evidence/live/smartcart-solari-live-proof-33501521988.json`
- Pages deployment run: [`33501869874`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33501869874) — successful for receipt commit `b7afbb9`
- Internal review log: [`SOLARI_RED_TEAM.md`](SOLARI_RED_TEAM.md)

This qualification keeps three claims separate: the interactive Walmart replay, actual credentialed Solari execution against the owned synthetic Demo Grocer, and production/native release status. Internal model reviews remain development feedback, not external validation.

## Demonstrated end-to-end use case

Chicken Parmesan Pasta produces five reviewed ingredients. SmartCart pantry allocation removes olive oil and garlic, leaving 1.5 lb chicken, 12 oz penne, and 3 oz Parmesan.

Credentialed run `33501521988` then performed the actual Solari path:

1. The SmartCart backend generated the fixed, schema-validated six-candidate request for the owned Demo Grocer.
2. Solari Browser loaded six JavaScript-rendered product pages without a profile, login, cookies, recording, stealth, proxy, captcha, cart, or checkout interaction.
3. Browser emitted six `retailer-observation-v1` records with exact source URL, product ID, package size, visible synthetic price, timestamp, qualitative confidence, and ambiguity.
4. The gluten-free penne and non-finely-shredded Parmesan alternatives were correctly downgraded to `medium` confidence with explicit reasons; the three selected matches remained `high`.
5. Solari Sandbox received only structured public quantities/observations, selected one adequate package for each need, and returned a complete `$12.79` synthetic-catalog basket.
6. SmartCart independently recomputed the Sandbox selection and arithmetic before returning success.
7. Every Browser page, Browser session/client, and Sandbox teardown completed before the success response. The final authority remained `user-controlled-retailer-handoff`.

The public interactive Walmart flow still loads the dated `2026-07-16T12:00:00Z` fixture and local optimizer. Its `$12.79` is not live/current pricing and is not attributed to Solari. The public page now links the separate credentialed live receipt without relabeling the replay.

## Fresh qualification checks

| Check | Result |
| --- | --- |
| credentialed owned-Demo-Grocer workflow | passed in run `33501521988` |
| live response mode/provenance | `live`; Browser and Sandbox confirmed; fixture false |
| live evidence | 6 timestamped Browser observations |
| live decisions | 3 Sandbox decisions; `$12.79`; independently verified |
| resource cleanup | Browser pages/session/client and Sandbox confirmed before success |
| `npm run test:solari` | 30 passed, 0 failed |
| `npm test` outside restricted sandbox | 160 passed, 0 failed |
| `python3 website/solari-demo/validate.py` | passed |
| demo Python unit tests | 4 passed, 0 failed |
| `node --check` for demo and retailer scripts | passed |
| `npm audit --omit=dev --audit-level=high` | 0 vulnerabilities |
| `git diff --check` | passed |
| secret-pattern scan | documented placeholders/test canaries only; live receipt clean |
| public Pages deployment | run `33501869874` passed |
| public page/receipt HTTP verification | exact live-proof and trust markers returned |

The restricted filesystem sandbox cannot bind localhost for the broad Node HTTP tests. The same suite passed 160/160 outside that sandbox. This is an execution-environment distinction, not a hidden test failure.

Native Debug full-source compile, Release full-source typecheck, and targeted `SolariEvidenceContractTests` source typecheck passed earlier; subsequent implementation changes are confined to backend Solari code, workflows, evidence, docs, and the static submission surface. Simulator/device runtime remains `PENDING` because the earlier CoreSimulatorService connection was invalid. No physical-device, TestFlight, App Store, production backend, or Release-native live-flow claim is made.

## What the evidence supports

- Production SmartCart and its remote remain untouched; this is an isolated public fork.
- Solari Browser actually performed the necessary dynamic-page observation job on the only admitted owned source.
- Solari Sandbox actually performed the authoritative isolated basket selection, followed by independent SmartCart verification.
- The exact run is bound to implementation commit, workflow run, request ID, response hash, source URLs, timestamps, decisions, trust assertions, and cleanup outcomes.
- No account, session profile, cart, checkout, payment, purchase, or autonomous handoff authority was used.
- The encrypted Solari key stayed server-side in GitHub Actions and is absent from the public receipt/repository.
- The live path materially improves evidence freshness, provenance, ambiguity handling, and isolated decision execution over normal seeded handoff architecture.

## What the evidence does not support

- The owned Demo Grocer is a synthetic catalog, not a consumer retailer or a claim of market value, inventory, or availability.
- The `$12.79` live receipt is a visible synthetic-catalog observation, not a current Walmart price or checkout quote.
- Solari did not run inside the public replay page; the page links a separate immutable live receipt.
- The backend live route is not deployed publicly, and the Release iOS app is not configured for live Solari.
- The native request builder remains a bounded internship demonstration rather than a general production shopping-list pipeline.
- There is no TestFlight/App Store shipment or externally validated hiring score.

## Remaining Low / productization issues

1. General native shopping-list-to-evidence integration and production user authentication are intentionally outside this isolated submission.
2. Browser and Sandbox have bounded individual timeouts, while one aggregate server-side request deadline remains a production hardening item.
3. The Browser SDK cannot pin remote DNS; production should use locked owned DNS plus a trusted egress/client-address boundary.
4. A consumer rollout needs a legally authorized retailer partner/API/feed or written automation permission. A key alone never authorizes Walmart, and Target remains unsupported.

These limitations prevent calling the fork a shipped SmartCart product. They do not negate the bounded internship result: actual Browser observation plus actual Sandbox optimization improved SmartCart's pre-handoff evidence while preserving the user's authority.
