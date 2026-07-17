import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import { createServer } from '../src/app.js';

function silentLogger() {
  return { debug() {}, info() {}, warn() {}, error() {} };
}

async function listen(options = {}) {
  const instance = createServer({
    logger: silentLogger(),
    config: { host: '127.0.0.1', port: 0, ...options }
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

async function jsonRequest(baseUrl, path, { method = 'GET', token, body, headers = {} } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(body ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers
    },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  const payload = response.status === 204 ? null : await response.json();
  return { response, payload };
}

function sampleManifest(overrides = {}) {
  return {
    recipeID: 'recipe-local-demo-1',
    recipeTitle: 'Local Demo Chili',
    retailerID: 'demo-retailer',
    storeID: 'demo-store-1',
    storeName: 'Demo Store',
    desiredServings: 4,
    fulfillmentMode: 'Pickup',
    handoffProgress: 'notStarted',
    items: [{
      ingredientID: 'ingredient-local-demo-1',
      ingredientName: 'Beans',
      requestedQuantity: '2 cans',
      purchaseQuantity: 2,
      product: { itemID: 'demo-item-1', title: 'Demo Beans', price: 1.25 },
      status: 'waiting'
    }],
    ...overrides
  };
}

describe('SmartCart local/demo HTTP service', () => {
  let service;
  let token;
  let account;

  before(async () => {
    service = await listen();
    const accountResult = await jsonRequest(service.baseUrl, '/v1/demo/accounts', {
      method: 'POST',
      body: { displayName: 'Demo Shopper', email: 'shopper@example.local' }
    });
    assert.equal(accountResult.response.status, 201);
    account = accountResult.payload.account;
    const sessionResult = await jsonRequest(service.baseUrl, '/v1/demo/sessions', {
      method: 'POST',
      body: { accountId: account.id }
    });
    assert.equal(sessionResult.response.status, 201);
    token = sessionResult.payload.session.token;
  });

  after(async () => {
    await service.close();
  });

  test('health reports explicit local/demo data boundaries', async () => {
    const { response, payload } = await jsonRequest(service.baseUrl, '/health');
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('x-smartcart-data-mode'), 'local-demo');
    assert.equal(payload.status, 'ok');
    assert.equal(payload.meta.persistence, 'ephemeral-in-memory');
    assert.match(payload.meta.catalog, /never-live/);
  });

  test('mock bearer sessions authenticate and can be revoked', async () => {
    const extraAccount = await jsonRequest(service.baseUrl, '/v1/demo/accounts', {
      method: 'POST',
      body: { displayName: 'Temporary Demo', email: 'temporary@example.local' }
    });
    const extraSession = await jsonRequest(service.baseUrl, '/v1/demo/sessions', {
      method: 'POST',
      body: { accountId: extraAccount.payload.account.id }
    });
    const extraToken = extraSession.payload.session.token;
    const authenticated = await jsonRequest(service.baseUrl, '/v1/demo/account', { token: extraToken });
    assert.equal(authenticated.response.status, 200);
    assert.equal(authenticated.payload.account.dataMode, 'local-demo');
    const revoked = await jsonRequest(service.baseUrl, '/v1/demo/sessions/current', {
      method: 'DELETE', token: extraToken
    });
    assert.equal(revoked.response.status, 200);
    const rejected = await jsonRequest(service.baseUrl, '/v1/demo/account', { token: extraToken });
    assert.equal(rejected.response.status, 401);
  });

  test('OAuth state and S256 PKCE are validated and one-time use', async () => {
    const rejectedStart = await jsonRequest(service.baseUrl, '/v1/oauth/demo/start', {
      method: 'POST', token, body: {}
    });
    const rejectedVerifier = await jsonRequest(service.baseUrl, '/v1/oauth/demo/callback', {
      method: 'POST',
      token,
      body: {
        state: rejectedStart.payload.oauth.state,
        code: 'local-demo-authorization-code',
        codeVerifier: 'x'.repeat(64)
      }
    });
    assert.equal(rejectedVerifier.response.status, 400);
    assert.equal(rejectedVerifier.payload.error.code, 'invalid_pkce_verifier');

    const started = await jsonRequest(service.baseUrl, '/v1/oauth/demo/start', {
      method: 'POST', token, body: {}
    });
    assert.equal(started.response.status, 201);
    assert.equal(started.payload.oauth.dataMode, 'local-demo');
    assert.match(started.payload.oauth.authorizationUrl, /^http:\/\/127\.0\.0\.1\/local-demo-oauth/);
    const callback = {
      state: started.payload.oauth.state,
      code: 'local-demo-authorization-code',
      codeVerifier: started.payload.oauth.codeVerifier
    };
    const completed = await jsonRequest(service.baseUrl, '/v1/oauth/demo/callback', {
      method: 'POST', token, body: callback
    });
    assert.equal(completed.response.status, 200);
    assert.equal(completed.payload.oauth.connected, true);
    const replayed = await jsonRequest(service.baseUrl, '/v1/oauth/demo/callback', {
      method: 'POST', token, body: callback
    });
    assert.equal(replayed.response.status, 400);
    assert.equal(replayed.payload.error.code, 'invalid_oauth_state');
  });

  test('manifests support create/read/update and reject stale versions', async () => {
    const created = await jsonRequest(service.baseUrl, '/v1/manifests', {
      method: 'POST', token, body: { manifest: sampleManifest() }
    });
    assert.equal(created.response.status, 201);
    const manifest = created.payload.manifest;
    assert.equal(manifest.version, 1);
    assert.equal(manifest.items[0].product.dataMode, 'local-demo-client-supplied-never-live');

    const read = await jsonRequest(service.baseUrl, `/v1/manifests/${manifest.id}`, { token });
    assert.equal(read.response.status, 200);
    assert.equal(read.payload.manifest.recipeTitle, 'Local Demo Chili');

    const updated = await jsonRequest(service.baseUrl, `/v1/manifests/${manifest.id}`, {
      method: 'PATCH', token, body: { expectedVersion: 1, manifest: { recipeTitle: 'Updated Demo Chili' } }
    });
    assert.equal(updated.response.status, 200);
    assert.equal(updated.payload.manifest.version, 2);

    const conflict = await jsonRequest(service.baseUrl, `/v1/manifests/${manifest.id}`, {
      method: 'PATCH', token, body: { expectedVersion: 1, manifest: { recipeTitle: 'Stale Title' } }
    });
    assert.equal(conflict.response.status, 409);
    assert.equal(conflict.payload.error.code, 'version_conflict');
  });

  test('manifest sync marks accepted state and returns server state on conflicts', async () => {
    const created = await jsonRequest(service.baseUrl, '/v1/manifests', {
      method: 'POST', token, body: sampleManifest({ recipeTitle: 'Sync Demo' })
    });
    const manifest = created.payload.manifest;
    const synced = await jsonRequest(service.baseUrl, `/v1/manifests/${manifest.id}/sync`, {
      method: 'POST', token, body: {
        baseVersion: 1,
        manifest: sampleManifest({ recipeTitle: 'Synced Demo' })
      }
    });
    assert.equal(synced.response.status, 200);
    assert.equal(synced.payload.manifest.version, 2);
    assert.equal(synced.payload.sync.status, 'accepted-local-demo');

    const conflict = await jsonRequest(service.baseUrl, `/v1/manifests/${manifest.id}/sync`, {
      method: 'POST', token, body: { baseVersion: 1, manifest: sampleManifest() }
    });
    assert.equal(conflict.response.status, 409);
    assert.equal(conflict.payload.error.details.serverManifest.version, 2);
  });

  test('analytics ingestion accepts bounded events and rejects identifier-like properties', async () => {
    const accepted = await jsonRequest(service.baseUrl, '/v1/analytics/events', {
      method: 'POST', token, body: { events: [{ name: 'manifest_saved', properties: { itemCount: 3 } }] }
    });
    assert.equal(accepted.response.status, 202);
    assert.equal(accepted.payload.accepted, 1);

    const rejected = await jsonRequest(service.baseUrl, '/v1/analytics/events', {
      method: 'POST', token, body: { events: [{ name: 'bad_event', properties: { email: 'no@example.local' } }] }
    });
    assert.equal(rejected.response.status, 400);
    assert.equal(rejected.payload.error.code, 'sensitive_analytics_data_rejected');
  });

  test('affiliate abstraction allows only HTTPS and uses its TTL cache', async () => {
    const body = { targetUrl: 'https://retailer.example/items/demo-1', retailerId: 'demo-retailer' };
    const first = await jsonRequest(service.baseUrl, '/v1/affiliate-links', {
      method: 'POST', token, body
    });
    assert.equal(first.response.status, 200);
    assert.equal(first.payload.link.cache, 'miss');
    assert.equal(first.payload.link.provider, 'local-demo');
    const second = await jsonRequest(service.baseUrl, '/v1/affiliate-links', {
      method: 'POST', token, body
    });
    assert.equal(second.payload.link.cache, 'hit');

    const rejected = await jsonRequest(service.baseUrl, '/v1/affiliate-links', {
      method: 'POST', token, body: { ...body, targetUrl: 'http://retailer.example/item' }
    });
    assert.equal(rejected.response.status, 400);
  });
});

test('rate limiter returns local/demo 429 metadata and retry headers', async () => {
  const service = await listen({ rateLimitMax: 2, rateLimitWindowMs: 60_000 });
  try {
    assert.equal((await jsonRequest(service.baseUrl, '/health')).response.status, 200);
    assert.equal((await jsonRequest(service.baseUrl, '/health')).response.status, 200);
    const limited = await jsonRequest(service.baseUrl, '/health');
    assert.equal(limited.response.status, 429);
    assert.ok(Number(limited.response.headers.get('retry-after')) >= 1);
    assert.equal(limited.payload.meta.dataMode, 'local-demo');
  } finally {
    await service.close();
  }
});
