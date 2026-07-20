# Closed beta validation plan

## Cohort

Recruit 20–50 testers who shop for groceries at least twice per month. Include a mix of iPhone models, Dynamic Type sizes, VoiceOver experience, household sizes, dietary preferences, and shopping styles. Do not promise live prices, retailer automation, account linkage, purchase detection, cart creation, or pickup reservations.

## Tester setup

1. Install the TestFlight build after Apple review.
2. In Account, enable **Internal tester mode** and keep local anonymous events enabled.
3. Choose realistic organic, dietary, budget, and store-brand preferences.
4. Complete at least three recipes from different source types and one Meal Prep plan.
5. Use Recipe Ready and the Safari Shopping Trip, then report whether they saved time compared with manual search.

## Recipe matrix

First complete the stricter source-level acceptance run in `OCR_PARSER_HUMAN_TEST_PLAN.md`. Then test at least 25 recipes across:

- 5 clean screenshots from recipe sites.
- 5 camera photos of cards, books, or handwritten print.
- 5 public recipe URLs with schema.org metadata.
- 3 short recipes with five or fewer ingredients.
- 3 complex recipes with 15 or more ingredients or multiple image pages.
- 2 organic-only cases, including one with no eligible exact organic product.
- 2 pantry-heavy cases with visible full or partial coverage suggestions; the tester must still choose pantry use, buy remainder, or buy full.

## Required task script

For every recipe, record:

1. Import method and whether extraction completed.
2. Ingredient corrections and whether Recipe Ready exposed blocking issues clearly without requiring a fixed multi-screen wizard.
3. Whether serving, pantry, retailer, store/fulfillment, and preference changes were understandable from Recipe Ready.
4. Product exceptions shown. High-confidence exact matches should continue without interruption; each fallback or lower-confidence choice must remain explicit.
5. Time from import start to the first retailer page.
6. Whether the tester completed the continuous Shopping Trip without a return questionnaire between pages.
7. Whether **Next Item**, unavailable, skip, replacement, pause, and resume behaved as described below.
8. Which post-trip pantry outcome the tester chose and whether quantities were correct after relaunch.
9. Whether a substitution was learned only after explicit opt-in.
10. One sentence describing the largest source of friction.

## Shopping Trip and reminder matrix

Exercise each of these paths for Walmart and Target where applicable:

1. After a successful retailer-page load, tap **Next Item**. Verify the next product opens in the same Safari trip and the prior item is recorded as `visited` only.
2. Verify `visited` does not claim saved-to-list, cart, order, checkout, or purchase knowledge. It may be selected by default in the later pantry check-in, but the tester must still confirm what was bought.
3. Tap **Pause** and verify the current waiting item resumes after relaunch without advancing.
4. Use Safari’s native close control or dismiss the sheet. Verify the result is the same safe pause at the current item.
5. Force a retailer-page load failure. **Next Item** must remain unavailable, the item must remain waiting, and retry, external open, skip, and pause must remain reachable.
6. Report unavailable, skip an item, and choose a safe replacement. Verify each explicit action advances or refreshes only the intended item.
7. Complete a trip and exercise the Home prompt: **Yes** opens the pantry update; **Not Yet** leaves it pending; **Archive** suppresses only the repeated reminder.
8. Relaunch after **Archive**. Verify the reminder stays hidden while the frozen completed trip remains intact and no pantry quantity, shopping outcome, or product preference changes.

Any automatic retailer action, inferred purchase, ambiguous close that advances, failed page that enables **Next Item**, or archive action that deletes trip data blocks beta promotion.

## Barcode matrix

Run the scanner on a supported physical iPhone and repeat the manual-entry portions in Simulator:

1. Scan a barcode already linked to pantry stock. Verify **Already in pantry** appears and adding another increments only that item.
2. Resolve a catalog barcode. Verify name and brand are prefilled but editable, and no price, availability, retailer, or verification claim appears.
3. Use a valid catalog miss. Verify **Product not found** requests a name, accepts an optional brand, and permits adding the item without a dead end.
4. Terminate and relaunch, then scan the manually named barcode again. Verify the saved pantry name resolves before any network lookup and is not requested again.
5. Stop or misconfigure the backend. Verify a valid barcode still reaches manual naming rather than an indefinite progress or error-only state.
6. Enter an invalid checksum and verify the validation explanation leaves entry and rescan available.
7. Hold one barcode in the camera frame and verify repeated detections do not restart lookup or increment stock.

Provider product identity is crowdsourced and editable. Any inferred price/availability, raw GTIN in backend logs, dead-end miss, lost manual mapping, or duplicate increment blocks beta promotion.

## Meal Prep matrix

Each tester should complete at least two plans using reviewed saved recipes:

1. One recipe with a changed serving count, proving Meal Prep converges into the same Recipe Ready flow as a single recipe.
2. Three to five recipes with at least one safe merge, one intentionally separate subtype, one incompatible measurement pair, and one partially covered pantry item.
3. Resolve every uncertain merge, then verify the plan enters Recipe Ready and uses the same exception-only matching and continuous Shopping Trip.
4. Terminate and relaunch during combined-ingredient review and during the Shopping Trip; verify the exact plan and waiting item restore.
5. Change a serving count after a trip exists and verify SmartCart starts a new compatible trip rather than resuming stale quantities.
6. Delete or edit a source recipe after starting a plan and verify the active trip retains its frozen title and ingredient provenance.
7. Complete pantry reconciliation twice and verify the second attempt cannot increment stock again.

Record incorrect merges, missed safe merges, pantry deduction errors, and any unclear source provenance. Any automatic cross-dimension merge or incompatible trip resume blocks beta promotion.

## Dynamic Type and VoiceOver

Run the core single-recipe and Meal Prep paths at the default size, an extra-extra-extra-large size, and at least one Accessibility size. Verify Recipe Ready rows and summaries, product-exception actions, the Shopping Trip bar and More menu, load-failure actions, and the Home reminder remain readable, scrollable, and reachable without clipped required controls.

With VoiceOver enabled, verify logical focus order; meaningful labels, values, traits, and hints; the “next issue” focus move; item position; **Pause** and **Next Item** meaning; disabled **Next Item** during loading/failure; and distinct **Yes**, **Not Yet**, and **Archive** actions. Retailer webpage accessibility is owned by the retailer, but SmartCart’s trip controls must remain operable.

## Metrics and decision thresholds

| Metric | Beta target | Stop/repair threshold |
| --- | ---: | ---: |
| Import success | at least 85% | below 75% |
| Median ingredients corrected | at most 20% | above 35% |
| Median time to first retailer page | under 4 minutes | over 7 minutes |
| Product replacement frequency | under 25% | over 40% |
| Shopping Trip completion | at least 70% | below 55% |
| Crash-free trips | at least 99% | any reproducible data-loss crash |

The thresholds are product hypotheses, not claims. Revisit them after the first ten tester trips.

## Privacy and evidence handling

The diagnostic funnel stays on device and excludes recipe text, URLs, addresses, emails, and UPC values. Testers should send screenshots or a structured feedback form voluntarily. Do not collect retailer credentials, payment details, health data, or precise location. Production telemetry requires a separate consent and privacy review.

## Exit gate

Advance beyond closed beta only after the import-to-pantry loop meets the targets, reconciliation never double-increments stock, the Dynamic Type and VoiceOver matrix passes, and every non-safety miss is documented and accepted. Silent purchasing errors, false pantry changes, inaccessible required actions, and data loss cannot be accepted as metric tradeoffs.
