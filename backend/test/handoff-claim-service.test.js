import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { contractEnvelope } from '../src/contracts/envelope.js';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { createHandoffClaimService } from '../src/handoff/create-handoff-claim-service.js';
import { HandoffClaimError, HandoffClaimService } from '../src/handoff/handoff-claim-service.js';
import { RecipeTextAnalyzer } from '../src/trip-intelligence/recipe-text-analyzer.js';
import { SmartCartPluginService } from '../src/mcp/smartcart-plugin-service.js';
import { CuratedIngredientIdentityResolver } from '../src/trip-intelligence/curated-ingredient-identity-resolver.js';
import { GroceryTripPlanner } from '../src/trip-intelligence/grocery-trip-planner.js';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(testDirectory, '../..');
const secret = Buffer.alloc(32, 0x45).toString('base64url');

function recipe({
  recipeText = '1 cup Parmesan cheese\nSalt to taste',
  sourceType = 'text',
  servings = 4,
  index = 1
} = {}) {
  const recipeId = `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`;
  const analyzed = new RecipeTextAnalyzer().analyze({
    recipeId,
    title: `Recipe ${index}`,
    servings,
    recipeText
  });
  const analysis = contractEnvelope({
    requestId: `10000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
    ...analyzed
  });
  return {
    sourceType,
    recipeText,
    analysis,
    quantityReviewIngredientIds: sourceType === 'image_transcription'
      ? analysis.data.ingredients
        .filter((ingredient) => ingredient.quantity?.kind === 'numeric')
        .map((ingredient) => ingredient.ingredientId)
      : []
  };
}

function service(options = {}) {
  return new HandoffClaimService({
    secret,
    baseUrl: 'https://smartcart.example',
    now: () => Date.UTC(2026, 7, 19, 12, 0, 0),
    randomBytesImpl: () => Buffer.alloc(12, 0x2a),
    ...options
  });
}

test('sealed handoff keeps the bearer in the URL fragment and round-trips a frozen recipe', async () => {
  const claimService = service();
  const created = await claimService.create({ recipes: [recipe()] });
  const url = new URL(created.data.claimUrl);
  assert.equal(url.protocol, 'https:');
  assert.equal(url.pathname, '/t');
  assert.equal(url.search, '');
  assert.match(url.hash, /^#v1\.[A-Za-z0-9_-]+$/u);
  assert.equal(created.data.claimUrl.includes('Parmesan'), false);

  const payload = await claimService.claim({ token: url.hash.slice(1) });
  assert.equal(payload.data.audience, 'smartcart-ios');
  assert.equal(payload.data.recipes.length, 1);
  assert.equal(payload.data.recipes[0].analysis.data.title, 'Recipe 1');
  assert.equal(payload.data.recipes[0].recipeText, '1 cup Parmesan cheese\nSalt to taste');
  assert.equal('trip' in payload.data, false);
  assert.equal(JSON.stringify(payload).includes('http://'), false);
  assert.equal(JSON.stringify(payload).includes('https://'), false);
  assert.equal(JSON.stringify(payload).includes('estimatedCheckoutCost'), false);

  const replayWithinTtl = await claimService.claim({ token: url.hash.slice(1) });
  assert.deepEqual(replayWithinTtl, payload);
});

test('image transcriptions require every numeric ingredient quantity to be reviewed', async () => {
  const claimService = service();
  const imageRecipe = recipe({ sourceType: 'image_transcription' });
  const created = await claimService.create({ recipes: [imageRecipe] });
  const payload = await claimService.claim({ token: new URL(created.data.claimUrl).hash.slice(1) });
  const ids = payload.data.recipes[0].quantityReviewIngredientIds;
  assert.equal(ids.length, 1);
  assert.equal(ids[0], payload.data.recipes[0].analysis.data.ingredients[0].ingredientId);

  imageRecipe.quantityReviewIngredientIds = [];
  await assert.rejects(
    claimService.create({ recipes: [imageRecipe] }),
    (error) => error instanceof HandoffClaimError && error.code === 'handoff_review_contract_invalid'
  );
});

test('plugin re-plans server-side, freezes stable analysis IDs, and rejects unsafe queries', async () => {
  const identityResolver = new CuratedIngredientIdentityResolver();
  const claims = service();
  const plugin = new SmartCartPluginService({
    analyzer: new RecipeTextAnalyzer(),
    identityResolver,
    groceryTripPlanner: new GroceryTripPlanner({ identityResolver }),
    handoffClaim: claims,
    createTripIntelligence() { throw new Error('Nutrition is not part of handoff creation.'); }
  });
  const handoff = await plugin.createSmartCartHandoff({
    recipes: [{
      title: 'Photo recipe',
      servings: 4,
      sourceType: 'image_transcription',
      recipeText: '1 cup Parmesan cheese\nSalt to taste'
    }]
  });
  const payload = await claims.claim({ token: new URL(handoff.data.claimUrl).hash.slice(1) });
  const imported = payload.data.recipes[0];
  assert.equal(imported.analysis.data.recipeId.length, 36);
  assert.equal(imported.quantityReviewIngredientIds.length, 1);
  assert.equal(imported.analysis.data.ingredients[0].ingredientId, imported.quantityReviewIngredientIds[0]);

  await assert.rejects(
    plugin.createSmartCartHandoff({
      recipes: [{
        title: 'Unsafe alternative',
        servings: 4,
        sourceType: 'text',
        recipeText: '1 cup shredded or flaked coconut'
      }]
    }),
    (error) => error.code === 'handoff_not_safe'
  );
});

test('tampered, wrong-key, and expired sealed handoffs fail with one generic response', async () => {
  let now = Date.UTC(2026, 7, 19, 12, 0, 0);
  const issuer = service({ now: () => now });
  const created = await issuer.create({ recipes: [recipe()] });
  const token = new URL(created.data.claimUrl).hash.slice(1);
  const final = token.endsWith('A') ? 'B' : 'A';
  const tampered = `${token.slice(0, -1)}${final}`;
  const otherKey = service({ secret: Buffer.alloc(32, 0x46).toString('base64url'), now: () => now });

  for (const attempt of [
    () => issuer.claim({ token: tampered }),
    () => otherKey.claim({ token })
  ]) {
    await assert.rejects(attempt, (error) => (
      error instanceof HandoffClaimError
      && error.status === 410
      && error.code === 'handoff_unavailable'
      && error.message === 'The SmartCart handoff is unavailable.'
    ));
  }

  now += 600_001;
  await assert.rejects(
    issuer.claim({ token }),
    (error) => error instanceof HandoffClaimError && error.code === 'handoff_unavailable'
  );
});

test('handoff limits reject rather than clamp recipes, servings, and token size', async () => {
  const claimService = service();
  await assert.rejects(
    claimService.create({ recipes: [recipe({ servings: 2.5 })] }),
    (error) => error.code === 'handoff_limits_exceeded'
  );
  await assert.rejects(
    claimService.create({ recipes: [recipe({ servings: 25 })] }),
    (error) => error.code === 'handoff_limits_exceeded'
  );
  await assert.rejects(
    claimService.create({ recipes: [recipe({ servings: 49 }), recipe({ index: 2 })] }),
    (error) => error.code === 'handoff_limits_exceeded'
  );
  await assert.rejects(
    claimService.create({ recipes: Array.from({ length: 6 }, (_, index) => recipe({ index: index + 1 })) }),
    (error) => error.code === 'handoff_limits_exceeded'
  );
  await assert.rejects(
    service({ maxTokenCharacters: 128 }).create({ recipes: [recipe()] }),
    (error) => error.code === 'handoff_token_too_large'
  );
});

test('handoff payload contract rejects fractional servings without narrowing general analysis', async () => {
  const claimService = service();
  const created = await claimService.create({ recipes: [recipe({ servings: 2 })] });
  const payload = await claimService.claim({ token: new URL(created.data.claimUrl).hash.slice(1) });
  payload.data.recipes[0].analysis.data.servings = 2.5;

  const validator = await createContractValidator();
  assert.equal(
    validator.validate(
      'https://schemas.smartcart.app/v1/handoff/smartcart-handoff-payload.schema.json',
      payload
    ).valid,
    false
  );
  assert.equal(
    validator.validate(
      'https://schemas.smartcart.app/v1/recipe/recipe-analysis-result.schema.json',
      payload.data.recipes[0].analysis
    ).valid,
    true
  );
});

test('factory fails closed without its independent secret and secure production origin', () => {
  assert.throws(
    () => createHandoffClaimService({ config: { env: 'production', smartCartHandoffTokenSecret: undefined } }),
    /HANDOFF_TOKEN_SECRET/u
  );
  assert.throws(
    () => createHandoffClaimService({
      config: {
        env: 'production',
        smartCartHandoffTokenSecret: secret,
        smartCartHandoffBaseUrl: undefined
      }
    }),
    /SMARTCART_HANDOFF_BASE_URL/u
  );
  assert.throws(
    () => service({ baseUrl: 'http://smartcart.example' }),
    /HTTPS origin/u
  );
  for (const baseUrl of [
    'https://user@smartcart.example',
    'https://smartcart.example/handoff',
    'https://smartcart.example?source=gpt',
    'https://smartcart.example#handoff'
  ]) {
    assert.throws(() => service({ baseUrl }), /HTTPS origin/u);
  }
});

test('handoff landing uses the exact bundled icon without custom-scheme token forwarding', async () => {
  const sourceIcon = await readFile(path.join(
    repositoryRoot,
    'SmartCart/Assets.xcassets/AppIcon.appiconset/SmartCart-AppIcon-1024.png'
  ));
  const handoffIcon = await readFile(path.join(repositoryRoot, 'backend/public/t/smartcart-icon.png'));
  const page = await readFile(path.join(repositoryRoot, 'backend/public/t/index.html'), 'utf8');
  assert.equal(createHash('sha256').update(handoffIcon).digest('hex'), createHash('sha256').update(sourceIcon).digest('hex'));
  assert.doesNotMatch(page, /window\.location|smartcart:\/\/|searchParams|\?token=|<script/u);
});

test('AASA associates only the /t Universal Link and Vercel serves it directly as JSON', async () => {
  const association = JSON.parse(await readFile(path.join(
    repositoryRoot,
    'backend/public/.well-known/apple-app-site-association.json'
  ), 'utf8'));
  assert.deepEqual(association, {
    applinks: {
      details: [{
        appIDs: ['WCNJVRP99K.com.blakestudio.smartcart'],
        components: [{
          '/': '/t',
          comment: 'Open a bounded SmartCart handoff.'
        }]
      }]
    }
  });

  const vercel = JSON.parse(await readFile(path.join(repositoryRoot, 'backend/vercel.json'), 'utf8'));
  const associationRoute = vercel.routes.find((candidate) => (
    candidate.src === '/\\.well-known/apple-app-site-association'
  ));
  assert.ok(associationRoute);
  assert.deepEqual(associationRoute.methods, ['GET', 'HEAD']);
  assert.equal(associationRoute.dest, '/.well-known/apple-app-site-association.json');
  assert.equal(associationRoute.headers['Content-Type'], 'application/json');
  assert.equal('status' in associationRoute, false);
  assert.equal(
    Object.keys(associationRoute.headers).some((key) => key.toLowerCase() === 'location'),
    false
  );

  assert.equal(
    vercel.routes.some((candidate) => candidate.src?.startsWith('/api/')),
    false,
    'Vercel function aliases are platform routes and must be covered by the same firewall policy.'
  );
});
