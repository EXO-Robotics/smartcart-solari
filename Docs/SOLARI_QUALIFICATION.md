# Solari V4 qualification status

This document keeps implementation, local tests, provider execution, deployment, App Attest, signed-device, and real-retailer evidence separate. None substitutes for another.

## Submission identity

- Repository: [EXO-Robotics/smartcart-solari](https://github.com/EXO-Robotics/smartcart-solari)
- Clean upstream base: [fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9)
- Production SmartCart repository/deployment: unchanged
- Immutable V4 provider-qualified runtime: **aee4429f2246518b935005f0bae068e170b2db64**

V4 provider execution was frozen and qualified at the exact runtime above. Later receipt, documentation, or supporting-site commits are publication-only and must not be mislabeled as the executed runtime.

## V4 behavior under qualification

The native action may be invoked for any trip with waiting items. Admission is intentionally bounded:

- only eligible exact SmartCart matches in eight seeded owned groups;
- 19 owned synthetic candidates total;
- 1–12 admitted requirements;
- 1–3 dimension-compatible candidates per requirement;
- at most 24 observations;
- canonical mass, volume, or count quantities;
- explicit skipped lines and **Researched X of Y items**;
- unchanged original SmartCart handoff after user confirmation.

Solari Browser must observe exact **current-v4** / synthetic owned pages. Solari Sandbox must run the **relative-surplus-premium-dp-v1** optimizer. The V4 schemas and both native/backend validators must reject unsupported IDs, sources, dimensions, stale evidence, arithmetic mismatch, and provenance mismatch.

## Current V4 evidence matrix

| Surface | Status | Required proof |
| --- | --- | --- |
| Frozen V4 commit | **PASS** | `aee4429f2246518b935005f0bae068e170b2db64` |
| Focused backend | **PASS** | 20/20 V3/V4 qualification/provider/DP checks |
| Full backend | **PASS** | 213/213 |
| Dependency audit | **PASS** | 0 vulnerabilities |
| Focused native | **PASS** | 27/27 on iPhone 17 Pro / iOS 26.5 Simulator |
| Web/owned catalog | **PASS** | 19 pages / 8 groups; 7/7 web tests; Pages run `33541494887` |
| Unsigned Release-SolariBeta build | **PASS** | generic iOS Simulator, signing disabled |
| Credentialed V4 Browser+Sandbox | **PASS** | run `33542014049`; 8 requirements, 16 observations, 8 decisions; sanitized receipt |
| V4 beta deployment | **PENDING** | READY deployment receipt and sanitized health/challenge smoke |
| Signed archive | **PENDING** | matching team capabilities/profiles |
| Signed App Attest request | **PENDING** | physical-device registration, assertion, request, replay rejection |
| TestFlight / App Store / downloadable app | **PENDING** | distribution evidence |
| Authorized real retailer | **PENDING** | API/feed or documented automation permission plus retailer-specific qualification |

The V4 provider receipt is [smartcart-solari-v4-qualification-33542014049.json](../evidence/live/smartcart-solari-v4-qualification-33542014049.json). It records a complete $24.20 synthetic basket, request/result digests, operator-only access boundary, exact commit, timestamps, provider provenance, and enforced cleanup. It does not claim signed App Attest or device execution.

## Required V4 checks

### Contracts and service

- all four V4 schemas compile and reject version, ID, cardinality, source, unit, and provenance drift;
- requests enforce 1–12 requirements, 1–3 candidates each, and 24 total observations;
- the 19 product IDs belong to the eight seeded semantic groups;
- candidates on a line share semantic group and quantity dimension;
- Browser accepts only exact owned HTTPS V4 paths and exact final URLs;
- observations contain exact page-provided V4/current/synthetic markers;
- freshness is recomputed at completion and revalidated;
- Sandbox DP output satisfies coverage, cheapest-reference, comparison, and $0.75-cap invariants;
- backend does not claim to independently recompute global optimality;
- cancellation, quota, lease, kill-switch, idempotency, secret, and cleanup tests pass.

### Native

- any waiting trip can form a plan when at least one supported exact line is eligible;
- unsupported, ambiguous, invalid, incompatible, duplicate, and over-limit lines are skipped explicitly;
- eligible and skipped lines sum to the original waiting count;
- mass, volume, and count normalize exactly;
- UI renders **Researched X of Y items** and per-line skip reasons;
- refresh uses a fresh request identity and does not retimestamp cached evidence;
- native verifies V4 evidence, arithmetic, cheapest reference, cap, freshness, and provider provenance;
- continuation revalidates the original selections and excludes every Demo Grocer ID/price.

### Provider and deployment

- run Browser against the published 19-page controlled V4 catalog;
- run Sandbox against more than one admitted trip shape, including multiple quantity dimensions;
- record exact runtime SHA, run ID, observation timestamps, result digest, and cleanup;
- deploy the same exact runtime to the beta alias;
- record deployment ID/immutable URL/alias and sanitized health/challenge results;
- do not call health/challenge smoke provider proof;
- do not call operator qualification signed App Attest proof.

## Historical V3 evidence

V3 remains useful prior evidence, but only for its fixed three-line predecessor:

| Evidence | Historical result | Scope |
| --- | --- | --- |
| Runtime | **772e65bac5cabfba8b5e8b6a9482191a715c616a** | V3 only |
| Credentialed run | [33533170189](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189) | real Browser + Sandbox on six owned synthetic pages |
| Receipt | [smartcart-solari-v3-qualification-33533170189.json](../evidence/live/smartcart-solari-v3-qualification-33533170189.json) | $13.32 selected, $12.79 cheapest, $0.53 premium, 16 oz surplus avoided |
| Deployment | **dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r** | protected V3 beta backend |
| Deployment receipt | [smartcart-solari-v3-deployment-772e65b-20260901.json](../evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json) | V3 alias health/challenge and deployment identity |
| Tests/build | 72/72 focused backend; 202/202 full backend; 22/22 focused native; 7/7 web; unsigned beta build PASS; npm audit 0 | V3 runtime state only |

The V3 receipt records actual credentialed provider execution, six fresh **current-v3** synthetic observations, Sandbox selection, result digest, and cleanup. It is not evidence for V4 cardinality, catalog, dimensions, partial trip coverage, DP implementation, deployment, or native App Attest.

## Signing and device status

Three Apple Development identities are visible, but the signed archive attempt failed because:

1. the personal team does not support Associated Domains and App Attest for the beta bundle;
2. no matching iOS App Development provisioning profile exists;
3. the Share Extension provisioning profile has an application-groups mismatch.

The physical iPhone is offline. Signed archive, real App Attest registration/assertion/research, device UX, TestFlight, App Store, and downloadable app remain **PENDING**. Release fixture replay or a client-side secret must not be used to manufacture a pass.

## Real-retailer status

The owned Demo Grocer is synthetic and provides no real-retailer value. Walmart data is historical fixture replay only, not provider execution or current pricing. Live retailer research remains disabled unless an API/feed or documented written automation authorization is obtained and separately qualified. Target is unsupported.

## Qualification conclusion

The defensible current statement is:

> V4 expands the product boundary from one fixed three-line prototype to a bounded eligible subset of any waiting trip, with explicit skipped-line preservation and versioned evidence. A real credentialed eight-line Solari Browser+Sandbox run passed at `aee4429`; deployment identity, signed-device App Attest, distribution, and real-retailer qualification remain PENDING.
