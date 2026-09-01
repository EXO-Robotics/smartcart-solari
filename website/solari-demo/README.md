# SmartCart × Solari replay UI

This dependency-free static demo presents the Chicken Parmesan Pasta experiment as a staged SmartCart workflow:

1. reviewed recipe and pantry exclusions;
2. Browser evidence boundary;
3. package and basket decision;
4. explicit, user-controlled retailer handoff.

The Walmart evidence is a dated fixture replay from SmartCart upstream seeded records. It is not a live retailer observation and does not prove a Solari run. Walmart Browser execution is disabled absent written authorization. `retailer/` is an owned, synthetic, JavaScript-rendered catalog for controlled Solari Browser testing; it has no account, cart, checkout, or retailer affiliation.

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
