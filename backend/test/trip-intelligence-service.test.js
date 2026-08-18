import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { contractEnvelope } from '../src/contracts/envelope.js';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { TripIntelligenceService } from '../src/trip-intelligence/trip-intelligence-service.js';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const contractsRoot = path.resolve(testDirectory, '../../contracts');
const fixtureRoot = path.join(contractsRoot, 'fixtures/v1/chicken-parmesan');

async function readJson(name) {
  return JSON.parse(await readFile(path.join(fixtureRoot, name), 'utf8'));
}

async function fixtureService() {
  const identity = await readJson('identity-output.json');
  const mass = await readJson('mass-output.json');
  const nutrition = await readJson('nutrition-output.json');

  return new TripIntelligenceService({
    resolverVersion: 'fixture-nutrition-v1',
    identityResolver: {
      async resolve(ingredient) {
        assert.equal(ingredient.ingredientId, identity.data.ingredientId);
        return structuredClone(identity.data);
      }
    },
    massEstimator: {
      async estimate({ ingredient, identity: resolvedIdentity }) {
        assert.equal(ingredient.ingredientId, mass.data.ingredientId);
        assert.equal(resolvedIdentity.identityKey, identity.data.identityKey);
        return structuredClone(mass.data);
      }
    },
    nutritionResolver: {
      async resolve({ ingredient, identity: resolvedIdentity, mass: resolvedMass }) {
        assert.equal(ingredient.ingredientId, nutrition.data.ingredientId);
        assert.equal(resolvedIdentity.identityKey, nutrition.data.identityKey);
        assert.deepEqual(resolvedMass.massGrams, nutrition.data.massGrams);
        return structuredClone(nutrition.data);
      }
    }
  });
}

test('Trip Intelligence reproduces the recipe golden contract', async () => {
  const validator = await createContractValidator({ contractsRoot });
  const request = await readJson('recipe-request.json');
  const expected = await readJson('recipe-nutrition-output.json');
  validator.assert(
    'https://schemas.smartcart.app/v1/nutrition/recipe-nutrition-request.schema.json',
    request
  );

  const service = await fixtureService();
  const result = await service.estimateRecipeNutrition(request.data);
  const response = contractEnvelope({ requestId: request.requestId, ...result });

  validator.assert(
    'https://schemas.smartcart.app/v1/nutrition/recipe-nutrition-estimate.schema.json',
    response
  );
  assert.deepEqual(response, expected);
});

test('shopping inclusion does not change recipe nutrition', async () => {
  const request = await readJson('recipe-request.json');
  request.data.ingredients[0].includeInTrip = false;

  const service = await fixtureService();
  const result = await service.estimateRecipeNutrition(request.data);

  assert.equal(result.data.ingredientResolutions.length, 1);
  assert.equal(result.data.totals.energyKilocalories.preferred, 378);
  assert.equal(result.data.perServing.energyKilocalories.preferred, 94.5);
});

test('ingredients excluded from the recipe are not included in nutrition totals', async () => {
  const request = await readJson('recipe-request.json');
  request.data.ingredients[0].includedInRecipe = false;

  const service = await fixtureService();
  const result = await service.estimateRecipeNutrition(request.data);

  assert.equal(result.data.ingredientResolutions.length, 0);
  assert.equal(result.data.totals, null);
  assert.equal(result.data.perServing, null);
  assert.equal(result.data.confidence, 'unresolved');
  assert.equal(result.data.issues[0].code, 'recipe_nutrition_incomplete');
});

test('Meal Prep aggregates frozen recipe estimates without changing recipe servings', async () => {
  const request = await readJson('recipe-request.json');
  const service = await fixtureService();
  const result = await service.estimateMealPrepNutrition({
    mealPlanId: '10000000-0000-4000-8000-000000000901',
    recipes: [request.data, { ...request.data, recipeId: '10000000-0000-4000-8000-000000000902' }]
  });

  assert.equal(result.data.recipeEstimates.length, 2);
  assert.equal(result.data.recipeEstimates[0].servings, 4);
  assert.equal(result.data.totals.energyKilocalories.preferred, 756);
  assert.equal(result.data.totals.proteinGrams.preferred, 66.6);
  assert.equal(result.data.totalServings, 8);
  assert.equal(result.data.weightedAveragePerServing.energyKilocalories.preferred, 94.5);
  assert.equal(result.data.weightedAveragePerServing.proteinGrams.preferred, 8.325);
});

test('Meal Prep weighted averages use the sum of frozen recipe servings', async () => {
  const request = await readJson('recipe-request.json');
  const expected = await readJson('meal-prep-nutrition-output.json');
  const validator = await createContractValidator({ contractsRoot });
  const service = await fixtureService();
  const result = await service.estimateMealPrepNutrition({
    mealPlanId: '10000000-0000-4000-8000-000000000903',
    recipes: [request.data, {
      ...request.data,
      recipeId: '10000000-0000-4000-8000-000000000904',
      servings: 2
    }]
  });

  assert.equal(result.data.totalServings, 6);
  assert.equal(result.data.totals.energyKilocalories.preferred, 756);
  assert.equal(result.data.weightedAveragePerServing.energyKilocalories.preferred, 126);
  assert.equal(result.data.weightedAveragePerServing.proteinGrams.preferred, 11.1);
  assert.equal(result.data.recipeEstimates[0].perServing.energyKilocalories.preferred, 94.5);
  assert.equal(result.data.recipeEstimates[1].perServing.energyKilocalories.preferred, 189);

  const response = contractEnvelope({ requestId: expected.requestId, ...result });
  validator.assert(
    'https://schemas.smartcart.app/v1/nutrition/meal-prep-nutrition-estimate.schema.json',
    response
  );
  assert.deepEqual(response, expected);
});
