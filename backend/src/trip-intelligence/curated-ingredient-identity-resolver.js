import { createHash } from 'node:crypto';
import catalog from './data/ingredient-identities-v1.json' with { type: 'json' };
import {
  inspectIngredientPreparation,
  inspectIngredientQueryName
} from './ingredient-query-safety.js';

const headingPattern = /^(ingredients?|directions?|instructions?|method|preparation|nutrition|notes?)\s*:?$/i;
const credibleNamePattern = /[\p{L}\p{N}]/u;

function normalized(value) {
  return value
    .normalize('NFKC')
    .trim()
    .replace(/[\s,;:]+$/u, '')
    .replace(/\s+/gu, ' ')
    .toLocaleLowerCase('en-US');
}

function slug(value) {
  const ascii = normalized(value)
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .replace(/[^a-z0-9]+/gu, '-')
    .replace(/^-+|-+$/gu, '');
  if (ascii.length > 0) return ascii;
  return `ingredient-${createHash('sha256').update(normalized(value)).digest('hex').slice(0, 16)}`;
}

function detectedForm(preparation) {
  const value = normalized(preparation);
  if (/\b(?:finely\s+)?grated\b/u.test(value)) return 'grated';
  if (/\bchopp?ed\b/u.test(value)) return 'chopped';
  if (/\bdiced\b/u.test(value)) return 'diced';
  if (/\bsliced\b/u.test(value)) return 'sliced';
  if (/\bminced\b/u.test(value)) return 'minced';
  return null;
}

function emptyModifiers(preparation) {
  const form = detectedForm(preparation);
  return {
    form,
    variety: null,
    criticalAttributes: [],
    unclassified: form === null && preparation.trim().length > 0
      ? [preparation.trim()]
      : []
  };
}

function unresolved(ingredient, code, message) {
  return {
    ingredientId: ingredient.ingredientId,
    identityKey: null,
    canonicalName: null,
    modifiers: emptyModifiers(ingredient.preparation),
    confidence: 'unresolved',
    safeForRetailerQuery: false,
    evidence: ingredient.evidence,
    issues: [{
      code,
      severity: 'blocking',
      message,
      field: 'name',
      evidenceIds: ingredient.evidence.map((evidence) => evidence.evidenceId)
    }]
  };
}

function catalogRecordFor(name) {
  const key = normalized(name);
  return catalog.records.find((record) => (
    record.aliases.some((alias) => normalized(alias) === key)
  ));
}

export class CuratedIngredientIdentityResolver {
  constructor({ catalogVersion = catalog.catalogVersion } = {}) {
    this.catalogVersion = catalogVersion;
  }

  async resolve(ingredient) {
    const inspected = inspectIngredientQueryName(ingredient.name);
    const inspectedPreparation = inspectIngredientPreparation(ingredient.preparation);
    const name = inspected.canonicalName ?? '';
    if (
      !inspected.safe
      || !inspectedPreparation.safe
      || name.length === 0
      || headingPattern.test(name)
      || !credibleNamePattern.test(name)
    ) {
      return unresolved(
        ingredient,
        inspected.code ?? inspectedPreparation.code ?? 'ingredient_identity_unsafe',
        inspected.message ?? inspectedPreparation.message
          ?? 'A credible ingredient name is required before shopping or nutrition lookup.'
      );
    }

    const record = catalogRecordFor(name);
    const canonicalName = record?.canonicalName ?? name;
    const identityKey = record?.identityKey ?? `smartcart-food:${slug(canonicalName)}`;
    if (identityKey.endsWith(':')) {
      return unresolved(
        ingredient,
        'ingredient_identity_unsafe',
        'The ingredient name could not be normalized safely.'
      );
    }

    const evidenceId = `identity-${ingredient.ingredientId}`;
    return {
      ingredientId: ingredient.ingredientId,
      identityKey,
      canonicalName,
      modifiers: emptyModifiers([ingredient.preparation, inspected.preparation].filter(Boolean).join(', ')),
      confidence: record ? 'strong' : 'moderate',
      safeForRetailerQuery: true,
      retailerQuery: record?.retailerQuery ?? canonicalName,
      evidence: [{
        evidenceId,
        kind: 'curatedData',
        sourceName: 'SmartCart ingredient identity catalog',
        sourceVersion: this.catalogVersion,
        sourceRecordId: identityKey,
        description: record
          ? 'A reviewed SmartCart identity alias matched this ingredient.'
          : 'The reviewed ingredient name was normalized without adding product claims.'
      }],
      issues: record ? [] : [{
        code: 'identity_not_curated',
        severity: 'informational',
        message: 'No curated alias was required; the reviewed name is used as the canonical identity.',
        field: 'name',
        evidenceIds: [evidenceId]
      }]
    };
  }
}

export function foodDataCentralReference(identityKey) {
  return catalog.records.find((record) => record.identityKey === identityKey)?.foodDataCentral ?? null;
}
