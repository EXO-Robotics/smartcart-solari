import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import * as z from 'zod/v4';
import { SmartCartPluginService } from './smartcart-plugin-service.js';

const recipeInput = {
  recipe_text: z.string().min(1).max(50_000).describe('A clear text ingredient list, ideally one ingredient per line.'),
  title: z.string().min(1).max(300).default('Imported Recipe'),
  servings: z.number().positive().max(10_000).default(4)
};

function toolResult(operation, data) {
  const structuredContent = { schemaVersion: '1.0', operation, ...data };
  return {
    content: [{ type: 'text', text: JSON.stringify(structuredContent, null, 2) }],
    structuredContent
  };
}

function toolError(operation, error) {
  const structuredContent = {
    schemaVersion: '1.0',
    operation,
    error: {
      code: typeof error?.code === 'string' ? error.code : 'trip_intelligence_error',
      message: typeof error?.message === 'string'
        ? error.message
        : 'SmartCart could not complete the request.',
      retryable: Boolean(error?.retryable)
    }
  };
  return {
    isError: true,
    content: [{ type: 'text', text: JSON.stringify(structuredContent, null, 2) }],
    structuredContent
  };
}

export function createSmartCartMcpServer(options = {}) {
  const pluginService = options.pluginService ?? new SmartCartPluginService(options);
  const server = new McpServer({ name: 'smartcart-trip-intelligence', version: '0.1.0' });

  server.registerTool('analyze_recipe', {
    title: 'Analyze recipe',
    description: 'Conservatively turn a text ingredient list into reviewed SmartCart ingredient contracts. Preserves source lines, semantic quantities, and blocking issues; it does not shop or mutate an account.',
    inputSchema: recipeInput
  }, async ({ recipe_text: recipeText, title, servings }) => {
    try {
      return toolResult('analyze_recipe', {
        analysis: pluginService.analyzeRecipe({ recipeText, title, servings })
      });
    } catch (error) {
      return toolError('analyze_recipe', error);
    }
  });

  server.registerTool('estimate_recipe', {
    title: 'Estimate recipe nutrition',
    description: 'Analyze a recipe and estimate calories and protein from server-side USDA evidence. Returns ranges and resolver evidence; unresolved quantities remain unresolved rather than becoming one.',
    inputSchema: recipeInput
  }, async ({ recipe_text: recipeText, title, servings }) => {
    try {
      return toolResult('estimate_recipe', await pluginService.estimateRecipe({ recipeText, title, servings }));
    } catch (error) {
      return toolError('estimate_recipe', error);
    }
  });

  server.registerTool('prepare_meal_plan', {
    title: 'Prepare meal plan',
    description: 'Analyze and aggregate nutrition for multiple recipes while preserving each recipe serving scale. This stateless tool does not save or modify a SmartCart account.',
    inputSchema: {
      recipes: z.array(z.object(recipeInput)).min(1).max(30)
    }
  }, async ({ recipes }) => {
    try {
      return toolResult('prepare_meal_plan', await pluginService.prepareMealPlan({
        recipes: recipes.map(({ recipe_text: recipeText, ...recipe }) => ({ ...recipe, recipeText }))
      }));
    } catch (error) {
      return toolError('prepare_meal_plan', error);
    }
  });

  server.registerTool('plan_grocery_trip', {
    title: 'Plan grocery trip',
    description: 'Build a stateless shopping-identity plan from recipe text and optional pantry names. Only validated canonical ingredient names become retailer queries. Costs remain unavailable until reviewed retailer package evidence exists.',
    inputSchema: {
      recipes: z.array(z.object(recipeInput)).min(1).max(30),
      pantry_ingredients: z.array(z.string().min(1).max(300)).max(500).default([])
    }
  }, async ({ recipes, pantry_ingredients: pantryIngredientNames }) => {
    try {
      return toolResult('plan_grocery_trip', await pluginService.planGroceryTrip({
        recipes: recipes.map(({ recipe_text: recipeText, ...recipe }) => ({ ...recipe, recipeText })),
        pantryIngredientNames
      }));
    } catch (error) {
      return toolError('plan_grocery_trip', error);
    }
  });

  return server;
}
