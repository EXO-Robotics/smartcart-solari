# SmartCart Trip Intelligence and MCP

SmartCart exposes portable recipe intelligence through authoritative versioned JSON contracts.
The Node service is the authority; Swift and MCP are bindings over the same request and response
semantics. SwiftUI, camera capture, OCR review, pantry interaction, Safari shopping execution, and
device trip persistence remain native iOS responsibilities.

## Public service boundaries

- `POST /v1/intelligence/nutrition/recipes/estimate` accepts and returns the authoritative v1
  recipe nutrition contracts.
- `POST /mcp` is a Streamable HTTP MCP endpoint.
- `POST /v1/handoffs/claim` exchanges a short-lived encrypted bearer for a frozen, contract-valid
  native recipe payload. The bearer is carried only in an HTTPS URL fragment.
- `GET /t` is the Universal Link target with an informational fallback page. It never forwards the
  fragment bearer into a custom URL scheme.
- `backend/src/mcp/stdio.js` provides the same tools over stdio for local plugin development.
- `plugins/smartcart-trip-intelligence/.mcp.json` is the checked-in local plugin binding.

The MCP surface has four stateless intelligence tools:

- `analyze_recipe`
- `estimate_recipe`
- `prepare_meal_plan`
- `plan_grocery_trip`

It also exposes one explicit action tool:

- `create_smartcart_handoff`

The action re-analyzes at most five recipes, refuses unsafe retailer queries, and returns a
short-lived bounded-use link. It does not mutate an account, pantry, saved recipe collection,
phone, Safari queue, or device trip. Native import begins only after the user opens the link.
One recipe is limited to 24 servings; Meal Prep handoffs allow up to five recipes with 48 servings
each. An `image_transcription` source explicitly marks every numeric quantity for confirmation in
the native Recipe Review before shopping.

## Contract authority

Schemas live under `contracts/v1`. `schemaVersion` describes transport compatibility;
`resolverVersion` identifies the algorithm or evidence revision that produced a result. Golden
fixtures under `contracts/fixtures/v1` are decoded by both Node and Swift tests.

Important invariants:

- Omitted and semantic quantities remain nonnumeric. They never become quantity one.
- Only a validated canonical identity may emit a retailer query.
- Source text and resolution evidence remain attached to results.
- Pantry ownership may change shopping intent but never recipe nutrition.
- Frozen recipes keep their own serving scales during Meal Prep aggregation.
- Recipe consumption cost, estimated checkout cost, and surplus value are separate concepts.
- Without reviewed retailer package evidence all three costs remain `null`; SmartCart never invents
  prices.

## Server configuration

Set the USDA FoodData Central key only in the server environment:

```text
USDA_FDC_API_KEY=<data.gov key>
USDA_FDC_BASE_URL=https://api.nal.usda.gov/fdc/v1
USDA_FDC_TIMEOUT_MS=8000
USDA_FDC_CACHE_TTL_SECONDS=86400
USDA_FDC_CACHE_MAX_ENTRIES=512
TRIP_INTELLIGENCE_RATE_LIMIT_PER_MINUTE=30
MCP_RATE_LIMIT_PER_MINUTE=60
SMARTCART_HANDOFF_BASE_URL=https://your-production-origin.example
SMARTCART_HANDOFF_TTL_SECONDS=600
SMARTCART_HANDOFF_MAX_PAYLOAD_BYTES=131072
SMARTCART_HANDOFF_MAX_TOKEN_CHARACTERS=24000
HANDOFF_TOKEN_SECRET=<32 random bytes encoded as base64url>
```

Never add the key to iOS configuration, plugin arguments, source control, fixtures, logs, or tool
results. Store `HANDOFF_TOKEN_SECRET` only as a Sensitive server environment variable; it is an
independent AES-256-GCM key and must never appear in the app, plugin arguments, URLs, logs, or
fixtures. `DEMO_KEY` is suitable only for the bounded live development verifier, not production.
Successful USDA searches and food details are cached and identical in-flight requests are coalesced
inside each warm server instance. The cache is bounded by entry count and TTL, never stores failures,
and never exposes the provider key. The two process-local admission limits protect warm server
instances and provider quota; production
should additionally enforce an equivalent Vercel Firewall rate rule because serverless instances do
not share in-memory counters. Cover canonical `/mcp` and `/v1/handoffs/claim` plus direct function
aliases `/api/mcp`, `/api/mcp.js`, `/api/handoff`, and `/api/handoff.js`. `vercel.json` returns 404
for the direct aliases before filesystem routing, but including them in firewall policy preserves
defense in depth against platform-routing changes.

## Verification

From `backend`:

```sh
npm run test:trip-intelligence
npm test
npm run verify:mcp
```

`verify:mcp` reads the checked-in plugin configuration, spawns the actual stdio server process,
lists all five tools, calls recipe analysis and grocery planning, and checks conservative retailer
and cost behavior. When `USDA_FDC_API_KEY` is present it additionally verifies live recipe nutrition
and Meal Prep aggregation against the selected official Parmesan record. When
`HANDOFF_TOKEN_SECRET` is present it also verifies the bounded-use handoff link boundary.

The local plugin scaffold is validated with the repository-independent plugin validator:

```sh
python3 scripts/validate_plugin.py plugins/smartcart-trip-intelligence
```

## Vercel and ChatGPT connection

The existing Vercel project uses `backend` as its configured root directory. Build from the repository
root so that the authoritative `contracts` directory can be traced into the intelligence function:

```sh
vercel pull --yes --environment=preview
vercel build
vercel deploy --prebuilt
```

After a preview reaches `READY`, verify `/health`, the REST estimate route, and the `/mcp` tool list
and `/v1/handoffs/claim` before promoting anything. Connect the resulting HTTPS `/mcp` URL as the SmartCart MCP server in the
ChatGPT developer/plugin surface. Do not promote a preview or point production traffic at it until
the real USDA key and independent handoff secret are configured and all five remote tool calls pass.

The handoff is deliberately bounded-use rather than server-persisted or one-time: its encrypted
payload can be reclaimed until its maximum ten-minute expiry. It contains analyzed recipes only,
never pantry conclusions, retailer product URLs, prices, or a remote trip record. SmartCart's native
review and persistence remain authoritative.
