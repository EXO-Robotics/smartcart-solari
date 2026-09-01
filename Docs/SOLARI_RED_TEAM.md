# Solari red-team record

The submission uses fresh Grok 4.6 terminal sessions as skeptical product/security reviewers. Reviews are read-only and target exact public commits. Model reasoning is not treated as evidence; only the structured verdict, cited repository evidence, and independently reproducible checks are retained.

## Iteration 1

- Session: `01a05c74-c85f-73c0-a189-582b7f8b1a9e`
- Reviewed commit: `a2a5167278eef44d5513c613cae9973fbf537df9`
- Score: **8.8/10**
- Findings: **0 Critical, 0 High, 1 Medium, 5 Low**
- Agreements: Solari materially improves SmartCart; the user-trust model is defensible; claims are evidence-backed; not yet effectively 10/10.
- Normalized structured verdict: [`red-team/grok-review-01.json`](red-team/grok-review-01.json)

The legitimate Medium finding was an unsupported hard-coded `96%` confidence value in the public replay. It was removed. The UI now exposes only the observation contract's qualitative confidence values, summarized from the currently selected evidence lines.

The demo was also repaired so a shopper's alternative selection survives stage changes, compatible pound/ounce quantities use normalized package math, and a missing price yields an incomplete/null estimate instead of contributing zero to a supposedly complete total. Regression guards reject the old numeric claim, selection reset, non-null incomplete total, or absent weight normalization.

## Low-finding dispositions

Three Low findings remain legitimate, disclosed hardening work:

1. Native types are intentionally narrower than the general wire schema for the frozen V1 demo; broader nullable and mixed-unit native ingestion remains future work.
2. Live research has per-operation timeouts and a six-candidate cap, but no single aggregate deadline across Browser research and Sandbox evaluation.
3. The remote Browser SDK cannot pin DNS resolution, and production should rely on a trusted proxy boundary rather than forwarded client-address metadata for rate limiting.

One Low finding was fixed alongside the Medium finding: demo alternative-selection state, compatible-unit math, and incomplete totals.

One Low finding is rejected as inapplicable. `@solarisdk/sandbox` 0.1.2 exposes no `SandboxClient.close()` or disposal method. The implementation kills the created Sandbox in `finally`, which is the SDK lifecycle operation available to the caller. This rejection does not weaken the requirement to close the Solari Browser session/client, which the Browser adapter does.

## Review standard

A final fresh review must target the remediation commit and explicitly confirm all of the following before signoff:

- no legitimate Critical, High, or Medium findings remain;
- Solari Browser and Sandbox each have a necessary, distinct job;
- the user-trust model remains defensible;
- price and provenance claims are evidence-backed;
- the submission is effectively 10/10 within its explicitly bounded demo scope.

The final review receipt is added only after that independent session completes. The implementation commit it reviewed and the later receipt-only commit must be reported separately so the evidence chain stays exact.

## Iteration 2 — final

- Fresh session: `01a05c83-e949-7243-ab59-7570237d3a31`
- Reviewed implementation commit: `29ed080c495bdc390ed997b3bef265411552e584`
- Public demo inspected: `https://exo-robotics.github.io/smartcart-solari/website/solari-demo/`
- Score: **9.7/10**
- Findings: **0 Critical, 0 High, 0 Medium, 3 Low**
- Agreements: **all true** — Solari materially improves SmartCart; the user-trust model remains defensible; claims are evidence-backed; the submission is effectively 10/10.
- Normalized final verdict: [`red-team/grok-review-02.json`](red-team/grok-review-02.json)
- Qualification receipt: [`SOLARI_QUALIFICATION.md`](SOLARI_QUALIFICATION.md)

Grok independently verified the Medium confidence-claim fix, the demo state/math fixes, all three disclosed residual Lows, the deployed Pages code, the executable Browser/Sandbox separation, and the absence of a Sandbox client close/dispose API. No further Critical, High, or Medium remediation is required.
