import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { createServer } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import {
  BarcodeCatalogService,
  BarcodeProviderError,
  normalizeGtin,
  OpenFoodFactsBarcodeProvider
} from '../src/services/barcode-catalog.js';

test('default Open Food Facts user agent identifies the public EXO-Robotics contact page', () => {
  assert.equal(
    loadConfig({}).openFoodFactsUserAgent,
    'SmartCartBeta/0.4 (https://github.com/EXO-Robotics)'
  );
});

test('GTIN normalization validates checksums and preserves canonical identity', () => {
  assert.equal(normalizeGtin('078742002163'), '00078742002163');
  assert.equal(normalizeGtin('96385074'), '00000096385074');
  assert.equal(normalizeGtin('078742002164'), null);
  assert.equal(normalizeGtin('abc'), null);
});

test('Open Food Facts provider sends an identifying user agent and returns identity only', async () => {
  let request;
  const provider = new OpenFoodFactsBarcodeProvider({
    userAgent: 'SmartCartTest/1.0 (https://example.test)',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        status: 200,
        json: async () => ({
          product: {
            product_name: 'Penne Pasta',
            brands: 'Example Brand',
            quantity: '16 oz',
            image_front_url: 'https://images.openfoodfacts.org/images/products/000/787/420/0216/front_en.jpg',
            nutriments: { energy: 999 },
            stores: 'Example Store'
          }
        })
      };
    }
  });

  const product = await provider.resolve('00078742002163');

  assert.match(request.url, /\/api\/v3\/product\/00078742002163/);
  assert.match(request.url, /image_front_url/);
  assert.equal(request.options.headers['user-agent'], 'SmartCartTest/1.0 (https://example.test)');
  assert.deepEqual(product, {
    name: 'Penne Pasta',
    brand: 'Example Brand',
    quantity: '16 oz',
    imageURL: 'https://images.openfoodfacts.org/images/products/000/787/420/0216/front_en.jpg'
  });
  assert.equal(product.price, undefined);
  assert.equal(product.availability, undefined);
  assert.equal(product.nutrition, undefined);
});

test('Open Food Facts provider aborts a stalled lookup at the configured timeout', async () => {
  const provider = new OpenFoodFactsBarcodeProvider({
    userAgent: 'SmartCartTest/1.0 (https://example.test)',
    timeoutMs: 5,
    fetchImpl: async (_url, { signal }) => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
    })
  });

  await assert.rejects(
    provider.resolve('00078742002163'),
    (error) => error instanceof BarcodeProviderError
      && error.kind === 'timed_out'
      && error.httpStatus === 504
  );
});

test('Open Food Facts provider distinguishes a true miss from typed provider failures', async (t) => {
  const cases = [
    {
      name: 'rate limit',
      response: new Response('{}', { status: 429 }),
      kind: 'rate_limited',
      status: 429
    },
    {
      name: 'upstream error',
      response: new Response('{}', { status: 503 }),
      kind: 'upstream_error',
      status: 502
    },
    {
      name: 'malformed JSON',
      response: new Response('{', { status: 200 }),
      kind: 'malformed_response',
      status: 502
    },
    {
      name: 'missing identity',
      response: new Response(JSON.stringify({ product: { quantity: '16 oz' } }), { status: 200 }),
      kind: 'malformed_response',
      status: 502
    }
  ];

  for (const entry of cases) {
    await t.test(entry.name, async () => {
      const provider = new OpenFoodFactsBarcodeProvider({
        userAgent: 'SmartCartTest/1.0 (https://example.test)',
        fetchImpl: async () => entry.response
      });
      await assert.rejects(
        provider.resolve('00078742002163'),
        (error) => error instanceof BarcodeProviderError
          && error.kind === entry.kind
          && error.httpStatus === entry.status
      );
    });
  }

  const missing = new OpenFoodFactsBarcodeProvider({
    userAgent: 'SmartCartTest/1.0 (https://example.test)',
    fetchImpl: async () => new Response('{}', { status: 404 })
  });
  assert.equal(await missing.resolve('00078742002163'), null);

  const offline = new OpenFoodFactsBarcodeProvider({
    userAgent: 'SmartCartTest/1.0 (https://example.test)',
    fetchImpl: async () => { throw new TypeError('network unavailable'); }
  });
  await assert.rejects(
    offline.resolve('00078742002163'),
    (error) => error instanceof BarcodeProviderError
      && error.kind === 'unavailable'
      && error.httpStatus === 503
  );
});

test('Open Food Facts provider drops unsafe or malformed image URLs', async () => {
  for (const image_front_url of [
    'http://images.openfoodfacts.org/product.jpg',
    'https://user:password@images.openfoodfacts.org/product.jpg',
    'not a URL'
  ]) {
    const provider = new OpenFoodFactsBarcodeProvider({
      userAgent: 'SmartCartTest/1.0 (https://example.test)',
      fetchImpl: async () => new Response(JSON.stringify({
        product: { product_name: 'Penne Pasta', image_front_url }
      }), { status: 200 })
    });
    assert.equal((await provider.resolve('00078742002163')).imageURL, null);
  }
});

test('catalog coalesces requests and caches positive and negative results separately', async () => {
  const calls = new Map();
  const provider = {
    async resolve(gtin) {
      calls.set(gtin, (calls.get(gtin) ?? 0) + 1);
      await Promise.resolve();
      return gtin === '00078742002163'
        ? { name: 'Penne Pasta', brand: null, quantity: '16 oz', imageURL: null }
        : null;
    }
  };
  const service = new BarcodeCatalogService({ provider });

  const [first, second] = await Promise.all([
    service.resolve('078742002163'),
    service.resolve('078742002163')
  ]);
  assert.deepEqual(first, second);
  assert.equal(calls.get('00078742002163'), 1);
  assert.equal((await service.resolve('078742002163')).status, 'resolved');
  assert.equal(calls.get('00078742002163'), 1);

  assert.equal((await service.resolve('041000303319')).status, 'not_found');
  assert.equal((await service.resolve('041000303319')).status, 'not_found');
  assert.equal(calls.get('00041000303319'), 1);
});

test('catalog does not cache provider failures as misses', async () => {
  let calls = 0;
  const provider = {
    async resolve() {
      calls += 1;
      if (calls === 1) throw new BarcodeProviderError('unavailable');
      return null;
    }
  };
  const service = new BarcodeCatalogService({ provider });

  await assert.rejects(
    service.resolve('078742002163'),
    (error) => error instanceof BarcodeProviderError && error.kind === 'unavailable'
  );
  assert.equal((await service.resolve('078742002163')).status, 'not_found');
  assert.equal((await service.resolve('078742002163')).status, 'not_found');
  assert.equal(calls, 2);
});

test('catalog process-local provider limit raises a typed rate-limit failure', async () => {
  const service = new BarcodeCatalogService({
    provider: { async resolve() { return null; } },
    rateLimit: 1
  });

  assert.equal((await service.resolve('078742002163')).status, 'not_found');
  await assert.rejects(
    service.resolve('041000303319'),
    (error) => error instanceof BarcodeProviderError
      && error.kind === 'rate_limited'
      && error.httpStatus === 429
  );
});

test('catalog response exposes only editable identity, quantity, image, and source', async () => {
  const service = new BarcodeCatalogService({
    provider: {
      async resolve() {
        return {
          name: 'Penne Pasta',
          brand: 'Example Brand',
          quantity: '16 oz',
          imageURL: 'https://images.openfoodfacts.org/product.jpg',
          price: 4.99,
          availability: 'in_stock',
          retailer: 'Example Store'
        };
      }
    }
  });

  const result = await service.resolve('078742002163');
  assert.deepEqual(result, {
    status: 'resolved',
    barcode: '00078742002163',
    product: {
      name: 'Penne Pasta',
      brand: 'Example Brand',
      quantity: '16 oz',
      imageURL: 'https://images.openfoodfacts.org/product.jpg'
    },
    source: 'open_food_facts',
    verified: false
  });
  assert.equal(result.product.price, undefined);
  assert.equal(result.product.availability, undefined);
  assert.equal(result.product.retailer, undefined);
});

test('barcode endpoint returns normalized product identity and redacts GTIN from logs', async () => {
  const lines = [];
  const logger = {
    debug() {},
    warn() {},
    error() {},
    info(_event, data) { lines.push(data); }
  };
  const app = createServer({
    logger,
    config: { host: '127.0.0.1', port: 0 },
    barcodeCatalog: {
      async resolve(gtin) {
        assert.equal(gtin, '078742002163');
        return {
          status: 'resolved',
          barcode: '00078742002163',
          product: {
            name: 'Penne Pasta',
            brand: 'Great Value',
            quantity: '16 oz',
            imageURL: 'https://images.openfoodfacts.org/product.jpg'
          },
          source: 'open_food_facts',
          verified: false
        };
      }
    }
  });
  app.server.listen(0, '127.0.0.1');
  await once(app.server, 'listening');

  try {
    const address = app.server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/barcodes/078742002163`);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.status, 'resolved');
    assert.equal(body.verified, false);
    assert.equal(body.product.name, 'Penne Pasta');
    assert.equal(body.product.quantity, '16 oz');
    assert.equal(body.product.imageURL, 'https://images.openfoodfacts.org/product.jpg');
    assert.equal(body.source, 'open_food_facts');
    assert.equal(body.product.price, undefined);
    assert.equal(body.product.availability, undefined);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(lines.at(-1).path, '/v1/barcodes/:gtin');
    assert.doesNotMatch(JSON.stringify(lines.at(-1)), /078742002163/);
  } finally {
    app.server.close();
    await once(app.server, 'close');
  }
});

test('barcode endpoint preserves typed provider failure HTTP status', async () => {
  const app = createServer({
    logger: { debug() {}, warn() {}, error() {}, info() {} },
    config: { host: '127.0.0.1', port: 0 },
    barcodeCatalog: {
      async resolve() { throw new BarcodeProviderError('rate_limited'); }
    }
  });
  app.server.listen(0, '127.0.0.1');
  await once(app.server, 'listening');

  try {
    const address = app.server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/barcodes/078742002163`);
    assert.equal(response.status, 429);
    const body = await response.json();
    assert.equal(body.error.code, 'barcode_provider_rate_limited');
    assert.doesNotMatch(JSON.stringify(body), /not_found/);
  } finally {
    app.server.close();
    await once(app.server, 'close');
  }
});
