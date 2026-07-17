import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import { createServer } from '../src/app.js';
import {
  InstacartApiProvider,
  InstacartDemoProvider,
  InstacartHandoffService,
  instacartHandoffInternals
} from '../src/services/instacart-handoff.js';

function silentLogger() {
  return { debug() {}, info() {}, warn() {}, error() {} };
}

async function listen(options = {}) {
  const instance = createServer({
    logger: silentLogger(),
    config: { host: '127.0.0.1', port: 0, ...options.config },
    ...options
  });
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

async function jsonRequest(baseUrl, path, { method = 'GET', token, body } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(body ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {})
    },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  return { response, payload: await response.json() };
}

async function createIdentity(service, suffix) {
  const accountResult = await jsonRequest(service.baseUrl, '/v1/demo/accounts', {
    method: 'POST',
    body: { displayName: `Shopper ${suffix}`, email: `shopper-${suffix}@example.local` }
  });
  const sessionResult = await jsonRequest(service.baseUrl, '/v1/demo/sessions', {
    method: 'POST',
    body: { accountId: accountResult.payload.account.id }
  });
  return sessionResult.payload.session.token;
}

function handoffItem(overrides = {}) {
  return {
    ingredientID: crypto.randomUUID(),
    ingredientName: 'Black beans',
    requestedQuantity: '2 cans',
    purchaseQuantity: 2,
    product: { itemID: 'beans-demo', title: 'Black beans' },
    status: 'waiting',
    commerce: {
      name: 'black beans',
      displayText: '2 cans black beans',
      quantity: 2,
      unit: 'cans',
      healthFilters: ['organic', 'vegan', 'NOT_AN_OFFICIAL_FILTER'],
      exactUPC: '012345678905',
      exactIdentityReliable: true,
      quantityConfirmed: true,
      quantityConfidence: 'high',
      unresolvedAlternative: false,
      ...overrides
    }
  };
}

function manifest(items) {
  return {
    recipeID: crypto.randomUUID(),
    recipeTitle: 'Safe pantry dinner',
    retailerID: 'instacart',
    storeID: 'advisory-only',
    storeName: 'Instacart Marketplace',
    desiredServings: 4,
    fulfillmentMode: 'Pickup',
    items,
    handoffProgress: 'notStarted'
  };
}

class RecordingProvider {
  constructor() {
    this.name = 'instacart-test';
    this.presentationMode = 'in_app_safari';
    this.calls = [];
  }

  async create(payload, context) {
    this.calls.push({ payload, context });
    return 'https://www.instacart.com/store/shopping-lists/test-list';
  }
}

describe('authenticated Instacart handoff endpoint', () => {
  let service;
  let provider;
  let token;

  before(async () => {
    provider = new RecordingProvider();
    service = await listen({ instacartProvider: provider });
    token = await createIdentity(service, 'primary');
  });

  after(async () => {
    await service.close();
  });

  test('loads an owned manifest, filters exclusions, maps official fields, and reuses the fingerprint cache', async () => {
    const pantry = handoffItem({ pantryExcluded: true, unresolvedAlternative: true, quantityConfirmed: false });
    const optional = handoffItem({ optionalSelected: false, name: 'hot sauce' });
    const filterOnly = handoffItem({
      name: 'rolled oats',
      displayText: undefined,
      quantity: 1,
      unit: 'cup',
      exactIdentityReliable: false,
      quantityConfidence: undefined
    });
    const created = await jsonRequest(service.baseUrl, '/v1/manifests', {
      method: 'POST', token, body: { manifest: manifest([handoffItem(), filterOnly, pantry, optional]) }
    });
    assert.equal(created.response.status, 201);

    const request = {
      shoppingManifestId: created.payload.manifest.id,
      postalCode: '94105',
      preferredRetailerKey: 'sprouts',
      fulfillmentPreference: 'pickup'
    };
    const first = await jsonRequest(service.baseUrl, '/api/handoffs/instacart', {
      method: 'POST', token, body: request
    });
    const second = await jsonRequest(service.baseUrl, '/api/handoffs/instacart', {
      method: 'POST', token, body: request
    });

    assert.equal(first.response.status, 200);
    assert.equal(second.response.status, 200);
    assert.equal(provider.calls.length, 1);
    assert.deepEqual(first.payload, second.payload);
    assert.match(first.payload.manifestFingerprint, /^[a-f0-9]{64}$/);
    assert.equal(first.payload.provider, 'instacart-test');
    assert.equal(first.payload.presentationMode, 'in_app_safari');
    assert.equal(provider.calls[0].payload.line_items.length, 2);
    assert.deepEqual(provider.calls[0].payload.line_items[0], {
      name: 'black beans',
      display_text: '2 cans black beans',
      upcs: ['012345678905'],
      line_item_measurements: [{ quantity: 2, unit: 'can' }]
    });
    assert.equal(provider.calls[0].payload.line_items[0].quantity, undefined);
    assert.equal(provider.calls[0].payload.line_items[0].unit, undefined);
    assert.deepEqual(provider.calls[0].payload.line_items[1], {
      name: 'rolled oats',
      line_item_measurements: [{ quantity: 1, unit: 'cup' }],
      filters: { health_filters: ['ORGANIC', 'VEGAN'] }
    });
  });

  test('requires authentication and refuses manifests owned by another account', async () => {
    const created = await jsonRequest(service.baseUrl, '/v1/manifests', {
      method: 'POST', token, body: { manifest: manifest([handoffItem({ exactUPC: undefined })]) }
    });
    const body = {
      shoppingManifestId: created.payload.manifest.id,
      postalCode: '10001',
      fulfillmentPreference: 'delivery'
    };
    const unauthenticated = await jsonRequest(service.baseUrl, '/api/handoffs/instacart', { method: 'POST', body });
    assert.equal(unauthenticated.response.status, 401);

    const otherToken = await createIdentity(service, 'other');
    const unowned = await jsonRequest(service.baseUrl, '/api/handoffs/instacart', {
      method: 'POST', token: otherToken, body
    });
    assert.equal(unowned.response.status, 404);
    assert.equal(unowned.payload.error.code, 'manifest_not_found');
  });

  for (const [label, override, message] of [
    ['unresolved alternatives', { unresolvedAlternative: true }, /unresolved/],
    ['unconfirmed quantity', { quantityConfirmed: false }, /confirmed/],
    ['low-confidence quantity', { quantityConfidence: 'low' }, /confidence/],
    ['unsupported measurement', { unit: 'scoopful' }, /supported/]
  ]) {
    test(`rejects ${label} before provider access`, async () => {
      const beforeCalls = provider.calls.length;
      const created = await jsonRequest(service.baseUrl, '/v1/manifests', {
        method: 'POST', token, body: { manifest: manifest([handoffItem(override)]) }
      });
      const rejected = await jsonRequest(service.baseUrl, '/api/handoffs/instacart', {
        method: 'POST',
        token,
        body: {
          shoppingManifestId: created.payload.manifest.id,
          postalCode: 'M5V 3A8',
          fulfillmentPreference: 'pickup'
        }
      });
      assert.equal(rejected.response.status, 422);
      assert.match(rejected.payload.error.message, message);
      assert.equal(provider.calls.length, beforeCalls);
    });
  }
});

test('live provider sends the official 2026 payload and applies a verified retailer as advisory URL state', async () => {
  const calls = [];
  const fetchFn = async (url, options) => {
    calls.push({ url: url.toString(), options });
    if (options.method === 'POST') {
      return new Response(JSON.stringify({ products_link_url: 'https://www.instacart.com/store/lists/abc?source=test' }), {
        status: 200,
        headers: { 'content-type': 'application/json' }
      });
    }
    return new Response(JSON.stringify({ retailers: [{ retailer_key: 'sprouts', name: 'Sprouts' }] }), {
      status: 200,
      headers: { 'content-type': 'application/json' }
    });
  };
  const provider = new InstacartApiProvider({
    apiKey: 'server-only-secret',
    baseUrl: 'https://connect.dev.instacart.tools',
    fetchFn
  });
  const payload = { title: 'List', link_type: 'shopping_list', line_items: [{ name: 'milk' }] };
  const url = await provider.create(payload, {
    postalCode: '94105', countryCode: 'US', preferredRetailerKey: 'sprouts'
  });

  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, 'https://connect.dev.instacart.tools/idp/v1/products/products_link');
  assert.equal(calls[0].options.headers.authorization, 'Bearer server-only-secret');
  assert.deepEqual(JSON.parse(calls[0].options.body), payload);
  assert.equal(calls[1].url, 'https://connect.dev.instacart.tools/idp/v1/retailers?postal_code=94105&country_code=US');
  assert.equal(new URL(url).searchParams.get('retailer_key'), 'sprouts');
});

test('retailer lookup failure is advisory and demo provider is explicitly non-live', async () => {
  let calls = 0;
  const provider = new InstacartApiProvider({
    apiKey: 'server-only-secret',
    baseUrl: 'https://connect.instacart.com',
    fetchFn: async () => {
      calls += 1;
      return calls === 1
        ? new Response(JSON.stringify({ products_link_url: 'https://www.instacart.com/store/lists/abc' }), { status: 200 })
        : new Response('{}', { status: 503 });
    }
  });
  const url = await provider.create({ title: 'List', line_items: [{ name: 'milk' }] }, {
    postalCode: '94105', countryCode: 'US', preferredRetailerKey: 'missing'
  });
  assert.equal(url, 'https://www.instacart.com/store/lists/abc');

  const demo = new InstacartDemoProvider({ url: 'https://demo.example/smartcart-handoff' });
  const service = new InstacartHandoffService({ provider: demo, now: () => 1_000 });
  const result = await service.create({
    id: crypto.randomUUID(), version: 1, recipeTitle: 'Demo', items: [handoffItem({ exactUPC: undefined })]
  }, { postalCode: '94105', fulfillmentPreference: 'pickup' });
  assert.equal(result.provider, 'instacart-demo');
  assert.equal(result.presentationMode, 'in_app_safari');
  assert.equal(result.url, 'https://demo.example/smartcart-handoff');
});

test('fingerprint cache survives backend manifest identity changes and converts common recipe counts', async () => {
  const provider = new RecordingProvider();
  const service = new InstacartHandoffService({ provider, now: () => 2_000 });
  const item = handoffItem({ exactUPC: undefined, quantity: 3, unit: 'cloves' });
  const base = { version: 1, recipeTitle: 'Garlic dinner', items: [item] };
  const request = { postalCode: '94105', fulfillmentPreference: 'pickup' };
  const first = await service.create({ ...base, id: crypto.randomUUID() }, request);
  const second = await service.create({ ...base, id: crypto.randomUUID(), version: 9 }, request);

  assert.equal(provider.calls.length, 1);
  assert.equal(first.manifestFingerprint, second.manifestFingerprint);
  assert.deepEqual(provider.calls[0].payload.line_items[0].line_item_measurements, [
    { quantity: 3, unit: 'each' }
  ]);
  const emptyUnitPayload = instacartHandoffInternals.buildProductsLinkPayload({
    recipeTitle: 'Eggs',
    items: [handoffItem({ exactUPC: undefined, name: 'eggs', quantity: 2, unit: '' })]
  });
  assert.deepEqual(emptyUnitPayload.line_items[0].line_item_measurements, [
    { quantity: 2, unit: 'each' }
  ]);
  assert.equal(
    instacartHandoffInternals.fingerprint({ stable: true }),
    instacartHandoffInternals.fingerprint({ stable: true })
  );
});
