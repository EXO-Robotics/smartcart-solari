import { loadConfig } from '../config.js';
import { CuratedIngredientIdentityResolver } from './curated-ingredient-identity-resolver.js';
import { FoodDataCentralClient } from './food-data-central-client.js';
import { IngredientMassEstimator } from './ingredient-mass-estimator.js';
import { TripIntelligenceService } from './trip-intelligence-service.js';
import { UsdaNutritionResolver } from './usda-nutrition-resolver.js';

export function createTripIntelligenceService(overrides = {}) {
  const config = loadConfig(overrides.config ?? {});
  const foodDataCentralClient = overrides.foodDataCentralClient ?? new FoodDataCentralClient({
    apiKey: config.usdaFoodDataApiKey,
    baseUrl: config.usdaFoodDataBaseUrl,
    timeoutMs: config.usdaFoodDataTimeoutMs
  });
  return new TripIntelligenceService({
    resolverVersion: 'trip-intelligence-nutrition-v1',
    identityResolver: overrides.identityResolver ?? new CuratedIngredientIdentityResolver(),
    massEstimator: overrides.massEstimator ?? new IngredientMassEstimator({ foodDataCentralClient }),
    nutritionResolver: overrides.nutritionResolver ?? new UsdaNutritionResolver({ foodDataCentralClient })
  });
}
