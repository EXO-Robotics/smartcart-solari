# SmartCart × Solari

[![SmartCart × Solari: From Recipe to Priced Basket](website/solari-case-study/assets/social-preview.jpg)](https://exo-robotics.github.io/smartcart-solari/)

**[Try the live research flow](https://exo-robotics.github.io/smartcart-solari/)** · **[Watch SmartCart before and after Solari](https://exo-robotics.github.io/smartcart-solari/#native-flow)** · **[See the verified run](https://exo-robotics.github.io/smartcart-solari/verified-run.html)** · [Inspect the receipt](evidence/live/smartcart-solari-v4-qualification-33546912947.json)

SmartCart could already turn a recipe into a shopping list. The annoying part came next: figuring out which packages to actually buy.

I used Solari to close that gap. Solari Browser researches approved product pages, Solari Sandbox compares the complete basket, and SmartCart checks the result before showing it to the shopper.

The shopper still makes the final decision.

## The problem before Solari

SmartCart already turned recipes into ingredients, removed pantry items, combined quantities, and prepared the retailer handoff. But a recipe might need 1.5 lb of chicken while a store sells several package sizes at different prices. The shopper still had to search every item and decide which packages made sense.

## What Solari changed

SmartCart now offers an optional **Research current options** step:

- **Solari Browser** opens approved rendered product pages and records the product, package size, visible price, source, and observation time.
- **Solari Sandbox** considers those observations together and chooses a complete basket under SmartCart's cost and overbuying rules.
- **SmartCart** verifies the evidence and arithmetic, then explains the recommendation in its native interface.
- **The shopper** accepts the research, edits the list, or continues with normal SmartCart.

SmartCart still owns the recipe, pantry, quantities, interface, and final action. Solari adds the missing research and decision layer.

## A real decision, not just a price scrape

In the qualified eight-item run, the cheapest basket that covered the recipe cost **$23.57**. SmartCart × Solari selected a **$24.20** basket instead.

Why spend another **$0.63**?

The cheaper basket used a 3 lb bag of chicken. The selected basket used a 1.5 lb package that still covered the recipe, avoiding roughly **680 g / 1.5 lb of excess chicken** while staying inside the shopper's $0.75 premium limit.

That is the useful part of the integration. Browser finds what the packages actually say; Sandbox can compare the effect of those package choices across the whole trip. The answer is not always the cheapest individual product.

## How it works

~~~text
Recipe + pantry
      |
      v
SmartCart shopping requirements
      |
      v
Solari Browser observes approved product pages
      |
      v
Solari Sandbox compares complete baskets
      |
      v
SmartCart verifies and explains the result
      |
      v
Shopper chooses what happens next
~~~

If SmartCart cannot safely research an item, that item stays on the original shopping list with a clear reason. If Solari is unavailable, normal SmartCart still works.

## Try it

The fastest path is the **[public case study](https://exo-robotics.github.io/smartcart-solari/)**. Press **Research this meal** to request the fixed eight-item Demo Grocer run. A fresh request may run Browser and Sandbox; rate-limited visitors receive the last verified result, clearly labeled as cached.

You can also:

- switch between the [before and after recordings](https://exo-robotics.github.io/smartcart-solari/#native-flow);
- read the [human-friendly verified result](https://exo-robotics.github.io/smartcart-solari/verified-run.html);
- inspect the [credentialed GitHub Actions run](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546912947); or
- run the small [Solari Cookbook example](https://github.com/EXO-Robotics/solari-cookbook/tree/main/examples/smartcart-basket-research-ts).

The native recordings are labeled **DEBUG RECORDED REPLAY · NOT LIVE**. They show the iPhone experience; the receipts prove the separate provider runs.

## Why Browser and Sandbox?

### Browser gathers the evidence

Product pages are rendered web interfaces, not stable database rows. Browser records package identity, quantity, visible synthetic price, source, and time from approved pages. The qualified catalog renders prices with JavaScript, so a static download is not enough.

### Sandbox makes the basket decision

Sandbox compares complete baskets, not isolated products. It finds the cheapest basket that buys enough of every ingredient, then may spend up to $0.75 more when another basket meaningfully reduces leftovers. SmartCart checks the evidence and arithmetic before showing the result.

### Why no Desktop?

Desktop is intentionally absent because it has no necessary job in this workflow.

## Intentional product boundaries

Solari improves the shopping decision before retailer handoff. It does not operate the shopper's retailer account.

- The shopper explicitly starts Solari research.
- Solari's research browser uses a fresh, logged-out session against an approved source.
- After SmartCart hands the shopper to Walmart, the shopper signs in and shops directly with Walmart.
- Walmart owns the shopper's session, cookies, lists, cart, payment, checkout, and order.
- SmartCart and Solari never request, receive, store, or inspect Walmart credentials or account data.
- They do not automate Walmart controls, modify the cart, or interpret a visited page as a purchase.
- Exact product matches may proceed automatically; search fallbacks and lower-confidence matches require shopper review.
- Substitutions remain limited to approved candidates.
- Pantry changes require shopper confirmation. A visited product is not treated as something purchased.
- Demo Grocer observations and prices are qualification evidence only and are never transferred into the Walmart shopping trip.
- Solari credentials remain server-side.
- Sandbox receives normalized product evidence, not complete retailer pages or unrestricted prose.
- No proxying, stealth behavior, CAPTCHA bypass, or account personalization is used.

The public route accepts one owned meal and one allowlisted catalog. Full boundaries are in the [threat model](Docs/SOLARI_THREAT_MODEL.md).

## Proof

| Check | Result |
| --- | --- |
| Frozen V4 provider qualification | **PASS** — real Solari Browser + Sandbox run [33546912947](https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33546912947) |
| Qualified trip | **PASS** — 8 requirements, 16 Browser observations, 8 Sandbox decisions, confirmed cleanup |
| Basket decision | **PASS** — $24.20 selected vs. $23.57 cheapest adequate; +$0.63 avoided about 1.5 lb excess chicken |
| Self-serve public route | **PASS** — credentialed 17.596-second run, 16 observations, 8 decisions, 0 skipped lines, confirmed cleanup ([receipt](evidence/live/smartcart-solari-public-demo-20260902.json)) |
| Focused tests | **PASS** — backend 100/100, full backend 230/230, native 29/29, case study 6/6, catalog/replay 7/7 |
| Native app compilation and Simulator flow | **PASS** — `Release-SolariBeta` compiled with signing disabled; the eight-item native flow and 29/29 focused tests ran in iOS Simulator |
| Apple-signed archive and App Attest device run | **PENDING** — blocked at signing/provisioning, not source compilation |
| TestFlight / App Store / downloadable app | **PENDING** |
| Authorized commercial-retailer research | **PENDING** |
| Independent household usage | **PENDING** |

The native app compiles and runs in Simulator. The provider receipt separately proves server-side Solari execution. What remains pending is Apple signing/provisioning for the capability-enabled target and a real App Attest request from a physical device—not implementation compilation. Commercial-retailer coverage, TestFlight distribution, and product-market fit are also separate milestones.

## Architecture and detailed evidence

The backend and native client share versioned evidence contracts. The exact rules and receipts live here:

- [Experiment and responsibility split](Docs/SOLARI_EXPERIMENT.md)
- [Qualification matrix](Docs/SOLARI_QUALIFICATION.md)
- [Threat model](Docs/SOLARI_THREAT_MODEL.md)
- [Demo and provider runbook](Docs/SOLARI_DEMO_RUNBOOK.md)
- [Submission evidence packet](Docs/SOLARI_SUBMISSION_PACKET.md)
- [V4 contracts](contracts/v4/solari/)

The frozen provider-qualified runtime is commit [`2dd4e6f`](https://github.com/EXO-Robotics/smartcart-solari/commit/2dd4e6f30be8286a3a8f465c92a56427828a60e2). Its [sanitized receipt](evidence/live/smartcart-solari-v4-qualification-33546912947.json) binds the request and result to that run.

## Run it locally

Requirements: Xcode, Node.js, npm, and Python 3. Solari credentials are only needed for an authorized provider run and stay on the backend.

~~~bash
git clone https://github.com/EXO-Robotics/smartcart-solari.git
cd smartcart-solari
npm --prefix backend ci
npm --prefix backend run test:solari
npm --prefix backend test
python3 website/solari-demo/validate.py
~~~

To see the native replay, open `SmartCart.xcodeproj`, run the `SmartCart` scheme in an iPhone Simulator, and choose **Open Solari Demo Meal** from Home.

For deployment or a real provider qualification, use the [runbook](Docs/SOLARI_DEMO_RUNBOOK.md). A passing health check is not provider proof, and a Simulator build is not device or App Store proof.

## Built from SmartCart

SmartCart is an existing grocery-planning application built by **Blake Grove / [@AionForge](https://x.com/AionForge)**. This public submission is maintained under EXO-Robotics and was forked from SmartCart commit [`fe6589b`](https://github.com/EXO-Robotics/smartcart-ios/commit/fe6589b1bd811a7ca8afa9824deba9d3cbde7ab9).

The Solari fork adds an optional research step immediately before SmartCart's existing retailer handoff. It does not replace the recipe, pantry, list, retailer, cart, or checkout behavior in normal SmartCart. The production SmartCart repository remains untouched.
