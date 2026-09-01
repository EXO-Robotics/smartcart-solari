# SmartCart × Solari native-flow demo

This dependency-free static demo presents the Chicken Parmesan Pasta native experiment as a staged SmartCart workflow:

1. reviewed Recipe Ready state after pantry exclusions;
2. the explicit **Research current options** action before retailer handoff;
3. evidence-backed basket review;
4. explicit, user-controlled retailer handoff.

Credentialed GitHub Actions run `33519606791` proves Solari Browser + Sandbox execution against the owned synthetic Demo Grocer. Its sanitized receipt is `evidence/live/smartcart-solari-live-proof-33519606791.json`. That receipt does not prove a signed native App Attest request, physical-device/TestFlight success, distribution, or current third-party retailer pricing.

The interactive Walmart evidence is deliberately demoted to a collapsed historical replay from SmartCart upstream seeded records. It is not the native live input and does not prove a Solari run. Walmart Browser execution is disabled absent written authorization. `retailer/` is the separate owned, synthetic, JavaScript-rendered catalog used for controlled Solari Browser testing; it has no account, cart, checkout, or retailer affiliation.

Serve the repository root so both the UI and canonical contract fixtures remain addressable:

```sh
python3 -m http.server 8080
```

Then open:

- `http://127.0.0.1:8080/website/solari-demo/`
- `http://127.0.0.1:8080/website/solari-demo/retailer/`
- `http://127.0.0.1:8080/website/solari-demo/retailer/product/10414680.html`

Run local validation:

```sh
python3 website/solari-demo/validate.py
python3 -m unittest discover -s website/solari-demo/tests -v
node --check website/solari-demo/app.js
node --check website/solari-demo/retailer/retailer.js
```
