import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import * as z from 'zod/v4';
import { SmartCartPluginService } from './smartcart-plugin-service.js';

const recipeInput = {
  recipe_text: z.string().min(1).max(50_000).describe('A clear text ingredient list, ideally one ingredient per line.'),
  title: z.string().min(1).max(300).default('Imported Recipe'),
  servings: z.number().positive().max(10_000).default(4)
};

const handoffRecipeInput = {
  recipe_text: z.string().min(1).max(50_000).describe('The exact ingredient-list text. Preserve the source wording and never infer missing text from a photo.'),
  title: z.string().min(1).max(300).default('Imported Recipe'),
  servings: z.number().int().positive().max(48).default(4),
  source_type: z.enum(['text', 'image_transcription']).describe('Use image_transcription whenever any recipe text came from an uploaded image. Its numeric quantities must be confirmed in SmartCart before shopping.')
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

const publicHandoffErrorCodes = new Set([
  'handoff_limits_exceeded',
  'handoff_not_safe',
  'handoff_payload_too_large',
  'handoff_review_contract_invalid',
  'handoff_servings_out_of_range',
  'handoff_token_too_large'
]);

function handoffToolError(error) {
  if (publicHandoffErrorCodes.has(error?.code)) return toolError('create_smartcart_handoff', error);
  const unavailable = new Error('SmartCart could not create a handoff. Try again later.');
  unavailable.code = 'handoff_unavailable';
  unavailable.retryable = true;
  return toolError('create_smartcart_handoff', unavailable);
}

export function createSmartCartMcpServer(options = {}) {
  const pluginService = options.pluginService ?? new SmartCartPluginService(options);
  const server = new McpServer({ name: 'smartcart-trip-intelligence', version: '0.2.0' });

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

  server.registerTool('create_smartcart_handoff', {
    title: 'Open grocery plan in SmartCart',
    description: 'Create a short-lived, bounded-use encrypted link for the native SmartCart app. This returns a link but does not mutate the phone or Safari queue; native import begins only after the user opens it. The server re-analyzes every recipe and refuses unsafe retailer queries. Set source_type to image_transcription for any uploaded-photo transcription so SmartCart requires confirmation of every numeric quantity before Safari shopping.',
    inputSchema: {
      recipes: z.array(z.object(handoffRecipeInput)).min(1).max(5)
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    }
  }, async ({ recipes }) => {
    try {
      const maximumServings = recipes.length === 1 ? 24 : 48;
      if (recipes.some((recipe) => recipe.servings > maximumServings)) {
        const error = new Error(
          recipes.length === 1
            ? 'A single SmartCart recipe supports at most 24 servings.'
            : 'Each SmartCart Meal Prep recipe supports at most 48 servings.'
        );
        error.code = 'handoff_servings_out_of_range';
        throw error;
      }
      return toolResult('create_smartcart_handoff', {
        handoff: await pluginService.createSmartCartHandoff({
          recipes: recipes.map(({ recipe_text: recipeText, source_type: sourceType, ...recipe }) => ({
            ...recipe,
            recipeText,
            sourceType
          }))
        })
      });
    } catch (error) {
      return handoffToolError(error);
    }
  });

  return server;
}
