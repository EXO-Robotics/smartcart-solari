import { createHash } from 'node:crypto';
import { inspectIngredientQueryName } from './ingredient-query-safety.js';

const stopHeading = /^(instructions?|directions?|method|steps?|preparation|nutrition|notes?)\s*:?$/i;
const ingredientHeading = /^ingredients?\s*:?$/i;
const instructionStart = /^(?:add|bake|beat|blend|bring|combine|cook|cover|drain|heat|mix|place|preheat|reduce|remove|serve|stir|whisk)\b/iu;
const units = [
  'fluid ounces?', 'fl oz', 'tablespoons?', 'tbsp', 'teaspoons?', 'tsp',
  'kilograms?', 'kg', 'grams?', 'g', 'pounds?', 'lbs?', 'ounces?', 'oz',
  'milliliters?', 'ml', 'liters?', 'l', 'cups?', 'packages?', 'cans?', 'cloves?',
  'pieces?', 'slices?', 'stalks?', 'sticks?', 'bunches?', 'heads?', 'sprigs?',
  'scoops?', 'pinches?', 'jars?', 'containers?', 'cartons?',
  'large', 'medium', 'small'
];
const unitExpression = units.join('|');
const unitPattern = new RegExp(`^(${unitExpression})\\.?\\b\\s*`, 'iu');
const quantityTokenExpression = String.raw`(?:\d+[\/\u2044]\d+|\d+[¼½¾⅓⅔⅛⅜⅝⅞]|[¼½¾⅓⅔⅛⅜⅝⅞]|\d+(?:\.\d+)?)`;
const compactQuantityUnitPattern = new RegExp(
  `^(${quantityTokenExpression})\\s*(${unitExpression})\\.?\\b\\s*`,
  'iu'
);
const fractionGlyphs = new Map([
  ['¼', 0.25], ['½', 0.5], ['¾', 0.75], ['⅓', 1 / 3], ['⅔', 2 / 3],
  ['⅛', 0.125], ['⅜', 0.375], ['⅝', 0.625], ['⅞', 0.875]
]);

function stableUuid(seed) {
  const bytes = createHash('sha256').update(seed).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function numericToken(token) {
  const normalizedToken = token.replace(/\u2044/gu, '/');
  if (fractionGlyphs.has(normalizedToken)) return fractionGlyphs.get(normalizedToken);
  const mixedGlyph = /^(\d+)([¼½¾⅓⅔⅛⅜⅝⅞])$/u.exec(normalizedToken);
  if (mixedGlyph) return Number(mixedGlyph[1]) + fractionGlyphs.get(mixedGlyph[2]);
  const fraction = /^(\d+)\/(\d+)$/u.exec(normalizedToken);
  if (fraction && Number(fraction[2]) !== 0) return Number(fraction[1]) / Number(fraction[2]);
  return /^\d+(?:\.\d+)?$/u.test(normalizedToken) ? Number(normalizedToken) : null;
}

function parseLeadingQuantity(value) {
  let remaining = value.trim();
  const compactRange = /^(\d+(?:\.\d+)?|\d+[\/\u2044]\d+|[¼½¾⅓⅔⅛⅜⅝⅞])\s*(?:-|–)\s*(\d+(?:\.\d+)?|\d+[\/\u2044]\d+|[¼½¾⅓⅔⅛⅜⅝⅞])\s*/u.exec(remaining);
  if (compactRange) {
    const start = numericToken(compactRange[1]);
    const end = numericToken(compactRange[2]);
    if (start !== null && end !== null) {
      remaining = remaining.slice(compactRange[0].length);
      const unitMatch = unitPattern.exec(remaining);
      const unit = unitMatch ? unitMatch[1] : '';
      if (unitMatch) remaining = remaining.slice(unitMatch[0].length);
      return {
        quantity: {
          kind: 'numeric',
          value: Math.max(start, end),
          minimumValue: Math.min(start, end),
          unit
        },
        remaining
      };
    }
  }
  const compactQuantityUnit = compactQuantityUnitPattern.exec(remaining);
  if (compactQuantityUnit) {
    const preferred = numericToken(compactQuantityUnit[1]);
    if (preferred !== null) {
      return {
        quantity: {
          kind: 'numeric',
          value: preferred,
          minimumValue: null,
          unit: compactQuantityUnit[2]
        },
        remaining: remaining.slice(compactQuantityUnit[0].length)
      };
    }
  }
  const firstMatch = /^(\S+)\s*/u.exec(remaining);
  if (!firstMatch) return { quantity: null, remaining };
  let preferred = numericToken(firstMatch[1]);
  if (preferred === null) return { quantity: null, remaining };
  remaining = remaining.slice(firstMatch[0].length);

  const mixed = /^(\d+[\/\u2044]\d+|[¼½¾⅓⅔⅛⅜⅝⅞])\s*/u.exec(remaining);
  if (mixed) {
    const part = numericToken(mixed[1]);
    if (part !== null) {
      preferred += part;
      remaining = remaining.slice(mixed[0].length);
    }
  }

  let minimumValue = null;
  const range = /^(?:-|–|to)\s*(\d+(?:\.\d+)?|\d+[\/\u2044]\d+|[¼½¾⅓⅔⅛⅜⅝⅞])\s*/iu.exec(remaining);
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

function qualitativeLeadingQuantity(value) {
  const match = /^(?:a\s+)?pinch(?:\s+of)?\s+(.+)$/iu.exec(value.trim());
  return match ? { remaining: match[1].trim(), quantity: null } : null;
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

function normalizedBoundaryText(value) {
  return value
    .normalize('NFKC')
    .trim()
    .replace(/^[•*\-–—]+\s*/u, '')
    .replace(/[\s:;.!?]+$/u, '')
    .replace(/\s+/gu, ' ')
    .toLocaleLowerCase('en-US');
}

const contextualSectionWords = new Set([
  'assembly', 'dough', 'filling', 'garnish', 'glaze', 'marinade', 'optional', 'sauce', 'topping'
]);

function nextNonemptyLineIsMeasured(lines, index) {
  for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
    const candidate = lines[cursor].trim().replace(/^[•*\-–—]+\s*/u, '').trim();
    if (candidate.length === 0) continue;
    const parsed = parseLeadingQuantity(candidate);
    return parsed.quantity?.kind === 'numeric' && parsed.remaining.trim().length > 0;
  }
  return false;
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
    const normalizedTitle = normalizedBoundaryText(title);
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
      if (normalizedTitle.length > 0 && normalizedBoundaryText(line) === normalizedTitle) {
        issues.push(issue(
          sourceLine,
          index,
          'ingredient_title_duplicate',
          'The recipe title cannot become a retailer query.',
          'blocking'
        ));
        continue;
      }
      if (
        contextualSectionWords.has(normalizedBoundaryText(line))
        && nextNonemptyLineIsMeasured(lines, index)
      ) {
        issues.push(issue(
          sourceLine,
          index,
          'ingredient_heading_fragment',
          'A recipe subsection heading cannot become a retailer query.',
          'blocking'
        ));
        continue;
      }
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
        const parsed = qualitativeLeadingQuantity(line) ?? parseLeadingQuantity(line);
        line = parsed.remaining;
        quantity = parsed.quantity;
      }

      const queryName = inspectIngredientQueryName(line);
      if (!queryName.safe) {
        issues.push(issue(
          sourceLine,
          index,
          queryName.code,
          queryName.message,
          'blocking'
        ));
        continue;
      }
      const { canonicalName: name, preparation } = queryName;
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

    if (ingredients.length === 0 && !issues.some((entry) => entry.severity === 'blocking')) {
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
