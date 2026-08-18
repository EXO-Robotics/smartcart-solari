const confidenceRank = new Map([
  ['verified', 4],
  ['strong', 3],
  ['moderate', 2],
  ['weak', 1],
  ['unresolved', 0]
]);

function weakestConfidence(values) {
  if (values.length === 0) return 'unresolved';
  return values.reduce((weakest, candidate) => (
    (confidenceRank.get(candidate) ?? 0) < (confidenceRank.get(weakest) ?? 0)
      ? candidate
      : weakest
  ), values[0]);
}

function addEstimates(estimates) {
  return estimates.reduce((total, estimate) => ({
    preferred: total.preferred + estimate.preferred,
    minimum: total.minimum + estimate.minimum,
    maximum: total.maximum + estimate.maximum
  }), { preferred: 0, minimum: 0, maximum: 0 });
}

function divideEstimate(estimate, divisor) {
  return {
    preferred: estimate.preferred / divisor,
    minimum: estimate.minimum / divisor,
    maximum: estimate.maximum / divisor
  };
}

function aggregateNutrition(resolutions) {
  const complete = resolutions.every((resolution) => resolution.nutrition !== null);
  if (!complete || resolutions.length === 0) return null;

  return {
    energyKilocalories: addEstimates(
      resolutions.map((resolution) => resolution.nutrition.energyKilocalories)
    ),
    proteinGrams: addEstimates(
      resolutions.map((resolution) => resolution.nutrition.proteinGrams)
    )
  };
}

export class TripIntelligenceConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TripIntelligenceConfigurationError';
  }
}

export class TripIntelligenceService {
  constructor({ identityResolver, massEstimator, nutritionResolver, resolverVersion }) {
    if (typeof identityResolver?.resolve !== 'function') {
      throw new TripIntelligenceConfigurationError('identityResolver.resolve is required');
    }
    if (typeof massEstimator?.estimate !== 'function') {
      throw new TripIntelligenceConfigurationError('massEstimator.estimate is required');
    }
    if (typeof nutritionResolver?.resolve !== 'function') {
      throw new TripIntelligenceConfigurationError('nutritionResolver.resolve is required');
    }
    if (typeof resolverVersion !== 'string' || resolverVersion.length === 0) {
      throw new TripIntelligenceConfigurationError('resolverVersion is required');
    }

    this.identityResolver = identityResolver;
    this.massEstimator = massEstimator;
    this.nutritionResolver = nutritionResolver;
    this.resolverVersion = resolverVersion;
  }

  async resolveIngredient(ingredient) {
    const identity = await this.identityResolver.resolve(ingredient);
    const mass = await this.massEstimator.estimate({ ingredient, identity });
    return this.nutritionResolver.resolve({ ingredient, identity, mass });
  }

  async estimateRecipeNutrition(recipe) {
    if (!Number.isFinite(recipe.servings) || recipe.servings <= 0) {
      throw new TypeError('Recipe servings must be a positive finite number');
    }

    const includedIngredients = recipe.ingredients.filter(
      (ingredient) => ingredient.includedInRecipe
    );
    const ingredientResolutions = await Promise.all(
      includedIngredients.map((ingredient) => this.resolveIngredient(ingredient))
    );
    const totals = aggregateNutrition(ingredientResolutions);
    const issues = ingredientResolutions.flatMap((resolution) => resolution.issues);

    if (totals === null) {
      issues.push({
        code: 'recipe_nutrition_incomplete',
        severity: 'review',
        message: 'At least one included ingredient could not be resolved for nutrition.',
        field: 'totals',
        evidenceIds: []
      });
    }

    return {
      resolverVersion: this.resolverVersion,
      data: {
        recipeId: recipe.recipeId,
        servings: recipe.servings,
        ingredientResolutions,
        totals,
        perServing: totals === null
          ? null
          : {
              energyKilocalories: divideEstimate(totals.energyKilocalories, recipe.servings),
              proteinGrams: divideEstimate(totals.proteinGrams, recipe.servings)
            },
        confidence: weakestConfidence(
          ingredientResolutions.map((resolution) => resolution.confidence)
        ),
        evidence: [{
          evidenceId: `calculation-${recipe.recipeId}`,
          kind: 'calculation',
          sourceName: 'TripIntelligenceService',
          sourceVersion: this.resolverVersion,
          sourceRecordId: null,
          description: `Included ingredient estimates summed and divided by ${recipe.servings} servings.`
        }],
        issues
      }
    };
  }
}
