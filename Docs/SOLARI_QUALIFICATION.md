# Solari submission qualification receipt

## Exact identities

- Public repository: `https://github.com/EXO-Robotics/smartcart-solari`
- Reviewed implementation commit: `29ed080c495bdc390ed997b3bef265411552e584`
- Clean upstream base: `fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`
- Public demo: `https://exo-robotics.github.io/smartcart-solari/website/solari-demo/`
- Pages deployment run: `33497484297` — successful for implementation commit `29ed080c495bdc390ed997b3bef265411552e584`
- Final Grok session: `01a05c83-e949-7243-ab59-7570237d3a31`

This receipt is added after the independent review, so its later documentation-only commit is not the commit Grok reviewed. The implementation target and the receipt commit must be reported separately.

## Demonstrated flow

Chicken Parmesan Pasta produces five reviewed ingredients. SmartCart pantry allocation removes olive oil and garlic, leaving 1.5 lb chicken, 12 oz penne, and 3 oz Parmesan. The public replay loads six dated Walmart fixture observations, lets the user inspect or choose candidates, normalizes compatible package units, computes required packages and an evidence-labeled estimate, then stops at explicit product-page handoff.

The public Walmart experience is a fixture replay observed at `2026-07-16T12:00:00Z`. Its canonical basket is `$12.79`; it is not a current or guaranteed price, availability, or proof that Solari ran. The executable live path admits only the owned JS-rendered Demo Grocer, where Solari Browser structures visible product evidence and Solari Sandbox performs the authoritative decision computation. No `SOLARI_API_KEY` was available during construction, so live provider qualification remains `PENDING` and no live receipt is claimed.

## Fresh checks on the reviewed implementation

| Check | Result |
| --- | --- |
| `npm run test:solari` | 25 passed, 0 failed |
| `npm test` outside restricted sandbox | 155 passed, 0 failed |
| `python3 website/solari-demo/validate.py` | passed |
| demo Python unit tests | 4 passed, 0 failed |
| `node --check` for demo and retailer scripts | passed |
| `npm audit --omit=dev --audit-level=high` | 0 vulnerabilities |
| `git diff --check` | passed |
| secret-pattern scan | only documented placeholders/test canaries |
| GitHub Pages workflow | passed for `29ed080` |
| local browser alternative flow | `$23.53`, `2 high · 1 medium`, 3 packages, selection preserved, no console errors |
| public deployment code check | no `96%`; qualitative confidence and normalized package math present |

The restricted sandbox cannot bind localhost, so its broad Node run produced only `listen EPERM` failures. The same suite passed 155/155 outside that sandbox. This is an execution-environment distinction, not a hidden test failure.

Native Debug full-source compile, Release full-source typecheck, and targeted `SolariEvidenceContractTests` source typecheck passed before the web-only red-team remediation. The diff from `a2a5167278eef44d5513c613cae9973fbf537df9` to reviewed `29ed080c495bdc390ed997b3bef265411552e584` changes only README, Solari docs/red-team evidence, and the static demo. Simulator runtime testing remains `PENDING`: `simctl` reports an invalid CoreSimulatorService connection and no available runtime discovery. No simulator/device-runtime claim is made.

## Final independent review

Grok 4.6 reviewed the exact public implementation commit and deployed demo under read/search/test/fetch-only permissions, with edits and mutating Git commands denied.

- Score: **9.7/10**
- Critical: **0**
- High: **0**
- Medium: **0**
- Low: **3**
- Solari materially improves SmartCart: **yes**
- User-trust model defensible: **yes**
- Claims evidence-backed: **yes**
- Effectively 10/10: **yes**

The normalized final verdict is [`red-team/grok-review-02.json`](red-team/grok-review-02.json). Reasoning traces are deliberately excluded; they are not product evidence.

## Remaining Low issues

1. Native evidence decoding and mixed-unit surplus validation are narrower than the general wire/backend contract.
2. Live Browser plus Sandbox work has bounded individual timeouts but no one aggregate request deadline.
3. The Browser SDK cannot pin remote DNS, and production must use locked owned DNS plus a trusted proxy/client-address boundary.

These are production-hardening items for a future enabled live service. They do not create a misleading price claim, unsafe purchase authority, or unbounded public live path in this default-off submission.
