import { readFile, readdir, stat } from 'node:fs/promises';
import { basename, dirname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const backendRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const publicRoot = join(backendRoot, 'public');
const manifestPath = join(publicRoot, 'weekly-meals', 'manifest.json');
const schemaPath = join(publicRoot, 'weekly-meals', 'schema', 'collection-v1.schema.json');
const allowedUnits = new Set([
  '', 'as needed', 'can', 'clove', 'cup', 'each', 'g', 'kg', 'l', 'lb',
  'ml', 'oz', 'package', 'pinch', 'tbsp', 'to taste', 'tsp'
]);
const allowedSlots = new Set(['breakfast', 'lunch', 'dinner', 'snack']);
const publicNutritionStatuses = new Set(['editorialEstimate', 'calculated', 'verified']);
const costStatuses = new Set(['requiresVerification', 'editorialEstimate', 'calculated', 'verified']);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function requiredString(value, path) {
  assert(typeof value === 'string' && value.trim().length > 0, `${path} must be a nonempty string`);
}

function validDate(value, path) {
  requiredString(value, path);
  assert(Number.isFinite(Date.parse(value)), `${path} must be an ISO-8601 date`);
}

function validLocalDate(value, path) {
  requiredString(value, path);
  assert(/^\d{4}-\d{2}-\d{2}$/.test(value), `${path} must use YYYY-MM-DD`);
  assert(Number.isFinite(Date.parse(`${value}T00:00:00Z`)), `${path} is not a valid date`);
}

function unique(values, path) {
  assert(new Set(values).size === values.length, `${path} must be unique`);
}

function validateRecipe(recipe, index) {
  const path = `recipes[${index}]`;
  requiredString(recipe.id, `${path}.id`);
  assert(Number.isInteger(recipe.contentVersion) && recipe.contentVersion > 0, `${path}.contentVersion is invalid`);
  requiredString(recipe.title, `${path}.title`);
  requiredString(recipe.shortDescription, `${path}.shortDescription`);
  assert(Number.isInteger(recipe.defaultServings) && recipe.defaultServings > 0, `${path}.defaultServings is invalid`);
  requiredString(recipe.servingDescription, `${path}.servingDescription`);
  assert(Array.isArray(recipe.ingredients) && recipe.ingredients.length > 0, `${path}.ingredients must not be empty`);
  unique(recipe.ingredients.map((ingredient) => ingredient.id), `${path}.ingredient IDs`);

  for (const [ingredientIndex, ingredient] of recipe.ingredients.entries()) {
    const ingredientPath = `${path}.ingredients[${ingredientIndex}]`;
    requiredString(ingredient.id, `${ingredientPath}.id`);
    requiredString(ingredient.rawText, `${ingredientPath}.rawText`);
    requiredString(ingredient.name, `${ingredientPath}.name`);
    assert(typeof ingredient.unit === 'string' && allowedUnits.has(ingredient.unit.toLowerCase()), `${ingredientPath}.unit is unsupported`);
    if (ingredient.isQualitative) {
      assert(ingredient.quantity === null, `${ingredientPath}.quantity must be null when qualitative`);
    } else {
      assert(Number.isFinite(ingredient.quantity) && ingredient.quantity > 0, `${ingredientPath}.quantity must be positive`);
    }
  }

  assert(Array.isArray(recipe.instructions) && recipe.instructions.length > 0, `${path}.instructions must not be empty`);
  unique(recipe.instructions.map((instruction) => instruction.id), `${path}.instruction IDs`);
  recipe.instructions.forEach((instruction, instructionIndex) => {
    assert(instruction.id === instructionIndex + 1, `${path}.instructions must be contiguous from one`);
    requiredString(instruction.text, `${path}.instructions[${instructionIndex}].text`);
  });

  const metadata = recipe.metadata;
  assert(metadata && typeof metadata === 'object', `${path}.metadata is required`);
  for (const key of ['prepMinutes', 'cookMinutes', 'passiveMinutes']) {
    assert(Number.isInteger(metadata[key]) && metadata[key] >= 0, `${path}.metadata.${key} is invalid`);
  }
  requiredString(metadata.accessibilityDescription, `${path}.metadata.accessibilityDescription`);
  requiredString(metadata.imageAssetName, `${path}.metadata.imageAssetName`);
  assert(/^[A-Za-z0-9_-]+$/.test(metadata.imageAssetName), `${path}.metadata.imageAssetName is unsafe`);

  if (metadata.nutrition !== null) {
    const nutrition = metadata.nutrition;
    assert(publicNutritionStatuses.has(nutrition.verificationStatus), `${path}.nutrition status is not public`);
    assert(Number.isFinite(nutrition.caloriesPerServing) && nutrition.caloriesPerServing > 0, `${path}.nutrition calories are invalid`);
    assert(Number.isFinite(nutrition.proteinGramsPerServing) && nutrition.proteinGramsPerServing >= 0, `${path}.nutrition protein is invalid`);
    assert(nutrition.servingDefinition === recipe.servingDescription, `${path}.nutrition serving definition differs`);
  }

  if (metadata.costEstimate !== null) {
    const cost = metadata.costEstimate;
    assert(costStatuses.has(cost.status), `${path}.costEstimate status is invalid`);
    assert(cost.recipeID === recipe.id && cost.recipeContentVersion === recipe.contentVersion, `${path}.costEstimate version differs`);
    assert(cost.servingDefinition === recipe.servingDescription, `${path}.costEstimate serving definition differs`);
    assert(/^[A-Z]{3}$/.test(cost.currencyCode), `${path}.costEstimate currency is invalid`);
    if (cost.status === 'requiresVerification') {
      assert(cost.totalRecipeCost === null && cost.costPerServing === null, `${path}.costEstimate cannot expose an unverified price`);
    } else {
      assert(Number.isFinite(cost.totalRecipeCost) && cost.totalRecipeCost > 0, `${path}.costEstimate total is invalid`);
      assert(Number.isFinite(cost.costPerServing) && cost.costPerServing > 0, `${path}.costEstimate per-serving value is invalid`);
    }
  }
}

async function main() {
  const schema = JSON.parse(await readFile(schemaPath, 'utf8'));
  assert(schema.$schema === 'https://json-schema.org/draft/2020-12/schema', 'collection schema draft is unsupported');
  assert(schema.properties?.schemaVersion?.const === 1, 'collection schema version differs from the validator');

  const manifestBytes = await stat(manifestPath);
  assert(manifestBytes.size <= 64 * 1024, 'manifest.json exceeds 64 KiB');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert(manifest.schemaVersion === 1, 'manifest.schemaVersion must be 1');
  requiredString(manifest.currentCollectionID, 'manifest.currentCollectionID');
  validDate(manifest.publishedAt, 'manifest.publishedAt');
  assert(/^\d+(\.\d+)*$/.test(manifest.minimumAppVersion), 'manifest.minimumAppVersion is invalid');
  assert(/^\/weekly-meals\/collections\/[A-Za-z0-9_-]+-v\d+\.json$/.test(manifest.currentCollectionURL), 'manifest must point to an immutable collection URL');

  const relativeCollectionPath = normalize(manifest.currentCollectionURL.slice(1));
  assert(!relativeCollectionPath.startsWith('..'), 'manifest collection path escapes public root');
  const collectionPath = join(publicRoot, relativeCollectionPath);
  const collectionBytes = await stat(collectionPath);
  assert(collectionBytes.size <= 1024 * 1024, 'collection exceeds 1 MiB');
  const document = JSON.parse(await readFile(collectionPath, 'utf8'));

  assert(document.schemaVersion === 1, 'collection.schemaVersion must be 1');
  assert(document.id === manifest.currentCollectionID, 'manifest and collection IDs differ');
  assert(Number.isInteger(document.revision) && document.revision > 0, 'collection.revision is invalid');
  validDate(document.publishedAt, 'collection.publishedAt');
  assert(document.collection.id === document.id, 'collection wrapper and body IDs differ');
  assert(document.collection.contentSchemaVersion === 1, 'collection content schema is unsupported');
  requiredString(document.collection.title, 'collection.title');
  validLocalDate(document.collection.weekStartDate, 'collection.weekStartDate');
  validLocalDate(document.collection.weekEndDateExclusive, 'collection.weekEndDateExclusive');
  assert(document.collection.weekStartDate < document.collection.weekEndDateExclusive, 'collection date range is invalid');

  const entries = document.collection.entries;
  assert(Array.isArray(entries) && entries.length === 8, 'collection must contain exactly eight entries');
  unique(entries.map((entry) => entry.id), 'entry IDs');
  unique(entries.map((entry) => `${entry.recipeReference.recipeID}@${entry.recipeReference.contentVersion}`), 'recipe references');
  assert(entries.filter((entry) => entry.isFeatured).length === 1, 'collection must contain exactly one featured entry');
  assert(entries.map((entry) => entry.displayOrder).sort((a, b) => a - b).every((value, index) => value === index), 'displayOrder must be contiguous from zero');
  for (const slot of allowedSlots) {
    assert(entries.filter((entry) => entry.slot === slot).length === 2, `collection must contain exactly two ${slot} entries`);
  }

  assert(Array.isArray(document.recipes) && document.recipes.length === 8, 'collection must contain exactly eight recipe records');
  unique(document.recipes.map((recipe) => recipe.id), 'recipe IDs');
  document.recipes.forEach(validateRecipe);
  const recipesByID = new Map(document.recipes.map((recipe) => [recipe.id, recipe]));
  entries.forEach((entry, index) => {
    const recipe = recipesByID.get(entry.recipeReference.recipeID);
    assert(recipe, `entries[${index}] references a missing recipe`);
    assert(recipe.contentVersion === entry.recipeReference.contentVersion, `entries[${index}] recipe version differs`);
    assert(allowedSlots.has(entry.slot), `entries[${index}] slot is unsupported`);
  });

  assert(
    basename(collectionPath).endsWith(`-v${document.revision}.json`),
    'immutable collection filename must include its revision'
  );

  const collectionDirectory = join(publicRoot, 'weekly-meals', 'collections');
  const collectionFiles = (await readdir(collectionDirectory)).filter((name) => name.endsWith('.json'));
  const recipeVersions = new Map();
  const collectionVersions = new Map();
  for (const filename of collectionFiles) {
    const candidate = JSON.parse(await readFile(join(collectionDirectory, filename), 'utf8'));
    const collectionKey = `${candidate.id}@${candidate.revision}`;
    const collectionFingerprint = JSON.stringify(candidate.collection);
    assert(
      !collectionVersions.has(collectionKey) || collectionVersions.get(collectionKey) === collectionFingerprint,
      `${collectionKey} changes collection content without a revision bump`
    );
    collectionVersions.set(collectionKey, collectionFingerprint);

    for (const recipe of candidate.recipes ?? []) {
      const recipeKey = `${recipe.id}@${recipe.contentVersion}`;
      const recipeFingerprint = JSON.stringify(recipe);
      assert(
        !recipeVersions.has(recipeKey) || recipeVersions.get(recipeKey) === recipeFingerprint,
        `${recipeKey} changes recipe content without a contentVersion bump`
      );
      recipeVersions.set(recipeKey, recipeFingerprint);
    }
  }

  console.log(`Validated ${document.id} revision ${document.revision}: ${document.recipes.length} recipes`);
}

main().catch((error) => {
  console.error(`Weekly Meals validation failed: ${error.message}`);
  process.exitCode = 1;
});
