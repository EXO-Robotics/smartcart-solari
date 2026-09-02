import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import test from 'node:test';
import {
  createSolariPublicDemoApi,
  InMemorySolariPublicDemoStore
} from '../src/solari/public-demo-api.js';
import { UpstashSolariPublicDemoStore } from '../src/solari/public-demo-store.js';
import {
  createV4PublicDemoRequest,
  PUBLIC_DEMO_MEAL_ID,
  PUBLIC_DEMO_REQUEST_SCHEMA_VERSION
} from '../src/solari/v4-public-demo-request.js';

const origin = 'https://exo-robotics.github.io';
const selector = { schemaVersion: PUBLIC_DEMO_REQUEST_SCHEMA_VERSION, mealID: PUBLIC_DEMO_MEAL_ID };
const fixedNow = Date.parse('2026-09-02T14:00:00Z');

function result(requestID = '70000000-0000-4000-8000-000000000001') {
  return {
    schemaVersion: 'solari-shopping-research-result-v4',
    requestID,
    provenance: {
      accessBoundary: 'public-demo',
      browserReplay: {
        status: 'available',
        url: 'https://replay.example/presigned.ndjson?signature=redacted-test',
        expiresAt: '2026-09-02T14:10:00.000Z'
      }
    },
    runtimeStats: {
      wallTimeMs: 10_661,
      browserObservationCount: 16,
      sandboxDecisionCount: 8,
      skippedRequirementCount: 0,
      costTelemetry: { status: 'unavailable' }
    }
  };
}

function config(overrides = {}) {
  return {
    solariPublicDemoEnabled: true,
    solariPublicDemoOrigin: origin,
    solariPublicDemoIpHmacSecret: 'test-only-hmac-secret-with-at-least-32-bytes',
    solariPublicDemoRuntimeKey: 'test:runtime',
    solariPublicDemoRuntimeBootstrapEnabled: false,
    solariPublicDemoPerIpDailyLimit: 1,
    solariPublicDemoGlobalDailyLimit: 25,
    solariPublicDemoConcurrencyLimit: 1,
    solariPublicDemoDailyBudgetUnits: 25,
    solariPublicDemoRunBudgetUnits: 1,
    solariPublicDemoLeaseTtlSeconds: 60,
    solariPublicDemoCacheTtlSeconds: 86_400,
    solariPublicDemoKillPollMs: 1_000,
    solariPublicDemoMaxBodyBytes: 512,
    ...overrides
  };
}

function api(options = {}) {
  return createSolariPublicDemoApi({
    config: config(options.config),
    store: options.store ?? new InMemorySolariPublicDemoStore({ now: () => fixedNow }),
    validator: options.validator ?? { assert() {} },
    researchService: options.researchService ?? { research: async (request) => result(request.requestID) },
    logger: { debug() {}, info() {}, warn() {}, error() {} },
    now: options.now ?? (() => fixedNow)
  });
}

async function request(handler, body = selector, { method = 'POST', requestOrigin = origin, ip = '198.51.100.10', path = '/public-demo/v1/solari/research' } = {}) {
  const encoded = body === undefined ? null : Buffer.from(JSON.stringify(body));
  const req = encoded ? Readable.from([encoded]) : Readable.from([]);
  req.method = method;
  req.url = path;
  req.headers = {
    origin: requestOrigin,
    ...(encoded ? { 'content-type': 'application/json', 'content-length': String(encoded.length) } : {}),
    'x-forwarded-for': ip
  };
  req.socket = { remoteAddress: '127.0.0.1' };
  const response = {
    status: null, headers: {}, body: '',
    writeHead(status, headers) { this.status = status; this.headers = headers; },
    end(value = '') { this.body += value; }
  };
  await handler(req, response);
  return { status: response.status, headers: response.headers, body: response.body ? JSON.parse(response.body) : null };
}

test('fixed public selector generates the complete server-owned eight-item V4 request', () => {
  const generated = createV4PublicDemoRequest({
    now: () => fixedNow,
    id: () => '70000000-0000-4000-8000-000000000099'
  });
  assert.equal(generated.requestID, '70000000-0000-4000-8000-000000000099');
  assert.equal(generated.requirements.length, 8);
  assert.equal(generated.requirements.flatMap(({ candidateProductIDs }) => candidateProductIDs).length, 16);
  assert.equal(generated.optimizationPolicy.maxPremiumOverCheapest, 0.75);
  assert.equal(JSON.stringify(generated).includes('http'), false);
});

test('public route is default-off, exact-origin, POST-only, and supports bounded preflight', async () => {
  const disabled = api({ config: { solariPublicDemoEnabled: false } });
  assert.equal((await request(disabled.handler)).status, 404);

  const enabled = api();
  const denied = await request(enabled.handler, selector, { requestOrigin: 'https://evil.example' });
  assert.equal(denied.status, 403);
  assert.equal(denied.headers['access-control-allow-origin'], undefined);
  assert.equal((await request(enabled.handler, selector, { method: 'GET' })).status, 404);
  const preflight = await request(enabled.handler, undefined, { method: 'OPTIONS' });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers['access-control-allow-origin'], origin);
  assert.equal(preflight.headers['access-control-allow-methods'], 'POST, OPTIONS');
});

test('public route rejects missing, altered, and extended selectors before provider work', async () => {
  let calls = 0;
  const endpoint = api({ researchService: { research: async () => { calls += 1; return result(); } } });
  for (const body of [
    {},
    { ...selector, mealID: 'another-meal' },
    { ...selector, candidateURL: 'https://evil.example' }
  ]) {
    const response = await request(endpoint.handler, body);
    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'public_demo_request_not_allowed');
  }
  assert.equal(calls, 0);
});

test('one HMAC-IP-admitted live run is cached; a repeat visitor receives the verified result', async () => {
  const store = new InMemorySolariPublicDemoStore({ now: () => fixedNow });
  let calls = 0;
  let generated;
  const endpoint = api({
    store,
    researchService: { research: async (requestValue) => { calls += 1; generated = requestValue; return result(requestValue.requestID); } }
  });
  const fresh = await request(endpoint.handler);
  assert.equal(fresh.status, 200);
  assert.equal(fresh.body.deliveryMode, 'live');
  assert.equal(fresh.headers['x-smartcart-live-execution'], 'fresh');
  assert.equal(fresh.body.result.provenance.accessBoundary, 'public-demo');
  assert.equal(fresh.body.result.runtimeStats.costTelemetry.status, 'unavailable');
  assert.equal(generated.requirements.length, 8);

  const repeated = await request(endpoint.handler);
  assert.equal(repeated.status, 200);
  assert.equal(repeated.body.deliveryMode, 'cached-verified-run');
  assert.equal(repeated.body.fallbackReason, 'visitor-daily');
  assert.equal('browserReplay' in repeated.body.result.provenance, false);
  assert.equal(calls, 1);
  assert.equal([...store.quotas.keys()].some((key) => key.includes('198.51.100.10')), false);
  assert.equal(JSON.stringify(fresh.body).includes('sessionId'), false);
});

test('runtime kill switch serves only a previously validated cached result', async () => {
  const store = new InMemorySolariPublicDemoStore({ now: () => fixedNow, runtimeEnabled: false });
  const empty = api({ store });
  assert.equal((await request(empty.handler)).status, 503);
  await store.putCachedResult({ storedAt: new Date(fixedNow).toISOString(), result: result() });
  const cached = await request(api({ store }).handler);
  assert.equal(cached.status, 200);
  assert.equal(cached.body.deliveryMode, 'cached-verified-run');
  assert.equal(cached.body.fallbackReason, 'runtime-disabled');
});

test('provider failure degrades to the last verified result without relabeling it live', async () => {
  const store = new InMemorySolariPublicDemoStore({ now: () => fixedNow });
  await store.putCachedResult({ storedAt: new Date(fixedNow).toISOString(), result: result() });
  const endpoint = api({ store, researchService: { research: async () => { throw new Error('provider detail must not escape'); } } });
  const response = await request(endpoint.handler, selector, { ip: '203.0.113.11' });
  assert.equal(response.status, 200);
  assert.equal(response.body.deliveryMode, 'cached-verified-run');
  assert.equal(response.body.fallbackReason, 'provider-unavailable');
  assert.doesNotMatch(JSON.stringify(response.body), /provider detail/);
});

test('replay capability URLs are never returned from cached public responses', async () => {
  const store = new InMemorySolariPublicDemoStore({ now: () => fixedNow, runtimeEnabled: false });
  const expired = result();
  await store.putCachedResult({ storedAt: new Date(fixedNow).toISOString(), result: expired });
  const response = await request(api({ store }).handler);
  assert.equal(response.status, 200);
  assert.equal('browserReplay' in response.body.result.provenance, false);
});

test('Upstash public admission is atomic across visitor, global, budget, and lease keys', async () => {
  let call;
  const redis = {
    async eval(script, keys, args) { call = { script, keys, args }; return ['allowed', 'lease-1']; },
    async zrem() {},
    async get() { return 'enabled'; },
    async set() { return 'OK'; }
  };
  const store = new UpstashSolariPublicDemoStore({ redis, prefix: 'test:public' });
  const admitted = await store.admit({
    visitorHash: 'abc', now: fixedNow, perIpDailyLimit: 1, globalDailyLimit: 25,
    concurrencyLimit: 1, dailyBudgetUnits: 25, runBudgetUnits: 1, leaseTtlSeconds: 60
  });
  assert.equal(admitted.allowed, true);
  assert.equal(call.keys.length, 4);
  assert.match(call.script, /visitor-daily/);
  assert.match(call.script, /global-daily/);
  assert.match(call.script, /budget/);
  assert.match(call.script, /ZCARD/);
});

test('Upstash runtime bootstrap is one-time and cannot silently re-enable after a kill', async () => {
  const calls = [];
  const redis = {
    async eval(script, keys, args) { calls.push({ script, keys, args }); return calls.length === 1 ? 'enabled' : 'disabled'; }
  };
  const store = new UpstashSolariPublicDemoStore({ redis, prefix: 'test:public' });
  assert.equal(await store.runtimeEnabled('test:runtime', { bootstrap: true }), true);
  assert.equal(await store.runtimeEnabled('test:runtime'), false);
  assert.deepEqual(calls[0].keys, ['test:runtime', 'test:runtime:bootstrap-complete']);
  assert.deepEqual(calls[0].args, ['true']);
  assert.deepEqual(calls[1].args, ['false']);
  assert.match(calls[0].script, /bootstrap-complete|EXISTS/);
});
