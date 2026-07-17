# Photo parser validation gates

SmartCart treats photo parsing as a purchasing-safety feature. A failed or
ambiguous parse must remain recoverable, and it must never manufacture a
plausible grocery item.

## Automated safety invariants

- Empty, instruction-only, or unreadable imports produce zero ingredients.
- Product matching cannot continue while an alternate OCR interpretation
  materially changes a quantity or unit.
- Every photo-derived ingredient retains its page index, normalized source
  box, OCR confidence, and credible purchasing-critical OCR alternatives.
- Source crops are generated locally for ingredient review. They are stored
  only in SmartCart's local persisted recipe state.
- A spanning instruction heading stops ingredient extraction across the page,
  not only inside the column that happened to receive the heading.
- OCR retries remain in accurate mode and use an orientation-normalized,
  grayscale contrast variant with a lower minimum text height.
- Vision's custom vocabulary is bounded to 96 cooking, recipe-title, and
  confirmed-pantry terms.

## Corpus receipt format

Each fixture or tester replay should record:

- source type and quality class;
- expected ingredient lines;
- expected quantity and unit for each line;
- Vision, layout, parser, and normalization confidence;
- final assigned confidence status;
- whether an instruction was admitted;
- whether the user corrected the ingredient, quantity, or unit;
- whether the import remained recoverable.

Never store tester names, account identifiers, retailer credentials, or full
camera-roll paths in corpus receipts.

## Promotion thresholds

### Clean screenshots

- Ingredient-line recall: at least 98%
- Quantity/unit exact match: at least 96%
- Wrong high-confidence ingredients: below 0.5%
- Instruction lines admitted: zero
- Invented ingredients: zero

### Normal physical recipe photos

- Import success: at least 90%
- Ingredient-line recall: at least 95%
- Quantity/unit exact match: at least 90%
- Wrong high-confidence ingredients: below 1%
- Every ambiguous quantity must expose source evidence and block matching

### Poor photos and handwriting

Automatic accuracy is not a promotion gate. Complete recovery is: the user
must be able to retry, replace the image, edit recognized text, or enter the
ingredient manually without SmartCart silently continuing.

## Human validation still required

- Replay at least 50 screenshots, 25 two-column cards, 25 cookbook photos,
  25 angled or low-quality photos, 15 handwritten/assisted imports, and 10
  multi-page recipes.
- Verify crop alignment and contrast on small iPhones, large iPhones, and with
  Dynamic Type and VoiceOver.
- Replay failed examples on a physical iPhone camera.
- Configure an HTTPS or reachable LAN recipe backend before testing URL import
  on a physical phone; `localhost` on the phone does not refer to the Mac.

Public release remains blocked until the measured corpus meets the applicable
thresholds. Passing unit tests alone does not satisfy this gate.
