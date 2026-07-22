import assert from 'node:assert/strict';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import test from 'node:test';
import { createPublicBarcodeApi } from '../src/public-barcode-api.js';
import { BarcodeProviderError } from '../src/services/barcode-catalog.js';

const silentLogger = { debug() {}, info() {}, warn() {}, error() {} };

async function listen(barcodeCatalog) {
  const { handler } = createPublicBarcodeApi({
    logger: silentLogger,
    barcodeCatalog,
    config: { host: '127.0.0.1', port: 0 }
  });
  const server = createServer(handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  return {
    baseURL: `http://127.0.0.1:${address.port}`,
    async close() {
      server.close();
      await once(server, 'close');
    }
  };
}

test('public function surface serves only health and barcode lookup methods', async () => {
  const service = await listen({
    async resolve(gtin) {
      assert.equal(gtin, '078742002163');
      return {
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
      };
    }
  });

  try {
    const health = await fetch(`${service.baseURL}/health`);
    assert.equal(health.status, 200);
    assert.equal(health.headers.get('x-smartcart-data-mode'), 'crowdsourced-catalog');
    assert.deepEqual(
      Object.keys(await health.json()).sort(),
      ['service', 'status', 'timestamp', 'version']
    );

    const head = await fetch(`${service.baseURL}/health`, { method: 'HEAD' });
    assert.equal(head.status, 200);
    assert.equal(await head.text(), '');

    const resolved = await fetch(`${service.baseURL}/v1/barcodes/078742002163`);
    assert.equal(resolved.status, 200);
    const payload = await resolved.json();
    assert.equal(payload.product.quantity, '16 oz');
    assert.equal(payload.product.imageURL, 'https://images.openfoodfacts.org/product.jpg');
    assert.equal(payload.source, 'open_food_facts');
    assert.equal(payload.product.price, undefined);
    assert.equal(payload.product.availability, undefined);

    for (const [path, method] of [
      ['/health', 'POST'],
      ['/v1/barcodes/078742002163', 'HEAD'],
      ['/v1/demo/accounts', 'POST'],
      ['/v1/manifests', 'POST'],
      ['/api/index.js', 'GET'],
      ['/anything?route=health', 'GET']
    ]) {
      const response = await fetch(`${service.baseURL}${path}`, { method });
      assert.equal(response.status, 404, `${method} ${path}`);
    }
  } finally {
    await service.close();
  }
});

test('public barcode lookup keeps a true miss distinct from provider failure responses', async (t) => {
  const cases = [
    { name: 'true miss', result: { status: 'not_found', barcode: '00078742002163' }, status: 200, code: null },
    { name: 'rate limit', error: new BarcodeProviderError('rate_limited'), status: 429, code: 'barcode_provider_rate_limited' },
    { name: 'timeout', error: new BarcodeProviderError('timed_out'), status: 504, code: 'barcode_provider_timed_out' },
    { name: 'unavailable', error: new BarcodeProviderError('unavailable'), status: 503, code: 'barcode_provider_unavailable' },
    { name: 'upstream', error: new BarcodeProviderError('upstream_error'), status: 502, code: 'barcode_provider_upstream_error' },
    { name: 'malformed', error: new BarcodeProviderError('malformed_response'), status: 502, code: 'barcode_provider_malformed_response' }
  ];

  for (const entry of cases) {
    await t.test(entry.name, async () => {
      const service = await listen({
        async resolve() {
          if (entry.error) throw entry.error;
          return entry.result;
        }
      });
      try {
        const response = await fetch(`${service.baseURL}/v1/barcodes/078742002163`);
        assert.equal(response.status, entry.status);
        const payload = await response.json();
        if (entry.code) {
          assert.equal(payload.error.code, entry.code);
          assert.doesNotMatch(JSON.stringify(payload), /not_found/);
        } else {
          assert.equal(payload.status, 'not_found');
        }
      } finally {
        await service.close();
      }
    });
  }
});

test('Vercel rewrite destination parameters reach the same narrow handler', async () => {
  const service = await listen({
    async resolve(gtin) {
      return { status: 'not_found', barcode: gtin };
    }
  });
  try {
    const health = await fetch(`${service.baseURL}/api/index.js?route=health`);
    assert.equal(health.status, 200);

    const barcode = await fetch(
      `${service.baseURL}/api/index.js?route=barcode&gtin=078742002163`
    );
    assert.equal(barcode.status, 200);
    assert.equal((await barcode.json()).barcode, '078742002163');
  } finally {
    await service.close();
  }
});

test('Vercel config restricts dynamic routes while allowing reviewed static Weekly Meals files', async () => {
  const config = JSON.parse(await readFile(new URL('../vercel.json', import.meta.url), 'utf8'));
  assert.deepEqual(Object.keys(config.functions), ['api/index.js']);
  assert.deepEqual(config.routes, [
    { handle: 'filesystem' },
    {
      src: '/health',
      methods: ['GET', 'HEAD'],
      dest: '/api/index.js?route=health'
    },
    {
      src: '/v1/barcodes/(?<gtin>\\d{8,14})',
      methods: ['GET'],
      dest: '/api/index.js?route=barcode&gtin=$gtin'
    },
    { src: '/.*', status: 404 }
  ]);
  const entrypoint = await readFile(new URL('../api/index.js', import.meta.url), 'utf8');
  assert.match(entrypoint, /createPublicBarcodeApi/);
  assert.doesNotMatch(entrypoint, /createApp|LocalDemoStore|oauth|manifest|session/iu);
});
