# Weekly Meals Local MVP

Weekly Meals is bundled editorial discovery that feeds the existing SmartCart recipe, pantry, product-resolution, grouping, shopping-session, retailer-handoff, and reconciliation pipeline.

The local MVP ships one versioned fallback collection with exactly eight recipe records. Bundled manifests are date-resolved with an injected calendar and fail closed when validation fails. A curated recipe becomes a deterministic frozen `Recipe` snapshot only when a shopper chooses Shop This Meal, Save Recipe, or Add to Meal Prep. Content version is part of snapshot identity, so future manifest changes cannot rewrite saved recipes or historical trips.

Nutrition values are `editorialEstimate` and always use estimated language. Production recipe costs remain `requiresVerification` until every baseline ingredient has reviewed price evidence. `pricing-v1.json` intentionally contains no prices; synthetic fixture prices exist only in tests.

Recipe cost per serving means the proportional representative value of ingredients consumed. It is independent of pantry ownership. Checkout cost means full retailer packages still needed after pantry allocation, retailer matching, and package planning. Weekly Meal cards never show checkout cost.

The Home carousel uses one horizontal `LazyHStack`, stable IDs, view-aligned snapping, a fixed standard-height card, and a single resolved display-model pass. The centered card stays at scale 1.0; adjacent cards reduce to 0.93 scale, 0.84 opacity, and at most 7 points of vertical offset. Reduce Motion disables scale and offset. Accessibility text sizes use full-width vertical cards rather than clipping or capping Dynamic Type.

No remote content, third-party carousel, retailer link, production price, or external recipe image is included in this feature.
