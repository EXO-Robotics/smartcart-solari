# Closed beta validation plan

## Current verdict

**SmartCart closed-beta application gate: NO-GO. Do not recruit the cohort or
distribute this candidate yet.** The eligible authoritative-path tests pass,
but the required live Shopping/Home/Recipes, physical-iPhone, and VoiceOver
walkthroughs are not complete on one frozen candidate.

**Contextual-filter promotion gate: NO-GO.** The separately invoked frozen
held-out aggregate selector failed on the latest frozen code candidate with
exit 65. The contextual classifier remains a discarded `DEBUG` shadow
comparison, while the legacy `RecipeParser` path remains authoritative for app
output. This failed promotion gate must remain visible, but it does not veto the
closed-beta application gate while contextual output is non-authoritative.

**Public/App Store gate: NO-GO.** Partner, legal, production-service, broad
corpus, physical-device, and App Store requirements remain outside this
closed-beta application decision.

Before changing this verdict, freeze one candidate and record all of the
following against that same commit:

1. The eligible development suite passes with
   `SmartCartTests/ContextualIngredientFilterTests/testFrozenHeldOutCorpusDoesNotRegressAgainstLegacy`
   explicitly skipped.
2. The authoritative legacy OCR contamination regression and required human
   OCR cases pass while the contextual filter remains shadow-only.
3. Ingredient deletion and shared pantry reallocation pass, including
   persistence rollback and completed-trip immutability.
4. `OCR_PARSER_HUMAN_TEST_PLAN.md` passes, including its physical-iPhone and
   provenance checks.
5. The Home/Recipes, Shopping Trip, barcode, Meal Prep, Dynamic Type, and
   VoiceOver walkthroughs below pass.

Never report the eligible result as a complete-suite pass while the frozen
held-out selector is excluded. Run and report the held-out selector separately,
keep its receipts aggregate-only, and do not place held-out case content in beta
artifacts. A held-out failure blocks contextual-filter promotion, not the
shadow-only closed-beta application path.

## Cohort

After all prerequisites pass and the verdict changes to `GO`, recruit 20–50 testers who shop for groceries at least twice per month. Include a mix of iPhone models, Dynamic Type sizes, VoiceOver experience, household sizes, dietary preferences, and shopping styles. Do not promise live prices, retailer automation, account linkage, purchase detection, cart creation, or pickup reservations.

## Tester setup

1. Install the TestFlight build only after Apple review and a recorded closed-beta `GO` for the exact build.
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

## Ingredient deletion stabilization matrix

Before the Home/library walkthrough, exercise Recipe Ready with a recipe whose
ingredients have stable, known IDs:

1. Delete the first, a middle, the last, and the only ingredient through the
   destructive confirmation. The four interactions must not crash or address a
   shifted row.
2. Repeat a deletion request for the same ID through the model regression; it
   must be a no-op.
3. After deleting the only ingredient, verify the recipe remains empty and
   **Start Shopping** is disabled with the explicit explanation to include at
   least one ingredient that still needs purchasing.
4. Relaunch and verify the empty active draft remains coherent. If the retained
   record is not a Saved Recipes member, verify deletion synchronizes its
   retained working record without silently restoring Saved Recipes membership.
5. Verify pantry state and unchanged editable pre-trip matches survive, only
   affected matches and purchase quantities refresh, and any in-flight stale
   match is rejected. With duplicate ingredients competing for finite pantry
   inventory, deleting the allocated row must release and deterministically
   reassign safe stock; deleting an unallocated row must not disturb a valid
   allocation. `buyFull` must survive, stale `useAvailable` must become
   `review`, and possible/name-only matches must remain opt-in.
6. Repeat against a recipe with a committed Shopping Trip. The session,
   manifest, outcomes, pantry, and product preferences must remain immutable.

## Home and Recipes stabilization matrix

This stabilization work does not change the established Recipe Ready,
product-exception, continuous Safari Shopping Trip, or user-confirmed pantry
update. Validate these Home and library changes before replaying the frozen
shopping-flow matrix below:

1. Verify **Start New Recipe** is visible immediately and Home rendered order
   is: header; **Start New Recipe**; one conditional
   **Shopping Trips** section; optional **Shop Again**; preferred store; and the
   checkout trust strip. Record order, not an unsupported claim that every
   control fits in the first viewport.
2. At standard Dynamic Type, verify compact, equal-height two-column rows for
   **Take Photo**/**Choose Photo** and **Paste Link**/**More**. At an
   Accessibility size, verify those four actions stack vertically. In both
   modes, **Meal Prep Mode** remains a full-width action below them.
3. With zero, one, and multiple pending trips, verify Home renders zero or one
   **Shopping Trips** section, never separate primary and secondary trip
   sections. Every pending trip must remain reachable.
4. Verify the primary Recipes library shows only Saved Recipes membership, with
   title/ingredient search and the pull-up **Recent Recipes** drawer. The drawer
   may show a retained unsaved recipe after an intentional **Shop Again** open.
   A fresh install must contain no tester recipes. The bundled eight-recipe
   **Weekly Meals** collection remains the only preloaded recipe discovery surface.
5. Import a new non-sample recipe, verify it is saved by default, and complete
   a Shopping Trip so **Shop Again** remains a reachable historical route.
   Remove it from Saved Recipes, relaunch, and verify its retained recipe
   record, Shopping Trips, pantry, preferences, product preferences, and frozen Meal Prep
   provenance remain intact while its Recent Recipes entry is removed. Verify
   it stays absent from Saved Recipes and Meal Prep selection.
6. Reopen the retained unsaved recipe through Home's **Shop Again**, edit it,
   and verify it remains unsaved until the tester explicitly chooses
   **Save Recipe**.
7. Verify importing or intentionally opening a whole recipe updates Recent
   Recipes. Retailer-page navigation, Shopping Trip resume, replacement,
   pantry reconciliation, **Next Item**, **Pause**, and archive actions must
   not create or reorder recipe-recency events.

## Shopping Trip and reminder matrix

Run the following as one continuous frozen trip for Walmart and repeat every
retailer-applicable step for Target. Begin from an imported/reviewed recipe,
resolve only genuine product exceptions, start the Safari Shopping Trip, and
preserve the same trip identity through pause, relaunch, completion, and pantry
review:

1. After a successful retailer-page load, tap **Next Item**. Verify the next product opens in the same Safari trip and the prior item is recorded as `visited` only.
2. Verify `visited` does not claim saved-to-list, cart, order, checkout, or purchase knowledge. It may be selected by default in the later pantry check-in, but the tester must still confirm what was bought.
3. Tap **Pause** and verify the current waiting item resumes after relaunch without advancing.
4. Use Safari’s native close control or dismiss the sheet. Verify the result is the same safe pause at the current item.
5. Force a retailer-page load failure. **Next Item** must remain unavailable, the item must remain waiting, and retry, external open, skip, and pause must remain reachable.
6. Report unavailable, skip an item, and choose a safe replacement. Verify each explicit action advances or refreshes only the intended item.
7. Complete a trip and return Home. Verify one pantry-update-pending card appears inside the **Shopping Trips** section. Open that card, then exercise the completion surface: **Yes, update pantry** opens review; **Not yet** leaves the update pending; **Archive without pantry update** suppresses only the pending reminder/card.
8. Relaunch after **Archive without pantry update**. Verify the pending reminder/card stays hidden while the frozen completed trip remains intact and no pantry quantity, shopping outcome, or product preference changes.

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
6. Remove a source recipe from Saved Recipes or edit it after starting a plan and verify the active trip retains its frozen title and ingredient provenance.
7. Complete pantry reconciliation twice and verify the second attempt cannot increment stock again.

Record incorrect merges, missed safe merges, pantry deduction errors, and any unclear source provenance. Any automatic cross-dimension merge or incompatible trip resume blocks beta promotion.

## Dynamic Type and VoiceOver

Run the core single-recipe and Meal Prep paths at the default size, an extra-extra-extra-large size, and at least one Accessibility size. Verify Home's grouped import actions and single Shopping Trips section, Recipe Ready rows and summaries, product-exception actions, the Shopping Trip bar and More menu, load-failure actions, and the pantry-update-pending Home card remain readable, scrollable, and reachable without clipped required controls.

With VoiceOver enabled, verify logical focus order; meaningful labels, values, traits, and hints; the “next issue” focus move; item position; **Pause** and **Next Item** meaning; disabled **Next Item** during loading/failure; and distinct **Yes, update pantry**, **Not yet**, and **Archive without pantry update** actions on the completion surface. Retailer webpage accessibility is owned by the retailer, but SmartCart’s trip controls must remain operable.

## Metrics and decision thresholds

| Metric | Beta target | Stop/repair threshold |
| --- | ---: | ---: |
| Import success | at least 85% | below 75% |
| Median ingredients corrected | at most 20% | above 35% |
| Median time to first retailer page | under 4 minutes | over 7 minutes |
| Product replacement frequency | under 25% | over 40% |
| Shopping Trip completion | at least 70% | below 55% |
| Crash-free trips | at least 99% | any reproducible data-loss crash |

The thresholds are product hypotheses, not claims. They cannot override a
failed authoritative-path safety check or a failed physical/accessibility
walkthrough. They also cannot promote the contextual filter past its separately
failed frozen held-out gate.
Revisit them after the first ten tester trips only after the candidate has a recorded
`GO`.

## Privacy and evidence handling

The diagnostic funnel stays on device and excludes recipe text, URLs, addresses, emails, and UPC values. Testers should send screenshots or a structured feedback form voluntarily. Do not collect retailer credentials, payment details, health data, or precise location. Production telemetry requires a separate consent and privacy review.

## Exit gate

Enter or advance beyond closed beta only after the eligible authoritative-path
suite, legacy OCR contamination regression, deletion/pantry reallocation, and
required human/physical walkthrough pass on the same candidate; the
import-to-pantry loop meets the targets; reconciliation never double-increments
stock; the Home/Recipes and Dynamic Type/VoiceOver matrices pass; and every
non-safety miss is documented and accepted. Silent purchasing errors, false
pantry changes, inaccessible required actions, and data loss cannot be accepted
as metric tradeoffs. The contextual promotion verdict remains independently
`NO-GO` until its frozen held-out selector and other promotion gates pass. The
current closed-beta application verdict also remains `NO-GO` because its live,
physical-device, and accessibility evidence is incomplete.
