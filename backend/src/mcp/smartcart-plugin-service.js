import { randomUUID } from 'node:crypto';
import { contractEnvelope } from '../contracts/envelope.js';
import { createHandoffClaimService } from '../handoff/create-handoff-claim-service.js';
import { CuratedIngredientIdentityResolver } from '../trip-intelligence/curated-ingredient-identity-resolver.js';
import { createTripIntelligenceService } from '../trip-intelligence/create-trip-intelligence-service.js';
import { GroceryTripPlanner } from '../trip-intelligence/grocery-trip-planner.js';
import { RecipeTextAnalyzer } from '../trip-intelligence/recipe-text-analyzer.js';

function hasBlockingIssues(analysis) {
  return analysis.data.issues.some((issue) => issue.severity === 'blocking');
}

export class SmartCartPluginService {
  constructor(options = {}) {
    this.analyzer = options.analyzer ?? new RecipeTextAnalyzer();
    const identityResolver = options.identityResolver ?? new CuratedIngredientIdentityResolver();
    this.tripIntelligence = options.tripIntelligence ?? null;
    this.createTripIntelligence = options.createTripIntelligence
      ?? (() => createTripIntelligenceService({ config: options.config }));
    this.groceryTripPlanner = options.groceryTripPlanner ?? new GroceryTripPlanner({ identityResolver });
    this.handoffClaim = options.handoffClaim ?? null;
    this.createHandoffClaim = options.createHandoffClaim
      ?? (() => createHandoffClaimService({ config: options.config }));
  }

  intelligence() {
    if (this.tripIntelligence === null) this.tripIntelligence = this.createTripIntelligence();
    return this.tripIntelligence;
  }

  handoff() {
    if (this.handoffClaim === null) this.handoffClaim = this.createHandoffClaim();
    return this.handoffClaim;
  }

  analyzeRecipe({ recipeText, title, servings, recipeId = randomUUID(), requestId = randomUUID() }) {
    const result = this.analyzer.analyze({ recipeId, title, servings, recipeText });
    return contractEnvelope({ requestId, ...result });
  }

  async estimateRecipe(input) {
    const analysis = this.analyzeRecipe(input);
    if (hasBlockingIssues(analysis)) {
      return { analysis, nutrition: null, readyForEstimate: false };
    }
    const result = await this.intelligence().estimateRecipeNutrition({
      recipeId: analysis.data.recipeId,
      title: analysis.data.title,
      servings: analysis.data.servings,
      ingredients: analysis.data.ingredients
    });
    return {
      analysis,
      nutrition: contractEnvelope({ requestId: randomUUID(), ...result }),
      readyForEstimate: true
    };
  }

  async prepareMealPlan({ recipes }) {
    const analyses = recipes.map((recipe) => this.analyzeRecipe(recipe));
    if (analyses.some(hasBlockingIssues)) {
      return {
        mealPlanId: randomUUID(),
        analyses,
        nutrition: null,
        readyForEstimate: false
      };
    }
    const mealPlanId = randomUUID();
    const result = await this.intelligence().estimateMealPrepNutrition({
      mealPlanId,
      recipes: analyses.map((analysis) => ({
        recipeId: analysis.data.recipeId,
        title: analysis.data.title,
        servings: analysis.data.servings,
        ingredients: analysis.data.ingredients
      }))
    });
    return {
      mealPlanId,
      analyses,
      nutrition: contractEnvelope({ requestId: randomUUID(), ...result }),
      readyForEstimate: true
    };
  }

  async planGroceryTrip({ recipes, pantryIngredientNames = [] }) {
    const analyses = recipes.map((recipe) => this.analyzeRecipe(recipe));
    const tripId = randomUUID();
    const result = await this.groceryTripPlanner.plan({
      tripId,
      pantryIngredientNames,
      recipes: analyses.map((analysis) => ({
        recipeId: analysis.data.recipeId,
        title: analysis.data.title,
        servings: analysis.data.servings,
        ingredients: analysis.data.ingredients
      }))
    });
    const parseIssues = analyses.flatMap((analysis) => analysis.data.issues);
    return {
      analyses,
      trip: contractEnvelope({ requestId: randomUUID(), ...result }),
      parseIssues,
      readyToShop: !parseIssues.some((issue) => issue.severity === 'blocking')
        && result.data.unresolvedItems.length === 0
    };
  }

  async createSmartCartHandoff({ recipes }) {
    const planned = await this.planGroceryTrip({ recipes, pantryIngredientNames: [] });
    if (!planned.readyToShop) {
      const error = new Error('Resolve every blocking or unresolved ingredient before creating a SmartCart handoff.');
      error.code = 'handoff_not_safe';
      throw error;
    }
    const handoffRecipes = recipes.map((recipe, index) => {
      const analysis = planned.analyses[index];
      const sourceType = recipe.sourceType ?? 'text';
      return {
        sourceType,
        recipeText: recipe.recipeText,
        analysis,
        quantityReviewIngredientIds: sourceType === 'image_transcription'
          ? analysis.data.ingredients
            .filter((ingredient) => ingredient.quantity?.kind === 'numeric')
            .map((ingredient) => ingredient.ingredientId)
          : []
      };
    });
    return this.handoff().create({ recipes: handoffRecipes });
  }
}
