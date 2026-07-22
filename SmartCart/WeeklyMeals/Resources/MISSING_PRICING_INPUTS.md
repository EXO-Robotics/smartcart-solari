# Weekly Meals v1 missing pricing inputs

`pricing-v1.json` intentionally contains no ingredient prices. No reviewed production pricing catalog was supplied for Week 1, so all eight bundled `RecipeCostEstimate` records remain `requiresVerification` with no public total or per-serving value.

To make a recipe estimate displayable, pricing version 1 needs one reviewed `WeeklyMealPriceRecord` for every baseline ingredient listed below. Each record must match the recipe ID, recipe content version 1, and ingredient ID and must supply a reviewed package price, package quantity, compatible package unit, stable pricing key, USD currency context, US pricing region, and an approved snapshot/staleness policy.

## Protein Overnight Oats

Recipe ID: `weekly.protein-overnight-oats`

Missing baseline ingredient IDs: `rolled-oats`, `milk`, `plain-greek-yogurt`, `vanilla-protein-powder`, `chia-seeds`, `mixed-berries`.

Excluded from the baseline: `maple-syrup` is optional and excluded by default; `salt` is qualitative.

## Make-Ahead Breakfast Burritos

Recipe ID: `weekly.make-ahead-breakfast-burritos`

Missing baseline ingredient IDs: `flour-tortillas`, `breakfast-sausage`, `eggs`, `potatoes`, `bell-pepper`, `onion`, `cheddar-cheese`, `salsa`, `cooking-oil`.

Excluded from pricing: `salt-and-black-pepper` is qualitative.

## Chicken Taco Rice Bowls

Recipe ID: `weekly.chicken-taco-rice-bowls`

Missing baseline ingredient IDs: `chicken-breast`, `cooked-rice`, `black-beans`, `corn`, `bell-pepper`, `onion`, `taco-seasoning`, `salsa`, `shredded-cheese`, `lime`, `cooking-oil`.

Excluded from pricing: `salt` is qualitative.

## Korean Ground Beef Bowls

Recipe ID: `weekly.korean-ground-beef-bowls`

Missing baseline ingredient IDs: `ground-beef`, `cooked-rice`, `broccoli`, `soy-sauce`, `brown-sugar-or-honey`, `sesame-oil`, `garlic`, `fresh-ginger`, `green-onions`.

Excluded from the baseline: `sesame-seeds` is optional and excluded by default.

## Honey Garlic Chicken and Rice

Recipe ID: `weekly.honey-garlic-chicken-rice`

Missing baseline ingredient IDs: `chicken-breast`, `cooked-rice`, `broccoli`, `honey`, `soy-sauce`, `garlic`, `rice-vinegar`, `cornstarch`, `water`, `cooking-oil`.

Excluded from pricing: `salt-and-black-pepper` is qualitative. A reviewed de minimis rule may later exclude the measured tablespoon of water, but no such production rule is encoded yet.

## One-Pot Cheeseburger Pasta

Recipe ID: `weekly.one-pot-cheeseburger-pasta`

Missing baseline ingredient IDs: `ground-beef`, `short-pasta`, `onion`, `tomato-paste`, `beef-broth`, `milk`, `cheddar-cheese`, `yellow-mustard`, `smoked-paprika`, `garlic-powder`.

Excluded from pricing: `salt-and-black-pepper` is qualitative.

## Protein Berry Smoothie

Recipe ID: `weekly.protein-berry-smoothie`

Missing baseline ingredient IDs: `milk`, `plain-greek-yogurt`, `frozen-mixed-berries`, `banana`, `vanilla-protein-powder`, `ice`.

Excluded from pricing: `water` is qualitative. A reviewed de minimis rule may later exclude ice, but no such production rule is encoded yet.

## Creamy Buffalo Chicken Dip

Recipe ID: `weekly.creamy-buffalo-chicken-dip`

Missing baseline ingredient IDs: `shredded-chicken`, `cream-cheese`, `plain-greek-yogurt`, `buffalo-hot-sauce`, `cheddar-cheese`, `ranch-seasoning`.

Excluded from the baseline: `green-onions` is optional and excluded by default. Chips, crackers, bread, wraps, and vegetables used for dipping are not part of the recipe or its base nutrition.

## Guardrails

- Synthetic prices belong only in unit-test fixtures and must never be copied into this directory.
- A partial set of reviewed prices must keep the recipe at `requiresVerification`.
- Recipe ingredient-use cost may prorate package value; retailer checkout cost uses complete package counts after pantry allocation and remains a separate downstream metric.
- Pantry ownership never changes recipe cost per serving.
