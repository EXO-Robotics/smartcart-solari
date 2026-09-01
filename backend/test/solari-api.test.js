import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createLogger } from '../src/lib/logger.js';
import { createPublicSolariApi } from '../src/solari/public-api.js';
import { controlledDemoProductURL } from '../src/solari/constants.js';

const requestPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json'
);
async function fixture() { return JSON.parse(await readFile(requestPath, 'utf8')); }

async function liveDemoFixture(baseURL = 'https://demo.example/solari-demo') {
  const request = await fixture();
  request.executionMode = 'live';
  request.retailerID = 'smartcart-demo-grocer';
  for (const requirement of request.requirements) {
    for (const candidate of requirement.candidates) {
      candidate.sourceURL = controlledDemoProductURL(baseURL, candidate.retailerProductID);
    }
  }
  return request;
}

async function listen(options = {}) {
  const api = createPublicSolariApi({
    config: { solariRateLimitPerMinute: 5, solariMaxBodyBytes: 32_768 },
    logger: { debug() {}, info() {}, warn() {}, error() {} },
    now: () => Date.parse('2026-09-01T12:00:00Z'),
    ...options
  });
  return { api, async close() {} };
}

async function post(api, body, headers = {}) {
  const encoded = Buffer.from(JSON.stringify(body));
  const request = Readable.from([encoded]);
  request.method = 'POST';
  request.url = '/v1/solari/research';
  request.headers = { 'content-type': 'application/json', 'content-length': String(encoded.length), ...headers };
  request.socket = { remoteAddress: '127.0.0.1' };
  const response = {
    status: null, headers: {}, body: '',
    writeHead(status, responseHeaders) { this.status = status; this.headers = responseHeaders; },
    end(value = '') { this.body += value; },
    get statusCode() { return this.status; }
  };
  await api.handler(request, response);
  return {
    response: {
      status: response.status,
      headers: { get: (name) => response.headers[name.toLowerCase()] ?? null }
    },
    payload: JSON.parse(response.body)
  };
}

test('POST /v1/solari/research returns the bounded fixture replay with explicit trust metadata', async () => {
  const server = await listen();
  try {
    const { response, payload } = await post(server.api, await fixture());
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(payload.executionMode, 'recorded_fixture');
    assert.equal(payload.provenance.fixtureReplay, true);
    assert.equal(payload.provenance.browser, 'not-run-fixture-replay');
    assert.equal(payload.basket.observedSubtotal, 12.79);
    assert.equal(payload.trust.checkoutAutomated, false);
  } finally { await server.close(); }
});

test('endpoint rejects arbitrary candidate URLs before any provider work', async () => {
  let calls = 0;
  const server = await listen({ browserProvider: { async observe() { calls += 1; return []; } } });
  try {
    const request = await fixture();
    request.requirements[0].candidates[0].sourceURL = 'https://evil.example/product';
    const { response, payload } = await post(server.api, request);
    assert.equal(response.status, 400);
    assert.equal(payload.error.code, 'candidate_url_not_allowed');
    assert.equal(calls, 0);
  } finally { await server.close(); }
});

test('per-client Solari rate limit is narrowly independent from the general backend limit', async () => {
  const server = await listen({ config: { solariRateLimitPerMinute: 1, solariMaxBodyBytes: 32_768 } });
  try {
    assert.equal((await post(server.api, await fixture())).response.status, 200);
    const limited = await post(server.api, await fixture());
    assert.equal(limited.response.status, 429);
    assert.equal(limited.payload.error.code, 'rate_limited');
    assert.ok(Number(limited.response.headers.get('retry-after')) >= 1);
  } finally { await server.close(); }
});

test('server logs redact provider failures by construction and never serialize the Solari key', async () => {
  const lines = [];
  const secret = 'slr_live_never_log_this';
  const logger = createLogger({ sink: (line) => lines.push(line), dataMode: 'solari-research-v1' });
  const server = await listen({
    logger,
    service: { async research() { throw new Error(`provider failed with ${secret}`); } }
  });
  try {
    const { response, payload } = await post(server.api, await fixture());
    assert.equal(response.status, 500);
    assert.equal(payload.error.message, 'Solari research could not complete the request.');
    assert.doesNotMatch(lines.join('\n'), new RegExp(secret));
    assert.match(lines.join('\n'), /"errorName":"Error"/);
  } finally { await server.close(); }
});

test('live Browser and Sandbox execution requires both enablement and an operator bearer', async () => {
  const operatorToken = 'operator-only-token-1234567890abcdef';
  let serviceCalls = 0;
  const service = { async research(request) { serviceCalls += 1; return { executionMode: request.executionMode, admitted: true }; } };
  const disabled = await listen({ service });
  try {
    const denied = await post(disabled.api, await liveDemoFixture());
    assert.equal(denied.response.status, 403);
    assert.equal(denied.payload.error.code, 'live_execution_not_authorized');
    assert.equal(denied.response.headers.get('x-smartcart-data-mode'), 'solari-error');
    assert.equal(serviceCalls, 0);
  } finally { await disabled.close(); }

  const enabled = await listen({
    config: {
      solariRateLimitPerMinute: 5,
      solariMaxBodyBytes: 32_768,
      solariLiveExecutionEnabled: true,
      solariOperatorToken: operatorToken
    },
    service
  });
  try {
    assert.equal((await post(enabled.api, await liveDemoFixture(), { authorization: 'Bearer wrong-wrong-wrong-wrong-wrong-wrong' })).response.status, 403);
    const admitted = await post(enabled.api, await liveDemoFixture(), { authorization: `Bearer ${operatorToken}` });
    assert.equal(admitted.response.status, 200);
    assert.equal(serviceCalls, 1);
  } finally { await enabled.close(); }
});

test('operator-authorized controlled live request returns typed unavailable when server key is missing', async () => {
  const operatorToken = 'operator-only-token-1234567890abcdef';
  const server = await listen({
    config: {
      solariRateLimitPerMinute: 5,
      solariMaxBodyBytes: 32_768,
      solariLiveExecutionEnabled: true,
      solariOperatorToken: operatorToken,
      solariDemoRetailerBaseUrl: 'https://demo.example/solari-demo',
      solariApiKey: undefined,
      solariBrowserTimeoutMs: 6000,
      solariSandboxTimeoutMs: 10000,
      solariSandboxBaseUrl: 'https://api.getsolari.com'
    },
    demoHostLookup: async () => [{ address: '93.184.216.34', family: 4 }]
  });
  try {
    const result = await post(server.api, await liveDemoFixture(), { authorization: `Bearer ${operatorToken}` });
    assert.equal(result.response.status, 503);
    assert.equal(result.payload.error.code, 'solari_unavailable');
  } finally { await server.close(); }
});
