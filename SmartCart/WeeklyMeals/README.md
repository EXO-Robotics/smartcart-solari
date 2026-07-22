# Weekly Meals

Weekly Meals is bundled editorial discovery that feeds the existing SmartCart recipe, pantry, product-resolution, grouping, shopping-session, retailer-handoff, and reconciliation pipeline.

The app ships one versioned fallback collection with exactly eight recipe records. It also checks a Git-managed static manifest for an immutable, self-contained collection file. Cached remote content appears immediately; a validated refresh replaces it atomically. Invalid, oversized, incompatible, stale, cross-origin, or unavailable remote content leaves the last valid collection untouched, with bundled Week 1 as the final fallback.

Refresh is stale-while-refresh: cold launch and foreground activation check only when the last validated cache is at least six hours old. Pull-to-refresh on Home forces a check. SwiftUI views read one shared `WeeklyMealsStore`, so Home, See All, detail, Save, Meal Prep, and Shop This Meal always resolve the same collection revision.

A curated recipe becomes a deterministic frozen `Recipe` snapshot only when a shopper chooses Shop This Meal, Save Recipe, or Add to Meal Prep. Content version is part of snapshot identity, so future manifest changes cannot rewrite saved recipes or historical trips.

Nutrition values are `editorialEstimate` and always use estimated language. Production recipe costs remain `requiresVerification` until every baseline ingredient has reviewed price evidence. `pricing-v1.json` intentionally contains no prices; synthetic fixture prices exist only in tests.

Recipe cost per serving means the proportional representative value of ingredients consumed. It is independent of pantry ownership. Checkout cost means full retailer packages still needed after pantry allocation, retailer matching, and package planning. Weekly Meal cards never show checkout cost.

The Home carousel uses one horizontal `LazyHStack`, stable IDs, view-aligned snapping, a fixed standard-height card, and a single resolved display-model pass. The centered card stays at scale 1.0; adjacent cards reduce to 0.93 scale, 0.84 opacity, and at most 7 points of vertical offset. Reduce Motion disables scale and offset. Accessibility text sizes use full-width vertical cards rather than clipping or capping Dynamic Type.

Remote v1 accepts approved bundled image asset keys only; it does not download arbitrary images. No third-party carousel, retailer link, production price, or external recipe image is included in this feature.

## Publishing

The production static files live under `backend/public/weekly-meals`:

- `manifest.json` is the small mutable pointer.
- `collections/week-NNN-vN.json` files are immutable and self-contained.
- `schema/collection-v1.schema.json` documents the public payload.

Create a content branch, add a new immutable collection file, update the manifest pointer and publication time, then run:

```sh
npm --prefix backend run validate:weekly-meals
```

The same validator runs in GitHub Actions. A branch push receives a Vercel preview; merging the reviewed content to the configured production branch publishes it. Do not overwrite an existing collection URL.
