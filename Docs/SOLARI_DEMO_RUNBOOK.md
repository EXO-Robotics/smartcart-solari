# Solari demo, deployment, and evidence runbook

This runbook keeps four claims separate:

1. **Walmart fixture replay** proves deterministic historical replay, package math, and trust copy. It never invokes Solari.
2. **Actions Browser + Sandbox proof** proves real Solari execution against the owned synthetic Demo Grocer at exact commit `eee8c84`.
3. **Deployed V2 backend smoke** proves Vercel routing, Upstash one-use challenge state, and fail-closed invalid/replay handling.
4. **Signed native V2 flow** remains PENDING until a physical iPhone build completes valid Apple attestation, assertion, and research.

Never combine these into a claim that Walmart was researched live or that the signed native path has run.

## Fixed use case

- Recipe: **Chicken Parmesan Pasta**
- Pantry exclusions: olive oil and garlic
- Remaining need: chicken 1.5 lb; penne 12 oz; Parmesan 3 oz
- Owned Demo Grocer selected basket: one 3 lb chicken package, one 16 oz penne package, one 6 oz finely shredded Parmesan package
- Observed synthetic subtotal: `$12.79`

The Walmart fixture uses the same three selected product IDs but retains historical observation time `2026-07-16T12:00:00Z`. It is not current/guaranteed pricing or availability.

## 1. Establish exact repository state

Run from the monorepo root in a clean submission worktree:

```sh
git status --short
git branch --show-current
git rev-parse HEAD
git merge-base --is-ancestor fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9 HEAD
git remote -v
```

Expected implementation identity is branch `feat/native-solari-beta`, commit `eee8c840b59def4428548c66203304193fa93520`, with `origin` pointing to `EXO-Robotics/smartcart-solari` and `upstream` to `EXO-Robotics/smartcart-ios`. If the worktree is dirty, do not deploy; create a clean worktree at the exact commit.

Native implementation commits are:

- `9369d70` — optional native research flow and App Attest client
- `2516414` — V2 contracts, App Attest verifier, Upstash admission/quotas/kill switch
- `eee8c84` — Vercel runtime asset packaging

## 2. Install and run deterministic qualification

From the monorepo root:

```sh
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
python3 website/solari-demo/validate.py
python3 -m unittest discover -s website/solari-demo/tests -v
node --check website/solari-demo/app.js
node --check website/solari-demo/retailer/retailer.js
```

Current frozen results are 55/55 focused Solari backend tests and 185/185 full backend tests. Report counts only from the exact run/commit being qualified.

The focused suite covers V1 fixture/live proof, V2 schemas, owned-source policy, URL/DNS/redirect checks, Browser/Sandbox lifecycle and cancellation, App Attest parsing/signatures/identity/request binding/replay, Upstash idempotency/quotas/concurrency/kill switch, and public API routing.

## 3. Exercise the historical replay

Start the local backend from the monorepo root:

```sh
npm --prefix backend start
```

In another shell:

```sh
curl --fail-with-body --silent --show-error \
  -X POST http://127.0.0.1:8787/v1/solari/research \
  -H 'content-type: application/json' \
  --data-binary @contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json
```

The response must be V1 `recorded_fixture`, complete `$12.79`, with Browser and Sandbox both `not-run-fixture-replay`. No key, operator token, or App Attest is required because fixture mode invokes none of them.

For the static submission UI:

```sh
python3 -m http.server 8080
```

Open `http://127.0.0.1:8080/website/solari-demo/`. Confirm historical/replay labeling, source/date, package counts, ambiguity, estimate exclusions, and explicit retailer links. The local Demo Grocer pages are only local inspection surfaces; cloud Browser proof uses the published HTTPS owned catalog.

## 4. Verify the credentialed Solari proof

Use the immutable workflow/receipt; do not infer live execution from the replay UI:

```sh
gh run view 33519606791 \
  --repo EXO-Robotics/smartcart-solari \
  --json databaseId,headSha,status,conclusion,url,workflowName

jq '{receiptVersion, qualifiedAt, submission, workflow, useCase, execution, basket, optimizer, trust}' \
  evidence/live/smartcart-solari-live-proof-33519606791.json
```

Required identity/evidence:

- workflow conclusion `success`;
- `headSha` exactly `eee8c840b59def4428548c66203304193fa93520`;
- six Browser observations between `2026-09-01T14:27:48.423Z` and `2026-09-01T14:27:55.394Z`;
- three Sandbox decisions and `$12.79` complete owned-catalog subtotal;
- `fixtureReplay: false`;
- Browser page/session/client and Sandbox cleanup enforced before response;
- source is SmartCart Demo Grocer synthetic catalog;
- no account, cart, or checkout action.

This is actual Solari Browser/Sandbox proof, but it is V1 operator qualification and synthetic-source evidence—not a native/App Attest or real-retailer receipt.

## 5. Verify deployed V2 identity and smoke

The authority is:

```sh
jq . evidence/live/smartcart-solari-beta-deployment-20260901.json
```

Confirm:

- production deployment `dpl_FD8iBpRhvmEckcUm7oo7v5tMoxdh`;
- READY state;
- API base `https://smartcart-solari-beta.vercel.app` and health URL `https://smartcart-solari-beta.vercel.app/health`;
- exact commit `eee8c84` and `feat/native-solari-beta`;
- health `200`;
- challenge issuance `201`;
- malformed attestation `403` with `app_attest_malformed`;
- consumed-challenge replay `403` with `app_attest_challenge_invalid`;
- Upstash one-time challenge burn observed.

A non-mutating reachability check is:

```sh
curl --fail-with-body --silent --show-error \
  https://smartcart-solari-beta.vercel.app/health
```

Do not casually rerun challenge/attestation smoke against production: challenge issuance creates short-lived Upstash state, and the invalid/replay sequence intentionally consumes it. Use the versioned receipt or a separately authorized smoke plan.

The existing smoke uses malformed evidence intentionally. It does not prove a successful Apple certificate chain, device key registration, assertion counter, or signed native research request.

## 6. Verify the native integration

Run the focused native tests on an available simulator:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SmartCartTests/SolariEvidenceContractTests
```

Current evidence: 13/13 focused native tests passed.

Build the beta configuration separately:

```sh
xcodebuild build \
  -project SmartCart.xcodeproj \
  -scheme SmartCart-SolariBeta \
  -configuration Release-SolariBeta \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Current evidence: Release-SolariBeta simulator build PASS. A separate Debug simulator build installed and launched successfully; Debug is useful for recorded replay only.

### Native demo flow

1. Open Chicken Parmesan Pasta in Recipe Ready.
2. Confirm olive oil and garlic are excluded and the remaining reviewed quantities are correct.
3. Confirm both **Shop This Recipe** and **Research current options** are present when the beta backend is configured.
4. Tap **Research current options**. Normal product preparation runs first; the research sheet appears before the retailer queue is finalized.
5. In Debug replay, confirm the screen states that App Attest, Browser, and Sandbox did not run.
6. Inspect package counts/coverage/surplus, source, observed time, confidence, ambiguity, subtotal/completeness, price limitations, and provenance.
7. Confirm **Refresh current options** bypasses the two-minute memory cache.
8. Confirm **Edit shopping list** returns without handoff.
9. Confirm a changed plan is rejected before continuation.
10. Confirm **Continue to retailer** invokes only SmartCart’s existing user-controlled queue.
11. Confirm no account/cart/order/purchase or automatic pantry update is claimed.

The native V2 live state cannot be legitimately demonstrated on Simulator as a successful App Attest vector.

## 7. Physical iPhone / App Attest gate

Check signing without exposing certificates:

```sh
security find-identity -v -p codesigning
```

Current result: `0 valid identities found`. Stop here. Do not weaken signing, remove the App Attest entitlement, add a client bearer, enable fixture replay in Release-SolariBeta, or claim public native use.

When signing becomes available, the qualification must use an allowlisted TestFlight `Release-SolariBeta` build on a physical iPhone. The verifier accepts the TestFlight validation category/build; a locally sideloaded development build is not sufficient:

1. Archive/sign/upload the beta and install the allowlisted build through TestFlight.
2. Start with a fresh App Attest key state.
3. Observe initial challenge → Apple attestation → accepted key.
4. Trigger **Research current options** and observe research challenge → assertion bound to exact V2 body → Browser/Sandbox result.
5. Verify a replayed challenge/assertion fails.
6. Verify runtime kill switch and quota UX.
7. Capture only sanitized request IDs, schema/provenance, timestamps, cleanup, and HTTP outcomes—never attestation/assertion blobs, keys, Redis credentials, or Solari capability URLs.
8. Run Dynamic Type and VoiceOver checks.

Only then can the signed native path move from PENDING. TestFlight and App Store are separate later gates.

## 8. Clean Vercel deployment procedure

The Git checkout is a monorepo and the Vercel CLI runs from that root, while the linked Vercel project’s configured Root Directory is `backend/`. This preserves access to the shared `contracts/` tree during function packaging. Deploy from a clean worktree at the intended commit:

```sh
git status --short
git rev-parse HEAD
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
vercel link
vercel deploy --prod
```

Do not change the linked project Root Directory from `backend/`, and do not `cd backend` or use `--cwd backend` for this monorepo deployment. `backend/vercel.json` and the root `.vercelignore` package the V2 contracts and Browser runtime assets while excluding native/docs artifacts.

Configure environment names in the Vercel project, never values in source/docs:

- `SOLARI_API_KEY`
- `SOLARI_DEMO_RETAILER_BASE_URL`
- `SOLARI_BETA_ENABLED`
- `KV_REST_API_URL`
- `KV_REST_API_TOKEN`
- `SOLARI_BETA_RUNTIME_KEY`
- `SOLARI_APP_ATTEST_TEAM_ID`
- `SOLARI_APP_ATTEST_BUNDLE_ID`
- `SOLARI_APP_ATTEST_ALLOWED_BUILDS`
- `SOLARI_APP_ATTEST_CHALLENGE_TTL_SECONDS`
- `SOLARI_BETA_PER_KEY_HOURLY_LIMIT`
- `SOLARI_BETA_PER_KEY_DAILY_LIMIT`
- `SOLARI_BETA_GLOBAL_DAILY_LIMIT`
- `SOLARI_BETA_CONCURRENCY_LIMIT`
- `SOLARI_BETA_IDEMPOTENCY_TTL_SECONDS`
- `SOLARI_BETA_LEASE_TTL_SECONDS`
- `SOLARI_BETA_MAX_BODY_BYTES`
- `SOLARI_BETA_KILL_POLL_MS`
- `SOLARI_BROWSER_BASE_URL`
- `SOLARI_SANDBOX_BASE_URL`
- `SOLARI_BROWSER_TIMEOUT_MS`
- `SOLARI_SANDBOX_TIMEOUT_MS`
- `SOLARI_REQUEST_TIMEOUT_MS`
- `SOLARI_MAX_BODY_BYTES`
- `SOLARI_RATE_LIMIT_PER_MINUTE`
- `SOLARI_TRUST_FORWARDED_FOR`

`SOLARI_OPERATOR_TOKEN` and `SOLARI_LIVE_EXECUTION_ENABLED` belong only to the separate V1/operator qualification surface, not native V2 authentication. Walmart authorization variables must remain unset/false without real written authorization.

After deployment, record immutable deployment ID/URL, application alias, exact commit/branch, READY state, runtime-switch state, non-secret app/build identity, state-store class, and sanitized smoke results in a new versioned receipt. Never include secret values.

## 9. Claim and secret checks

From monorepo root:

```sh
rg -n "live Walmart|live Target|guaranteed price|current Walmart price|public native|shipped native" \
  README.md Docs SmartCart backend website evidence

rg -n "slr_live_|SOLARI_API_KEY=|KV_REST_API_TOKEN=|cdpEndpoint|wsEndpoint|replay-url" . \
  -g '!backend/node_modules/**' -g '!.git/**' -g '!.env*'

git diff --check
```

Expected matches are negations, environment-name documentation, code/test canaries, or known provider field names—not real credentials or unsupported claims.

## 10. Final receipt checklist

Record:

- repository, branch, and exact commit;
- upstream base and isolated production boundary;
- V1 live run ID/commit/receipt separately from V2 deployment/native evidence;
- Vercel deployment ID/READY receipt;
- backend/native/build/test counts from the exact commit;
- simulator build versus install/launch distinction;
- physical signing and valid signed App Attest state;
- synthetic Demo Grocer and Walmart replay limitations;
- Browser/Sandbox roles and cleanup;
- App Attest/Upstash/kill-switch/quota/cache/cancellation boundaries;
- remaining signing, physical-device, TestFlight, App Store, accessibility, and authorized-retailer gates.

Do not claim a signed native run, public native beta, TestFlight, App Store, live Walmart/Target evidence, or real-retailer value without exact corresponding evidence.
