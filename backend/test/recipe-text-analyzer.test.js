import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { RecipeTextAnalyzer } from '../src/trip-intelligence/recipe-text-analyzer.js';

const requestId = '20000000-0000-4000-8000-000000000091';
const recipeId = '10000000-0000-4000-8000-000000000091';

test('text analyzer preserves evidence, fractions, semantic quantities, and preparations', async () => {
  const analyzer = new RecipeTextAnalyzer();
  const result = analyzer.analyze({
    recipeId,
    title: 'Parmesan test',
    servings: 4,
    recipeText: `Ingredients
1 1/2 cups finely grated Parmesan cheese
Olive oil, as needed
Salt to taste
Instructions
Mix everything together.`
  });
  const envelope = {
    schemaVersion: '1.0',
    resolverVersion: result.resolverVersion,
    requestId,
    data: result.data
  };
  const validator = await createContractValidator({ contractsRoot: path.resolve('..', 'contracts') });
  validator.assert(
    'https://schemas.smartcart.app/v1/recipe/recipe-analysis-result.schema.json',
    envelope
  );

  assert.equal(result.data.ingredients.length, 3);
  assert.deepEqual(result.data.ingredients[0].quantity, {
    kind: 'numeric', value: 1.5, minimumValue: null, unit: 'cups'
  });
  assert.equal(result.data.ingredients[0].name, 'Parmesan cheese');
  assert.equal(result.data.ingredients[0].preparation, 'finely grated');
  assert.deepEqual(result.data.ingredients[1].quantity, { kind: 'semantic', text: 'as needed' });
  assert.equal(result.data.ingredients[2].quantity.text, 'to taste');
  assert.equal(result.data.evidence.some((entry) => entry.description === 'Mix everything together.'), true);
  assert.equal(result.data.issues.length, 0);
});

test('text analyzer blocks malformed measurements and never invents quantity one', () => {
  const analyzer = new RecipeTextAnalyzer();
  const result = analyzer.analyze({
    recipeId,
    title: 'Unsafe test',
    servings: 1,
    recipeText: `% Cup All Purpose Flour
Fresh basil`
  });

  assert.equal(result.data.ingredients.length, 1);
  assert.equal(result.data.ingredients[0].name, 'Fresh basil');
  assert.equal(result.data.ingredients[0].quantity, null);
  assert.equal(result.data.issues.length, 1);
  assert.equal(result.data.issues[0].severity, 'blocking');
  assert.equal(result.data.evidence[0].description, '% Cup All Purpose Flour');
});

test('text analyzer excludes headings and instruction sections from ingredient outputs', () => {
  const analyzer = new RecipeTextAnalyzer();
  const result = analyzer.analyze({
    recipeId,
    title: 'Boundary test',
    servings: 2,
    recipeText: `INGREDIENTS:
2 lb chicken breast
DIRECTIONS:
Add chicken to a pan.
1 cup misleading instruction sugar`
  });

  assert.deepEqual(result.data.ingredients.map((ingredient) => ingredient.name), ['chicken breast']);
});
