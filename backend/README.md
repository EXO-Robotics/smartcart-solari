# SmartCart local/demo backend

This directory is a zero-dependency Node.js ESM HTTP service intended for local development and automated tests. It can optionally make a server-authenticated Instacart Developer Platform handoff request when explicitly configured and can resolve food identity through Open Food Facts.

**Nothing here is production-ready.** Accounts and bearer sessions are mock local/demo identities. Manifests, handoff URL caches, barcode lookup caches, and analytics events exist only in process memory and disappear on restart. OAuth performs no provider request or token exchange. Affiliate URLs are deterministic local/demo decoration and do not provide attribution, pricing, inventory, cart transfer, or checkout. Recipe-page extraction, food-identity lookup, and an explicitly configured Instacart handoff are the only deliberate outbound capabilities.

## Requirements and start

- Node.js 20 or newer (tested with Node.js 24).
- No package installation and no credentials.

```sh
cd backend
cp .env.example .env
node --env-file=.env src/server.js
```

Or run with the built-in defaults:

```sh
cd backend
npm start
```

The default listener is `http://127.0.0.1:8787`. The service intentionally binds to loopback unless configuration explicitly changes it.

## Test

```sh
cd backend
npm test
```

Tests use only `node:test`, saved HTML, injected fetch doubles, and an ephemeral loopback HTTP port. No live website, provider, database, or package download is required.

## Beta public deployment surface

The Vercel project rooted at this `backend` directory deliberately deploys only one small
function plus reviewed static Weekly Meals JSON. `vercel.json` exposes `GET`/`HEAD /health`,
`GET /v1/barcodes/{gtin}`, and files under `/weekly-meals`; it returns 404 for every other route
and method. The function reuses `BarcodeCatalogService`; it does not
import or deploy the mock account, session, OAuth, manifest, analytics, recipe-page, affiliate,
or Instacart application routes.

This is a beta product-identity lookup, not a deployment of the complete local/demo backend.
Its positive and negative caches and provider limiter are process-local and may be cold after a
new function instance starts. Do not configure a Vercel project for this directory as if the
other local/demo routes were production services.

Weekly Meals uses `public/weekly-meals/manifest.json` as a mutable pointer and immutable,
self-contained files under `public/weekly-meals/collections`. Validate every editorial change
with `npm run validate:weekly-meals`; GitHub Actions runs the same command before reviewed content
reaches the production branch. The iOS client validates and caches content independently and
falls back to its bundled collection when this static surface is unavailable or invalid.

## API overview

Local/demo JSON responses include `meta.dataMode: "local-demo"`, and every JSON response carries `X-SmartCart-Data-Mode: local-demo`. The barcode response instead carries explicit `source` and `verified` fields because it may contain crowdsourced provider identity.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Health and local/demo capability disclosure |
| `GET` | `/v1/barcodes/{gtin}` | Resolve food identity without price or availability claims |
| `POST` | `/v1/demo/accounts` | Create an in-memory mock account |
| `POST` | `/v1/demo/sessions` | Issue an expiring in-memory bearer token |
| `GET` | `/v1/demo/account` | Read the authenticated mock account |
| `DELETE` | `/v1/demo/sessions/current` | Revoke the current mock session |
| `POST` | `/v1/oauth/{provider}/start` | Create one-time state and an S256 PKCE pair |
| `POST` | `/v1/oauth/{provider}/callback` | Validate state/verifier and simulate a connection |
| `POST` | `/v1/manifests` | Create an in-memory manifest |
| `GET` | `/v1/manifests/{id}` | Read an owned manifest |
| `PATCH` | `/v1/manifests/{id}` | Update with `expectedVersion` concurrency control |
| `POST` | `/v1/manifests/{id}/sync` | Sync against `baseVersion`; return `409` on conflict |
| `POST` | `/v1/analytics/events` | Ingest up to 100 bounded, identifier-free events |
| `POST` | `/v1/affiliate-links` | Decorate an HTTPS target through a provider abstraction |
| `POST` | `/v1/recipe-pages/extract` | Bounded HTTPS fetch and deterministic recipe extraction |
| `POST` | `/api/handoffs/instacart` | Validate an owned manifest and create/reuse an Instacart shopping-list URL |

The complete contract is in [`openapi.yaml`](openapi.yaml).

## Minimal local/demo flow

Create a mock account and then create a mock session using the returned account ID:

```sh
curl -s http://127.0.0.1:8787/v1/demo/accounts \
  -H 'content-type: application/json' \
  -d '{"displayName":"Demo Shopper","email":"shopper@example.local"}'

curl -s http://127.0.0.1:8787/v1/demo/sessions \
  -H 'content-type: application/json' \
  -d '{"accountId":"REPLACE_WITH_LOCAL_DEMO_ACCOUNT_ID"}'
```

Use the returned token only as a local/demo bearer token:

```sh
curl -s http://127.0.0.1:8787/v1/demo/account \
  -H 'authorization: Bearer REPLACE_WITH_LOCAL_DEMO_TOKEN'
```

## Design and security boundaries

- `src/app.js` owns routing, CORS, security headers, body limits, authentication gates, rate-limit responses, and error envelopes.
- `LocalDemoStore` owns capacity-limited in-memory local/demo accounts, manifests, and analytics plus expiring sessions. It is not durable persistence.
- `LocalDemoOAuthPkce` generates state, verifier, and S256 challenge values, consumes state once, and simulates completion. It deliberately has no client secret and no token exchange implementation.
- `AffiliateLinkService` depends on a provider interface and uses a TTL cache. Its included provider only appends clearly named local/demo query parameters.
- `TtlCache` provides lazy TTL expiry for sessions, OAuth state, and affiliate results.
- `FixedWindowRateLimiter` is process-local and keyed by remote address plus path. It is a development safeguard, not distributed abuse protection.
- Barcode lookup validates and canonicalizes GTIN-8, UPC-A, EAN-13, and GTIN-14, checks the in-memory positive/negative cache, and then calls Open Food Facts at most 12 times per minute per process. Concurrent requests for the same GTIN are coalesced. Raw GTIN path values are redacted from structured request logs.
- Open Food Facts results are crowdsourced and are returned as editable, `verified: false` product identity only. Name, optional brand, display-only package quantity, validated optional HTTPS image URL, and source are the entire product response. SmartCart does not return or infer price, availability, retailer identity, nutrition, pantry amount, or purchase state from this endpoint.
- Structured JSON logging redacts authorization, cookies, tokens, secrets, passwords, email-like fields, OAuth codes, and PKCE values. Request bodies are never logged.
- Analytics rejects property keys that resemble direct identifiers or credentials, limits event/property counts and sizes, and retains at most 10,000 events in memory.
- Affiliate targets must be HTTPS and cannot contain embedded URL credentials.
- Recipe pages must use HTTPS, including every redirect, and cannot contain URL credentials. The fetcher uses `SmartCartRecipePageFetcher/0.1 (user-requested recipe import)` as its user agent, follows at most 5 redirects, times out after 10 seconds, accepts only `text/html` or `application/xhtml+xml`, and reads at most 2 MiB after transport decoding. These limits are configurable with `RECIPE_PAGE_MAX_REDIRECTS`, `RECIPE_PAGE_TIMEOUT_MS`, and `RECIPE_PAGE_MAX_BYTES`.
- HTML decoding honors a response `charset`, a Unicode BOM, or an early HTML `<meta charset>` when Node's `TextDecoder` supports that encoding. Unsupported encodings fail explicitly instead of silently guessing.
- Recipe extraction is deterministic and inert: it uses `JSON.parse` for JSON-LD and a local HTML tokenizer for fallback markup. It never evaluates JavaScript, loads subresources, follows page links, or exposes fetched HTML in the API response.
- `InstacartHandoffService` filters pantry and explicitly excluded optional items, blocks unresolved alternatives and unconfirmed or low-confidence quantities, maps only official health filters and supported measurements, and fingerprints the normalized manifest plus postal/retailer/fulfillment preference with SHA-256 before provider access.
- `INSTACART_API_KEY` is read only by the server and sent only as an authorization header to the configured Instacart API base. Structured logging also redacts API-key and credential-shaped fields. Do not put this key in a client bundle, request body, checked-in file, or URL.
- Recipe candidates are searched through JSON-LD objects, arrays, `@graph`, and nested values; the candidate with the most ingredient lines wins, with document order as the tie-breaker. Fallback order is recipe microdata, common recipe-plugin ingredient containers, then visible `Ingredients` content. Fallbacks preserve section headings and stop before instructions, directions, methods, notes, nutrition, or equipment.
- CORS permits only configured local origins. Responses use no-store, MIME-sniffing, frame, and referrer protections.

## Recipe-page extraction

The endpoint requires a local/demo bearer token. It returns flattened `ingredients` for simple clients and `ingredientSections` for clients that preserve recipe groups, plus `originalUrl`, `finalUrl`, redirect count, MIME, charset, and byte length. Fetched HTML is discarded after extraction.

```sh
curl -s http://127.0.0.1:8787/v1/recipe-pages/extract \
  -H 'authorization: Bearer REPLACE_WITH_LOCAL_DEMO_TOKEN' \
  -H 'content-type: application/json' \
  -d '{"url":"https://recipes.example/recipe"}'
```

Typed failures distinguish invalid or non-HTTPS URLs, invalid/unsafe redirects, redirect-limit and missing-location errors, network failure, timeout, upstream access denial/not-found/rate-limit/other status, oversized pages, unsupported MIME or charset, empty bodies, and pages with no extractable recipe.

## Barcode identity lookup

`GET /v1/barcodes/{gtin}` is intentionally credential-free so the iOS scanner can use it before any retailer interaction. Configure a reachable backend URL in the app with `SMARTCART_BARCODE_BACKEND_URL`; recipe or commerce backend URLs remain fallbacks for local testing. The service sends the configured identifying User-Agent, normalizes provider fields, caches positive matches for one day and true 404 misses for 15 minutes, and returns either `resolved` or `not_found`. Provider rate limits, timeouts, unavailability, upstream errors, and malformed responses use truthful 429/504/503/502 statuses and are never cached as misses.

## Instacart shopping-list handoff

`POST /api/handoffs/instacart` requires the local/demo bearer token and accepts `shoppingManifestId`, `postalCode`, optional `preferredRetailerKey`, and `fulfillmentPreference` (`pickup`, `delivery`, or `decide_in_instacart`). The manifest is loaded through the authenticated account, so another account receives the same `404 manifest_not_found` boundary as the manifest read API.

Each included manifest item must provide a `commerce` object (the SmartCart client contract), an `instacart` compatibility object, or the same fields directly on the item with:

- `name`, optional `displayText`, positive `quantity` and a supported `unit` (or 1–10 `lineItemMeasurements`);
- `quantityConfirmed: true` and `unresolvedAlternative: false`; if a separate `quantityConfidence` is supplied, it must be high (`high`, `High confidence`, or a score of at least `0.82`). SmartCart's client maps unresolved low-confidence review state to `quantityConfirmed: false` before upload;
- optional `healthFilters`, of which only Instacart's official `ORGANIC`, `GLUTEN_FREE`, `FAT_FREE`, `VEGAN`, `KOSHER`, `SUGAR_FREE`, and `LOW_FAT` values are forwarded;
- optional `exactUPC`, which is forwarded only when `exactIdentityReliable: true`, `upcExactAndReliable: true`, `exactUPCReliable: true`, or `upcReliability: "exact"` is also explicit, and only when it is a valid 12- or 14-digit UPC.

Items marked as pantry (`pantryExcluded: true`, `inclusion: "pantry"`, `pantry: true`, or equivalent confirmed pantry state) or optional-excluded (`optionalSelected: false`, `inclusion: "optional-excluded"`, `optionalExcluded: true`, or `includeInList: false`) are removed before safety validation. The provider request uses the official 2026 `line_items` and `line_item_measurements` fields; deprecated line-item `quantity` and `unit` fields are never emitted.

Configure a development key with `INSTACART_API_KEY` and the default development base `https://connect.dev.instacart.tools`. Production defaults to `https://connect.instacart.com`; either can be overridden with `INSTACART_API_BASE_URL`. If a preferred retailer key is supplied, the service makes an advisory `GET /idp/v1/retailers` lookup using the postal code and appends a verified `retailer_key` to the generated URL. Lookup failure or a missing retailer match does not block creation of the otherwise valid shopping-list URL.

For UI-only development, `INSTACART_DEMO_HANDOFF_URL` returns that explicit URL with `provider: "instacart-demo"` and `presentationMode: "development-demo"`; it makes no Instacart call and is rejected when `NODE_ENV=production`. Successful results are cached in memory by the 64-character SHA-256 `manifestFingerprint`, so identical normalized manifest and preference requests reuse the original URL and `createdAt`.

## What production work would still require

Do not promote this process unchanged. A live service would require reviewed durable storage and migrations, real identity/session management, CSRF and origin strategy, provider-specific OAuth discovery and token handling, secret management, catalog ingestion with provenance and freshness, distributed rate limiting, production observability and retention controls, affiliate compliance review, deployment hardening, outbound-network/SSRF policy, DNS and IP-range controls, robots/publisher-policy review, and threat modeling.
