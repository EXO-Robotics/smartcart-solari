# SmartCart local-state schema migration

## Version 6

Schema v6 adds Meal Prep without replacing the existing recipe-centric state.
New persisted fields are optional or have empty defaults so a v5 installation
migrates without changing its active recipe, shopping list, manifests, pantry,
or Retailer Assistant sessions.

New durable state:

- current `ShoppingScope` (`singleRecipe` or `mealPrep`);
- Meal Prep draft and reviewed combined ingredient lines;
- frozen plan snapshots on combined manifests and shopping sessions.

The legacy decoders remain isolated by schema version. Loading a valid v0-v5
file creates a v6 state in memory and then attempts an atomic rewrite. If that
rewrite fails after a successful decode, SmartCart continues from the migrated
in-memory state, preserves the original legacy bytes at the state path or a
migration-recovery path, and surfaces a recoverable persistence warning.
Rewrite failure alone must never quarantine valid legacy data or replace it
with defaults.

Legacy v5 Retailer Assistant recovery uses durable semantic identity rather
than assuming manifest-line and shopping-item UUIDs match. Recovery compares
scope, retailer/store context, normalized ingredient identity, product
identity, quantity/unit, and trip timing. Duplicate aliases retain one identity
even when their old trip IDs differ or one recovered alias lacks its manifest
link, while a repeat begun after the prior commit receives a new identity.

## Compatibility rules

- A newer schema is never quarantined or overwritten by an older build.
- Legacy single-recipe manifests and sessions remain valid and infer a
  single-recipe scope from their recipe identifier.
- Meal Prep manifests and sessions carry frozen source snapshots. Recipe edits
  or deletion therefore do not mutate historical trips.
- A completed shopping session is immutable. Editing a completed plan creates a
  new trip with a new fingerprint.
- Draft, reviewed lines, manifest, session, and reconciliation writes use the
  existing atomic state-store boundary; observable state changes only after a
  successful save for transactional operations.

## Validation

Fixed repository fixtures preserve representative v0-v4 JSON bytes without
regenerating them through current model encoders. The migration tests assert
recipes and ingredient corrections, serving selection, store and fulfillment
context, shopping-item progress, saved manifests, and recovered started-trip
sessions for every fixture. A completed legacy manifest is restored as a
read-only completed session and requires an explicit editable fork. Tests also
assert preferences and feature flags from v1 onward; pantry, product
preferences, and analytics from v2 onward; OCR and barcode-era metadata from
v3 onward; and the v4 Walmart Wishlist reference.

For every fixed v0-v4 fixture, tests inject rewrite failure, verify the migrated
in-memory fields and byte-exact source preservation, retry the current-schema
rewrite, and relaunch from the rewritten file before checking the same durable
fields again. Separate v5 regressions cover realistic Retailer Assistant
recovery, including manifests whose line UUIDs are disjoint from shopping-item
UUIDs. Forward-schema tests verify unsupported newer versions remain untouched
and report `unsupportedSchema`.
