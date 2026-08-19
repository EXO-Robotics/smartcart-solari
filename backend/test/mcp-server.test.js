import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import test from 'node:test';
import { createSmartCartMcpServer } from '../src/mcp/server.js';
import { SmartCartPluginService } from '../src/mcp/smartcart-plugin-service.js';
import { CuratedIngredientIdentityResolver } from '../src/trip-intelligence/curated-ingredient-identity-resolver.js';
import { GroceryTripPlanner } from '../src/trip-intelligence/grocery-trip-planner.js';
import { RecipeTextAnalyzer } from '../src/trip-intelligence/recipe-text-analyzer.js';

async function connectedClient(pluginService) {
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const server = createSmartCartMcpServer({ pluginService });
  const client = new Client({ name: 'smartcart-test-client', version: '1.0.0' });
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  return {
    client,
    async close() {
      await client.close();
      await server.close();
    }
  };
}

test('MCP exposes the four stateless tools and explicit native handoff action', async () => {
  const calls = [];
  const service = {
    analyzeRecipe(input) { calls.push(['analyze', input]); return { data: { ingredients: [] } }; },
    async estimateRecipe(input) { calls.push(['estimate', input]); return { nutrition: null }; },
    async prepareMealPlan(input) { calls.push(['meal', input]); return { nutrition: null }; },
    async planGroceryTrip(input) { calls.push(['trip', input]); return { readyToShop: true }; },
    async createSmartCartHandoff(input) {
      calls.push(['handoff', input]);
      return {
        schemaVersion: '1.0',
        resolverVersion: 'smartcart-handoff-v1',
        requestId: '00000000-0000-4000-8000-000000000001',
        data: {
          claimUrl: 'https://smartcart.app/t#v1.opaque',
          expiresAt: '2026-08-19T12:10:00.000Z'
        }
      };
    }
  };
  const connection = await connectedClient(service);
  try {
    const listed = await connection.client.listTools();
    assert.deepEqual(
      listed.tools.map((tool) => tool.name).sort(),
      [
        'analyze_recipe',
        'create_smartcart_handoff',
        'estimate_recipe',
        'plan_grocery_trip',
        'prepare_meal_plan'
      ]
    );
    const handoffTool = listed.tools.find((tool) => tool.name === 'create_smartcart_handoff');
    assert.deepEqual(handoffTool.annotations, {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    });

    for (const name of ['analyze_recipe', 'estimate_recipe']) {
      const result = await connection.client.callTool({
        name,
        arguments: { recipe_text: '1 lb chicken breast', title: 'Chicken', servings: 4 }
      });
      assert.equal(result.isError, undefined);
      assert.equal(result.structuredContent.operation, name);
    }
    const meal = await connection.client.callTool({
      name: 'prepare_meal_plan',
      arguments: { recipes: [{ recipe_text: '1 lb chicken breast', title: 'Chicken', servings: 4 }] }
    });
    assert.equal(meal.structuredContent.operation, 'prepare_meal_plan');
    const trip = await connection.client.callTool({
      name: 'plan_grocery_trip',
      arguments: {
        recipes: [{ recipe_text: '1 lb chicken breast', title: 'Chicken', servings: 4 }],
        pantry_ingredients: ['salt']
      }
    });
    assert.equal(trip.structuredContent.operation, 'plan_grocery_trip');
    const handoff = await connection.client.callTool({
      name: 'create_smartcart_handoff',
      arguments: {
        recipes: [{
          recipe_text: '1 lb chicken breast',
          title: 'Chicken',
          servings: 4,
          source_type: 'image_transcription'
        }]
      }
    });
    assert.equal(handoff.structuredContent.operation, 'create_smartcart_handoff');
    assert.equal(calls.at(-1)[1].recipes[0].sourceType, 'image_transcription');
    assert.equal(calls.length, 5);
  } finally {
    await connection.close();
  }
});

test('MCP handoff rejects fractional servings before invoking its service', async () => {
  let calls = 0;
  const connection = await connectedClient({
    async createSmartCartHandoff() {
      calls += 1;
      throw new Error('The service must not receive invalid tool input.');
    }
  });
  try {
    const result = await connection.client.callTool({
      name: 'create_smartcart_handoff',
      arguments: {
        recipes: [{
          recipe_text: '1 lb chicken breast',
          title: 'Chicken',
          servings: 2.5,
          source_type: 'text'
        }]
      }
    });
    assert.equal(result.isError, true);
    assert.equal(calls, 0);
  } finally {
    await connection.close();
  }
});

test('real grocery planning emits only validated queries and keeps all three cost concepts empty', async () => {
  const identityResolver = new CuratedIngredientIdentityResolver();
  const plugin = new SmartCartPluginService({
    analyzer: new RecipeTextAnalyzer(),
    identityResolver,
    groceryTripPlanner: new GroceryTripPlanner({ identityResolver }),
    createTripIntelligence() { throw new Error('nutrition is not needed for this test'); }
  });
  const result = await plugin.planGroceryTrip({
    recipes: [{
      title: 'Safe list',
      servings: 2,
      recipeText: `Ingredients
1 cup Parmesan cheese
% Cup All Purpose Flour
Salt to taste`
    }],
    pantryIngredientNames: ['salt']
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(result.trip.data.itemsToShop.map((item) => item.retailerQuery), ['Parmesan cheese']);
  assert.deepEqual(result.trip.data.pantrySatisfiedItems.map((item) => item.retailerQuery), ['Salt']);
  assert.equal(result.trip.data.unresolvedItems.length, 0);
  assert.equal(result.parseIssues[0].severity, 'blocking');
  assert.deepEqual(result.trip.data.costs, {
    status: 'requiresRetailerEvidence',
    currencyCode: null,
    recipeConsumptionCost: null,
    estimatedCheckoutCost: null,
    surplusValue: null,
    reason: 'No reviewed retailer prices or package observations were supplied. SmartCart does not invent costs.'
  });
});

test('handoff tool fails closed without leaking server configuration details', async () => {
  const identityResolver = new CuratedIngredientIdentityResolver();
  const plugin = new SmartCartPluginService({
    analyzer: new RecipeTextAnalyzer(),
    identityResolver,
    groceryTripPlanner: new GroceryTripPlanner({ identityResolver }),
    config: { env: 'production', smartCartHandoffTokenSecret: undefined }
  });
  const connection = await connectedClient(plugin);
  try {
    const result = await connection.client.callTool({
      name: 'create_smartcart_handoff',
      arguments: {
        recipes: [{
          recipe_text: '1 cup Parmesan cheese',
          title: 'Safe recipe',
          servings: 4,
          source_type: 'text'
        }]
      }
    });
    assert.equal(result.isError, true);
    assert.equal(result.structuredContent.error.code, 'handoff_unavailable');
    assert.equal(result.structuredContent.error.message, 'SmartCart could not create a handoff. Try again later.');
    assert.equal(JSON.stringify(result).includes('HANDOFF_TOKEN_SECRET'), false);
  } finally {
    await connection.close();
  }
});
