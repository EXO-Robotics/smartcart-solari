# SmartCart local/demo backend

This directory is a credential-free Milestone 7 backend foundation. It is a zero-dependency Node.js ESM HTTP service intended only for local development and automated tests.

**Nothing here is live or production-ready.** Accounts and bearer sessions are mock local/demo identities. Manifests and analytics events exist only in process memory and disappear on restart. Product/catalog fields are client-supplied local/demo records and are never refreshed from a retailer. OAuth performs no provider request or token exchange. Affiliate URLs are deterministic local/demo decoration and do not provide attribution, pricing, inventory, cart transfer, or checkout.

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

Tests use only `node:test` and an ephemeral loopback HTTP port. No network service, provider, database, or package download is required.

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
- CORS permits only configured local origins. Responses use no-store, MIME-sniffing, frame, and referrer protections.

## What production work would still require

Do not promote this process unchanged. A live service would require reviewed durable storage and migrations, real identity/session management, CSRF and origin strategy, provider-specific OAuth discovery and token handling, secret management, catalog ingestion with provenance and freshness, distributed rate limiting, production observability and retention controls, affiliate compliance review, deployment hardening, and threat modeling.
