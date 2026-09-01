# Solari V3 qualification

This document separates code/test evidence, credentialed Solari execution, deployed backend evidence, simulator evidence, and still-pending signed-device evidence. None substitutes for another.

## Exact submission identity

- Repository: [`EXO-Robotics/smartcart-solari`](https://github.com/EXO-Robotics/smartcart-solari)
- Branch: `feat/native-solari-beta` / public `main`
- Qualified runtime commit: `772e65bac5cabfba8b5e8b6a9482191a715c616a`
- Clean upstream base: [`fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9)
- Production SmartCart repository/deployment: unchanged

`772e65b` is the exact executed runtime identity pinned by both live receipts. These documentation changes, receipt-file publication, and supporting-site copy are publication-only layers that may land afterward. They must not be described as if a later publication commit itself ran Browser, Sandbox, or the deployed backend. No self-referential “final docs commit” is invented in this receipt.

## Current evidence matrix

| Surface | Evidence | Result | What it proves |
| --- | --- | --- | --- |
| Focused Solari backend | `npm --prefix backend run test:solari` | 72/72 PASS | V1 replay/live safeguards, V3 contracts/providers/optimizer, completion-time freshness, App Attest admission, cleanup/cancellation, URL/source policy |
| Full backend | `npm --prefix backend test` | 202/202 PASS | No observed backend regression at the qualified runtime state |
| Dependency audit | `npm audit` | 0 vulnerabilities | npm’s current installed dependency audit found no known advisory |
| Focused native | `SolariEvidenceContractTests` on iPhone 17 Pro, iOS 26.5 Simulator | 22/22 PASS | request/refresh identity, cache eviction, 75/90-second timeout policy, V3 evidence validation, unchanged-list continuation |
| Web | Python demo tests | 7/7 PASS | public artifact/catalog structure, current explanatory copy, and required V3 markers |
| Beta build | generic iOS Simulator, `Release-SolariBeta`, unsigned | PASS | beta configuration compiles without claiming signing/device execution |
| Owned catalog at runtime qualification | Pages run [`33533099042`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533099042) | PASS | exact JavaScript-rendered Browser targets were deployed for the qualified runtime; later copy publication is separate |
| V3 providers | Actions run [`33533170189`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533170189) | PASS | actual Solari Browser and Sandbox ran against the owned synthetic source |
| Vercel | deployment `dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r` | READY | qualified runtime is deployed behind protected immutable URL and public alias |
| Signed archive | local archive attempt | FAIL / PENDING | signing/provisioning prerequisites are not satisfied |
| Signed native App Attest | physical iPhone | PENDING | no signed native research request has run |
| TestFlight / App Store / downloadable app | distribution | PENDING | no public native availability claim |

## Credentialed V3 Browser + Sandbox proof

The authority is [`evidence/live/smartcart-solari-v3-qualification-33533170189.json`](../evidence/live/smartcart-solari-v3-qualification-33533170189.json).

The receipt records:

- receipt version `smartcart-solari-v3-qualification-v1`;
- exact qualified runtime `772e65bac5cabfba8b5e8b6a9482191a715c616a` and run `33533170189`;
- qualification time `2026-09-01T16:40:38.632Z`;
- `server-side-direct-service-receipt` / `operator-qualification` access boundary;
- six fresh `retailer-observation-v3` records from exact `dg-*` pages, with age recomputed at result completion before final acceptance;
- every observation marked `current-v3`, `syntheticPrice: true`, and controlled-demo location;
- Browser and Sandbox completion plus cleanup before the receipt;
- internally computed accepted-result SHA-256 `fb83ae0033ca0b228ae7df454b8c617eefaece6111d2d55d88d37ecf8c586971`;
- no fixture replay, retailer account, cart change, or checkout automation.

### Qualified decision

| Metric | Receipt value |
| --- | ---: |
| Selected observed synthetic subtotal | $13.32 |
| Cheapest adequate subtotal | $12.79 |
| Premium | $0.53 |
| Maximum premium | $0.75 |
| Cheapest basket surplus | 31 oz |
| Selected basket surplus | 15 oz |
| Surplus avoided | 16 oz |

Selected products were `dg-chicken-rightsize-1lb` (two packages), `dg-penne-value-16oz` (one), and `dg-parmesan-value-6oz` (one). Solari Sandbox is the authority for the global low-surplus selection among baskets within the price cap. SmartCart verified admitted evidence, coverage/package/price arithmetic, stable cheapest reference, comparison arithmetic, and premium cap; it did not locally recompute the global argmin.

This is real credentialed Solari execution against an owned synthetic catalog. It is not a signed iPhone/App Attest receipt, a third-party retailer run, a live/guaranteed price claim, or consumer-value proof.

## Owned Pages proof

Pages runtime deployment [`33533099042`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33533099042) published the V3 artifact used by runtime qualification at `https://exo-robotics.github.io/smartcart-solari/website/solari-demo/`:

- `dg-chicken-value-3lb.html`
- `dg-chicken-rightsize-1lb.html`
- `dg-penne-value-16oz.html`
- `dg-penne-rightsize-12oz.html`
- `dg-parmesan-value-6oz.html`
- `dg-parmesan-rightsize-3oz.html`

The Browser qualification—not Pages deployment alone—proves the rendered evidence markers were observed. Publication-only Pages run [`33534199401`](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33534199401) later published corrected explanatory copy at public head `bc083d6`. That run does not replace or relabel runtime SHA `772e65b`.

## Production deployment proof

The authority is [`evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json`](../evidence/live/smartcart-solari-v3-deployment-772e65b-20260901.json).

- Deployment: `dpl_7DdE2hNBKjzfgDFdvi4Zgdtfct4r`
- Immutable URL: `https://smartcart-solari-beta-iifvcowlq-blake23.vercel.app` (Vercel authentication redirect/protection observed)
- App alias: `https://smartcart-solari-beta.vercel.app`
- State: READY / production
- Qualified runtime: `772e65bac5cabfba8b5e8b6a9482191a715c616a`
- Access design: Apple App Attest, allowlisted beta bundle/build, Upstash state, runtime kill switch, server-side Solari credential
- Co-deployment safety: V1 operator-live route rejected by configuration when App Attest beta is enabled

Sanitized smoke at `2026-09-01T16:42:36Z` recorded public-alias health 200 and challenge issuance 201. The immutable deployment URL returned 302 for health and 401 for challenge because Vercel deployment protection was active. The receipt claims no provider execution from smoke; provider proof comes only from run `33533170189`.

That smoke proves public-alias reachability and challenge issuance for the current deployment, plus protection of the immutable host. It does not prove an Apple certificate chain, device key registration, assertion counter, provider execution, or successful signed native request.

## Native product evidence

The normal native flow now exposes **Research current options** after pantry exclusions and existing product preparation, before retailer handoff. Its successful state shows the V3 comparison and provides **Continue with original SmartCart list**. Continuation revalidates only the original requirement/match fingerprint and finalizes SmartCart’s existing user-controlled queue; Demo Grocer IDs/prices are not transferred.

Focused native tests passed 22/22 on iPhone 17 Pro / iOS 26.5 Simulator. They include explicit-refresh request identity/cache eviction and 75-second request / 90-second resource timeout checks. A generic unsigned `Release-SolariBeta` simulator build passed. These are compilation/contract evidence, not public native availability or App Attest proof.

## Signing and physical-device status

Three valid Apple Development identities are now visible. A signed archive nevertheless failed for exact provisioning/capability reasons:

1. the personal team **Blake Grove** does not support Associated Domains and App Attest for `com.blakestudio.smartcart.solari-beta`;
2. no matching iOS App Development provisioning profile exists;
3. the Share Extension provisioning profile has an application-groups mismatch.

The physical iPhone is offline. Therefore signed archive, real signed App Attest registration/assertion/research, physical-device UI, TestFlight, App Store, and downloadable-app status all remain **PENDING**. Do not weaken entitlements, add a client secret, or enable Release fixture replay to manufacture a pass.

## Historical evidence kept separate

- V1 credentialed run `33519606791` and its `$12.79` basket are historical prior proof only. They do not cover the V3 IDs, page markers, `$13.32` decision, or global low-surplus policy.
- The Walmart fixture is replay of upstream seeded observations dated `2026-07-16T12:00:00Z`. It invokes no Solari provider and does not establish current, guaranteed, location-specific, or checkout pricing.
- The public website explains the product and hosts owned Browser targets. It is not a substitute for the native SmartCart integration.

## Remaining qualification gates

- use a team/profile set that supports Associated Domains, App Attest, the beta bundle ID, and the Share Extension app group;
- produce a signed Release-SolariBeta archive;
- bring a physical iPhone online and run initial attestation plus a request-bound assertion;
- verify replay rejection, runtime kill switch, quota/cancellation UX, and cleanup on that signed path;
- inspect source/time/ambiguity/partial-total and unchanged-handoff copy on device with VoiceOver and Dynamic Type;
- separately qualify TestFlight, App Store, and any downloadable/public-native claim;
- use an authorized retailer API/feed or documented automation permission before claiming real-retailer value.

Until those gates pass, the defensible claim is: **the native product integration, protected deployed backend, owned dynamic pages, and credentialed V3 Browser/Sandbox computation are demonstrated; signed consumer-native and real-retailer value remain pending.**
