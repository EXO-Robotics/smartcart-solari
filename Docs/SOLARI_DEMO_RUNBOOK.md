# Solari demo and evidence runbook

This runbook keeps three claims separate:

- **Walmart fixture replay** proves deterministic contracts, package math, API/UI behavior, and truthful retailer copy against dated upstream observations.
- **Live Demo Grocer** proves Solari Browser observed an owned page and Solari Sandbox evaluated it during that run.
- **Live Walmart** fails closed unless both written-authorization gates are present; this submission has neither authorization nor a live receipt. **Live Target** is unsupported.

Never use a fixture receipt, screenshot, local server, passing test, or Demo Grocer receipt as evidence of live third-party retailer research.

## Fixed product demo

- Recipe: **Chicken Parmesan Pasta**
- Walmart mode: **fixture replay only**
- Pantry exclusions: olive oil and garlic

| Ingredient need | Walmart product fixture | Package | Historical fixture price |
| --- | --- | --- | ---: |
| Chicken, 1.5 lb | `10414680` | 1 × 3 lb | $9.47 |
| Penne, 12 oz | `10534084` | 1 × 16 oz | $1.24 |
| Parmesan, 3 oz | `10452414` | 1 × 6 oz | $2.08 |

Expected fixture estimate: **$12.79**. Observation time: `2026-07-16T12:00:00Z`. These are historical seeded observations, not current/guaranteed prices, availability, or Solari-run proof.

## 1. Establish repository identity

```sh
git status --short
git branch --show-current
git rev-parse HEAD
git merge-base --is-ancestor fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9 HEAD
git remote -v
```

Record the submission commit. Confirm `upstream` is `EXO-Robotics/smartcart-ios` and `origin` is `EXO-Robotics/smartcart-solari`. Do not run from the production checkout.

## 2. Install and inspect credential status

```sh
cd backend
npm install
if test -n "${SOLARI_API_KEY:-}"; then
  echo "SOLARI_API_KEY=set"
else
  echo "SOLARI_API_KEY=missing"
fi
```

The construction environment should report `missing`. Continue with fixture replay and make no live claim. Fixture replay is public and rate-limited, requires no operator credential, and never invokes Solari. A key alone never authorizes Walmart, and Target is not an admitted live retailer.

## 3. Deterministic qualification

From `backend/`:

```sh
npm run test:solari
npm test
```

`npm run test:solari` runs `backend/test/solari*.test.js`, covering the four AJV schemas, canonical fixtures, bounded live-request generator, URL/policy admission, fixture provider, optimizer, API, Browser/Sandbox lifecycle adapters, and authorization boundary. Report only a count from a fresh run; do not preserve a count here because the suite can grow. `npm test` is the broader Node regression milestone.

From repository root, validate the dependency-free submission UI and synthetic Demo Grocer catalog:

```sh
python3 website/solari-demo/validate.py
python3 -m unittest discover -s website/solari-demo/tests -v
node --check website/solari-demo/app.js
node --check website/solari-demo/retailer/retailer.js
```

Then run claim and secret checks:

```sh
rg -n "live price|guaranteed price|current price|live Walmart|live Target|live Solari" README.md Docs backend SmartCart website
rg -n "SOLARI_API_KEY|slr_live_|cdpEndpoint|wsEndpoint|replay-url|profileId" . \
  -g '!backend/node_modules/**' -g '!.git/**'
```

Interpretation:

- Documentation may contain risky phrases only while negating/explaining them.
- Source may name environment/endpoint fields and defenses, but must not contain a real key/capability URL or client-side key path.
- Fixtures decode as replay mode and retain `2026-07-16T12:00:00Z`.
- [`contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json`](../contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json) and [`chicken-parmesan-walmart-result.json`](../contracts/fixtures/v1/solari/chicken-parmesan-walmart-result.json) validate against all four Solari V1 schemas.
- $12.79 is complete only because all three fixture lines have valid USD package count/price.
- A missing-price test returns null/incomplete total, not `$0.00` or a partial sum labeled total.
- Tests reject unknown versions, source/observation/reference mismatch, unauthorized retailer/live mode, disallowed URL/redirect/private address, incompatible units, non-finite/negative values, and fixture-to-live relabeling.

## 4. Walmart fixture demo

Start the backend. Fixture replay requires no Solari key:

```sh
cd backend
npm start
```

In another shell at repository root, exercise the exact endpoint/contract directly:

```sh
curl --fail-with-body --silent --show-error \
  -X POST http://127.0.0.1:8787/v1/solari/research \
  -H 'content-type: application/json' \
  --data-binary @contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json
```

The response must be `solari-shopping-research-result-v1`, `recorded_fixture`, Walmart, complete, $12.79, and carry provenance `not-run-fixture-replay` for both Browser and Sandbox.

The Debug Xcode configuration points the experiment at `http://localhost:8787` and enables Walmart fixture replay; Base/Release leave the endpoint blank and replay off. Launch `SmartCart.xcodeproj` on an iOS 17+ simulator.

1. Select Chicken Parmesan Pasta.
2. Confirm extraction and servings in Recipe Ready.
3. Confirm pantry removes olive oil and garlic.
4. Start Walmart comparison in fixture replay mode.
5. Inspect product IDs, package counts, prices, sources, `2026-07-16T12:00:00Z`, confidence/ambiguity, replay label, and $12.79 estimate.
6. Confirm copy says historical—not live/current/guaranteed—and may not match location.
7. Confirm estimate exclusions: tax, fees, promotions, membership, fulfillment, later changes.
8. Tap an explicit Walmart handoff and verify the retailer page opens under user control.
9. Return and verify no cart/order/purchase is claimed and pantry is unchanged without confirmation.

Capture a fixture receipt with repository commit, fixture ID, versions, commands/results, and replay time. Never alter `observedAt`.

The parallel static submission demo is available by serving repository root:

```sh
python3 -m http.server 8080
```

Open `http://127.0.0.1:8080/website/solari-demo/`. The Browser-controlled synthetic products are under `http://127.0.0.1:8080/website/solari-demo/retailer/product/<id>.html`; these local URLs are for inspection only and are unreachable from a cloud Solari Browser.

## 5. Live Demo Grocer (credential-gated)

Deploy `website/solari-demo/` to an owned, credential-free HTTPS origin so the cloud Browser can reach the controlled product pages, then set `SOLARI_DEMO_RETAILER_BASE_URL` to that deployment’s `/solari-demo` root. Use only that owned host/source and server-side `SOLARI_API_KEY`. Live execution also requires the explicit `SOLARI_LIVE_EXECUTION_ENABLED=true` flag and a randomly generated 32–256 character `SOLARI_OPERATOR_TOKEN` using only ASCII letters, digits, `.`, `_`, `~`, or `-`. `SOLARI_BROWSER_BASE_URL` is optional; `SOLARI_SANDBOX_BASE_URL` defaults to `https://api.getsolari.com`. Defaults are Browser 6,000 ms, Sandbox 10,000 ms, request body 32,768 bytes, and five research requests per minute. Never put either secret in Xcode, frontend state, screenshots, fixtures, logs, or committed `.env`; never paste a literal token into a saved command or shell history.

Before running, verify:

- live requests receive `403` before service/provider work unless the flag is enabled, the token is validly configured, and the operator supplies its exact `Authorization: Bearer ...` value;
- the operator token is never shipped to iOS/web; fixture replay requires no token and never invokes Solari;
- allowlist is exactly the owned host/routes and arbitrary client URLs are rejected;
- the configured host resolves only to public addresses and the final post-navigation URL exactly equals the admitted candidate;
- Walmart live requests fail with a key alone unless both authorization gates are present, and Target is rejected;
- redirects/private-address destinations fail;
- profile, recording, proxy, stealth, and captcha are absent/false;
- volumes and snapshots are not used;
- candidate/time/concurrency/rate/cost limits are active;
- Browser session and Solari Browser client close, and Sandbox kills, on success/timeout/cancellation/error;
- no raw HTML/screenshot/replay retention;
- Sandbox receives no secret and needs no network.

Generate the only admitted live Demo Grocer request from the bounded server-side template, then submit it from a controlled operator shell. Do not expose this Bearer token through native or web artifacts:

```sh
cd backend
npm run --silent build:solari-demo-request -- \
  --base-url https://YOUR_PUBLIC_HOST/solari-demo \
  > /tmp/solari-live-request.json

curl --fail-with-body --silent --show-error \
  -X POST https://YOUR_BACKEND_HOST/v1/solari/research \
  -H 'content-type: application/json' \
  -H "Authorization: Bearer ${SOLARI_OPERATOR_TOKEN}" \
  --data-binary @/tmp/solari-live-request.json
```

The generator rejects non-HTTPS origins, credentials, IP/localhost hosts, queries, and fragments. It emits only the frozen three-requirement/six-candidate Demo Grocer request with fresh request metadata and exact `/retailer/product/<id>.html` paths. Use the curl example only in a supervised operator environment where process visibility is controlled; do not paste the expanded command or secret into tickets, recordings, receipts, or CI logs. A successful response must return `x-smartcart-data-mode: live`; an error returns `solari-error`.

The sanitized receipt includes submission commit/time, evidence/decision versions, live-owned-demo mode, canonical source and per-product `observedAt`, observed fields or rejection reasons, package/basket decision/completeness, and successful close/kill outcomes with all resource IDs/capability URLs redacted.

Reject the run on unexpected login/captcha/consent, out-of-allowlist navigation, indefensible package/price match, or unconfirmed cleanup. Do not enable bypass capabilities to force a pass.

## 6. Native and visual checks

Run the focused evidence-contract tests:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SmartCartTests/SolariEvidenceContractTests
```

Then run the broader simulator build/test milestone appropriate to the frozen submission commit. Verify:

- fixture vs live-owned-demo mode is prominent near prices;
- source/date are visible without debug UI;
- prices do not say live/current/guaranteed;
- location uncertainty is visible;
- confidence/ambiguity are understandable;
- incomplete basket has no complete total;
- Dynamic Type/VoiceOver preserve disclosures and handoff;
- the only retailer action is user-controlled open.

A simulator screenshot is visual evidence only—not physical-device, App Store, live Walmart/Target, or purchase evidence.

## 7. Final receipt

Record public repository URL/commit; deployed demo URL or `not deployed`; fixture and live-owned-demo qualification separately; exact fresh test commands/counts; contract files/versions and fixture ID; red-team iteration/score/remaining Low findings/justified rejections; authorization/location/expiry limitations; and inspection paths for README, these docs, schemas/fixtures, Browser adapter, Sandbox optimizer, API boundary, and native view/model/tests.

Do not claim 10/10 review, live demo, live Solari, production readiness, or zero issues without a current receipt.
