# SmartCart × Solari submission brief

Prepared from the frozen V4 qualification evidence. This packet is written to make SmartCart the product, Solari the necessary capability, and the current proof boundary explicit.

**Start here:** [interactive before/after case study](https://exo-robotics.github.io/smartcart-solari/) · [implementation](https://github.com/EXO-Robotics/smartcart-solari) · [credentialed Browser + Sandbox receipt](https://github.com/EXO-Robotics/smartcart-solari/blob/main/evidence/live/smartcart-solari-v4-qualification-33546912947.json)

## Core story

> I took an existing grocery-planning product, identified where its retailer handoff stopped being useful, and directed AI to integrate Solari as a trust-preserving research and optimization capability.

This is not a story about building a Solari demo. SmartCart already turns recipes into an actionable shopping trip. Solari closes a specific gap between knowing what the shopper needs and understanding which observed packages sensibly satisfy those needs.

## Before and after

### Original SmartCart

- Converts recipes into ingredients.
- Applies pantry exclusions.
- Aggregates the remaining shopping list.
- Prepares product matches and hands control to the shopper at the retailer.
- Does not know which currently observed packages cover the trip.
- Cannot compare package overage, observed basket cost, or source evidence across the trip.

### Solari-enhanced SmartCart

- Preserves SmartCart's existing recipe, pantry, quantity, matching, and retailer-handoff workflow.
- Lets the shopper intentionally request research for eligible waiting items.
- Uses Solari Browser to observe exact allowlisted product pages from an owned synthetic retailer surface.
- Records product identity, package quantity and unit, visible synthetic price, source URL, observation time, confidence, ambiguity, and freshness.
- Uses Solari Sandbox to evaluate bounded package combinations across the admitted portion of the trip.
- Makes SmartCart independently validate evidence membership, coverage, arithmetic, freshness, the cheapest reference, and the allowed premium.
- Shows the recommendation natively, preserves unsupported or ambiguous lines, and returns to the original user-controlled retailer handoff.
- Keeps Solari out of the shopper's retailer account. After handoff, the shopper signs in and shops directly with the retailer; the retailer owns the session, cart, payment, and checkout.

SmartCart remains the product. Solari makes its existing shopping workflow materially more capable.

## Judgment and AI direction

The strongest evidence of AI-assisted development is the series of product and engineering corrections made during the work:

1. Rejected the initial website-demo framing and required integration into SmartCart's real native shopping workflow.
2. Rejected the hardcoded three-ingredient prototype and generalized it to a bounded eligible subset of variable trips, with explicit partial coverage.
3. Refused to invent quantities for ambiguous inputs such as “olive oil for frying.”
4. Required unsupported or dimension-incompatible units to be skipped safely instead of fabricating package math.
5. Kept Solari, operator, App Attest, and state-store credentials server-side.
6. Kept retailer authentication and account activity out of Solari. The shopper signs in and shops directly with the retailer after handoff.
7. Required timestamped provenance and freshness instead of unsupported “live price” claims.
8. Challenged an optimizer result that was mathematically valid but not useful to shoppers.
9. Redirected optimization toward a comprehensible tradeoff: a basket may spend at most $0.75 above the cheapest adequate basket to reduce relative package surplus.
10. Made the resulting tradeoff visible: the qualified run spent $0.63 more to avoid about 680 g / 1.5 lb of excess chicken.
11. Used repeated skeptical Grok reviews to find legitimate issues, fixed those issues, and did not present internal AI review as external validation.

This demonstrates direction across product, architecture, security, evidence, optimization, and UX—not merely prompting an AI to generate a repository.

## 65-second before/after narrative

The case study contains two hash-bound silent recordings: **39.63 seconds before Solari** and **25.10 seconds after Solari**. Together they form a 64.73-second product narrative while remaining independently selectable on the public page.

### 0–8 seconds — Original SmartCart

**Show:** Recipe import or scan → pantry exclusions → aggregated shopping list → basic retailer handoff.

**Narration:**

> SmartCart could determine what you needed, but the retailer handoff could not tell you which observed packages sensibly satisfied the trip.

**On-screen label:** `Original SmartCart`

### 8–30 seconds — Enhanced native workflow

**Show:** Tap **Research current options**. Let the native research state progress, then show **Researched X of Y items** and at least one preserved skipped line if it can be shown cleanly.

**Narration:**

> I integrated Solari as an optional intelligence layer. Browser collects structured product observations, and Sandbox evaluates package combinations across the eligible part of the trip.

**On-screen label:** `User-requested research · partial coverage preserved`

### 30–48 seconds — Useful result

**Show:** Selected products, package counts, observed subtotal, cheapest adequate subtotal, premium, required versus covered quantities, overage, source, observation time, and confidence or ambiguity.

**Narration:**

> SmartCart independently validates the evidence and presents the result inside its existing shopping workflow. In the qualified run, spending 63 cents more avoided about one and a half pounds of excess chicken.

**On-screen label:** `$24.20 selected · $23.57 cheapest adequate · +$0.63 · ~1.5 lb excess chicken avoided`

### 48–58 seconds — Trust boundary

**Show:** **Continue with original SmartCart list**, followed by the normal shopper-controlled retailer handoff. Avoid implying that Demo Grocer products or prices are transferred into a retailer cart.

**Narration:**

> The shopper still decides what to buy. Solari never touches the shopper's retailer account. After handoff, the shopper signs in and shops directly with the retailer.

**On-screen label:** `Your retailer account stays between you and the retailer`

### 58–65 seconds — Technical proof

**Show:** A simple architecture card:

> SmartCart requirements → Solari Browser → Solari Sandbox → SmartCart validation → user handoff

**Narration:**

> SmartCart remains the product. Solari makes its existing workflow materially more capable.

**Footer:** `Provider-qualified on an owned synthetic retailer surface · signed-device and store distribution pending`

## Primary submission copy

I enhanced SmartCart, my existing grocery-planning app, with Solari—not by embedding a demo, but by addressing a real limitation in its retailer handoff.

SmartCart already understands recipes, pantry exclusions, ingredient identity, required quantities, and shopping-list aggregation. It previously could not determine which observed retailer packages sensibly satisfied an entire trip.

I directed an AI-assisted development process to integrate Solari Browser for structured product observations and Solari Sandbox for bounded basket optimization. SmartCart independently validates the returned evidence and shows researched coverage, selected packages, estimated synthetic cost, overage, freshness, confidence, ambiguity, and provenance before the shopper chooses the normal retailer handoff.

During development, I rejected a hardcoded three-item prototype, unsupported quantity assumptions, misleading confidence percentages, client-side credentials, autonomous purchasing, and an optimizer result that was mathematically correct but not meaningful to shoppers.

The frozen credentialed run researched eight shopping requirements from 16 fresh observations. It selected a complete synthetic $24.20 basket instead of the $23.57 cheapest adequate basket—spending $0.63 within a user-visible $0.75 cap to avoid approximately 680 g / 1.5 lb of excess chicken.

The qualified research source is SmartCart's owned synthetic Demo Grocer, used for authorized end-to-end provider qualification. The receipt demonstrates real Solari Browser and Solari Sandbox execution without claiming unauthorized retailer access, guaranteed consumer pricing, or a signed iPhone request.

The native beta path, contracts, backend protection, validation, and UI are implemented. Provider execution and the protected beta deployment are qualified. Signed-device App Attest, TestFlight/App Store distribution, and authorized real-retailer qualification remain pending.

SmartCart remains the product. Solari makes its existing shopping workflow materially more capable.

## Short social post

I integrated Solari into SmartCart, my existing grocery-planning app, to solve a real gap: turning recipe and pantry requirements into evidence-backed package choices before the shopper goes to a retailer.

Solari Browser observes structured product evidence. Solari Sandbox evaluates bounded basket tradeoffs. SmartCart validates the result and keeps the shopper in control. Solari never touches the shopper's Walmart account; after handoff, the shopper signs in and shops directly with Walmart.

In a credentialed eight-item run against an owned synthetic retailer, SmartCart spent $0.63 above the cheapest adequate basket to avoid about 1.5 lb of excess chicken.

SmartCart is the product. Solari makes its retailer handoff materially smarter.

@harrychow_ @getsolari

Repository: https://github.com/EXO-Robotics/smartcart-solari

Before/after case study: https://exo-robotics.github.io/smartcart-solari/

Runtime receipt: https://github.com/EXO-Robotics/smartcart-solari/blob/8f749e33808119ee403142929da5b757ed934e35/evidence/live/smartcart-solari-v4-qualification-33546912947.json

## Evidence links

- Repository: https://github.com/EXO-Robotics/smartcart-solari
- Interactive before/after case study: https://exo-robotics.github.io/smartcart-solari/
- Provider-qualified runtime: https://github.com/EXO-Robotics/smartcart-solari/commit/2dd4e6f30be8286a3a8f465c92a56427828a60e2
- Credentialed Solari Browser + Sandbox run: https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546912947
- Sanitized runtime receipt: https://github.com/EXO-Robotics/smartcart-solari/blob/8f749e33808119ee403142929da5b757ed934e35/evidence/live/smartcart-solari-v4-qualification-33546912947.json
- Qualification matrix: https://github.com/EXO-Robotics/smartcart-solari/blob/main/Docs/SOLARI_QUALIFICATION.md
- Architecture and trust boundary: https://github.com/EXO-Robotics/smartcart-solari#architecture
- Owned synthetic retailer surface: https://exo-robotics.github.io/smartcart-solari/website/solari-demo/retailer-v4/

The repository and runtime receipt belong in the primary submission. The Pages surface, deployment receipt, detailed qualification matrix, and internal Grok reviews belong in the technical appendix.

## Evidence matrix and claim boundary

| Claim | Status | Evidence or required wording |
| --- | --- | --- |
| Existing SmartCart product was the integration base | **PASS** | Submission fork is based on upstream SmartCart commit `fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9`; production SmartCart remains unchanged. |
| Generalized native research path | **PASS** | V4 admits 1–12 eligible requirements from a waiting trip, preserves unsupported/skipped lines, and continues through the original handoff. |
| Real Solari Browser execution | **PASS** | Run `33546912947` observed 16 exact JavaScript-rendered owned synthetic product pages. |
| Real Solari Sandbox execution | **PASS** | The same run executed `relative-surplus-premium-dp-v1` and returned eight decisions. |
| Useful basket tradeoff | **PASS** | $24.20 selected versus $23.57 cheapest adequate; $0.63 premium; about 680 g / 1.5 lb excess chicken avoided. |
| Credential cleanup | **PASS** | Receipt records enforced Browser and Sandbox cleanup before receipt generation. |
| Protected beta backend deployment | **PASS** | Deployment receipt records READY, `/health` 200, and App Attest challenge 201. These smoke results are not provider execution or a signed native request. |
| Native implementation, compilation, and Simulator flow | **PASS** | Focused native tests passed, unsigned `Release-SolariBeta` compiled successfully, and the eight-item flow ran in iOS Simulator. Apple signing/provisioning is a separate pending gate. |
| Signed native App Attest request | **PENDING** | Do not infer this from provider qualification or challenge issuance. |
| Physical-device validation | **PENDING** | Do not call simulator or unsigned build evidence device proof. |
| TestFlight/App Store/downloadable product | **PENDING** | Use “native beta integration” or “developer/beta testing,” not “available on TestFlight” or “shipped.” |
| Authorized real-retailer research | **PENDING** | Demo Grocer is an owned synthetic qualification surface; historical Walmart data is fixture replay only. |
| Current or guaranteed consumer pricing | **NOT CLAIMED** | Say “timestamped visible synthetic price” or “observed synthetic subtotal.” |
| External validation | **NOT CLAIMED** | Grok reviews are internal adversarial review, not independent acceptance. |

## Publication checklist

- [x] Record and hash-bind the original native flow and enhanced native replay.
- [x] Keep the combined before/after recording time under 65 seconds (64.73 seconds total).
- [ ] Show **Research current options** as an intentional shopper action.
- [ ] Show package counts, required/covered quantities, overage, source, and observation time—not only a basket total.
- [ ] Include **Researched X of Y items** or an explicit skipped-line example to demonstrate partial coverage.
- [ ] Show the $0.63 / 1.5 lb chicken tradeoff visibly enough to read.
- [ ] Show the user-controlled continuation into SmartCart's original retailer handoff.
- [ ] Include the owned-synthetic qualification label in the video or submission text.
- [ ] Verify the tags `@harrychow_` and `@getsolari` immediately before publication.
- [ ] Link the repository and immutable runtime receipt.
- [ ] Keep Pages replay, deployment detail, and internal Grok review in the appendix.
- [ ] Do not say “live retailer prices,” “signed iPhone run,” “TestFlight,” “App Store,” “downloadable,” or “shipped” unless new exact evidence closes those gates.

## Final one-sentence positioning

> SmartCart already knew what the shopper needed; I integrated Solari so it could research and evaluate which observed packages sensibly satisfy the trip—without taking control away from the shopper.
