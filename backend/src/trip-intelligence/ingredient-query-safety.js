const unsafeGlyphPattern = /(?:�|\?{2,})/u;
const malformedLeadingSymbolPattern = /^%/u;
const malformedFractionPattern = /^\d+\|\d+(?:\s|$)/u;
const measurementPrefixPattern = /^(?:(?:\d+(?:\.\d+)?|\d+[\/\u2044]\d+|[\u00BC-\u00BE\u2150-\u215E])\s+|(?:[iIl|])\s+(?=(?:cups?|tbsp|tsp|oz|lbs?|grams?|kg|ml|liters?)\b)|(?:cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|kg|kilograms?|ml|milliliters?|liters?|fl\s+oz|packages?|cans?|cloves?|pieces?|slices?|stalks?|sticks?|bunches?|heads?|sprigs?|scoops?|pinches?|jars?|containers?|cartons?)\b)/iu;
const embeddedMeasurementPattern = /(?:^|\s)(?:\d+(?:\.\d+)?|\d+[\/\u2044]\d+|[\u00BC-\u00BE\u2150-\u215E])\s+(?:cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|kg|kilograms?|ml|milliliters?|liters?|fl\s+oz|packages?|cans?|cloves?|pieces?|slices?|stalks?|sticks?|bunches?|heads?|sprigs?|scoops?|pinches?|jars?|containers?|cartons?)\b/iu;
const embeddedCountPattern = /(?:^|\s)(?:\d+(?:\.\d+)?|\d+[\/\u2044]\d+|[\u00BC-\u00BE\u2150-\u215E])\s+\p{L}/u;
const trailingCountPattern = /\s(?:\d+(?:\.\d+)?|\d+[\/\u2044]\d+|[\u00BC-\u00BE\u2150-\u215E])$/u;
const orphanConnectorPattern = /^(?:and|or|with|plus|then)\b/iu;
const headingFragmentPattern = /^(?:for\s+(?:the\s+)?|to\s+(?:make|prepare)\b)/iu;
const colonSectionHeadingPattern = /^(?:sauce|marinade|dough|topping|filling|glaze|assembly|optional|garnish)\s*:$/iu;
const uppercaseSectionHeadingPattern = /^(?:SAUCE|MARINADE|DOUGH|TOPPING|FILLING|GLAZE|ASSEMBLY|OPTIONAL|GARNISH)$/u;
const numberedInstructionPattern = /^\d+[.)]\s+\p{L}/u;
const instructionFragmentPattern = /^(?:set\s+aside|season(?:\s+with\b|$)|until\b|fold\s+in\b|transfer\s+to\b)/iu;
const unresolvedAlternativePattern = /\b(?:or|and\/or)\b/iu;
const preparationOnlyPattern = /^(?:preferably(?:\s+.+)?|(?:(?:very|finely|coarsely|roughly|thinly|freshly)\s+)?(?:chopped|diced|grated|sliced|minced|melted|softened|packed|shredded|flaked|divided)|drained(?:\s+and\s+rinsed)?|rinsed|for\s+(?:frying|garnish|serving)|to\s+taste|as\s+needed)$/iu;

const prefixPreparations = [
  'tightly packed',
  'loosely packed',
  'finely grated',
  'freshly grated',
  'coarsely grated',
  'finely chopped',
  'coarsely chopped',
  'roughly chopped',
  'thinly sliced',
  'packed',
  'grated',
  'chopped',
  'diced',
  'sliced',
  'minced'
];

const suffixPreparations = [
  'drained and rinsed',
  'coarsely chopped',
  'roughly chopped',
  'finely chopped',
  'freshly grated',
  'finely grated',
  'coarsely grated',
  'thinly sliced',
  'at room temperature',
  'plus more to taste',
  'for garnish',
  'for serving',
  'melted',
  'softened',
  'chopped',
  'diced',
  'sliced',
  'minced',
  'grated',
  'divided',
  'drained',
  'rinsed'
];

function unsafe(code, message) {
  return { safe: false, canonicalName: null, preparation: '', code, message };
}

function isSectionHeading(value) {
  return colonSectionHeadingPattern.test(value)
    || uppercaseSectionHeadingPattern.test(value)
    || /^garnish$/iu.test(value);
}

/**
 * Produces only a retailer-safe ingredient name. This intentionally strips
 * cooking/measurement preparation while retaining product-defining modifiers
 * such as "unsalted", "boneless skinless", "fresh", and "reduced-sodium".
 */
export function inspectIngredientQueryName(value) {
  let candidate = value.normalize('NFKC').trim().replace(/[.;]+$/u, '');
  if (candidate.length === 0 || !/[\p{L}\p{N}]/u.test(candidate)) {
    return unsafe('ingredient_structure_unresolved', 'A credible ingredient name is required before shopping.');
  }
  if (
    malformedLeadingSymbolPattern.test(candidate)
    || malformedFractionPattern.test(candidate)
    || unsafeGlyphPattern.test(candidate)
    || measurementPrefixPattern.test(candidate)
    || embeddedMeasurementPattern.test(candidate)
    || embeddedCountPattern.test(candidate)
    || trailingCountPattern.test(candidate)
  ) {
    return unsafe(
      'ingredient_measurement_conflict',
      'Measurement text remained inside the ingredient name and must be reviewed before shopping.'
    );
  }
  if (orphanConnectorPattern.test(candidate)) {
    return unsafe(
      'ingredient_orphan_continuation',
      'This line appears to continue another ingredient and cannot become a retailer query.'
    );
  }
  if (numberedInstructionPattern.test(candidate)) {
    return unsafe(
      'ingredient_instruction_fragment',
      'Instruction text cannot become a retailer query.'
    );
  }
  if (instructionFragmentPattern.test(candidate)) {
    return unsafe(
      'ingredient_instruction_fragment',
      'Instruction text cannot become a retailer query.'
    );
  }
  if (unresolvedAlternativePattern.test(candidate)) {
    return unsafe(
      'ingredient_alternative_unresolved',
      'Choose one ingredient alternative before shopping.'
    );
  }
  if (preparationOnlyPattern.test(candidate)) {
    return unsafe(
      'ingredient_preparation_fragment',
      'Preparation-only text cannot become a retailer query.'
    );
  }
  if (headingFragmentPattern.test(candidate)) {
    return unsafe(
      'ingredient_heading_fragment',
      'A recipe subsection heading cannot become a retailer query.'
    );
  }
  if (isSectionHeading(candidate)) {
    return unsafe(
      'ingredient_heading_fragment',
      'A recipe subsection heading cannot become a retailer query.'
    );
  }

  let preparation = '';
  const lower = candidate.toLocaleLowerCase('en-US');
  for (const prefix of prefixPreparations) {
    if (lower.startsWith(`${prefix} `)) {
      preparation = prefix;
      candidate = candidate.slice(prefix.length).trim();
      break;
    }
  }

  let commaIndex = candidate.lastIndexOf(',');
  while (commaIndex >= 0) {
    const suffix = candidate.slice(commaIndex + 1).trim().toLocaleLowerCase('en-US');
    const recognized = suffixPreparations.find((entry) => entry === suffix);
    if (!recognized) {
      return unsafe(
        'ingredient_parse_conflict',
        'Unresolved text after the ingredient name must be reviewed before shopping.'
      );
    }
    preparation = [preparation, recognized].filter(Boolean).join(', ');
    candidate = candidate.slice(0, commaIndex).trim();
    commaIndex = candidate.lastIndexOf(',');
  }

  if (
    candidate.length === 0
    || !/[\p{L}\p{N}]/u.test(candidate)
    || malformedLeadingSymbolPattern.test(candidate)
    || malformedFractionPattern.test(candidate)
    || unsafeGlyphPattern.test(candidate)
    || measurementPrefixPattern.test(candidate)
    || embeddedMeasurementPattern.test(candidate)
    || embeddedCountPattern.test(candidate)
    || trailingCountPattern.test(candidate)
    || orphanConnectorPattern.test(candidate)
    || headingFragmentPattern.test(candidate)
    || isSectionHeading(candidate)
    || numberedInstructionPattern.test(candidate)
    || instructionFragmentPattern.test(candidate)
    || unresolvedAlternativePattern.test(candidate)
    || preparationOnlyPattern.test(candidate)
  ) {
    return unsafe(
      'ingredient_identity_unsafe',
      'The ingredient line could not produce a safe retailer query.'
    );
  }

  return { safe: true, canonicalName: candidate, preparation, code: null, message: null };
}

export function inspectIngredientPreparation(value) {
  const preparation = value.normalize('NFKC').trim();
  if (preparation.length === 0) return { safe: true, code: null, message: null };
  if (
    malformedLeadingSymbolPattern.test(preparation)
    || unsafeGlyphPattern.test(preparation)
    || measurementPrefixPattern.test(preparation)
  ) {
    return unsafe(
      'ingredient_measurement_conflict',
      'Measurement text cannot be stored as ingredient preparation.'
    );
  }
  if (orphanConnectorPattern.test(preparation)) {
    return unsafe(
      'ingredient_orphan_continuation',
      'Preparation appears to be an unresolved continuation.'
    );
  }
  if (unresolvedAlternativePattern.test(preparation)) {
    return unsafe(
      'ingredient_alternative_unresolved',
      'Choose one preparation alternative before shopping.'
    );
  }
  return { safe: true, code: null, message: null };
}
