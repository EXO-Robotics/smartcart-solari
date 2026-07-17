import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { describe, test } from 'node:test';
import { createServer } from '../src/app.js';
import { RecipePageExtractor } from '../src/services/recipe-page-extractor.js';
import {
  RecipePageError,
  RecipePageFetcher,
  SMARTCART_RECIPE_USER_AGENT
} from '../src/services/recipe-page-fetcher.js';

const fixtureUrl = new URL('./fixtures/amycakes-style-recipe.html', import.meta.url);

function silentLogger() {
  return { debug() {}, info() {}, warn() {}, error() {} };
}

async function listen(options = {}) {
  const instance = createServer({ logger: silentLogger(), ...options, config: { port: 0, ...options.config } });
  await new Promise((resolve, reject) => {
    instance.server.once('error', reject);
    instance.server.listen(0, '127.0.0.1', resolve);
  });
  const address = instance.server.address();
  return {
    ...instance,
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolve, reject) => instance.server.close((error) => error ? reject(error) : resolve()))
  };
}

async function request(baseUrl, path, { body, token } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {})
    },
    body: JSON.stringify(body)
  });
  return { response, payload: await response.json() };
}

async function demoToken(service) {
  const account = await request(service.baseUrl, '/v1/demo/accounts', {
    body: { displayName: 'Recipe Tester', email: 'recipe@example.local' }
  });
  const session = await request(service.baseUrl, '/v1/demo/sessions', {
    body: { accountId: account.payload.account.id }
  });
  return session.payload.session.token;
}

describe('RecipePageExtractor', () => {
  const extractor = new RecipePageExtractor();

  test('extracts Recipe JSON-LD from objects, arrays, @graph, and nested values', () => {
    const documents = [
      { '@type': 'Recipe', name: 'Object Recipe', recipeIngredient: ['1 cup oats'] },
      [{ '@type': 'Recipe', name: 'Array Recipe', recipeIngredient: ['1 cup rice'] }],
      { '@graph': [{ '@type': 'Recipe', name: 'Graph Recipe', recipeIngredient: ['1 cup beans'] }] },
      { payload: { content: { '@type': ['Thing', 'Recipe'], name: 'Nested Recipe', ingredients: ['1 cup peas'] } } }
    ];

    for (const document of documents) {
      const result = extractor.extract(`<script type="application/ld+json">${JSON.stringify(document)}</script>`);
      assert.equal(result.extractionMethod, 'json-ld');
      assert.equal(result.ingredients.length, 1);
    }
  });

  test('selects the strongest of multiple JSON-LD recipe candidates deterministically', () => {
    const html = `
      <script type="application/ld+json">{"@type":"Recipe","name":"Teaser","recipeIngredient":["salt"]}</script>
      <script type="application/ld+json">[{"wrapper":{"@graph":[{"@type":"Recipe","name":"Full Recipe","recipeIngredient":["1 cup flour","2 eggs","1 cup milk"]}]}}]</script>`;
    const result = extractor.extract(html);
    assert.equal(result.name, 'Full Recipe');
    assert.deepEqual(result.ingredients, ['1 cup flour', '2 eggs', '1 cup milk']);
  });

  test('preserves nested JSON-LD ingredient sections without treating section names as ingredients', () => {
    const document = {
      '@type': 'Recipe',
      name: 'Layered Dip',
      recipeIngredient: [
        { name: 'Base', itemListElement: ['1 can beans', '1 cup rice'] },
        { name: 'Topping', ingredients: [{ name: '1 avocado' }] }
      ]
    };
    const result = extractor.extract(`<script type="application/ld+json">${JSON.stringify(document)}</script>`);
    assert.deepEqual(result.ingredients, ['1 can beans', '1 cup rice', '1 avocado']);
    assert.deepEqual(result.ingredientSections.map((section) => section.name), ['Base', 'Topping']);
  });

  test('saved Amycakes-style fixture has exactly 20 JSON-LD ingredients', async () => {
    const html = await readFile(fixtureUrl, 'utf8');
    const result = extractor.extract(html);
    assert.equal(result.extractionMethod, 'json-ld');
    assert.equal(result.ingredients.length, 20);
  });

  test('JSON-LD removal falls back with four sections and preserves linked, compound, and alternative text', async () => {
    const html = (await readFile(fixtureUrl, 'utf8')).replace(/<script\b[\s\S]*?<\/script>/i, '');
    const result = extractor.extract(html);
    assert.equal(result.extractionMethod, 'plugin');
    assert.equal(result.ingredients.length, 20);
    assert.deepEqual(result.ingredientSections.map((section) => section.name), [
      'Cake', 'Vanilla Syrup', 'Berry Filling', 'Frosting'
    ]);
    assert.ok(result.ingredients.includes('1 teaspoon vanilla extract'));
    assert.ok(result.ingredients.includes('1/4 cup + 2 tablespoons heavy cream'));
    assert.ok(result.ingredients.includes('1 cup fresh or frozen strawberries'));
  });

  test('microdata ingredients preserve section headings', () => {
    const result = extractor.extract(`
      <main itemscope itemtype="https://schema.org/Recipe"><h1>Flatbread</h1><h2>Ingredients</h2>
      <section><h3>Dough</h3><ul><li itemprop="recipeIngredient">2 cups flour</li></ul></section>
      <section><h3>Topping</h3><ul><li itemprop="recipeIngredient">1 cup tomatoes</li></ul></section></main>`);
    assert.equal(result.extractionMethod, 'microdata');
    assert.deepEqual(result.ingredientSections.map((section) => section.name), ['Dough', 'Topping']);
  });

  test('visible Ingredients fallback stops at instruction boundaries', () => {
    const result = extractor.extract(`
      <h1>Soup</h1><h2>Ingredients</h2><h3>Soup base</h3><ul><li>2 cups stock</li><li>1 onion</li></ul>
      <h2>Directions</h2><ol><li>Simmer for twenty minutes</li></ol>`);
    assert.equal(result.extractionMethod, 'visible');
    assert.deepEqual(result.ingredients, ['2 cups stock', '1 onion']);
    assert.deepEqual(result.ingredientSections, [{ name: 'Soup base', ingredients: ['2 cups stock', '1 onion'] }]);
  });

  test('visible fallback preserves legitimate repeated ingredients across sections', () => {
    const result = extractor.extract(`
      <h1>Layer Cake</h1><h2>Ingredients</h2>
      <h3>Cake</h3><ul><li>1 teaspoon vanilla</li><li>1 pinch salt</li></ul>
      <h3>Frosting</h3><ul><li>1 teaspoon vanilla</li><li>1 pinch salt</li></ul>
      <h2>Directions</h2><p>Mix each component.</p>`);

    assert.deepEqual(result.ingredientSections, [
      { name: 'Cake', ingredients: ['1 teaspoon vanilla', '1 pinch salt'] },
      { name: 'Frosting', ingredients: ['1 teaspoon vanilla', '1 pinch salt'] }
    ]);
    assert.equal(result.ingredients.filter((item) => item === '1 teaspoon vanilla').length, 2);
    assert.equal(result.ingredients.filter((item) => item === '1 pinch salt').length, 2);
  });

  test('malformed JSON-LD is ignored in favor of fallback markup', () => {
    const result = extractor.extract(`
      <script type="application/ld+json">{"@type":"Recipe", broken}</script>
      <h1>Fallback</h1><h2>Ingredients</h2><ul><li>1 cup lentils</li></ul><h2>Instructions</h2>`);
    assert.equal(result.extractionMethod, 'visible');
    assert.deepEqual(result.ingredients, ['1 cup lentils']);
  });

  test('malformed pages without a recipe return a typed failure', () => {
    assert.throws(
      () => extractor.extract('<html><script type="application/ld+json">not json</script><p>Hello</p></html>'),
      (error) => error instanceof RecipePageError && error.code === 'recipe_not_found' && error.status === 422
    );
  });
});

describe('RecipePageFetcher', () => {
  test('rejects non-HTTPS URLs before making a request', async () => {
    let called = false;
    const fetcher = new RecipePageFetcher({ fetchImpl: async () => { called = true; } });
    await assert.rejects(fetcher.fetch('http://recipes.example/cake'), { code: 'recipe_page_https_required' });
    assert.equal(called, false);
  });

  test('follows relative HTTPS redirects, sends an identifiable user agent, and decodes Windows-1252', async () => {
    const requests = [];
    const fetcher = new RecipePageFetcher({
      fetchImpl: async (url, options) => {
        requests.push({ url: url.href, options });
        if (requests.length === 1) {
          return new Response(null, { status: 302, headers: { location: '/final' } });
        }
        const bytes = Uint8Array.from(Buffer.from('<h1>Caf\xe9</h1>', 'latin1'));
        return new Response(bytes, { headers: { 'content-type': 'text/html; charset=windows-1252' } });
      }
    });
    const page = await fetcher.fetch('https://recipes.example/start');
    assert.equal(page.originalUrl, 'https://recipes.example/start');
    assert.equal(page.finalUrl, 'https://recipes.example/final');
    assert.equal(page.redirectCount, 1);
    assert.equal(page.charset, 'windows-1252');
    assert.match(page.html, /Café/);
    assert.equal(requests[0].options.redirect, 'manual');
    assert.equal(requests[0].options.headers['user-agent'], SMARTCART_RECIPE_USER_AGENT);
  });

  test('rejects redirects that downgrade to HTTP', async () => {
    const fetcher = new RecipePageFetcher({
      fetchImpl: async () => new Response(null, { status: 302, headers: { location: 'http://recipes.example/final' } })
    });
    await assert.rejects(fetcher.fetch('https://recipes.example/start'), { code: 'unsafe_recipe_page_redirect' });
  });

  test('returns a precise typed failure for upstream 403', async () => {
    const fetcher = new RecipePageFetcher({ fetchImpl: async () => new Response('Forbidden', { status: 403 }) });
    await assert.rejects(
      fetcher.fetch('https://recipes.example/private'),
      (error) => error.code === 'recipe_page_access_denied'
        && error.status === 502
        && error.details.upstreamStatus === 403
    );
  });

  test('returns a precise typed timeout failure', async () => {
    const fetcher = new RecipePageFetcher({
      timeoutMs: 5,
      fetchImpl: async (_url, { signal }) => new Promise((_resolve, reject) => {
        signal.addEventListener('abort', () => {
          const error = new Error('aborted');
          error.name = 'AbortError';
          reject(error);
        }, { once: true });
      })
    });
    await assert.rejects(fetcher.fetch('https://recipes.example/slow'), {
      code: 'recipe_page_timeout',
      status: 504
    });
  });

  test('enforces MIME and streamed body-size limits', async () => {
    const wrongMime = new RecipePageFetcher({
      fetchImpl: async () => new Response('{}', { headers: { 'content-type': 'application/json' } })
    });
    await assert.rejects(wrongMime.fetch('https://recipes.example/data'), { code: 'unsupported_recipe_page_mime' });

    const oversized = new RecipePageFetcher({
      maxBytes: 4,
      fetchImpl: async () => new Response('12345', { headers: { 'content-type': 'text/html' } })
    });
    await assert.rejects(oversized.fetch('https://recipes.example/large'), { code: 'recipe_page_too_large' });
  });
});

test('authenticated recipe-page endpoint returns provenance without exposing fetched HTML', async () => {
  const service = await listen({
    recipePageFetcher: {
      async fetch(url) {
        return {
          originalUrl: url,
          finalUrl: 'https://recipes.example/final',
          redirectCount: 1,
          contentType: 'text/html',
          charset: 'utf-8',
          byteLength: 100,
          html: '<script type="application/ld+json">{"@type":"Recipe","name":"Toast","recipeIngredient":["2 slices bread"]}</script>'
        };
      }
    }
  });
  try {
    const token = await demoToken(service);
    const result = await request(service.baseUrl, '/v1/recipe-pages/extract', {
      token,
      body: { url: 'https://recipes.example/start' }
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.payload.page.originalUrl, 'https://recipes.example/start');
    assert.equal(result.payload.page.finalUrl, 'https://recipes.example/final');
    assert.deepEqual(result.payload.recipe.ingredients, ['2 slices bread']);
    assert.equal(result.payload.html, undefined);
    assert.equal(result.payload.meta.recipePageSource, 'user-requested-third-party-page');
  } finally {
    await service.close();
  }
});
