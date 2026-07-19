# Closed beta validation plan

## Cohort

Recruit 20–50 testers who shop for groceries at least twice per month. Include a mix of iPhone models, accessibility settings, household sizes, dietary preferences, and shopping styles. Do not promise live prices, cart creation, or pickup reservations.

## Tester setup

1. Install the TestFlight build after Apple review.
2. In Account, enable **Internal tester mode** and keep local anonymous events enabled.
3. Choose realistic organic, dietary, budget, and store-brand preferences.
4. Complete at least three recipes from different source types.
5. Use the guided retailer handoff, then report whether it saved time compared with manual search.

## Recipe matrix

First complete the stricter source-level acceptance run in
`OCR_PARSER_HUMAN_TEST_PLAN.md`. Then test at least 25 recipes across:

- 5 clean screenshots from recipe sites.
- 5 camera photos of cards, books, or handwritten print.
- 5 public recipe URLs with schema.org metadata.
- 3 short recipes with five or fewer ingredients.
- 3 complex recipes with 15 or more ingredients or multiple image pages.
- 2 organic-only cases, including one with no eligible exact organic product.
- 2 pantry-heavy cases where most ingredients should receive visible full or
  partial coverage suggestions; the tester must still confirm use, remainder,
  or buy-full behavior.

## Required task script

For every recipe, record:

1. Import method and whether extraction completed.
2. Number of ingredient corrections before continuing.
3. Whether serving scaling was understandable.
4. Whether pantry exclusions were correct.
5. Whether the chosen store/fulfillment language was truthful.
6. Number of product replacements and retailer search fallbacks.
7. Time from import start to first retailer product handoff.
8. Whether the tester completed the guided flow.
9. Which post-shopping outcome the tester selected and whether the resulting
   pantry quantities were correct after relaunch.
10. Whether a substitution was recorded and learned only after explicit opt-in.
11. One sentence describing the largest source of friction.

## Meal Prep matrix

Meal Prep is the final major beta feature. Each tester should complete at least
two plans using only reviewed saved recipes:

1. One recipe with a changed serving count, proving the single-recipe shopping
   workflow still behaves the same.
2. Three to five recipes with at least one safe merge, one intentionally
   separate subtype (for example red and yellow onion), one incompatible
   measurement pair, and one partially covered pantry item.
3. Terminate and relaunch once during combined-ingredient review and once during
   Retailer Assistant; verify the exact plan and item position restore.
4. Change a serving count after a trip exists and verify SmartCart starts a new
   compatible trip rather than resuming stale quantities.
5. Delete or edit a source recipe after starting a plan and verify the active
   trip retains its frozen title and ingredient provenance.
6. Complete pantry reconciliation twice and verify the second attempt cannot
   increment stock again.

Record incorrect merges, missed safe merges, pantry deduction errors, and any
case where the source recipe for a combined line is unclear. Any automatic
cross-dimension merge or incompatible session resume blocks beta promotion.

## Metrics and decision thresholds

| Metric | Beta target | Stop/repair threshold |
| --- | ---: | ---: |
| Import success | at least 85% | below 75% |
| Median ingredients corrected | at most 20% | above 35% |
| Median time to first handoff | under 4 minutes | over 7 minutes |
| Product replacement frequency | under 25% | over 40% |
| Guided-flow completion | at least 70% | below 55% |
| Crash-free sessions | at least 99% | any reproducible data-loss crash |

The thresholds are product hypotheses, not claims. Revisit them after the first ten tester sessions.

## Privacy and evidence handling

The app’s diagnostic funnel stays on device and excludes recipe text, URLs, addresses, emails, and UPC values. Testers should send screenshots or a structured feedback form voluntarily. Do not collect retailer credentials, payment details, health data, or precise location. Production telemetry requires a separate consent and privacy review.

## Exit gate

Advance beyond closed beta only after the core import-to-pantry loop meets the
targets above, reconciliation never double-increments stock, and the team has
documented and accepted every non-safety miss. Silent purchasing errors, false
pantry removals, and data loss cannot be accepted as metric tradeoffs.
