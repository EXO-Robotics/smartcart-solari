import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:http';
import test from 'node:test';
import { createLogger } from '../src/lib/logger.js';
import { createPublicHandoffApi } from '../src/public-handoff-api.js';
import { HandoffClaimService } from '../src/handoff/handoff-claim-service.js';
import { contractEnvelope } from '../src/contracts/envelope.js';
import { RecipeTextAnalyzer } from '../src/trip-intelligence/recipe-text-analyzer.js';

const secret = Buffer.alloc(32, 0x51).toString('base64url');
const fixedNow = Date.UTC(2026, 7, 19, 12, 0, 0);

function handoffRecipe() {
  const recipeText = '1 cup Parmesan cheese';
  const result = new RecipeTextAnalyzer().analyze({
    recipeId: '00000000-0000-4000-8000-000000000001',
    title: 'API recipe',
    servings: 4,
    recipeText
  });
  return {
    sourceType: 'text',
    recipeText,
    analysis: contractEnvelope({
      requestId: '10000000-0000-4000-8000-000000000001',
      ...result
    }),
    quantityReviewIngredientIds: []
  };
}

function claimService() {
  return new HandoffClaimService({
    secret,
    baseUrl: 'https://smartcart.example',
    now: () => fixedNow,
    randomBytesImpl: () => Buffer.alloc(12, 0x52)
  });
}

async function listen(options = {}) {
  const { handler } = createPublicHandoffApi({
    claimService: options.claimService ?? claimService(),
    config: {
      env: 'test',
      host: '127.0.0.1',
      port: 0,
      smartCartHandoffClaimRateLimitPerMinute: 30,
      smartCartHandoffTokenRateLimitPerMinute: 6,
      ...(options.config ?? {})
    },
    logger: options.logger,
    ipLimiter: options.ipLimiter,
    tokenLimiter: options.tokenLimiter,
    now: () => fixedNow
  });
  const server = createServer(options.preparsed
    ? async (request, response) => {
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        request.body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        await handler(request, response);
      }
    : handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  return {
    url: `http://127.0.0.1:${address.port}/v1/handoffs/claim`,
    async close() {
      server.close();
      await once(server, 'close');
    }
  };
}

async function createClaimToken(service) {
  const created = await service.create({ recipes: [handoffRecipe()] });
  return new URL(created.data.claimUrl).hash.slice(1);
}

function requestBody(token) {
  return {
    schemaVersion: '1.0',
    requestId: '20000000-0000-4000-8000-000000000001',
    data: { claimToken: token }
  };
}

test('claim endpoint validates and returns a no-store contract without echoing its bearer', async () => {
  const service = claimService();
  const token = await createClaimToken(service);
  const http = await listen({ claimService: service });
  try {
    const response = await fetch(http.url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(requestBody(token))
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
    const payload = await response.json();
    assert.equal(payload.requestId, '20000000-0000-4000-8000-000000000001');
    assert.equal(payload.data.audience, 'smartcart-ios');
    assert.equal(JSON.stringify(payload).includes(token), false);
  } finally {
    await http.close();
  }
});

test('claim endpoint accepts only a contract-compatible UUID as its trace ID', async () => {
  const service = claimService();
  const http = await listen({ claimService: service });
  const malformedTrace = 'a'.repeat(36);
  const validTrace = '30000000-0000-4000-8000-000000000001';
  try {
    const malformedResponse = await fetch(http.url, {
      headers: { 'x-request-id': malformedTrace }
    });
    assert.equal(malformedResponse.status, 404);
    const generatedTrace = malformedResponse.headers.get('x-request-id');
    assert.notEqual(generatedTrace, malformedTrace);
    assert.match(
      generatedTrace,
      /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/iu
    );
    assert.equal((await malformedResponse.json()).requestId, generatedTrace);

    const validResponse = await fetch(http.url, {
      headers: { 'x-request-id': validTrace }
    });
    assert.equal(validResponse.status, 404);
    assert.equal(validResponse.headers.get('x-request-id'), validTrace);
    assert.equal((await validResponse.json()).requestId, validTrace);
  } finally {
    await http.close();
  }
});

test('claim endpoint handles Vercel-preparsed JSON and enforces token attempt limits', async () => {
  const service = claimService();
  const token = await createClaimToken(service);
  const tokenLimiter = {
    calls: 0,
    consume() {
      this.calls += 1;
      return {
        allowed: this.calls === 1,
        limit: 1,
        remaining: 0,
        resetAt: fixedNow + 60_000,
        retryAfterSeconds: 60
      };
    }
  };
  const http = await listen({ claimService: service, tokenLimiter, preparsed: true });
  try {
    const options = {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(requestBody(token))
    };
    assert.equal((await fetch(http.url, options)).status, 200);
    const limited = await fetch(http.url, options);
    assert.equal(limited.status, 429);
    assert.equal(limited.headers.get('retry-after'), '60');
  } finally {
    await http.close();
  }
});

test('claim endpoint rejects malformed and oversized requests before unsealing', async () => {
  const http = await listen({ config: { maxBodyBytes: 128 } });
  try {
    const malformed = await fetch(http.url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ schemaVersion: '1.0', requestId: 'bad', data: { claimToken: 'bad' } })
    });
    assert.equal(malformed.status, 400);

    const oversized = await fetch(http.url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ padding: 'x'.repeat(512) })
    });
    assert.equal(oversized.status, 413);
  } finally {
    await http.close();
  }
});

test('handoff logs contain neither bearer token nor recipe payload', async () => {
  const lines = [];
  const logger = createLogger({
    level: 'info',
    sink: (line) => lines.push(line),
    now: () => new Date(fixedNow),
    dataMode: 'bounded-handoff-v1'
  });
  const service = claimService();
  const token = await createClaimToken(service);
  const http = await listen({ claimService: service, logger });
  try {
    await fetch(http.url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(requestBody(token))
    });
    const logged = lines.join('\n');
    assert.equal(logged.includes(token), false);
    assert.equal(logged.includes('Parmesan'), false);
  } finally {
    await http.close();
  }
});
