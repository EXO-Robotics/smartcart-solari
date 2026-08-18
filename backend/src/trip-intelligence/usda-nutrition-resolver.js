import { foodDataCentralReference } from './curated-ingredient-identity-resolver.js';

const ENERGY_IDS = [1008, 2048, 2047];
const PROTEIN_ID = 1003;

function nutrient(food, ids, unit) {
  for (const id of ids) {
    const record = food.nutrients.find((candidate) => (
      candidate.nutrientId === id && candidate.unitName === unit
    ));
    if (record) return record.value;
  }
  return null;
}

function scale(perHundredGrams, mass) {
  return {
    preferred: perHundredGrams * mass.preferred / 100,
    minimum: perHundredGrams * mass.minimum / 100,
    maximum: perHundredGrams * mass.maximum / 100
  };
}

function normalizedTokens(value) {
  return value
    .normalize('NFKC')
    .toLocaleLowerCase('en-US')
    .match(/[\p{L}\p{N}]+/gu) ?? [];
}

function conservativeFoodSelection(foods, canonicalName) {
  const requiredTokens = normalizedTokens(canonicalName).filter((token) => token.length > 1);
  if (requiredTokens.length === 0) return null;
  const candidates = foods.filter((food) => {
    if (!['Foundation', 'SR Legacy'].includes(food.dataType)) return false;
    const descriptionTokens = new Set(normalizedTokens(food.description));
    return requiredTokens.every((token) => descriptionTokens.has(token));
  });
  return candidates.length === 1 ? candidates[0] : null;
}

function incomplete(ingredient, identity, mass, code, message, inheritedIssues = []) {
  return {
    ingredientId: ingredient.ingredientId,
    identityKey: identity.identityKey,
    massGrams: mass.massGrams,
    nutrition: null,
    confidence: 'unresolved',
    evidence: [...identity.evidence, ...mass.evidence],
    issues: [
      ...identity.issues,
      ...mass.issues,
      ...inheritedIssues,
      {
        code,
        severity: 'review',
        message,
        field: 'nutrition',
        evidenceIds: []
      }
    ]
  };
}

export class UsdaNutritionResolver {
  constructor({ foodDataCentralClient, resolverVersion = 'usda-nutrition-v1' }) {
    if (typeof foodDataCentralClient?.searchFoods !== 'function') {
      throw new TypeError('foodDataCentralClient is required');
    }
    this.client = foodDataCentralClient;
    this.resolverVersion = resolverVersion;
  }

  async resolve({ ingredient, identity, mass }) {
    if (identity.identityKey === null || !identity.safeForRetailerQuery) {
      return incomplete(
        ingredient,
        identity,
        mass,
        'nutrition_identity_unresolved',
        'Nutrition lookup requires a validated ingredient identity.'
      );
    }
    if (mass.massGrams === null) {
      return incomplete(
        ingredient,
        identity,
        mass,
        'nutrition_mass_unresolved',
        'Nutrition lookup requires a reviewed mass estimate.'
      );
    }

    const reference = foodDataCentralReference(identity.identityKey);
    let food;
    if (reference !== null) {
      food = await this.client.foodDetails(reference.fdcId);
    } else {
      const foods = await this.client.searchFoods(identity.canonicalName, { pageSize: 5 });
      food = conservativeFoodSelection(foods, identity.canonicalName);
    }

    if (food === null) {
      return incomplete(
        ingredient,
        identity,
        mass,
        'usda_food_not_found',
        'No USDA food record could be selected conservatively.'
      );
    }

    const energy = nutrient(food, ENERGY_IDS, 'KCAL');
    const protein = nutrient(food, [PROTEIN_ID], 'G');
    if (energy === null || protein === null) {
      return incomplete(
        ingredient,
        identity,
        mass,
        'usda_nutrients_missing',
        'The selected USDA record lacks energy or protein data.'
      );
    }

    const evidenceId = `usda-nutrition-${ingredient.ingredientId}`;
    return {
      ingredientId: ingredient.ingredientId,
      identityKey: identity.identityKey,
      massGrams: mass.massGrams,
      nutrition: {
        energyKilocalories: scale(energy, mass.massGrams),
        proteinGrams: scale(protein, mass.massGrams)
      },
      confidence: reference === null ? 'moderate' : 'strong',
      evidence: [
        ...identity.evidence,
        ...mass.evidence,
        {
          evidenceId,
          kind: 'usdaFoodData',
          sourceName: 'USDA FoodData Central',
          sourceVersion: food.dataType,
          sourceRecordId: String(food.fdcId),
          description: `${food.description}; energy and protein values per 100 grams.`
        }
      ],
      issues: [...identity.issues, ...mass.issues]
    };
  }
}
