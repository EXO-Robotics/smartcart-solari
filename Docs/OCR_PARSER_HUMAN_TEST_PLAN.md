# OCR and parser human validation run

This is the first hands-on acceptance run for SmartCart's critical path:

`import → Recipe Ready → Shopping Trip → optional pantry update`

It is intentionally small enough to finish with real devices before the larger
promotion corpus in `PHOTO_PARSER_RELEASE_GATES.md`. Passing this run permits a
closed human beta; it does not replace the public-release corpus.

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

## Before each run

1. Record the app build/commit, device model, iOS version, source class, and a
   non-identifying fixture ID.
2. Relaunch SmartCart. For migration cases, preserve the previous local state;
   for clean-install cases, delete the app first.
3. Do not record tester names, account identifiers, retailer credentials, full
   camera-roll paths, or Walmart page contents.
4. For URL tests, run the approved local backend and record only its fixture ID
   and result category.

## Per-recipe walkthrough

1. Import the recipe with the assigned method.
2. Verify the title and every extracted ingredient against the expected list.
3. For photo imports, open every review-required ingredient and verify the
   source crop, page, original OCR text, and alternatives.
4. Correct at least one OCR value. Confirm the corrected ingredient remains
   attached to the correct original evidence. If two source lines are equally
   plausible, SmartCart must not attach either one automatically.
5. Confirm that instruction text never becomes a grocery and that a failed
   import never manufactures fallback ingredients.
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
- pantry suggestion and override correctness;
- match constraint correctness;
- Shopping Trip completion;
- reconciliation outcome, selected count, substitution count, and idempotency;
- relaunch restoration result;
- crash, freeze, or material scroll hitch;
- short failure note with no personal data.

## Closed-beta acceptance gates

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
aggregate score.

## Device and accessibility spot checks

- Run at least five photo imports and all barcode substitutions on a physical
  iPhone; the Simulator cannot validate the camera scanner.
- Repeat one short and one complex recipe with the largest Dynamic Type size.
- Complete ingredient review and shopping reconciliation once with VoiceOver.
- Check light and dark mode, keyboard dismissal, long localized product names,
  and reduced motion.

## Exit artifact

Keep the completed receipt locally with the candidate commit SHA and a final
`PASS` or `BLOCKED` verdict. List every blocking fixture ID and assign it to OCR,
layout, parser, pantry, matching, retailer trip, persistence, or accessibility.
