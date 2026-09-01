# Internal Solari red-team work log

This is an internal development log, not an external audit, hiring score, or proof that Solari ran. Grok 4.6 sessions were used as skeptical product/security feedback against exact commits. Only reproducible repository findings should influence the submission; model scores and self-assessments do not qualify the product.

## Iteration 1

- Session: `01a05c74-c85f-73c0-a189-582b7f8b1a9e`
- Reviewed commit: `a2a5167278eef44d5513c613cae9973fbf537df9`
- Findings: **0 Critical, 0 High, 1 Medium, 5 Low**
- Internal findings artifact: [`red-team/grok-review-01.json`](red-team/grok-review-01.json)

The legitimate Medium finding was an unsupported hard-coded `96%` confidence value in the public replay. It was removed. The UI now exposes only the observation contract's qualitative confidence values, summarized from the currently selected evidence lines.

The demo was also repaired so a shopper's alternative selection survives stage changes, compatible pound/ounce quantities use normalized package math, and a missing price yields an incomplete/null estimate instead of contributing zero to a supposedly complete total. Regression guards reject the old numeric claim, selection reset, non-null incomplete total, or absent weight normalization.

## Low-finding dispositions

At that iteration, three Low findings remained legitimate disclosed hardening work; Iteration 3 records their later disposition:

1. Native types are intentionally narrower than the general wire schema for the frozen V1 demo; broader nullable and mixed-unit native ingestion remains future work.
2. Live research has per-operation timeouts and a six-candidate cap, but no single aggregate deadline across Browser research and Sandbox evaluation.
3. The remote Browser SDK cannot pin DNS resolution, and production should rely on a trusted proxy boundary rather than forwarded client-address metadata for rate limiting.

One Low finding was fixed alongside the Medium finding: demo alternative-selection state, compatible-unit math, and incomplete totals.

One Low finding is rejected as inapplicable. `@solarisdk/sandbox` 0.1.2 exposes no `SandboxClient.close()` or disposal method. The implementation kills the created Sandbox in `finally`, which is the SDK lifecycle operation available to the caller. This rejection does not weaken the requirement to close the Solari Browser session/client, which the Browser adapter does.

## Review standard used during development

Iteration 2 was asked to target the remediation commit and check all of the following:

- no legitimate Critical, High, or Medium findings remain;
- Solari Browser and Sandbox each have a necessary, distinct job;
- the user-trust model remains defensible;
- price and provenance claims are evidence-backed;
- fixture/live distinctions and residual gaps remain explicit.

Its finding artifact identifies the implementation commit separately from later documentation-only commits. That preserves change provenance without treating the model's conclusions as external validation.

## Iteration 2

- Fresh session: `01a05c83-e949-7243-ab59-7570237d3a31`
- Reviewed implementation commit: `29ed080c495bdc390ed997b3bef265411552e584`
- Public demo inspected: `https://exo-robotics.github.io/smartcart-solari/website/solari-demo/`
- Findings: **0 Critical, 0 High, 0 Medium, 3 Low**
- Internal findings artifact: [`red-team/grok-review-02.json`](red-team/grok-review-02.json)
- Qualification receipt: [`SOLARI_QUALIFICATION.md`](SOLARI_QUALIFICATION.md)

The session verified the Medium confidence-claim fix, the demo state/math fixes, all three disclosed residual Lows, the deployed Pages code, the executable Browser/Sandbox separation, and the absence of a Sandbox client close/dispose API. Those were useful internal checks. At that commit no credentialed live run existed; later sections supersede that execution gap with immutable first-party receipts, without converting a model review into external validation.

## Iteration 3 — post-live skeptical review

- Reviewed public commit: `95b28a465d00ba7c9d908cf9584f33aadd62e2a7`
- Credentialed run inspected: [`33501521988`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33501521988)
- Public Pages replay and separate live receipt inspected
- Findings: **0 Critical, 0 High, 0 Medium, 4 Low**
- Internal score: **9.2/10**; retained here only because the requested final report asks for the reviewer score

The fresh reviewer explicitly agreed that Solari materially improves SmartCart, the trust model is defensible, the claims are evidence-backed, and the repository demonstrates a real use case rather than only a website demo. It did not agree that the submission was effectively 10/10, citing four Low areas:

1. Native decoding was narrower than nullable wire evidence and mixed pound/ounce package math.
2. Browser and Sandbox had operation timeouts but did not share one aggregate deadline.
3. Remote Browser DNS cannot be pinned, and rate limiting trusted forwarded client metadata by default.
4. The receipt used externally suggestive confirmation wording and did not pin the exact selected SKUs, package counts, and subtotal.

Commit `a55c11fb35fa3b9f86ed2976053e97f6c8dbf61e` fixed every actionable part: native nullable/mixed-unit parity, one shared deadline, default-off forwarded-address trust, explicit result cleanup provenance, first-party receipt terminology, and exact output pinning with negative tests. Remote Browser DNS pinning is not exposed by the Solari SDK; the bounded owned host, exact source paths, public-address preflight, redirect checks, and production egress recommendation remain the defensible mitigation. Credentialed run [`33504222095`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33504222095) then passed the hardened qualifier.

A fresh reviewer must inspect that remediation and receipt before final signoff. Its conclusions will be recorded as another internal iteration, never as independent audit proof.

## Iteration 4 — hardened live-receipt review

- Reviewed public commit: `c469f70c3e8a4fffc19c50eab0e45535b6718931`
- Live-qualified implementation: `a55c11fb35fa3b9f86ed2976053e97f6c8dbf61e`
- Credentialed run inspected: [`33504222095`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33504222095)
- Findings: **0 Critical, 0 High, 0 Medium, 2 Low**
- Internal score: **9.5/10**

This fresh read-only review verified all four Iteration 3 remediations and again explicitly agreed that Solari materially improves SmartCart, the trust model is defensible, claims are evidence-backed, and this is a real backend use case rather than a decorative website integration. It retained two Low issues:

1. Remote Browser DNS cannot be pinned by the current SDK, leaving a bounded DNS time-of-check/time-of-use residual.
2. The aggregate deadline was checked before each provider operation, but `page.evaluate` and an already-running SDK call were not raced against the remaining deadline, and HTTP disconnect was not propagated.

The DNS residual is accepted and documented because the Solari Browser SDK exposes no DNS pinning control. V1 is limited to an operator-gated owned GitHub Pages hostname, exact HTTPS paths, public-address preflight, final URL/product matching, and no proxy; any consumer source still requires a controlled egress boundary.

The cancellation issue was legitimate and fixed in commit `25ab69b582e5f6d92053a2f42640736e92b5b8dc`. The API now turns client disconnect into an `AbortSignal`; the service passes one signal and deadline through Browser and Sandbox; every provider call, including Browser evaluation, is raced against its remaining time; aborted Browser work closes page/session/client; and an aborted Sandbox command kills the microVM. Regression tests cover the in-flight deadline, disconnect propagation, and both teardown paths. Credentialed run [`33505918379`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33505918379) passed on that exact remediation commit.

Because Iteration 4 did not review commit `25ab69b` or run `33505918379`, its 9.5 score is not final signoff. A fresh final review remains required.

## Iteration 5 — final bounded-scope signoff

- Reviewed public commit: `d8bc285886bfaa74bf3f3e9de9bb9840e671d506`
- Live-qualified implementation: `25ab69b582e5f6d92053a2f42640736e92b5b8dc`
- Credentialed run inspected: [`33505918379`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33505918379)
- Receipt Pages deployment: [`33506173772`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33506173772)
- Findings: **0 Critical, 0 High, 0 Medium, 2 Low**
- Internal score: **9.6/10**
- Bounded internship verdict: **SHIP**
- Production/App Store/authorized-retailer verdict: **DO NOT SHIP**

The fresh read-only reviewer verified the public commit/run/receipt identities, sequential Browser-shaped timestamps, exact basket, cancellation implementation, provider cleanup, native/fixture labels, and one owned JS-rendered product page with no product evidence in its initial static HTML. It explicitly agreed:

- `solariMateriallyImprovesSmartCart: true`
- `userTrustModelDefensible: true`
- `claimsEvidenceBacked: true`
- `realUseCaseNotJustWebsiteDemo: true`
- `effectivelyTenOfTenWithinBoundedInternshipScope: true`

Two legitimate Low issues remain. First, the Solari Browser SDK cannot pin navigation DNS to the address set checked during admission; the existing exact owned-host/path/product checks and default-off operator gate make this non-blocking for V1, while production still requires controlled egress. Second, Node request `aborted` and incomplete-body `close` events cancel work, but a socket hangup after a complete POST body may not emit either condition; that work remains bounded by the aggregate deadline. Production should also abort on response `close`/`error` while the response is unfinished.

The 9.6 score and booleans answer the requested internal red-team loop. They are not external validation, production certification, or evidence that a consumer retailer authorized automation. The immutable Actions receipt—not the reviewer—is the proof that Solari Browser and Sandbox ran.
