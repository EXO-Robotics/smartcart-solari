# Internal Solari red-team work log

This is an internal development ledger, not an external audit, certification, hiring score, or proof that Solari ran. Fresh terminal Grok sessions were used as skeptical product/security feedback. Findings influenced the product only when reproduced against code, deployment, or receipts. The credentialed Actions receipt—not a reviewer’s opinion—is execution evidence.

## V3 review scope

The skeptical review was asked to examine the normal native recipe/pantry/research/handoff flow, V3 schemas, Browser extraction, Sandbox optimizer, App Attest/Upstash admission, owned public catalog, deployment, tests, evidence receipts, and trust copy. It specifically targeted unnecessary Solari usage, unsupported product matches, misleading price claims, synthetic/retailer contamination, secrets/session privacy, unsafe commerce automation, weak provenance, basket math, UX, SmartCart contract divergence, and overengineering.

The first fresh V3 review began against commit `3d39dbb`. Its findings were treated as an engineering queue rather than a release verdict. A second fresh review is not yet recorded here; no score or signoff is invented.

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
   - Disposition: **fixed in this documentation update**. README, experiment design, qualification, threat model, and runbook now cite exact commit `ced1154`, runs `33528975472` / `33529059284`, the `$13.32`/`$12.79` comparison, V3 deployment receipt, current test counts, and signed-device blockers.

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

- exact code: `ced1154e76a376a7d630900f7c5f4b4317a3932d`;
- Pages: run `33528975472`, six V3 `dg-*` pages HTTP 200;
- credentialed V3 Browser/Sandbox: run [`33529059284`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33529059284), [receipt](../evidence/live/smartcart-solari-v3-qualification-33529059284.json);
- protected production deployment: [receipt](../evidence/live/smartcart-solari-v3-deployment-20260901.json);
- deterministic checks: 71/71 focused backend, 201/201 full backend, 20/20 native, 6/6 web, npm audit 0;
- generic unsigned Release-SolariBeta build: PASS;
- signed archive / physical App Attest / TestFlight / App Store / downloadable app: PENDING.

A future fresh review should inspect this exact post-documentation state and its immutable receipts. Until that happens, this log makes no final reviewer-score or independent-signoff claim.
