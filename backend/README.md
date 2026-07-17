# SmartCart local/demo backend

This directory is a credential-free Milestone 7 backend foundation. It is a zero-dependency Node.js ESM HTTP service intended only for local development and automated tests.

**Nothing here is production-ready.** Accounts and bearer sessions are mock local/demo identities. Manifests and analytics events exist only in process memory and disappear on restart. Product/catalog fields are client-supplied local/demo records and are never refreshed from a retailer. OAuth performs no provider request or token exchange. Affiliate URLs are deterministic local/demo decoration and do not provide attribution, pricing, inventory, cart transfer, or checkout. The recipe-page endpoint is the one deliberate outbound capability: when an authenticated caller supplies a URL, it requests that third-party page under the limits below.

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

## API overview

Every JSON response includes `meta.dataMode: "local-demo"`, and every JSON response carries `X-SmartCart-Data-Mode: local-demo`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Health and local/demo capability disclosure |
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
- Structured JSON logging redacts authorization, cookies, tokens, secrets, passwords, email-like fields, OAuth codes, and PKCE values. Request bodies are never logged.
- Analytics rejects property keys that resemble direct identifiers or credentials, limits event/property counts and sizes, and retains at most 10,000 events in memory.
- Affiliate targets must be HTTPS and cannot contain embedded URL credentials.
- Recipe pages must use HTTPS, including every redirect, and cannot contain URL credentials. The fetcher uses `SmartCartRecipePageFetcher/0.1 (user-requested recipe import)` as its user agent, follows at most 5 redirects, times out after 10 seconds, accepts only `text/html` or `application/xhtml+xml`, and reads at most 2 MiB after transport decoding. These limits are configurable with `RECIPE_PAGE_MAX_REDIRECTS`, `RECIPE_PAGE_TIMEOUT_MS`, and `RECIPE_PAGE_MAX_BYTES`.
- HTML decoding honors a response `charset`, a Unicode BOM, or an early HTML `<meta charset>` when Node's `TextDecoder` supports that encoding. Unsupported encodings fail explicitly instead of silently guessing.
- Recipe extraction is deterministic and inert: it uses `JSON.parse` for JSON-LD and a local HTML tokenizer for fallback markup. It never evaluates JavaScript, loads subresources, follows page links, or exposes fetched HTML in the API response.
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

## What production work would still require

Do not promote this process unchanged. A live service would require reviewed durable storage and migrations, real identity/session management, CSRF and origin strategy, provider-specific OAuth discovery and token handling, secret management, catalog ingestion with provenance and freshness, distributed rate limiting, production observability and retention controls, affiliate compliance review, deployment hardening, outbound-network/SSRF policy, DNS and IP-range controls, robots/publisher-policy review, and threat modeling.
