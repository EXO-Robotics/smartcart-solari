import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createLogger } from '../src/lib/logger.js';
import { createPublicSolariApi } from '../src/solari/public-api.js';
import { controlledDemoProductURL } from '../src/solari/constants.js';
import { SolariResearchError } from '../src/solari/errors.js';

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

async function post(api, body, headers = {}, url = '/v1/solari/research', method = 'POST') {
  const encoded = Buffer.from(JSON.stringify(body));
  const request = Readable.from([encoded]);
  request.method = method;
  request.url = url;
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

test('public Solari API wires challenge, attestation, and V2 envelope without the V1 operator gate', async () => {
  const calls=[];
  const betaApi={
    async challenge(payload){calls.push(['challenge',payload]);return{status:201,payload:{schemaVersion:'solari-app-attest-challenge-result-v1'}};},
    async attestation(payload){calls.push(['attestation',payload]);return{status:201,payload:{schemaVersion:'solari-app-attestation-result-v1'}};},
    async researchEnvelope(payload){calls.push(['research',payload]);return{status:200,payload:{schemaVersion:'solari-shopping-research-result-v3',executionMode:'live'}};}
  };
  let v1Calls=0;const server=await listen({betaApi,service:{research:async()=>{v1Calls+=1;}}});
  const challenge=await post(server.api,{schemaVersion:'solari-app-attest-challenge-request-v1'}, {}, '/v1/solari/access/challenges');
  assert.equal(challenge.response.status,201);assert.equal(challenge.response.headers.get('x-smartcart-data-mode'),'solari-app-attest');
  assert.equal((await post(server.api,{schemaVersion:'solari-app-attestation-request-v1'}, {}, '/v1/solari/access/attestations')).response.status,201);
  const envelope={schemaVersion:'solari-app-attest-research-envelope-v1'};assert.equal((await post(server.api,envelope)).response.status,200);
  assert.deepEqual(calls.map(([name])=>name),['challenge','attestation','research']);assert.equal(v1Calls,0);
  assert.equal((await post(server.api,{}, {}, '/v1/solari/access/challenges','GET')).response.status,404);
  assert.equal((await post(server.api,{}, {}, '/v1/solari/access/unknown')).response.status,404);
});

test('development route is default-off and isolated from the distribution App Attest lane', async () => {
  const distributionCalls=[];const developmentCalls=[];
  const makeBeta=(calls)=>({
    async challenge(payload){calls.push(['challenge',payload]);return{status:201,payload:{schemaVersion:'solari-app-attest-challenge-result-v1'}};},
    async attestation(payload){calls.push(['attestation',payload]);return{status:201,payload:{schemaVersion:'solari-app-attestation-result-v1'}};},
    async researchEnvelope(payload){calls.push(['research',payload]);return{status:200,payload:{schemaVersion:'solari-shopping-research-result-v4',executionMode:'live'}};}
  });
  const disabled=await listen({developmentBetaApi:makeBeta(developmentCalls)});
  assert.equal((await post(disabled.api,{}, {}, '/dev/v1/solari/access/challenges')).response.status,404);

  let v1Calls=0;
  const enabled=await listen({
    config:{solariRateLimitPerMinute:10,solariMaxBodyBytes:32_768,solariDevelopmentLaneEnabled:true},
    betaApi:makeBeta(distributionCalls),
    developmentBetaApi:makeBeta(developmentCalls),
    service:{research:async()=>{v1Calls+=1;}}
  });
  assert.equal((await post(enabled.api,{}, {}, '/v1/solari/access/challenges')).response.status,201);
  assert.equal((await post(enabled.api,{}, {}, '/dev/v1/solari/access/challenges')).response.status,201);
  assert.equal((await post(enabled.api,{}, {}, '/dev/v1/solari/access/attestations')).response.status,201);
  assert.equal((await post(enabled.api,{schemaVersion:'solari-app-attest-research-envelope-v1'}, {}, '/dev/v1/solari/research')).response.status,200);
  const legacy=await post(enabled.api,await fixture(),{},'/dev/v1/solari/research');
  assert.equal(legacy.response.status,403);assert.equal(legacy.payload.error.code,'app_attest_envelope_required');
  assert.deepEqual(distributionCalls.map(([name])=>name),['challenge']);
  assert.deepEqual(developmentCalls.map(([name])=>name),['challenge','attestation','research']);
  assert.equal(v1Calls,0);
});

test('POST /v1/solari/research returns the bounded fixture replay with explicit trust metadata', async () => {
  const server = await listen();
  try {
    const { response, payload } = await post(server.api, await fixture());
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(payload.executionMode, 'recorded_fixture');
    assert.equal(payload.provenance.fixtureReplay, true);
    assert.equal(payload.provenance.browser, 'not-run-fixture-replay');
    assert.deepEqual(payload.provenance.resourceCleanup, {
      browser: 'not-run-fixture-replay', sandbox: 'not-run-fixture-replay'
    });
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

test('V1 retains its original body limit while the signed V2 envelope has a separate bound', async () => {
  const original=await fixture(),originalBytes=Buffer.byteLength(JSON.stringify(original));
  const server=await listen({config:{solariRateLimitPerMinute:5,solariMaxBodyBytes:originalBytes+8,solariBetaMaxBodyBytes:65_536}});
  const oversized={...original,padding:'x'.repeat(32)};const result=await post(server.api,oversized);
  assert.equal(result.response.status,413);assert.equal(result.payload.error.code,'payload_too_large');
});

test('untrusted forwarded addresses cannot bypass the Solari rate limit', async () => {
  const server = await listen({
    config: {
      solariRateLimitPerMinute: 1,
      solariMaxBodyBytes: 32_768,
      solariTrustForwardedFor: false
    }
  });
  try {
    assert.equal((await post(server.api, await fixture(), { 'x-forwarded-for': '198.51.100.10' })).response.status, 200);
    const spoofed = await post(server.api, await fixture(), { 'x-forwarded-for': '203.0.113.20' });
    assert.equal(spoofed.response.status, 429);
  } finally { await server.close(); }
});

test('client disconnect aborts in-flight Solari work and suppresses a response write', async () => {
  let startedResolve;
  const started = new Promise((resolve) => { startedResolve = resolve; });
  let admittedSignal;
  const server = await listen({
    service: {
      async research(_payload, { signal }) {
        admittedSignal = signal;
        startedResolve();
        return new Promise((_resolve, reject) => {
          signal.addEventListener('abort', () => reject(new SolariResearchError(
            'solari_request_aborted',
            'The bounded Solari research request was cancelled.',
            { status: 408, retryable: true }
          )), { once: true });
        });
      }
    }
  });
  const encoded = Buffer.from(JSON.stringify(await fixture()));
  const request = Readable.from([encoded]);
  request.method = 'POST';
  request.url = '/v1/solari/research';
  request.headers = { 'content-type': 'application/json', 'content-length': String(encoded.length) };
  request.socket = { remoteAddress: '127.0.0.1' };
  const response = {
    status: null,
    headers: {},
    body: '',
    destroyed: false,
    writeHead(status, responseHeaders) { this.status = status; this.headers = responseHeaders; },
    end(value = '') { this.body += value; }
  };
  const handling = server.api.handler(request, response);
  await started;
  response.destroyed = true;
  request.aborted = true;
  request.emit('aborted');
  await handling;
  assert.equal(admittedSignal.aborted, true);
  assert.equal(response.status, null);
  assert.equal(response.body, '');
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

test('App Attest beta deployment rejects V1 operator-live execution before provider work', async () => {
  const operatorToken = 'operator-only-token-1234567890abcdef';
  let serviceCalls = 0;
  const server = await listen({
    config: {
      solariRateLimitPerMinute: 5,
      solariMaxBodyBytes: 32_768,
      solariBetaEnabled: true,
      solariLiveExecutionEnabled: true,
      solariOperatorToken: operatorToken
    },
    service: { async research() { serviceCalls += 1; return { executionMode: 'live' }; } }
  });
  try {
    const denied = await post(server.api, await liveDemoFixture(), { authorization: `Bearer ${operatorToken}` });
    assert.equal(denied.response.status, 503);
    assert.equal(denied.payload.error.code, 'solari_execution_mode_conflict');
    assert.equal(serviceCalls, 0);
  } finally { await server.close(); }
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
