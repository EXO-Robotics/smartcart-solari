# Solari V3 demo, deployment, and evidence runbook

Keep these claims separate:

1. **Native product flow:** SmartCart’s normal post-pantry/pre-handoff UI contains the optional research action and unchanged-list continuation.
2. **Walmart replay:** dated deterministic fixture; no Solari provider runs.
3. **Credentialed V3 proof:** real Browser and Sandbox execution against owned synthetic Demo Grocer through an operator-only server qualification boundary.
4. **Protected production backend:** deployed App Attest/Upstash admission and fail-closed smoke.
5. **Signed physical-device flow:** PENDING.

Never combine them into a claim that Walmart was researched live, Demo Grocer is a real retailer, or an Apple-signed native request ran.

## Fixed native flow

- Recipe: **Chicken Parmesan Pasta**
- Pantry exclusions: olive oil and garlic
- Remaining need: chicken 1.5 lb; penne 12 oz; Parmesan 3 oz
- Action: **Research current options** after normal SmartCart preparation
- V3 result: two 1 lb synthetic chicken packages, one 16 oz penne, one 6 oz Parmesan
- Selected observed synthetic subtotal: `$13.32`
- Cheapest adequate reference: `$12.79`
- Premium: `$0.53` within a `$0.75` cap
- Surplus: 31 oz → 15 oz; 16 oz avoided
- Final action: **Continue with original SmartCart list**; Demo IDs/prices do not transfer

## 1. Establish exact repository state

Run from a clean isolated monorepo root:

```sh
git status --short
git branch --show-current
git rev-parse HEAD
git merge-base --is-ancestor fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9 HEAD
git remote -v
```

Qualified code identity is `ced1154e76a376a7d630900f7c5f4b4317a3932d`. `origin` must be the submission repository and upstream must remain production SmartCart. If deployment files are dirty, create a clean worktree at the exact commit; do not deploy from the production checkout.

## 2. Run deterministic qualification

```sh
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
npm --prefix backend audit
python3 website/solari-demo/validate.py
python3 -m unittest discover -s website/solari-demo/tests -v
node --check website/solari-demo/app.js
node --check website/solari-demo/retailer/retailer.js
```

Frozen evidence at commit `ced1154`:

- focused Solari backend 71/71;
- full backend 201/201;
- web tests 6/6;
- npm audit 0 vulnerabilities.

Report counts only from the exact code under qualification.

## 3. Inspect the native product

Focused tests:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:SmartCartTests/SolariEvidenceContractTests
```

Current result: 20/20 PASS.

Generic unsigned beta build:

```sh
xcodebuild build \
  -project SmartCart.xcodeproj \
  -scheme SmartCart-SolariBeta \
  -configuration Release-SolariBeta \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Current result: PASS. This is not signing, App Attest, device, TestFlight, or App Store evidence.

### Native inspection flow

1. Open Chicken Parmesan Pasta in Recipe Ready.
2. Confirm olive oil and garlic are excluded; remaining quantities are 1.5 lb / 12 oz / 3 oz.
3. Confirm **Research current options** appears alongside the normal SmartCart action when the beta endpoint is configured.
4. Tap it and verify normal SmartCart preparation occurs before the research sheet.
5. In Debug replay, verify the sheet explicitly says App Attest, Browser, and Sandbox did not run.
6. Verify the V3 sheet explains the synthetic owned source and low-surplus-within-`$0.75` policy.
7. Inspect exact source/time, confidence/ambiguity, required/covered/package quantities, line totals, selected `$13.32`, cheapest `$12.79`, premium `$0.53`, and 16 oz surplus avoided.
8. Verify overage is explicit; no per-serving or “smallest sufficient” shortcut obscures package surplus.
9. Verify refresh bypasses cache and edit/done does not finalize or mutate the original list.
10. Change the plan and confirm continuation fails revalidation.
11. Tap **Continue with original SmartCart list** and verify only original SmartCart retailer matches are finalized. No `dg-*` ID or price appears in the retailer queue/cart.
12. Confirm no account, cart, purchase, checkout, inventory, or pantry-update claim.

The website can support explanation, but the demo narrative must begin with this native flow.

## 4. Verify the owned Browser surfaces

Use the Pages run and exact public pages:

```sh
gh run view 33528975472 \
  --repo EXO-Robotics/smartcart-solari \
  --json databaseId,headSha,status,conclusion,url,workflowName
```

Check HTTP 200 for each URL under:

`https://exo-robotics.github.io/smartcart-solari/website/solari-demo/retailer/product/`

- `dg-chicken-value-3lb.html`
- `dg-chicken-rightsize-1lb.html`
- `dg-penne-value-16oz.html`
- `dg-penne-rightsize-12oz.html`
- `dg-parmesan-value-6oz.html`
- `dg-parmesan-rightsize-3oz.html`

The initial page is deliberately JavaScript-rendered. After render, the product element must carry the exact product ID plus `data-catalog-era="current-v3"` and `data-synthetic-price="true"`. HTTP reachability alone is not Browser evidence; the credentialed receipt supplies that claim.

## 5. Verify credentialed V3 Browser + Sandbox

Do not infer execution from the web artifact. Inspect the immutable Actions identity and receipt:

```sh
gh run view 33529059284 \
  --repo EXO-Robotics/smartcart-solari \
  --json databaseId,headSha,status,conclusion,url,workflowName

jq '{receiptVersion,qualifiedAt,submission,workflow,execution,selectedProductIDs,basket,comparison,optimizer,trust}' \
  evidence/live/smartcart-solari-v3-qualification-33529059284.json
```

Require:

- conclusion `success` and head SHA exactly `ced1154e76a376a7d630900f7c5f4b4317a3932d`;
- access boundary `operator-qualification`, never App Attest;
- six exact V3 observations with unique IDs/URLs, fresh timestamps, `current-v3`, and `syntheticPrice: true`;
- selected IDs `dg-chicken-rightsize-1lb`, `dg-penne-value-16oz`, `dg-parmesan-value-6oz`;
- selected `$13.32`, cheapest `$12.79`, premium `$0.53`, cap `$0.75`;
- surplus 31 → 15 oz, 16 oz avoided;
- optimizer authority `solari-sandbox` and verification `smartcart-policy-invariants-no-local-global-argmin`;
- Browser/Sandbox cleanup before receipt;
- internally computed result SHA-256;
- no `rawText`, account, cart, or checkout evidence.

If authorized to run a new credentialed qualification, use the existing workflow rather than placing a key on a client:

```sh
gh workflow run solari-v3-qualification.yml \
  --repo EXO-Robotics/smartcart-solari
```

The workflow reads `SOLARI_API_KEY` only from repository secrets, invokes `npm run --prefix backend qualify:solari-v3`, and uploads a sanitized receipt. Never print or download secrets/capability URLs into submission artifacts.

The historical V1 run `33519606791` is prior proof only. Its `$12.79` selected basket does not qualify V3 IDs, current markers, or the new optimizer.

## 6. Verify deployed beta backend

The authority is:

```sh
jq . evidence/live/smartcart-solari-v3-deployment-20260901.json
```

Confirm:

- deployment `dpl_6DgqhKjWN4fm1CHpL6cWcZnWks2x`;
- immutable `https://smartcart-solari-beta-cipegeumf-blake23.vercel.app`;
- alias `https://smartcart-solari-beta.vercel.app`;
- READY / production / exact `ced1154` commit;
- health 200 and challenge 201;
- malformed V3 envelope 400 / `contract_validation_failed`;
- V3 request contract selected and provider execution false for the rejection;
- runtime kill switch and Upstash state configured;
- V1 operator-live co-deployment rejected by configuration.

Non-mutating health check:

```sh
curl --fail-with-body --silent --show-error \
  https://smartcart-solari-beta.vercel.app/health
```

Do not casually create production challenges; they write short-lived Upstash state. Use the receipt or an authorized smoke plan. The recorded malformed request deliberately proves rejection, not a valid signed native flow.

## 7. Exercise historical Walmart replay

Start the local backend:

```sh
npm --prefix backend start
```

Then:

```sh
curl --fail-with-body --silent --show-error \
  -X POST http://127.0.0.1:8787/v1/solari/research \
  -H 'content-type: application/json' \
  --data-binary @contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json
```

The result must be `recorded_fixture`, observed `2026-07-16T12:00:00Z`, with Browser/Sandbox marked not run. `$12.79` is a historical seeded estimate, not current/guaranteed/location-specific pricing or a Solari execution receipt.

## 8. Signing and physical-device gate

Inspect identities without exposing certificate material:

```sh
security find-identity -v -p codesigning
```

Current evidence records three valid Apple Development identities. Do **not** infer archive readiness. The signed archive attempt failed because:

- personal team Blake Grove does not support Associated Domains and App Attest for `com.blakestudio.smartcart.solari-beta`;
- no matching iOS App Development provisioning profile exists;
- Share Extension provisioning has an application-groups mismatch.

The physical iPhone is offline. Stop: signed archive, physical App Attest, TestFlight, App Store, and downloadable native build are PENDING. Do not remove entitlements, add client bearer/API keys, enable Release fixture replay, or claim a signed pass.

To close the gate legitimately:

1. use a team supporting the beta app’s Associated Domains and App Attest capabilities;
2. create matching main-app and Share Extension profiles with the correct app group;
3. archive/sign `Release-SolariBeta`;
4. install an allowlisted build on a physical iPhone through the intended distribution path;
5. observe initial challenge → Apple attestation → accepted key;
6. send exact V3 bytes in the v1 envelope and observe challenge → assertion → Browser/Sandbox result;
7. verify replay rejection, kill-switch/quota/cancellation UX, and cleanup;
8. capture only sanitized IDs/outcomes, never App Attest blobs, secrets, or capability URLs;
9. separately qualify VoiceOver, Dynamic Type, TestFlight, and App Store.

## 9. Clean Vercel deployment

The Vercel project Root Directory is configured as `backend/`, while shell commands run from the clean monorepo root so `backend/` and `contracts/` are in the upload. `backend/vercel.json` uses `includeFiles` for shared contracts.

```sh
git status --short
git rev-parse HEAD
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
vercel link
vercel deploy --prod
```

Do not `cd backend`, use `--cwd backend`, or change the project Root Directory.

Configure names in Vercel without putting values in source/docs:

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

Operator-only `SOLARI_OPERATOR_TOKEN` / `SOLARI_LIVE_EXECUTION_ENABLED` do not belong in the native beta path or any client. Walmart authorization variables stay unset/false without actual written authorization.

After deployment, write a sanitized immutable receipt recording exact commit, deployment ID/immutable URL/alias, READY state, non-secret app/build configuration, state-store class, and smoke outcomes. Do not include secret values.

## 10. Claim, secret, and link checks

```sh
rg -n "live Walmart|live Target|guaranteed price|public native|downloadable app|signed App Attest.*PASS" \
  README.md Docs SmartCart backend website evidence

rg -n "slr_live_|SOLARI_API_KEY=|KV_REST_API_TOKEN=|Authorization: Bearer|cdpEndpoint|wsEndpoint|replay-url" . \
  -g '!backend/node_modules/**' -g '!.git/**' -g '!.env*'

git diff --check
```

Expected matches are negations, environment-name documentation, tests/canaries, or provider field names—not actual credentials or unsupported claims.

Final submission evidence must name the exact commit; V3 run/receipt; Pages run; deployment/receipt; backend/native/web counts; unsigned versus signed build state; physical-device status; synthetic source; historical Walmart replay; Browser/Sandbox authority and cleanup; unchanged handoff; and every remaining PENDING gate.
