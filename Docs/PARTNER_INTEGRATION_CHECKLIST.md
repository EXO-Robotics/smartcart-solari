# Partner integration checklist

No production partner is connected in this repository. Complete one section at a time and keep credentials out of Git.

## Universal requirements

- [ ] Written approval or valid developer-program access.
- [ ] Production and sandbox client IDs stored in a secrets manager.
- [ ] Redirect URIs registered exactly for development, beta, and production.
- [ ] Terms permit the intended search, deep-link, affiliate, cart, wishlist, and delivery behavior.
- [ ] Rate limits, attribution, caching, price freshness, deletion, and branding rules documented.
- [ ] User-facing capability label is driven by the connector’s actual approved features.
- [ ] Contract tests cover expired credentials, 401/403, 404, 429, timeouts, partial data, and revoked access.
- [ ] Logs redact authorization headers, tokens, email, address, recipe text, UPC, and checkout details.

## Instacart

- [ ] Partner/developer access approved.
- [ ] Client ID, secret, allowed origins, and redirect URIs provided.
- [ ] Confirm whether product search, retailer selection, basket transfer, attribution, and delivery handoff are approved.
- [ ] Replace the credential-free adapter only for capabilities supported by the agreement.

## Walmart

- [ ] Affiliate or partner program approved.
- [ ] Affiliate ID and link-attribution requirements supplied.
- [ ] Confirm whether any catalog, price, inventory, cart, or pickup APIs are actually available to this product.
- [ ] Retain seeded/demo labels until live requests are verified end to end.

## Kroger

- [ ] Keep the in-app Kroger card labeled Coming Soon until its guided-list adapter and contract tests are complete.
- [ ] Developer application approved.
- [ ] OAuth client ID/secret, scopes, redirect URIs, and location strategy supplied.
- [ ] Implement token refresh and consent revocation.
- [ ] Verify price/location/store attribution and caching policy.

## Target

- [x] Credential-free demo guide uses a bounded seeded catalog, exact public product pages, labeled searches, and Target Shopping Lists instructions.
- [x] Demo copy states that SmartCart cannot link an account, edit a list, confirm fulfillment, create a cart, or check out.
- [ ] Identify an approved public or partner integration before adding live catalog, price, inventory, account, list, cart, Drive Up, or delivery capabilities.
- [ ] Replace demo records only after live contract tests and branding/data-use review pass.

## Amazon Fresh, DoorDash, and Uber

- [ ] Identify an approved public or partner integration appropriate for grocery product handoff.
- [ ] Do not infer cart or delivery-transfer support from ordinary consumer deep links.
- [ ] Keep each connector in research-only state until approval and contract tests exist.

## Credential handoff to Codex

Provide variable names and sandbox credentials through an approved secrets surface, never pasted into source files or chat transcripts. The local backend’s `.env.example` is a schema only. After secrets exist, wire one provider in a dedicated branch, validate against sandbox accounts, and keep demo mode available for deterministic tests.
