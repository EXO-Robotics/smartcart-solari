# SmartCart transport contracts

This directory is the authoritative, platform-neutral contract for SmartCart
Trip Intelligence. Swift, HTTP, MCP, tests, and future clients are bindings of
these schemas; no client-side model is the wire authority.

## Versioning

- `schemaVersion` changes only when the transport contract changes.
- `resolverVersion` changes when matching, density, nutrition, or calculation
  behavior changes without changing the transport shape.
- Additive compatible changes remain within `v1` and require fixture coverage.
- Breaking changes receive a new top-level contract directory.

All schemas use JSON Schema draft 2020-12. Stable schema identifiers are rooted
at `https://schemas.smartcart.app/`; this identifier is not a promise that the
schema is currently hosted at that URL.

## Evidence and estimate rules

- Original user/source text is preserved in `IngredientInput.sourceText`.
- Unknown values are omitted or represented by `null`; resolvers do not invent
  numeric quantities.
- Numeric estimates retain preferred, minimum, and maximum values.
- Resolution issues use `blocking`, `review`, or `informational` severity.
- Resolver results carry evidence and a resolver version for auditability.
- Retail pricing and checkout economics are intentionally not part of the
  initial nutrition contract. Future retail contracts must keep recipe
  consumption cost, package checkout cost, and surplus value separate.

## Golden fixtures

`fixtures/v1/` contains contract-valid examples consumed by backend and iOS
tests. Fixture values are deterministic test evidence, not a production food or
price catalog.
