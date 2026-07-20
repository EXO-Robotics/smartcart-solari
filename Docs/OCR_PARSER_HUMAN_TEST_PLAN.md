# OCR and parser human validation run

This is the first hands-on acceptance run for SmartCart's critical path:

`import → Recipe Ready → Shopping Trip → optional pantry update`

It is intentionally small enough to finish with real devices before the larger
promotion corpus in `PHOTO_PARSER_RELEASE_GATES.md`. Passing this run is
necessary but does not by itself permit a closed human beta. The eligible
development suite, the separately invoked frozen held-out aggregate gate, this
human
walkthrough, and the physical-device/accessibility checks must all pass on the
same candidate before a `GO`.

## Current candidate status

**Closed-beta verdict: NO-GO.** The development-focused gates are green, but
the frozen held-out aggregate selector failed on the latest frozen code
candidate with exit 65. Case-level output remains suppressed. The contextual
classifier remains a `DEBUG` shadow comparison; the legacy `RecipeParser` path is still the
authoritative app parser, and contextual classification is not a production
default.

## Automated evidence boundary

There are 144 oracle-labeled document cases in total:

- a fixed 120-document core corpus with separate development and frozen
  held-out subsets; and
- a separate 24-document independent spatial development expansion.

Do not describe those as one 144-case held-out corpus. Run the normal eligible
suite while explicitly excluding the frozen held-out selector:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skip-testing:SmartCartTests/ContextualIngredientFilterTests/testFrozenHeldOutCorpusDoesNotRegressAgainstLegacy
```

Then invoke the frozen held-out aggregate gate separately against the same
commit and build configuration:

```sh
xcodebuild test \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SmartCartTests/ContextualIngredientFilterTests/testFrozenHeldOutCorpusDoesNotRegressAgainstLegacy
```

Keep that receipt aggregate-only: candidate SHA, command, timestamp, exit
status, and `PASS` or `FAIL`. The corpus is source-visible but held out by
process: freeze the candidate before invoking it and do not tune against its
case-level results. Do not copy held-out case text or diagnostics into this
plan. The 25 recipes below are an independent human run, not a substitute for
either automated invocation.

## OCR text and provenance vocabulary

- **Raw observations** are the immutable Vision candidates: original text,
  page index, normalized bounding box, OCR confidence, alternatives, and source
  observation ID.
- **Reconstructed text** is the geometry-ordered ingredient stream assembled
  from those observations. Reconstructed source lines also retain column,
  continuation, union geometry, source IDs, and reconstruction confidence.
- **Layout-filtered lines** are reconstructed ingredient lines after layout and
  instruction-region exclusion. They are not yet parser-sanitized text.
- **Sanitized/accepted ingredient text** is the later authoritative
  `RecipeParser` result used to construct ingredients; any proven removed
  instruction suffix remains attached to source evidence for review.
- **Ignored source lines** are OCR/layout lines excluded before parsing. They
  are distinct from contextual-classifier ignored decisions, which exist only
  in the discarded development shadow report.

## Test inventory

Use 25 recipes that the tester is legally allowed to photograph or access.
Keep the expected ingredient list in a separate local receipt.

| Class | Count | Required variation |
| --- | ---: | --- |
| Clean screenshots | 5 | One-column, two-column, bullets, compact units, ranges |
| Cookbook/card photos | 5 | Angled page, shadows, glossy page, low contrast, two columns |
| Recipe URLs | 4 | JSON-LD, visible-page fallback, repeated section ingredients, unsupported/blocked page |
| Short pasted recipes | 3 | Quantityless items, optional item, alternatives |
| Complex recipes | 4 | 15+ ingredients, sections, package sizes, mixed fractions, compound quantities |
| Pantry-heavy recipes | 2 | Full and partial pantry coverage with buy-full override |
| Preference edge cases | 2 | Organic-only miss and dietary-filter miss |

At least five recipes must contain a purchasing-critical ambiguity such as
`1/2` versus `12`, `1O` versus `10`, a range, or an uncertain unit.

## Required blocker and compatibility fixtures

In addition to the 25-recipe inventory, run these named acceptance checks:

1. Import a geometry-equivalent photo with `Flaky Sea Salt` on the ingredient
   side, horizontally distant `Sourdough Discard & Vanilla`, the aligned prose
   `EASY AS 1-2-3! Mash banana. Stir in peanut butter`, and a `for topping`
   continuation. Only `Flaky Sea Salt` may be retained. Quantity/preparation
   must be correct or explicitly marked **Review**; the distant title and
   instruction prose must not enter the ingredient or preparation.
2. Open **View Source Text** and the ingredient's **Source evidence**. Confirm
   the full unmodified OCR text remains reachable even though only the safe
   ingredient is admitted.
3. Import the repository's two-column and chocolate-chip photo fixtures, then
   a real multi-page recipe. Verify reading order, column boundaries,
   continuations, and the instruction stop boundary.
4. Exercise a structured recipe URL, a pasted ingredient list, hyphenated
   ingredient names, quantity ranges, and known preparation clauses. Verify
   punctuation and safe preparation text survive without admitting method
   prose.

## Before each run

1. Record the app build/commit, device model, iOS version, source class, and a
   non-identifying fixture ID.
2. Relaunch SmartCart. For migration cases, preserve the previous local state;
   for clean-install cases, delete the app first.
3. Do not record tester names, account identifiers, retailer credentials, full
   camera-roll paths, or retailer page contents.
4. For URL tests, run the approved local backend and record only its fixture ID
   and result category.

## Per-recipe walkthrough

1. Import the recipe with the assigned method.
2. Verify the title and every extracted ingredient against the expected list.
3. For photo imports, open every review-required ingredient in Recipe Ready and
   verify the source crop, original OCR text, visible parser/normalization/layout
   confidences, and credible alternatives. For repository fixtures, use the
   automated provenance regressions to separately verify page, normalized
   source box, source-observation IDs, column/continuation metadata,
   reconstruction confidence, reconstructed line, layout-filtered line,
   parser-sanitized ingredient, and ignored-line fields. For a human photo,
   mark those fields `not manually inspected` unless a privacy-reviewed Debug
   probe was used. They are not all rendered in the shipping Recipe Ready
   disclosure and must not be described as though they are.
4. Correct at least one OCR value. Confirm the corrected ingredient remains
   attached to the correct original evidence. If two source lines are equally
   plausible, SmartCart must not attach either one automatically.
5. Confirm that instruction text never becomes a grocery, including text from
   an adjacent column or disconnected card region, and that a failed import
   never manufactures fallback ingredients. If a proven instruction suffix is
   removed from an otherwise valid ingredient, verify the original line and
   removal reason remain reviewable.
6. Adjust servings and verify range/package quantities remain understandable.
7. Review pantry suggestions. Test `use available`, `buy remainder`, and
   `buy full`; no suggestion may silently remove a purchase.
8. Apply the assigned shopping preferences. An unsatisfied organic or dietary
   constraint must remain visible instead of silently selecting a conflicting
   product.
9. Complete the continuous Walmart Shopping Trip. Walmart sign-in, list changes,
   prices, availability, checkout, and pickup remain retailer-controlled.
10. Choose one shopping outcome:
    - Bought all available items: confirm once, or select an unavailable/skipped
      item if it was bought elsewhere or substituted.
    - Bought most: tap only items not bought.
    - Bought only a few: tap only items bought.
    - Did not shop: verify no pantry quantity changes.
11. On five runs, record a substitution by matched alternative or barcode. The
    preferred-product rule may change only when `Prefer this product next time`
    is explicitly enabled.
12. Force-quit and relaunch. Verify the recipe, review choices, shopping list,
    Shopping Trip, substitution, and pantry quantities restore exactly.
13. Repeat the pantry-update confirmation once. Quantities must not increment a
    second time.

## Receipt fields

Record one local row per recipe:

- fixture ID and source class;
- expected and extracted ingredient counts;
- ingredient recall;
- exact quantity-and-unit count;
- instruction false positives;
- invented ingredients;
- review-required purchasing ambiguities and whether each blocked matching;
- number of user name, quantity, and unit corrections;
- crop/evidence correctness;
- raw-observation, reconstructed-line, layout-filtered-line, parser-sanitized,
  and ignored-line agreement;
- page/box, column, source-observation ID, continuation, and reconstruction
  provenance correctness;
- pantry suggestion and override correctness;
- match constraint correctness;
- Shopping Trip completion;
- reconciliation outcome, selected count, substitution count, and idempotency;
- relaunch restoration result;
- crash, freeze, or material scroll hitch;
- short failure note with no personal data.

For provenance fields not rendered in Recipe Ready, cite the fixed-fixture
automated receipt or record `not manually inspected`; do not infer them from the
visible crop.

## Closed-beta acceptance gates

Automated prerequisites on the exact candidate:

- eligible development suite: `PASS`, with the frozen held-out selector explicitly
  skipped;
- separate frozen held-out aggregate selector: `PASS`; and
- no report may flatten those two results into a single suite status.

- Ingredient-line recall: at least 97% overall and at least 93% in every class.
- Exact quantity and unit: at least 95% overall.
- Invented ingredients: zero.
- Silent purchasing-critical errors: zero.
- Purchasing-critical ambiguities blocked for confirmation: 100%.
- Instruction false-positive rate: at most 1%, with no admitted line allowed to
  reach product matching.
- Median corrections: at most one ingredient per recipe; 90th percentile: at
  most three.
- Import crashes or freezes: zero of 25.
- Pantry false auto-removals: zero; buy-full override succeeds in every case.
- Organic/dietary constraint violations selected as valid matches: zero.
- Reconciliation double increments after retry/relaunch: zero.
- Saved-flow restoration: 25 of 25.

Any silent quantity error, invented item, false pantry removal, conflicting
dietary match, or duplicate pantry commit blocks the beta regardless of the
aggregate score. A frozen-held-out-gate failure also blocks the beta regardless of green
development or human metrics.

## Device and accessibility spot checks

- Run at least five photo imports and all barcode substitutions on a physical
  iPhone; the Simulator cannot validate the camera scanner.
- Repeat one short and one complex recipe with the largest Dynamic Type size.
- Complete ingredient review and shopping reconciliation once with VoiceOver.
- Check light and dark mode, keyboard dismissal, long localized product names,
  and reduced motion.

## Exit artifact

Keep the completed receipt locally with the candidate commit SHA, separate
eligible-suite and frozen-held-out-gate statuses, physical-device/accessibility results,
and a final `GO` or `NO-GO` verdict. List human-run blocking fixture IDs and
assign them to OCR, layout, parser, pantry, matching, retailer trip,
persistence, or accessibility. Keep held-out case IDs and content out of this
artifact. A `GO` is prohibited until both automated invocations and the human
and physical walkthrough pass on the same candidate; the current verdict is
`NO-GO`.
