#!/usr/bin/env node
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, '../..');
const pluginRoot = path.join(repositoryRoot, 'plugins/smartcart-trip-intelligence');
const config = JSON.parse(await readFile(path.join(pluginRoot, '.mcp.json'), 'utf8'));
const serverConfig = config.mcpServers?.['smartcart-trip-intelligence'];

if (!serverConfig || typeof serverConfig.command !== 'string') {
  throw new Error('SmartCart plugin MCP configuration is missing.');
}

const inheritedEnvironment = Object.fromEntries(
  (serverConfig.env_vars ?? []).flatMap((name) => (
    typeof process.env[name] === 'string' ? [[name, process.env[name]]] : []
  ))
);
const transport = new StdioClientTransport({
  command: serverConfig.command,
  args: serverConfig.args ?? [],
  cwd: path.resolve(pluginRoot, serverConfig.cwd ?? '.'),
  env: inheritedEnvironment,
  stderr: 'pipe'
});
const stderr = [];
transport.stderr?.on('data', (chunk) => stderr.push(chunk.toString('utf8')));
const client = new Client({ name: 'smartcart-mcp-verifier', version: '1.0.0' });

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

try {
  await client.connect(transport);
  const listed = await client.listTools();
  const toolNames = listed.tools.map((tool) => tool.name).sort();
  assert(
    JSON.stringify(toolNames) === JSON.stringify([
      'analyze_recipe',
      'estimate_recipe',
      'plan_grocery_trip',
      'prepare_meal_plan'
    ]),
    `Unexpected MCP tools: ${toolNames.join(', ')}`
  );

  const analysis = await client.callTool({
    name: 'analyze_recipe',
    arguments: {
      title: 'MCP process verification',
      servings: 4,
      recipe_text: `Ingredients
1 cup finely grated Parmesan cheese
Olive oil, as needed
Instructions
Mix and serve.`
    }
  });
  assert(!analysis.isError, 'analyze_recipe returned an MCP error');
  assert(analysis.structuredContent?.analysis?.data?.ingredients?.length === 2, 'Recipe analysis did not return two ingredients');

  const trip = await client.callTool({
    name: 'plan_grocery_trip',
    arguments: {
      recipes: [{
        title: 'MCP process verification',
        servings: 4,
        recipe_text: `1 cup Parmesan cheese
Salt to taste`
      }],
      pantry_ingredients: ['Salt']
    }
  });
  assert(!trip.isError, 'plan_grocery_trip returned an MCP error');
  assert(trip.structuredContent?.readyToShop === true, 'Safe grocery plan was not marked ready');
  assert(trip.structuredContent?.trip?.data?.itemsToShop?.[0]?.retailerQuery === 'Parmesan cheese', 'Validated retailer query was not preserved');
  assert(trip.structuredContent?.trip?.data?.pantrySatisfiedItems?.[0]?.retailerQuery === 'Salt', 'Pantry context was not applied');
  assert(trip.structuredContent?.trip?.data?.costs?.estimatedCheckoutCost === null, 'Checkout cost must remain unavailable without retailer evidence');

  let liveNutrition = 'skipped-no-usda-key';
  if (process.env.USDA_FDC_API_KEY) {
    const estimate = await client.callTool({
      name: 'estimate_recipe',
      arguments: {
        title: 'USDA evidence verification',
        servings: 4,
        recipe_text: '1 cup Parmesan cheese'
      }
    });
    assert(!estimate.isError, 'estimate_recipe returned an MCP error');
    const nutrition = estimate.structuredContent?.nutrition?.data;
    assert(nutrition?.totals?.energyKilocalories?.preferred === 420, 'USDA energy estimate did not match the selected official record');
    assert(nutrition?.totals?.proteinGrams?.preferred === 28.42, 'USDA protein estimate did not match the selected official record');
    liveNutrition = 'passed';
  }

  process.stdout.write(`${JSON.stringify({
    status: 'passed',
    transport: 'stdio-child-process',
    configuredFrom: 'plugins/smartcart-trip-intelligence/.mcp.json',
    tools: toolNames,
    analyzeRecipe: 'passed',
    planGroceryTrip: 'passed',
    liveUsdaNutrition: liveNutrition
  }, null, 2)}\n`);
} catch (error) {
  if (stderr.length > 0) process.stderr.write(stderr.join(''));
  throw error;
} finally {
  await client.close();
}
