import { createHash } from 'node:crypto';

const stopHeading = /^(instructions?|directions?|method|steps?|preparation|nutrition|notes?)\s*:?$/i;
const ingredientHeading = /^ingredients?\s*:?$/i;
const unsafeMeasurementPrefix = /^(?:%|�|\?{2,}|(?:cups?|tbsp|tsp|oz|lbs?|grams?|kg|ml|liters?)\b)/iu;
const instructionStart = /^(?:add|bake|beat|blend|bring|combine|cook|cover|drain|heat|mix|place|preheat|reduce|remove|serve|stir|whisk)\b/iu;
const units = [
  'fluid ounces?', 'fl oz', 'tablespoons?', 'tbsp', 'teaspoons?', 'tsp',
  'kilograms?', 'kg', 'grams?', 'g', 'pounds?', 'lbs?', 'ounces?', 'oz',
  'milliliters?', 'ml', 'liters?', 'l', 'cups?', 'packages?', 'cans?', 'cloves?',
  'pieces?', 'slices?', 'large', 'medium', 'small'
];
const unitPattern = new RegExp(`^(${units.join('|')})\\.?\\b\\s*`, 'iu');
const fractionGlyphs = new Map([
  ['¼', 0.25], ['½', 0.5], ['¾', 0.75], ['⅓', 1 / 3], ['⅔', 2 / 3],
  ['⅛', 0.125], ['⅜', 0.375], ['⅝', 0.625], ['⅞', 0.875]
]);
const prefixPreparations = [
  ['finely grated', 'finely grated'],
  ['freshly grated', 'freshly grated'],
  ['grated', 'grated'],
  ['finely chopped', 'finely chopped'],
  ['chopped', 'chopped'],
  ['diced', 'diced'],
  ['thinly sliced', 'thinly sliced'],
  ['sliced', 'sliced'],
  ['minced', 'minced']
];

function stableUuid(seed) {
  const bytes = createHash('sha256').update(seed).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function numericToken(token) {
  if (fractionGlyphs.has(token)) return fractionGlyphs.get(token);
  const mixedGlyph = /^(\d+)([¼½¾⅓⅔⅛⅜⅝⅞])$/u.exec(token);
  if (mixedGlyph) return Number(mixedGlyph[1]) + fractionGlyphs.get(mixedGlyph[2]);
  const fraction = /^(\d+)\/(\d+)$/u.exec(token);
  if (fraction && Number(fraction[2]) !== 0) return Number(fraction[1]) / Number(fraction[2]);
  return /^\d+(?:\.\d+)?$/u.test(token) ? Number(token) : null;
}

function parseLeadingQuantity(value) {
  let remaining = value.trim();
  const firstMatch = /^(\S+)\s*/u.exec(remaining);
  if (!firstMatch) return { quantity: null, remaining };
  let preferred = numericToken(firstMatch[1]);
  if (preferred === null) return { quantity: null, remaining };
  remaining = remaining.slice(firstMatch[0].length);

  const mixed = /^(\d+\/\d+|[¼½¾⅓⅔⅛⅜⅝⅞])\s*/u.exec(remaining);
  if (mixed) {
    const part = numericToken(mixed[1]);
    if (part !== null) {
      preferred += part;
      remaining = remaining.slice(mixed[0].length);
    }
  }

  let minimumValue = null;
  const range = /^(?:-|–|to)\s*(\d+(?:\.\d+)?|\d+\/\d+|[¼½¾⅓⅔⅛⅜⅝⅞])\s*/iu.exec(remaining);
  if (range) {
    const end = numericToken(range[1]);
    if (end !== null) {
      minimumValue = Math.min(preferred, end);
      preferred = Math.max(preferred, end);
      remaining = remaining.slice(range[0].length);
    }
  }

  const unitMatch = unitPattern.exec(remaining);
  const unit = unitMatch ? unitMatch[1] : '';
  if (unitMatch) remaining = remaining.slice(unitMatch[0].length);
  return {
    quantity: {
      kind: 'numeric',
      value: preferred,
      minimumValue,
      unit
    },
    remaining
  };
}

function semanticQuantity(value) {
  const match = /(?:,?\s+)(as needed|to taste|for frying)\s*$/iu.exec(value);
  if (!match) return null;
  return {
    remaining: value.slice(0, match.index).trim(),
    quantity: { kind: 'semantic', text: match[1].toLocaleLowerCase('en-US') }
  };
}

function separatePreparation(value) {
  const trimmed = value.trim().replace(/[.;]+$/u, '');
  const comma = /^(.+?),\s*(finely grated|freshly grated|grated|finely chopped|chopped|diced|thinly sliced|sliced|minced)(?:,.*)?$/iu.exec(trimmed);
  if (comma) return { name: comma[1].trim(), preparation: comma[2].trim() };
  const lower = trimmed.toLocaleLowerCase('en-US');
  for (const [prefix, preparation] of prefixPreparations) {
    if (lower.startsWith(`${prefix} `)) {
      return { name: trimmed.slice(prefix.length).trim(), preparation };
    }
  }
  return { name: trimmed, preparation: '' };
}

function issue(line, index, code, message, severity = 'review') {
  return {
    code,
    severity,
    message,
    field: `recipeText.line.${index + 1}`,
    evidenceIds: [`source-line-${index + 1}`]
  };
}

export class RecipeTextAnalyzer {
  constructor({ resolverVersion = 'recipe-text-v1' } = {}) {
    this.resolverVersion = resolverVersion;
  }

  analyze({ recipeId, title, servings, recipeText }) {
    const ingredients = [];
    const evidence = [];
    const issues = [];
    const lines = recipeText.split(/\r?\n/u);
    let reachedInstructions = false;

    for (const [index, sourceLine] of lines.entries()) {
      let line = sourceLine.trim().replace(/^[•*\-–—]+\s*/u, '').trim();
      if (line.length === 0) continue;
      const evidenceId = `source-line-${index + 1}`;
      evidence.push({
        evidenceId,
        kind: 'sourceText',
        sourceName: 'User-provided recipe text',
        sourceVersion: this.resolverVersion,
        sourceRecordId: null,
        description: sourceLine
      });
      if (ingredientHeading.test(line)) continue;
      if (stopHeading.test(line)) {
        reachedInstructions = true;
        continue;
      }
      if (reachedInstructions) continue;
      if (instructionStart.test(line)) {
        issues.push(issue(line, index, 'instruction_line_ignored', 'Instruction-like text was not treated as an ingredient.', 'informational'));
        continue;
      }

      const semantic = semanticQuantity(line);
      let quantity;
      if (semantic) {
        line = semantic.remaining;
        quantity = semantic.quantity;
      } else {
        const parsed = parseLeadingQuantity(line);
        line = parsed.remaining;
        quantity = parsed.quantity;
      }

      const { name, preparation } = separatePreparation(line);
      if (name.length === 0 || unsafeMeasurementPrefix.test(name) || !/[\p{L}\p{N}]/u.test(name)) {
        issues.push(issue(
          sourceLine,
          index,
          'ingredient_structure_unresolved',
          'This line could not produce a safe ingredient identity.',
          'blocking'
        ));
        continue;
      }
      ingredients.push({
        ingredientId: stableUuid(`${recipeId}:${index}:${sourceLine}`),
        sourceText: sourceLine,
        name,
        preparation,
        quantity,
        includedInRecipe: true,
        includeInTrip: true,
        brandPreference: null,
        evidence: [{
          evidenceId,
          kind: 'sourceText',
          sourceName: 'User-provided recipe text',
          sourceVersion: this.resolverVersion,
          sourceRecordId: null,
          description: 'Original recipe line retained verbatim.'
        }]
      });
    }

    if (ingredients.length === 0) {
      issues.push({
        code: 'no_ingredients_detected',
        severity: 'blocking',
        message: 'No safe ingredient lines were detected.',
        field: 'recipeText',
        evidenceIds: []
      });
    }
    return {
      resolverVersion: this.resolverVersion,
      data: { recipeId, title, servings, ingredients, evidence, issues }
    };
  }
}
