import { foodDataCentralReference } from './curated-ingredient-identity-resolver.js';

const massUnits = new Map([
  ['g', 1], ['gram', 1], ['grams', 1],
  ['kg', 1_000], ['kilogram', 1_000], ['kilograms', 1_000],
  ['oz', 28.349523125], ['ounce', 28.349523125], ['ounces', 28.349523125],
  ['lb', 453.59237], ['lbs', 453.59237], ['pound', 453.59237], ['pounds', 453.59237]
]);

const volumeUnits = new Map([
  ['ml', 1], ['milliliter', 1], ['milliliters', 1],
  ['l', 1_000], ['liter', 1_000], ['liters', 1_000],
  ['tsp', 4.92892159375], ['teaspoon', 4.92892159375], ['teaspoons', 4.92892159375],
  ['tbsp', 14.78676478125], ['tablespoon', 14.78676478125], ['tablespoons', 14.78676478125],
  ['cup', 236.5882365], ['cups', 236.5882365],
  ['fl oz', 29.5735295625], ['fluid ounce', 29.5735295625], ['fluid ounces', 29.5735295625]
]);

function issue(code, severity, message, field = 'quantity', evidenceIds = []) {
  return { code, severity, message, field, evidenceIds };
}

function unitKey(value) {
  return value.trim().toLocaleLowerCase('en-US').replace(/\.$/u, '');
}

function estimate(value, minimumValue, factor) {
  const first = value * factor;
  const second = (minimumValue ?? value) * factor;
  return {
    preferred: first,
    minimum: Math.min(first, second),
    maximum: Math.max(first, second)
  };
}

function sourceQuantity(value, dimension, unit, certainty) {
  return { value, dimension, unit, certainty };
}

function portionLabel(portion) {
  return `${portion.modifier} ${portion.measureUnit}`.trim().toLocaleLowerCase('en-US');
}

function matchedPortion(food, unit) {
  const wanted = unitKey(unit);
  return food.portions.find((portion) => {
    const label = portionLabel(portion);
    return label === wanted || label.split(/\s+/u).includes(wanted);
  });
}

export class IngredientMassEstimator {
  constructor({ foodDataCentralClient = null, resolverVersion = 'mass-v1' } = {}) {
    this.foodDataCentralClient = foodDataCentralClient;
    this.resolverVersion = resolverVersion;
  }

  async estimate({ ingredient, identity }) {
    const base = {
      ingredientId: ingredient.ingredientId,
      sourceQuantity: null,
      massGrams: null,
      confidence: 'unresolved',
      evidence: [],
      issues: []
    };

    if (ingredient.quantity === null || ingredient.quantity.kind === 'semantic') {
      return {
        ...base,
        issues: [issue(
          'quantity_not_numeric',
          'informational',
          'Nutrition requires a numeric amount; shopping identity remains available.'
        )]
      };
    }

    const { value, minimumValue, unit } = ingredient.quantity;
    const key = unitKey(unit);
    if (massUnits.has(key)) {
      const factor = massUnits.get(key);
      return {
        ...base,
        sourceQuantity: sourceQuantity(value * factor, 'mass', 'g', 'exact'),
        massGrams: estimate(value, minimumValue, factor),
        confidence: 'strong',
        evidence: [{
          evidenceId: `mass-conversion-${ingredient.ingredientId}`,
          kind: 'calculation',
          sourceName: 'SmartCart canonical unit conversion',
          sourceVersion: this.resolverVersion,
          sourceRecordId: key,
          description: `Converted ${unit} to grams using a fixed physical unit conversion.`
        }]
      };
    }

    if (volumeUnits.has(key)) {
      const milliliters = value * volumeUnits.get(key);
      const reference = foodDataCentralReference(identity.identityKey);
      if (reference !== null && this.foodDataCentralClient !== null) {
        const food = await this.foodDataCentralClient.foodDetails(reference.fdcId);
        const portion = matchedPortion(food, key);
        if (portion) {
          const gramsPerUnit = portion.gramWeight / portion.amount;
          const evidenceId = `usda-portion-${ingredient.ingredientId}`;
          return {
            ...base,
            sourceQuantity: sourceQuantity(milliliters, 'volume', 'ml', 'exact'),
            massGrams: estimate(value, minimumValue, gramsPerUnit),
            confidence: 'strong',
            evidence: [{
              evidenceId,
              kind: 'usdaFoodData',
              sourceName: 'USDA FoodData Central',
              sourceVersion: food.dataType,
              sourceRecordId: String(food.fdcId),
              description: `USDA portion evidence maps ${portion.amount} ${unitKey(portion.modifier || portion.measureUnit)} to ${portion.gramWeight} grams.`
            }]
          };
        }
      }
      return {
        ...base,
        sourceQuantity: sourceQuantity(milliliters, 'volume', 'ml', 'exact'),
        issues: [issue(
          'density_evidence_missing',
          'review',
          'A reviewed density or portion weight is required to estimate nutrition from volume.'
        )]
      };
    }

    return {
      ...base,
      issues: [issue(
        'unit_not_convertible_to_mass',
        'review',
        'This unit does not yet have reviewed mass evidence.'
      )]
    };
  }
}
