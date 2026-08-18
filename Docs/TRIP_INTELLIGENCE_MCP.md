# SmartCart Trip Intelligence and MCP

SmartCart exposes portable recipe intelligence through authoritative versioned JSON contracts.
The Node service is the authority; Swift and MCP are bindings over the same request and response
semantics. SwiftUI, camera capture, OCR review, pantry interaction, Safari shopping execution, and
device trip persistence remain native iOS responsibilities.

## Public service boundaries

- `POST /v1/intelligence/nutrition/recipes/estimate` accepts and returns the authoritative v1
  recipe nutrition contracts.
- `POST /mcp` is a stateless Streamable HTTP MCP endpoint.
- `backend/src/mcp/stdio.js` provides the same tools over stdio for local plugin development.
- `plugins/smartcart-trip-intelligence/.mcp.json` is the checked-in local plugin binding.

The MCP surface is intentionally stateless:

- `analyze_recipe`
- `estimate_recipe`
- `prepare_meal_plan`
- `plan_grocery_trip`

It does not read or mutate an account, pantry, saved recipe collection, or device trip. Pantry names
may be supplied explicitly as request context. A future authenticated claim-token handoff can be
added without changing these stateless tools.

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
```

Never add the key to iOS configuration, plugin arguments, source control, fixtures, logs, or tool
results. `DEMO_KEY` is suitable only for the bounded live development verifier, not production.
Successful USDA searches and food details are cached and identical in-flight requests are coalesced
inside each warm server instance. The cache is bounded by entry count and TTL, never stores failures,
and never exposes the provider key. The two process-local admission limits protect warm server
instances and provider quota; production
should additionally enforce an equivalent Vercel Firewall rate rule because serverless instances do
not share in-memory counters.

## Verification

From `backend`:

```sh
npm run test:trip-intelligence
npm test
npm run verify:mcp
```

`verify:mcp` reads the checked-in plugin configuration, spawns the actual stdio server process,
lists all four tools, calls recipe analysis and grocery planning, and checks conservative retailer
and cost behavior. When `USDA_FDC_API_KEY` is present it additionally verifies live recipe nutrition
and Meal Prep aggregation against the selected official Parmesan record.

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
before promoting anything. Connect the resulting HTTPS `/mcp` URL as the SmartCart MCP server in the
ChatGPT developer/plugin surface. Do not promote a preview or point production traffic at it until
the real USDA key is configured and the four remote tool calls pass.

The current V1 does not implement user authentication, pantry mutation, remote trip persistence,
or an iPhone claim token. Those remain explicit later milestones rather than hidden behavior in the
stateless tools.
