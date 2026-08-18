import { randomUUID } from 'node:crypto';
import { contractEnvelope } from '../contracts/envelope.js';
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
    this.createTripIntelligence = options.createTripIntelligence ?? (() => createTripIntelligenceService());
    this.groceryTripPlanner = options.groceryTripPlanner ?? new GroceryTripPlanner({ identityResolver });
  }

  intelligence() {
    if (this.tripIntelligence === null) this.tripIntelligence = this.createTripIntelligence();
    return this.tripIntelligence;
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
}
