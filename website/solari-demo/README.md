# SmartCart × Solari native-flow demo

This dependency-free static demo presents the Chicken Parmesan Pasta native experiment as a staged SmartCart workflow:

1. reviewed Recipe Ready state after pantry exclusions;
2. the explicit **Research current options** action before retailer handoff;
3. evidence-backed basket review;
4. explicit, user-controlled retailer handoff.

Credentialed GitHub Actions run `33519606791` is prior V1 Solari Browser + Sandbox proof against the owned synthetic Demo Grocer. Its sanitized receipt is `evidence/live/smartcart-solari-live-proof-33519606791.json`. It does not cover the current V3 IDs or low-waste policy and does not prove a signed native App Attest request, physical-device/TestFlight success, distribution, or current third-party retailer pricing.

The default V3 catalog has six distinct `dg-*` products: value and right-size choices for chicken, penne, and Parmesan. Its expected whole-basket policy allows at most `$0.75` above the `$12.79` minimum-cost basket, then maximizes avoided overbuy. The expected result is `$13.32`: two 1 lb chicken packages plus value penne and Parmesan, avoiding 16 oz of chicken overbuy for a `$0.53` premium. This is deterministic test math pending a new credentialed run.

The interactive Walmart evidence is deliberately demoted to a collapsed historical replay from SmartCart upstream seeded records. It is not the native live input and does not prove a Solari run. Walmart Browser execution is disabled absent written authorization. `retailer/legacy-catalog.json` and the six numeric product URLs preserve immutable V1 evidence links with explicit historical labels. The default `retailer/catalog.json` and `dg-*` pages expose only current V3 synthetic candidates. Neither surface has account, cart, checkout, or retailer affiliation.

Serve the repository root so both the UI and canonical contract fixtures remain addressable:

```sh
python3 -m http.server 8080
```

Then open:

- `http://127.0.0.1:8080/website/solari-demo/`
- `http://127.0.0.1:8080/website/solari-demo/retailer/`
- `http://127.0.0.1:8080/website/solari-demo/retailer/product/dg-chicken-rightsize-1lb.html`

Historical V1 numeric product URLs remain routable but are not listed by the default catalog.

Run local validation:

```sh
python3 website/solari-demo/validate.py
python3 -m unittest discover -s website/solari-demo/tests -v
node --check website/solari-demo/app.js
node --check website/solari-demo/retailer/retailer.js
```
