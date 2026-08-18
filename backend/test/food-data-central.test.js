import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { CuratedIngredientIdentityResolver } from '../src/trip-intelligence/curated-ingredient-identity-resolver.js';
import {
  FoodDataCentralClient,
  FoodDataCentralError
} from '../src/trip-intelligence/food-data-central-client.js';
import { IngredientMassEstimator } from '../src/trip-intelligence/ingredient-mass-estimator.js';
import { TripIntelligenceService } from '../src/trip-intelligence/trip-intelligence-service.js';
import { UsdaNutritionResolver } from '../src/trip-intelligence/usda-nutrition-resolver.js';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(testDirectory, '../..');

async function json(relativePath) {
  return JSON.parse(await readFile(path.join(repoRoot, relativePath), 'utf8'));
}

function mockResponse(body, { status = 200 } = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' }
  });
}

async function parmesanClient() {
  const details = await json('backend/test/fixtures/usda/parmesan-food-details.json');
  return new FoodDataCentralClient({
    apiKey: 'test-key-never-sent',
    async fetchImpl(url) {
      assert.equal(url.pathname, '/fdc/v1/food/171247');
      assert.equal(url.searchParams.get('api_key'), 'test-key-never-sent');
      return mockResponse(details);
    }
  });
}

test('USDA client normalizes only the bounded food evidence SmartCart consumes', async () => {
  const client = await parmesanClient();
  const food = await client.foodDetails(171247);

  assert.deepEqual(food, {
    fdcId: 171247,
    description: 'Cheese, parmesan, grated',
    dataType: 'SR Legacy',
    publishedDate: null,
    nutrients: [
      { nutrientId: 1008, value: 420, unitName: 'KCAL' },
      { nutrientId: 1003, value: 28.42, unitName: 'G' }
    ],
    portions: [
      { amount: 1, gramWeight: 28.35, modifier: 'oz', measureUnit: 'undetermined' },
      { amount: 1, gramWeight: 100, modifier: 'cup', measureUnit: 'undetermined' },
      { amount: 1, gramWeight: 5, modifier: 'tbsp', measureUnit: 'undetermined' }
    ]
  });
});

test('USDA failures never reveal the API key', async () => {
  const client = new FoodDataCentralClient({
    apiKey: 'sensitive-test-key',
    async fetchImpl() { return mockResponse({ error: 'nope' }, { status: 401 }); }
  });

  await assert.rejects(
    client.foodDetails(171247),
    (error) => {
      assert(error instanceof FoodDataCentralError);
      assert.equal(error.code, 'usda_request_failed');
      assert.equal(error.message.includes('sensitive-test-key'), false);
      return true;
    }
  );
});

test('USDA details cache coalesces identical requests and isolates cached values', async () => {
  const details = await json('backend/test/fixtures/usda/parmesan-food-details.json');
  let fetchCount = 0;
  let releaseFetch;
  const fetchGate = new Promise((resolve) => { releaseFetch = resolve; });
  const client = new FoodDataCentralClient({
    apiKey: 'cache-test-key',
    async fetchImpl() {
      fetchCount += 1;
      await fetchGate;
      return mockResponse(details);
    }
  });

  const firstRequest = client.foodDetails(171247);
  const secondRequest = client.foodDetails(171247);
  releaseFetch();
  const [first, second] = await Promise.all([firstRequest, secondRequest]);

  assert.equal(fetchCount, 1);
  first.description = 'mutated by caller';
  const cached = await client.foodDetails(171247);
  assert.equal(fetchCount, 1);
  assert.equal(second.description, 'Cheese, parmesan, grated');
  assert.equal(cached.description, 'Cheese, parmesan, grated');
});

test('USDA search cache coalesces normalized queries and never caches failures', async () => {
  let fetchCount = 0;
  let shouldFail = true;
  const client = new FoodDataCentralClient({
    apiKey: 'cache-test-key',
    async fetchImpl() {
      fetchCount += 1;
      if (shouldFail) return mockResponse({ error: 'temporary' }, { status: 503 });
      return mockResponse({ foods: [{ fdcId: 171247, description: 'Cheese, parmesan, grated' }] });
    }
  });

  await assert.rejects(client.searchFoods(' Parmesan cheese '), FoodDataCentralError);
  shouldFail = false;
  const [first, second] = await Promise.all([
    client.searchFoods('Parmesan cheese'),
    client.searchFoods('parmesan cheese')
  ]);

  assert.equal(fetchCount, 2);
  assert.deepEqual(first, second);
  await client.searchFoods('PARMESAN CHEESE');
  assert.equal(fetchCount, 2);
});

test('official USDA portion and nutrient evidence produces a valid recipe estimate', async () => {
  const validator = await createContractValidator({ contractsRoot: path.join(repoRoot, 'contracts') });
  const request = await json('contracts/fixtures/v1/chicken-parmesan/recipe-request.json');
  const client = await parmesanClient();
  const service = new TripIntelligenceService({
    resolverVersion: 'trip-intelligence-nutrition-v1',
    identityResolver: new CuratedIngredientIdentityResolver(),
    massEstimator: new IngredientMassEstimator({ foodDataCentralClient: client }),
    nutritionResolver: new UsdaNutritionResolver({ foodDataCentralClient: client })
  });

  const result = await service.estimateRecipeNutrition(request.data);
  const response = {
    schemaVersion: '1.0',
    resolverVersion: result.resolverVersion,
    requestId: request.requestId,
    data: result.data
  };
  validator.assert(
    'https://schemas.smartcart.app/v1/nutrition/recipe-nutrition-estimate.schema.json',
    response
  );

  const ingredient = response.data.ingredientResolutions[0];
  assert.deepEqual(ingredient.massGrams, { preferred: 100, minimum: 100, maximum: 100 });
  assert.deepEqual(
    ingredient.nutrition.energyKilocalories,
    { preferred: 420, minimum: 420, maximum: 420 }
  );
  assert.deepEqual(
    ingredient.nutrition.proteinGrams,
    { preferred: 28.42, minimum: 28.42, maximum: 28.42 }
  );
  assert.equal(ingredient.evidence.some((evidence) => evidence.kind === 'usdaFoodData'), true);
});

test('semantic and omitted quantities remain shoppable but do not invent nutrition mass', async () => {
  const source = await json('contracts/fixtures/v1/semantic-quantity/ingredient-input.json');
  const client = await parmesanClient();
  const identityResolver = new CuratedIngredientIdentityResolver();
  const estimator = new IngredientMassEstimator({ foodDataCentralClient: client });

  for (const quantity of [source.quantity, null]) {
    const ingredient = { ...source, quantity };
    const identity = await identityResolver.resolve(ingredient);
    const mass = await estimator.estimate({ ingredient, identity });
    assert.equal(identity.safeForRetailerQuery, true);
    assert.equal(mass.massGrams, null);
    assert.equal(mass.issues[0].code, 'quantity_not_numeric');
  }
});

test('headings and malformed ingredient names never produce retailer queries', async () => {
  const resolver = new CuratedIngredientIdentityResolver();
  const template = (name) => ({
    ingredientId: '10000000-0000-4000-8000-000000000199',
    sourceText: name,
    name,
    preparation: '',
    quantity: null,
    includedInRecipe: true,
    includeInTrip: true,
    brandPreference: null,
    evidence: [{
      evidenceId: 'source-unsafe-1',
      kind: 'sourceText',
      sourceName: 'Test',
      sourceVersion: '1',
      sourceRecordId: null,
      description: 'Test source.'
    }]
  });

  for (const name of ['Ingredients', '% Cup All Purpose Flour', '???']) {
    const identity = await resolver.resolve(template(name));
    assert.equal(identity.safeForRetailerQuery, false);
    assert.equal('retailerQuery' in identity, false);
    assert.equal(identity.issues[0].severity, 'blocking');
  }
});
