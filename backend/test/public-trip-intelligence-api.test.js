import assert from 'node:assert/strict';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import test from 'node:test';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { createPublicTripIntelligenceApi } from '../src/public-trip-intelligence-api.js';

const silentLogger = { debug() {}, info() {}, warn() {}, error() {} };

async function fixture(name) {
  return JSON.parse(await readFile(
    new URL(`../../contracts/fixtures/v1/chicken-parmesan/${name}`, import.meta.url),
    'utf8'
  ));
}

async function listen(tripIntelligenceService, options = {}) {
  const validator = await createContractValidator();
  const { handler } = createPublicTripIntelligenceApi({
    logger: silentLogger,
    validator,
    tripIntelligenceService,
    config: { host: '127.0.0.1', port: 0, ...(options.config ?? {}) },
    limiter: options.limiter
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

test('public Trip Intelligence endpoint validates and returns the authoritative contract', async () => {
  const request = await fixture('recipe-request.json');
  const expected = await fixture('recipe-nutrition-output.json');
  const service = await listen({
    async estimateRecipeNutrition(data) {
      assert.deepEqual(data, request.data);
      return { resolverVersion: expected.resolverVersion, data: expected.data };
    }
  });

  try {
    const response = await fetch(`${service.baseURL}/v1/intelligence/nutrition/recipes/estimate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(request)
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('x-smartcart-data-mode'), 'trip-intelligence-v1');
    assert.deepEqual(await response.json(), expected);
  } finally {
    await service.close();
  }
});

test('invalid and unknown requests fail closed without invoking intelligence', async () => {
  let calls = 0;
  const service = await listen({
    async estimateRecipeNutrition() { calls += 1; throw new Error('must not run'); }
  });
  try {
    const invalid = await fetch(`${service.baseURL}/v1/intelligence/nutrition/recipes/estimate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ schemaVersion: '1.0' })
    });
    assert.equal(invalid.status, 400);
    const invalidPayload = await invalid.json();
    assert.equal(invalidPayload.error.code, 'contract_validation_failed');
    assert.equal(invalidPayload.error.issues[0].severity, 'blocking');

    const unknown = await fetch(`${service.baseURL}/v1/intelligence/anything`, { method: 'POST' });
    assert.equal(unknown.status, 404);
    assert.equal((await unknown.json()).error.code, 'route_not_found');
    assert.equal(calls, 0);
  } finally {
    await service.close();
  }
});

test('public Trip Intelligence rejects over-limit requests before provider access', async () => {
  let calls = 0;
  const service = await listen({
    async estimateRecipeNutrition() { calls += 1; throw new Error('must not run'); }
  }, {
    limiter: {
      consume() {
        return { allowed: false, limit: 1, remaining: 0, resetAt: 60_000, retryAfterSeconds: 60 };
      }
    }
  });
  try {
    const response = await fetch(`${service.baseURL}/v1/intelligence/nutrition/recipes/estimate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}'
    });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get('retry-after'), '60');
    assert.equal(response.headers.get('x-rate-limit-remaining'), '0');
    const payload = await response.json();
    assert.equal(payload.error.code, 'rate_limited');
    assert.equal(payload.error.retryable, true);
    assert.equal(calls, 0);
  } finally {
    await service.close();
  }
});

test('public Trip Intelligence rejects an oversized body pre-parsed by Vercel', async () => {
  let calls = 0;
  const { handler } = createPublicTripIntelligenceApi({
    tripIntelligenceService: {
      async estimateRecipeNutrition() { calls += 1; throw new Error('should not run'); }
    },
    config: { host: '127.0.0.1', port: 0, maxBodyBytes: 128 }
  });
  const httpServer = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    request.body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    await handler(request, response);
  });
  httpServer.listen(0, '127.0.0.1');
  await once(httpServer, 'listening');
  const address = httpServer.address();
  try {
    const response = await fetch(
      `http://127.0.0.1:${address.port}/v1/intelligence/nutrition/recipes/estimate`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ padding: 'x'.repeat(512) })
      }
    );
    assert.equal(response.status, 413);
    const payload = await response.json();
    assert.equal(payload.error.code, 'payload_too_large');
    assert.equal(calls, 0);
  } finally {
    httpServer.close();
    await once(httpServer, 'close');
  }
});

test('Vercel exposes only the reviewed barcode and Trip Intelligence surfaces', async () => {
  const config = JSON.parse(await readFile(new URL('../vercel.json', import.meta.url), 'utf8'));
  assert.deepEqual(
    Object.keys(config.functions).sort(),
    ['api/index.js', 'api/intelligence.js', 'api/mcp.js']
  );
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
    {
      src: '/v1/intelligence/nutrition/recipes/estimate',
      methods: ['POST'],
      dest: '/api/intelligence.js?route=recipe-nutrition'
    },
    {
      src: '/mcp',
      methods: ['POST'],
      dest: '/api/mcp.js?route=mcp'
    },
    { src: '/.*', status: 404 }
  ]);
  const entrypoint = await readFile(new URL('../api/intelligence.js', import.meta.url), 'utf8');
  assert.match(entrypoint, /createPublicTripIntelligenceApi/);
  assert.doesNotMatch(entrypoint, /createApp|LocalDemoStore|oauth|manifest|session/iu);
});
