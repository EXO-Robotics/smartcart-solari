import assert from 'node:assert/strict';
import test from 'node:test';
import { SmartCartPluginService } from '../src/mcp/smartcart-plugin-service.js';
import { CuratedIngredientIdentityResolver } from '../src/trip-intelligence/curated-ingredient-identity-resolver.js';
import { GroceryTripPlanner } from '../src/trip-intelligence/grocery-trip-planner.js';
import { RecipeTextAnalyzer } from '../src/trip-intelligence/recipe-text-analyzer.js';

function plugin() {
  const identityResolver = new CuratedIngredientIdentityResolver();
  return new SmartCartPluginService({
    analyzer: new RecipeTextAnalyzer(),
    identityResolver,
    groceryTripPlanner: new GroceryTripPlanner({ identityResolver }),
    createTripIntelligence() { throw new Error('nutrition is not needed for retailer-query tests'); }
  });
}

function retailerQueries(result) {
  return result.trip.data.itemsToShop.map((item) => item.retailerQuery);
}

test('exact cookie fixture preserves 1 1/2 and strips only retailer-irrelevant preparation', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Chocolate Chip Cookie Bars',
      servings: 12,
      recipeText: `INGREDIENTS
1½ cups unsalted butter, melted
1 cup packed brown sugar
1 large egg
1 teaspoon vanilla extract
1 cup semi-sweet chocolate chips
INSTRUCTIONS
Whisk flour, baking powder, and salt together.`
    }]
  });

  assert.equal(result.readyToShop, true);
  assert.deepEqual(retailerQueries(result), [
    'unsalted butter',
    'brown sugar',
    'egg',
    'vanilla extract',
    'semi-sweet chocolate chips'
  ]);
  assert.equal(result.analyses[0].data.ingredients[0].quantity.value, 1.5);
  assert.equal(result.analyses[0].data.ingredients[0].preparation, 'melted');
  assert.equal(result.analyses[0].data.ingredients[1].preparation, 'packed');
});

test('Thai fixture queues only credible identities and blocks headings alternatives and cropped qualifiers', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Thai Infused Rum',
      servings: 6,
      recipeText: `For the Thai Infused Rum
1 lime
1/2 stalk lemongrass, coarsely chopped
1/4 cup shredded or flaked coconut
6 basil leaves
2 teaspoons grated fresh ginger
1.5 cups rum, preferably`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), ['lime', 'lemongrass', 'basil leaves', 'fresh ginger']);
  assert.deepEqual(
    result.parseIssues.map((issue) => issue.code),
    ['ingredient_heading_fragment', 'ingredient_alternative_unresolved', 'ingredient_parse_conflict']
  );
  assert.equal(result.analyses[0].data.ingredients[1].preparation, 'coarsely chopped');
});

test('orphan continuations preparation fragments and measurement conflicts never become queries', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Unsafe fragments',
      servings: 1,
      recipeText: `and salt
finely chopped
for garnish
1 cup 2 tbsp flour
Cup all-purpose flour`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), []);
  assert.deepEqual(new Set(result.parseIssues.map((issue) => issue.code)), new Set([
    'ingredient_orphan_continuation',
    'ingredient_preparation_fragment',
    'ingredient_measurement_conflict'
  ]));
});

test('subsection labels numbered instructions and qualifier fragments block without queries', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Non-ingredient rows',
      servings: 1,
      recipeText: `SAUCE:
MARINADE:
Garnish
preferably dark
1. Mix until smooth`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), []);
  assert.deepEqual(result.parseIssues.map((issue) => issue.code), [
    'ingredient_heading_fragment',
    'ingredient_heading_fragment',
    'ingredient_heading_fragment',
    'ingredient_preparation_fragment',
    'ingredient_instruction_fragment'
  ]);
});

test('known all-caps and colon subsection labels block while plausible food names remain valid', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Section labels',
      servings: 1,
      recipeText: `DOUGH
TOPPING:
FILLING
GLAZE:
ASSEMBLY
OPTIONAL
1 lb chicken
1 cup dough mix`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), ['chicken', 'dough mix']);
  assert.deepEqual(
    result.parseIssues.map((issue) => issue.code),
    Array(6).fill('ingredient_heading_fragment')
  );
});

test('an exact recipe-title line blocks without suppressing real ingredients', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Chicken Parmesan',
      servings: 4,
      recipeText: `Chicken Parmesan
1 lb chicken
1 cup Parmesan cheese`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), ['chicken', 'Parmesan cheese']);
  assert.deepEqual(result.parseIssues.map((issue) => issue.code), ['ingredient_title_duplicate']);
});

test('numbered prose and common imperative continuations block without queries', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Instruction fragments',
      servings: 1,
      recipeText: `2) Set aside
Set aside
Season with salt
until smooth
1 lb chicken`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), ['chicken']);
  assert.deepEqual(
    result.parseIssues.map((issue) => issue.code),
    Array(4).fill('ingredient_instruction_fragment')
  );
});

test('compact ASCII and en-dash quantity ranges parse without contaminating retailer queries', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Ranges',
      servings: 1,
      recipeText: `1-2 cups flour
1–2 cups sugar`
    }]
  });

  assert.equal(result.readyToShop, true);
  assert.deepEqual(retailerQueries(result), ['flour', 'sugar']);
  assert.deepEqual(
    result.analyses[0].data.ingredients.map((ingredient) => ingredient.quantity),
    [
      { kind: 'numeric', value: 2, minimumValue: 1, unit: 'cups' },
      { kind: 'numeric', value: 2, minimumValue: 1, unit: 'cups' }
    ]
  );
});

test('compact fraction quantities parse without leaking measurement text into queries', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Compact quantities',
      servings: 1,
      recipeText: `1/2cup sugar
1⁄2cup sugar
½cup sugar
1½cups flour`
    }]
  });

  assert.equal(result.readyToShop, true);
  assert.deepEqual(retailerQueries(result), ['sugar', 'flour']);
  assert.deepEqual(
    result.analyses[0].data.ingredients.map((ingredient) => ingredient.quantity.value),
    [0.5, 0.5, 0.5, 1.5]
  );
  assert.deepEqual(
    result.analyses[0].data.ingredients.map((ingredient) => ingredient.name),
    ['sugar', 'sugar', 'sugar', 'flour']
  );
});

test('a pipe-corrupted fraction blocks without a retailer query', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{ title: 'Malformed fraction', servings: 1, recipeText: '1|2 cup sugar' }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), []);
  assert.deepEqual(result.parseIssues.map((issue) => issue.code), ['ingredient_measurement_conflict']);
});

test('a second embedded measurement blocks a merged cross-ingredient row', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Merged row',
      servings: 1,
      recipeText: '1 cup flour 2 tbsp sugar'
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), []);
  assert.deepEqual(result.parseIssues.map((issue) => issue.code), ['ingredient_measurement_conflict']);
});

test('cross-count merges block while percentage milk remains a clean identity', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Count boundaries',
      servings: 1,
      recipeText: `2 eggs 1 onion
1 cup flour 2 eggs
eggs 2
1 cup 2% milk`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), ['2% milk']);
  assert.deepEqual(
    result.parseIssues.map((issue) => issue.code),
    Array(3).fill('ingredient_measurement_conflict')
  );
});

test('contextual bare headings and instruction fragments block while unspecified apples remain valid', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Context boundaries',
      servings: 1,
      recipeText: `Dough
1 cup flour
Sauce
1 cup tomatoes
Fold in chocolate chips
Transfer to a bowl
apples`
    }]
  });

  assert.equal(result.readyToShop, false);
  assert.deepEqual(retailerQueries(result), ['flour', 'tomatoes', 'apples']);
  assert.deepEqual(result.parseIssues.map((issue) => issue.code), [
    'ingredient_heading_fragment',
    'ingredient_heading_fragment',
    'ingredient_instruction_fragment',
    'ingredient_instruction_fragment'
  ]);
  assert.equal(result.analyses[0].data.ingredients.at(-1).quantity, null);
});

test('a Unicode fraction slash is recovered conservatively without changing its evidence', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{ title: 'Fraction', servings: 1, recipeText: '1⁄2 cup sugar' }]
  });

  assert.equal(result.readyToShop, true);
  assert.deepEqual(retailerQueries(result), ['sugar']);
  assert.equal(result.analyses[0].data.ingredients[0].quantity.value, 0.5);
  assert.equal(result.analyses[0].data.ingredients[0].sourceText, '1⁄2 cup sugar');
});

test('identity resolver independently refuses unsafe names when parsing is bypassed', async () => {
  const resolver = new CuratedIngredientIdentityResolver();
  const base = {
    ingredientId: '10000000-0000-4000-8000-000000000099',
    preparation: '',
    evidence: []
  };

  for (const name of [
    'shredded or flaked coconut',
    'and salt',
    'finely chopped',
    'Cup flour',
    'rum, preferably',
    'SAUCE:',
    'Garnish',
    'preferably dark',
    '1. Mix until smooth',
    'flour 2 tbsp sugar',
    'DOUGH',
    'TOPPING:',
    'Set aside',
    'Season with salt',
    'until smooth',
    '2) Set aside',
    'Fold in chocolate chips',
    'Transfer to a bowl',
    '1|2 cup sugar',
    'flour 2 eggs',
    'eggs 2'
  ]) {
    const identity = await resolver.resolve({ ...base, name });
    assert.equal(identity.safeForRetailerQuery, false, name);
    assert.equal('retailerQuery' in identity, false, name);
  }

  const butter = await resolver.resolve({ ...base, name: 'unsalted butter, melted' });
  assert.equal(butter.safeForRetailerQuery, true);
  assert.equal(butter.retailerQuery, 'unsalted butter');

  const alternativePreparation = await resolver.resolve({
    ...base,
    name: 'coconut',
    preparation: 'shredded or flaked'
  });
  assert.equal(alternativePreparation.safeForRetailerQuery, false);
  assert.equal('retailerQuery' in alternativePreparation, false);
});

test('product-defining modifiers and valid semantic quantities remain shoppable', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{
      title: 'Safe modifiers',
      servings: 4,
      recipeText: `1 lb boneless skinless chicken breast
1/4 cup reduced-sodium soy sauce
1 cup 2% milk
Pinch of fine salt
Fresh ginger as needed
Salt to taste
Cooking oil for frying`
    }]
  });

  assert.equal(result.readyToShop, true);
  assert.deepEqual(retailerQueries(result), [
    'boneless skinless chicken breast',
    'reduced-sodium soy sauce',
    '2% milk',
    'fine salt',
    'Fresh ginger',
    'Salt',
    'Cooking oil'
  ]);
  assert.deepEqual(
    result.analyses[0].data.ingredients.slice(4).map((ingredient) => ingredient.quantity),
    [
      { kind: 'semantic', text: 'as needed' },
      { kind: 'semantic', text: 'to taste' },
      { kind: 'semantic', text: 'for frying' }
    ]
  );
  assert.equal(result.analyses[0].data.ingredients[3].quantity, null);
});

test('food identities that share subsection words remain valid when they are not labels', async () => {
  const result = await plugin().planGroceryTrip({
    recipes: [{ title: 'Sauce product', servings: 1, recipeText: '1 cup sauce' }]
  });

  assert.equal(result.readyToShop, true);
  assert.deepEqual(retailerQueries(result), ['sauce']);
});
