# Internal Solari red-team work log

This is an internal development ledger, not an external audit, certification, hiring score, or proof that Solari ran. Fresh terminal Grok sessions were used as skeptical product/security feedback. Findings influenced the product only when reproduced against code, deployment, or receipts. The credentialed Actions receipt—not a reviewer’s opinion—is execution evidence.

## V3 review scope

The skeptical review was asked to examine the normal native recipe/pantry/research/handoff flow, V3 schemas, Browser extraction, Sandbox optimizer, App Attest/Upstash admission, owned public catalog, deployment, tests, evidence receipts, and trust copy. It specifically targeted unnecessary Solari usage, unsupported product matches, misleading price claims, synthetic/retailer contamination, secrets/session privacy, unsafe commerce automation, weak provenance, basket math, UX, SmartCart contract divergence, and overengineering.

The first fresh V3 review began against commit `3d39dbb`. Its findings were treated as an engineering queue rather than a release verdict. A second fresh terminal review was later run against the pre-fix publication state; its reproduced findings and dispositions are recorded below. A third fresh terminal review inspected post-fix public head `bc083d6` and qualified runtime `772e65b`; its conclusion is recorded as internal feedback, not external proof.

## Fresh V3 review 1 — reproduced findings and dispositions

### High

1. **Public Pages/main and receipt links were stale or returned 404.**
   - Disposition: **fixed**. Submission `main` was fast-forwarded, Pages run [`33528975472`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33528975472) completed, and all six `dg-*` pages returned HTTP 200.

2. **Swift uppercase UUID encoding was incompatible with the lowercase wire contract.**
   - Disposition: **fixed**. Native and schemas now jointly use V3 UUID identities with normalized compatible encoding; regression tests cover the boundary.

### Medium

1. **The synthetic Demo Grocer reused Walmart-like product IDs/prices and then appeared to continue to Walmart.**
   - Disposition: **fixed**. The current catalog uses distinct `dg-*` identities, the V3 low-surplus `$13.32` basket, exact owned sources, and an explicit **Continue with original SmartCart list** action. Demo identities/prices never transfer.

2. **Raw page text crossed the Browser/result boundary in the earlier V2-shaped implementation.**
   - Disposition: **fixed for the current V3 structured path**. V3 reads bounded structured fields and forbids raw text in qualification receipts/Sandbox input. Historical V1 support remains isolated and is not current evidence.

3. **The V1 operator-live route could coexist with the App Attest beta.**
   - Disposition: **fixed**. Configuration now fails closed when those modes would coexist.

4. **Sandbox duplicated a locally implemented greedy optimizer and therefore lacked a necessary job.**
   - Disposition: **fixed**. Sandbox now owns the global cross-line low-surplus selection within the `$0.75` premium cap. SmartCart checks admitted evidence, coverage, arithmetic, cheapest reference, and cap, but intentionally does not recompute global argmin.

### Low

1. **The public artifact looked like a Solari lab instead of SmartCart.**
   - Disposition: **fixed in product framing**. Native SmartCart’s normal recipe/pantry flow leads the submission; the website is supporting evidence and an owned Browser surface.

2. **Cost/serving copy did not clearly state package overage.**
   - Disposition: **fixed**. Native copy exposes package counts, coverage, surplus, cheapest comparison, and premium.

3. **The health response retains an older shared-backend service name.**
   - Disposition: **accepted Low**. It is a shared backend health identity, not the user-facing product or evidence contract. Renaming it creates unrelated regression risk.

4. **Shared beta app group, remote Browser DNS TOCTOU, and post-body socket-hangup behavior remain residual hardening areas.**
   - Disposition: **accepted Low and documented**. Exact owned host/path/product checks, public-address preflight, default-off forwarded trust, aggregate deadline, cancellation, and cleanup bound the internship experiment. Production still requires correct app-group provisioning, controlled egress, and stronger response-socket cancellation/reconciliation.

## Follow-up native and UX audit

The next review pass reproduced additional integration defects. All High and Medium findings were fixed:

### High

- **Native admission quantities did not match backend canonical quantities.** Fixed by sharing the exact three canonical V3 requirements and negative tests.
- **Non-UUID schema identities conflicted with Swift UUID decoding.** Fixed by standardizing V3 request/observation/decision identities as UUIDs.
- **Synthetic/current provenance was asserted by code rather than observed from pages.** Fixed with exact rendered `current-v3` / `syntheticPrice=true` markers, Browser extraction, backend validation, and negative tests for absent/false/wrong markers.

### Medium

- **Successful research had no clear path back to normal retailer handoff.** Fixed with explicit unchanged-original-list continuation and plan/match revalidation.
- **`independentlyVerified` overstated what SmartCart proves.** Fixed with `policyInvariantsVerified` and `smartcart-policy-invariants-no-local-global-argmin`.
- **Freshness age could disagree with observation timestamps.** Fixed with actual-age, tolerance, maximum-age, and future-time checks.
- **JSON-LD `InStock` implied unsupported availability.** Removed and forbidden from the owned current catalog.
- **Arbitrary `substitutionNote` could cross the trust boundary.** Fixed by restricting it to admitted ambiguity evidence/membership.

The Low “smallest sufficient” wording was also corrected to describe the actual low-surplus-within-price-cap policy.

## Final trust-focused pass before documentation refresh

The final trust pass reported no reproduced Critical or High finding. It identified two Medium items:

1. **The qualification result digest could be supplied by a caller.**
   - Disposition: **fixed**. The receipt generator now computes SHA-256 internally from the accepted result, with regression coverage.

2. **Submission documentation described the superseded pre-V3 state.**
   - Disposition: **fixed in the first documentation refresh**, then superseded by the fresh runtime described below.

## Fresh V3 review 2 — pre-fix score and dispositions

The second terminal Grok session assigned the pre-fix state an internal `7.0/10`. That number is preserved only as historical reviewer feedback required by the work log; it is not SmartCart’s self-score, an external audit, a current score, or release evidence. The session reported one legitimate High and four legitimate Medium findings:

### High 1 — qualification freshness and current execution

**Finding:** observation freshness was calculated during sequential Browser collection but not recomputed after Sandbox work at result completion, and the latest fixes lacked a fresh credentialed receipt.

**Disposition: fixed.** The runtime recomputes every observation’s age at `completedAt`, revalidates the completed evidence set, and fails closed if the set is no longer fresh. Credentialed run [`33533170189`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189) passed against runtime `772e65bac5cabfba8b5e8b6a9482191a715c616a`; its receipt records completion freshness, six current observations, Browser/Sandbox cleanup, and the existing `$13.32` / 16 oz decision.

### Medium 1 — explicit refresh reused request identity/cache state

**Finding:** bypassing the cache did not by itself guarantee a fresh request UUID/submission time and clean eviction of the old plan entry.

**Disposition: fixed.** Explicit refresh evicts the fingerprint entry, rebuilds the unchanged reviewed plan with a new request UUID and timestamp, and then refetches. Native regression tests verify new identities across consecutive refreshes while preserving requirements, original SmartCart selections, and plan fingerprint.

### Medium 2 — native timeout budget was shorter than the backend path

**Finding:** client timing could fail before the bounded provider/backend flow had a reasonable chance to return, creating misleading native failures.

**Disposition: fixed.** The ephemeral native session now uses a 75-second per-request timeout and 90-second resource timeout. Tests pin cookies/cache disabled and those exact values. Backend/provider aggregate deadlines and cancellation remain authoritative server-side bounds.

### Medium 3 — public Pages copy contradicted current evidence

**Finding:** supporting-site copy still described V3 as pending a new credentialed run and could lead reviewers to stale evidence.

**Disposition: fixed in the supporting-site publication layer.** Pages runtime deployment [`33533099042`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533099042) is the deployed source associated with the qualified runtime. Publication-only Pages run [`33534199401`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33534199401) published corrected explanatory copy at public head `bc083d6`, citing run `33533170189` and its receipt.

### Medium 4 — runtime and publication provenance were conflated

**Finding:** calling a later repository head the “exact” qualified code would incorrectly imply that documentation, evidence-file, or supporting-site publication commits themselves ran Browser/Sandbox and Vercel qualification.

**Disposition: fixed.** Exact runtime identity is `772e65bac5cabfba8b5e8b6a9482191a715c616a`, pinned by run `33533170189` and deployment `dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r`. Later docs/evidence/site commits are explicitly publication-only. This log does not invent a self-referential final publication SHA.

The second session’s pre-fix score is not carried forward as a post-fix score. The fresh post-fix session below inspected the fixes and immutable runtime receipts before reaching its own conclusion.

## Fresh V3 review 3 — post-fix internal verdict

The third fresh terminal Grok process used a new public checkout at publication head `bc083d6` and read-only repository tools. It verified the runtime-to-publication boundary, the current receipts, and the five review-2 fixes from implementation and tests rather than trusting their documentation.

Its exact severity conclusion was: **“There are no legitimate Critical, High, or Medium findings.”** It scored the bounded internship artifact `9.4/10`, answered **Yes** that Solari materially improves SmartCart, **Yes** that the user-trust model remains defensible, **Yes** that claims are evidence-backed and accurately scoped, and **Yes** that the submission is effectively 10/10 within its honest bounded internship scope. Its separate verdicts were **Ship** for the internship artifact and **No-ship** for TestFlight/App Store/downloadable distribution while those gates remain PENDING.

Those answers are skeptical internal feedback, not an external audit, certification, execution receipt, or product-market-fit evidence. The credentialed Actions receipt and deterministic tests remain the authorities for runtime claims.

The reviewer retained only Low issues:

- remote Browser DNS cannot be pinned with the current SDK, leaving bounded TOCTOU risk;
- a client hangup after a complete request body can run until the aggregate deadline/kill switch;
- the unauthenticated, rate-limited historical V1 recorded-fixture route remains on the beta host, but cannot spend live Solari;
- native package-count verification relies on backend ceil verification plus coverage/surplus/premium checks rather than independently asserting the exact ceil count;
- requirement/ingredient UUID casing is consistent with UUID schemas and decoding but not normalized like `requestID`;
- unused `V3_PRODUCT_CATALOG` creates future drift risk;
- production should keep backend timeout configuration below native 75/90-second budgets;
- shared health naming remains legacy;
- signed distribution, authorized retailer evidence, and consumer PMF remain PENDING product gaps rather than defects in the bounded claim.

The reviewer also noted that the publication-only Pages run was not yet in the tree it inspected; run `33534199401` is now recorded above without changing the reviewed runtime or website implementation.

## Rejected finding

One suggestion was technically incorrect: call `SandboxClient.close()` after killing the Sandbox. `@solarisdk/sandbox` 0.1.2 exposes `sandbox.kill()` as microVM teardown and does not expose a `SandboxClient.close()` / dispose operation. The implementation kills the created Sandbox in `finally`, matching [Solari’s documented teardown](https://docs.getsolari.com/sandboxes). This rejection does not weaken Browser cleanup: Browser pages, session, and client are closed before success.

## Remaining accepted Low risks

- Owned Demo Grocer is synthetic and cannot prove real-retailer usefulness, price accuracy, location behavior, or authorization.
- Remote Browser DNS cannot be pinned by the current SDK; exact-host checks and public DNS preflight do not eliminate TOCTOU.
- A response-socket hangup after a complete request body can run until the aggregate deadline/kill switch.
- Beta app/Share Extension app-group and App Attest/Associated Domains provisioning remain unresolved; signed archive and device flow are pending.
- Health service naming reflects the shared backend.

These are disclosed constraints, not permission to broaden automation. Walmart stays replay-only, all pricing claims remain timestamped/synthetic or historical, and account/cart/checkout automation remains absent.

## Evidence after remediation

- qualified runtime: `772e65bac5cabfba8b5e8b6a9482191a715c616a`;
- Pages runtime deployment: run `33533099042`; publication-only supporting-copy run `33534199401` remains a separate identity;
- credentialed V3 Browser/Sandbox: run [`33533170189`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189), [receipt](../evidence/live/smartcart-solari-v3-qualification-33533170189.json);
- protected production deployment: [receipt](../evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json);
- deterministic checks: 72/72 focused backend, 202/202 full backend, 22/22 native, 7/7 web, npm audit 0;
- generic unsigned Release-SolariBeta build: PASS;
- signed archive / physical App Attest / TestFlight / App Store / downloadable app: PENDING.

The post-fix review inspected public head `bc083d6` and runtime `772e65b`. This log records that internal conclusion while continuing to treat runtime receipts, tests, and explicit PENDING gates as the authoritative evidence.
