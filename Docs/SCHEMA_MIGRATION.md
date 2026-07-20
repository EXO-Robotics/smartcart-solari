# SmartCart local-state schema migration

## Version 6

Schema v6 adds Meal Prep without replacing the existing recipe-centric state. New persisted fields are optional or have empty defaults so a v5 installation migrates without changing its active recipe, shopping list, internal manifests, pantry, or durable shopping-trip records.

New durable state includes:

- current `ShoppingScope` (`singleRecipe` or `mealPrep`);
- Meal Prep draft and reviewed combined ingredient lines;
- frozen plan snapshots on internal `ShoppingManifest` and `ShoppingSession` records;
- matching fingerprints used by exception-only product review;
- `GuidedItemStatus.visited`, meaning only that the user explicitly advanced after viewing a successfully loaded retailer page;
- optional `ShoppingSession.pantryUpdateReminderArchivedAt`, which suppresses only the Home pantry-update reminder.
- optional `Recipe.rawSourceText`, which preserves recognized or pasted source text for an explicit Recipe Ready review sheet.

These fields are backward-compatible additions within schema v6, not a schema-v7 boundary. A v6 trip written before the reminder or recipe source-text fields existed decodes them as `nil`. Legacy status cases (`added`, `saved_to_wishlist`, and `added_to_cart`) remain decodable; new normal-flow advancement writes `visited` instead.

The legacy decoders remain isolated by schema version. Loading a valid v0-v5 file creates a v6 state in memory and then attempts an atomic rewrite. If that rewrite fails after a successful decode, SmartCart continues from the migrated in-memory state, preserves the original legacy bytes at the state path or a migration-recovery path, and surfaces a recoverable persistence warning. Rewrite failure alone must never quarantine valid legacy data or replace it with defaults.

Legacy v5 trip recovery uses durable semantic identity rather than assuming internal manifest-line and shopping-item UUIDs match. Recovery compares scope, retailer/store context, normalized ingredient identity, product identity, quantity/unit, and trip timing. Duplicate aliases retain one identity even when their old trip IDs differ or one recovered alias lacks its manifest link, while a repeat begun after the prior commit receives a new identity.

## Compatibility rules

- A newer schema is never quarantined or overwritten by an older build.
- Legacy single-recipe internal manifests and sessions remain valid and infer a single-recipe scope from their recipe identifier.
- Meal Prep internal manifests and sessions carry frozen source snapshots, so recipe edits or deletion do not mutate historical trips.
- A completed trip is immutable. Editing a completed recipe or plan creates a new trip with a new fingerprint.
- `visited` is completed trip progress, but never evidence of a saved item, cart action, order, checkout, or purchase. The later pantry update remains user-confirmed.
- Archiving a pantry-update reminder sets only the optional timestamp on every alias of the same logical completed trip. It does not create reconciliation, change pantry or product preferences, or delete the frozen trip.
- Draft, reviewed-line, internal manifest/session, and reconciliation writes use the existing atomic state-store boundary; observable transactional state changes only after a successful save.

## Validation

Fixed repository fixtures preserve representative v0-v4 JSON bytes without regenerating them through current model encoders. Migration tests assert recipes and ingredient corrections, serving selection, store and fulfillment context, shopping-item progress, saved internal manifests, and recovered started trips for every fixture. A completed legacy manifest is restored as a read-only completed trip and requires an explicit editable fork. Tests also assert preferences and feature flags from v1 onward; pantry, product preferences, and analytics from v2 onward; OCR and barcode-era metadata from v3 onward; and the v4 Walmart shared-Wishlist reference.

For every fixed v0-v4 fixture, tests inject rewrite failure, verify migrated in-memory fields and byte-exact source preservation, retry the current-schema rewrite, and relaunch from the rewritten file before checking the same durable fields again. Separate v5 regressions cover realistic trip recovery, including manifests whose line UUIDs are disjoint from shopping-item UUIDs. Forward-schema tests verify unsupported newer versions remain untouched and report `unsupportedSchema`.

Current-schema regressions must also round-trip `visited`, decode an absent reminder timestamp as `nil`, persist reminder archival across relaunch, keep archived trips available for later reconciliation/history, and roll back visible archive state if persistence fails.
