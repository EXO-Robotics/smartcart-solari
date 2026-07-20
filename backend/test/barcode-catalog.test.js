import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { createServer } from '../src/app.js';
import {
  BarcodeCatalogService,
  normalizeGtin,
  OpenFoodFactsBarcodeProvider
} from '../src/services/barcode-catalog.js';

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
            nutriments: { energy: 999 },
            stores: 'Example Store'
          }
        })
      };
    }
  });

  const product = await provider.resolve('00078742002163');

  assert.match(request.url, /\/api\/v3\/product\/00078742002163/);
  assert.equal(request.options.headers['user-agent'], 'SmartCartTest/1.0 (https://example.test)');
  assert.deepEqual(product, {
    name: 'Penne Pasta',
    brand: 'Example Brand',
    quantity: '16 oz',
    imageURL: null
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
    (error) => error.name === 'AbortError'
  );
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
          product: { name: 'Penne Pasta', brand: 'Great Value', quantity: '16 oz', imageURL: null },
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
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(lines.at(-1).path, '/v1/barcodes/:gtin');
    assert.doesNotMatch(JSON.stringify(lines.at(-1)), /078742002163/);
  } finally {
    app.server.close();
    await once(app.server, 'close');
  }
});
