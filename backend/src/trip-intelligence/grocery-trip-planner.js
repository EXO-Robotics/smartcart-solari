function normalized(value) {
  return value.normalize('NFKC').trim().replace(/\s+/gu, ' ').toLocaleLowerCase('en-US');
}

function requirement(recipeId, ingredient) {
  return {
    recipeId,
    ingredientId: ingredient.ingredientId,
    sourceText: ingredient.sourceText,
    quantity: ingredient.quantity
  };
}

export class GroceryTripPlanner {
  constructor({ identityResolver, resolverVersion = 'grocery-trip-identity-v1' }) {
    if (typeof identityResolver?.resolve !== 'function') {
      throw new TypeError('identityResolver is required');
    }
    this.identityResolver = identityResolver;
    this.resolverVersion = resolverVersion;
  }

  async plan({ tripId, recipes, pantryIngredientNames }) {
    const pantry = new Set(pantryIngredientNames.map(normalized));
    const grouped = new Map();
    const unresolvedItems = [];
    const issues = [];

    for (const recipe of recipes) {
      for (const ingredient of recipe.ingredients) {
        if (!ingredient.includedInRecipe || !ingredient.includeInTrip) continue;
        const identity = await this.identityResolver.resolve(ingredient);
        if (
          !identity.safeForRetailerQuery
          || identity.identityKey === null
          || identity.canonicalName === null
          || typeof identity.retailerQuery !== 'string'
        ) {
          unresolvedItems.push({
            recipeId: recipe.recipeId,
            ingredientId: ingredient.ingredientId,
            sourceText: ingredient.sourceText,
            issues: identity.issues
          });
          issues.push(...identity.issues);
          continue;
        }

        const existing = grouped.get(identity.identityKey) ?? {
          identityKey: identity.identityKey,
          canonicalName: identity.canonicalName,
          retailerQuery: identity.retailerQuery,
          requirements: []
        };
        existing.requirements.push(requirement(recipe.recipeId, ingredient));
        grouped.set(identity.identityKey, existing);
      }
    }

    const itemsToShop = [];
    const pantrySatisfiedItems = [];
    for (const item of grouped.values()) {
      if (pantry.has(normalized(item.canonicalName)) || pantry.has(normalized(item.retailerQuery))) {
        pantrySatisfiedItems.push(item);
      } else {
        itemsToShop.push(item);
      }
    }

    return {
      resolverVersion: this.resolverVersion,
      data: {
        tripId,
        itemsToShop,
        pantrySatisfiedItems,
        unresolvedItems,
        costs: {
          status: 'requiresRetailerEvidence',
          currencyCode: null,
          recipeConsumptionCost: null,
          estimatedCheckoutCost: null,
          surplusValue: null,
          reason: 'No reviewed retailer prices or package observations were supplied. SmartCart does not invent costs.'
        },
        issues
      }
    };
  }
}
