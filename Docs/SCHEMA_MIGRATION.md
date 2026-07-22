# SmartCart local-state schema migration

## Version 8

Schema v8 adds a persisted `persistenceRevision` and routes every post-load
AppModel write through one revision-ordered persistence coordinator. The JSON
store accepts only the exact durable successor, or a byte-identical retry of an
already committed revision. A delayed older snapshot cannot replace a newer
durable graph. Encoding and atomic file replacement run on the coordinator's
serial store queue; the current compatibility wrapper remains caller-synchronous
so existing rollback and navigation behavior does not change before Slice 7.

Missing revision metadata decodes as generation zero. Successful migrations
from schemas v0-v7 rewrite to schema v8 revision 1. If that rewrite fails, the
usable in-memory state remains at revision zero, the exact source bytes are
preserved in place or in a recovery sibling, and relaunch safely retries. A
future schema is rejected explicitly and is never quarantined or rewritten.

Schema v6 and v7 migrate by exact pass-through of recipes, editable shopping
rows, manifests, started/completed/reconciled sessions, pantry state, identity
mirrors, ordering, quantities, and statuses. Missing purchase groups remain
`nil`; migration never groups duplicate retailer rows or re-evaluates pantry
decisions. Schema-v7 ingredient resolutions are retained only as inert Codable
pass-through data until runtime exhaustive matching is integrated later.

`IngredientSourceEvidence.sourceCropReference` is an optional, structurally
validated locator. Existing inline crop data remains inline in this slice.
Missing or malformed new optional crop/group metadata is localized to `nil`
instead of invalidating an otherwise recoverable state.

Schema v7 was an internal foundation shape containing terminal ingredient
resolutions and optional purchase-group metadata. No pushed schema-v7 runtime
grouping or package-planning behavior is inferred during its migration.

## Version 6

Schema v6 adds Meal Prep without replacing the existing recipe-centric state. New persisted fields are optional or have empty defaults so a v5 installation migrates without changing its active recipe, shopping list, internal manifests, pantry, or durable shopping-trip records.

New durable state includes:

- current `ShoppingScope` (`singleRecipe` or `mealPrep`);
- Meal Prep draft and reviewed combined ingredient lines;
- frozen plan snapshots on internal `ShoppingManifest` and `ShoppingSession` records;
- matching fingerprints used by exception-only product review;
- `GuidedItemStatus.visited`, meaning only that the user explicitly advanced after viewing a successfully loaded retailer page;
- optional `ShoppingSession.pantryUpdateReminderArchivedAt`, which suppresses the pantry-update-pending Home card without removing the frozen completed trip;
- optional `Recipe.rawSourceText`, which preserves recognized or pasted source text for an explicit Recipe Ready review sheet;
- optional `Recipe.sourceDocument`, which preserves raw OCR observations separately from reconstructed text, layout-filtered ingredient lines, and ignored source lines; accepted parser output remains in `Recipe.ingredients`; and
- optional `savedRecipeIDs`, which records Saved Recipes library membership independently from retained recipe records.

These fields are backward-compatible additions within schema v6, not a schema-v7 boundary. A schema-v6 state payload written before these optional fields existed decodes their missing values as `nil`. Legacy status cases (`added`, `saved_to_wishlist`, and `added_to_cart`) remain decodable; new normal-flow advancement writes `visited` instead.

`savedRecipeIDs` has presence-sensitive compatibility semantics:

- absent in an older schema-v6 payload: infer Saved Recipes membership for retained, valid non-sample recipes;
- present and empty: preserve an intentionally empty library;
- present with unknown IDs: intersect with retained recipe IDs and discard the unknown values; and
- present with valid IDs: expose only those retained recipes in Saved Recipes and Meal Prep selection.

The same inference applies after v0-v5 decoding because those legacy migrations produce no membership field. A fresh install begins with no tester recipe records and empty Saved Recipes membership; curated discovery is supplied independently by bundled Weekly Meals. The first import of a new non-sample recipe saves it by default, and reopening a retained unsaved recipe does not silently resave it.

The legacy decoders remain isolated by schema version. Loading a valid v0-v5 file first applies the existing v6 domain migration and then advances to the current schema through the revision-safe rewrite boundary. If that rewrite fails after a successful decode, SmartCart continues from the migrated in-memory state, preserves the original legacy bytes at the state path or a migration-recovery path, and surfaces a recoverable persistence warning. Rewrite failure alone must never quarantine valid legacy data or replace it with defaults.

Legacy v5 trip recovery uses durable semantic identity rather than assuming internal manifest-line and shopping-item UUIDs match. Recovery compares scope, retailer/store context, normalized ingredient identity, product identity, quantity/unit, and trip timing. Duplicate aliases retain one identity even when their old trip IDs differ or one recovered alias lacks its manifest link, while a repeat begun after the prior commit receives a new identity.

## Compatibility rules

- A newer schema is never quarantined or overwritten by an older build.
- Legacy single-recipe internal manifests and sessions remain valid and infer a single-recipe scope from their recipe identifier.
- Meal Prep internal manifests and sessions carry frozen source snapshots, so recipe edits or removal from Saved Recipes do not mutate historical trips.
- A completed trip is immutable. Editing a completed recipe or plan creates a new trip with a new fingerprint.
- `visited` is completed trip progress, but never evidence of a saved item, cart action, order, checkout, or purchase. The later pantry update remains user-confirmed.
- Archiving a pantry-update reminder sets only the optional timestamp on every alias of the same logical completed trip. It hides the pending Home card but does not create reconciliation, change pantry or product preferences, or delete the frozen trip.
- Removing Saved Recipes membership preserves the retained recipe record, Shopping Trips, saved manifests, pantry, shopping and product preferences, analytics, and frozen Meal Prep state. After the JSON membership write succeeds, the separately stored Recent Recipes entry is pruned; a failed write rolls membership back and leaves recency unchanged.
- Recent Recipes is timestamped UI history in app defaults, not a schema-v6 JSON field. Only an import or intentional whole-recipe open adds or reorders entries; retailer pages, Shopping Trip resume, replacement, and reconciliation do not. Successful Saved Recipes membership removal may prune its matching entry.
- Photo provenance keeps raw observation text/page/normalized geometry/confidence/alternatives and source IDs in `Recipe.sourceDocument`, distinct from its reconstructed, layout-filtered, and ignored text streams. Accepted ingredients separately retain `IngredientSourceEvidence`, including their column/continuation metadata, reconstruction confidence, original line, and any removed suffix. `filteredIngredientLines` means layout-filtered input, not parser-sanitized output.
- Draft, reviewed-line, internal manifest/session, and reconciliation writes use the existing atomic state-store boundary; observable transactional state changes only after a successful save.

## Validation

Fixed repository fixtures preserve representative v0-v4 JSON bytes without regenerating them through current model encoders. Migration tests assert recipes and ingredient corrections, serving selection, store and fulfillment context, shopping-item progress, saved internal manifests, and recovered started trips for every fixture. A completed legacy manifest is restored as a read-only completed trip and requires an explicit editable fork. Tests also assert preferences and feature flags from v1 onward; pantry, product preferences, and analytics from v2 onward; OCR and barcode-era metadata from v3 onward; and the v4 Walmart shared-Wishlist reference.

For every fixed v0-v4 fixture, tests inject rewrite failure, verify migrated in-memory fields and byte-exact source preservation, retry the current-schema rewrite, and relaunch from the rewritten file before checking the same durable fields again. Separate v5 regressions cover realistic trip recovery, including manifests whose line UUIDs are disjoint from shopping-item UUIDs. Forward-schema tests verify unsupported newer versions remain untouched and report `unsupportedSchema`.

Current-schema regressions must also:

- round-trip `visited`, decode an absent reminder timestamp as `nil`, persist reminder archival across relaunch, keep archived trips available for later reconciliation/history, and roll back visible archive state if persistence fails;
- decode an absent `savedRecipeIDs` as inferred valid non-sample membership, preserve a present empty set, discard dangling IDs, and keep a fresh sample-backed install's membership empty;
- auto-save only a new non-sample import, keep the sample catalog dedicated, and require explicit save after reopening a retained unsaved recipe;
- remove membership atomically while preserving retained records, historical trips, pantry, preferences, and frozen Meal Prep state and pruning only successful recency removal; and
- round-trip raw OCR observations and reconstructed/layout-filtered/ignored source-document streams, decode missing optional source fields, and exercise accepted parser evidence separately in the OCR/parser regressions without collapsing those provenance roles.
