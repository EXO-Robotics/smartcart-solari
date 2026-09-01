import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { WalmartFixtureReplayProvider } from '../src/solari/fixture-provider.js';
import { deterministicOptimize } from '../src/solari/optimizer.js';

const fixturePath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json'
);

async function requestFixture() {
  return JSON.parse(await readFile(fixturePath, 'utf8'));
}

test('deterministic package math selects the cheapest adequate recorded basket', async () => {
  const request = await requestFixture();
  const observations = await new WalmartFixtureReplayProvider({ now: () => Date.parse('2026-08-31T12:00:00Z') }).observe(request);
  const result = deterministicOptimize(request.requirements, observations, { allowStale: true });
  assert.equal(result.basket.completeness, 'complete');
  assert.equal(result.basket.observedSubtotal, 12.79);
  assert.equal(result.optimizer.independentlyVerified, false);
  assert.deepEqual(result.decisions.map((item) => ({
    id: item.observationID, count: item.packageCount, surplus: item.surplusQuantity
  })), [
    { id: 'obs-walmart-10414680', count: 1, surplus: 1.5 },
    { id: 'obs-walmart-10534084', count: 1, surplus: 4 },
    { id: 'obs-walmart-10452414', count: 1, surplus: 3 }
  ]);
});

test('unknown prices are never treated as zero and partial subtotal is explicit', async () => {
  const request = await requestFixture();
  const observations = await new WalmartFixtureReplayProvider({ now: () => Date.parse('2026-08-31T12:00:00Z') }).observe(request);
  for (const observation of observations.filter((item) => item.requirementID === request.requirements[1].id)) {
    observation.visiblePrice = null;
    observation.currency = null;
  }
  const result = deterministicOptimize(request.requirements, observations, { allowStale: true });
  assert.equal(result.basket.completeness, 'partial');
  assert.equal(result.basket.pricedLineCount, 2);
  assert.equal(result.basket.missingPriceLineCount, 1);
  assert.equal(result.basket.observedSubtotal, 11.55);
  assert.equal(result.decisions[1].lineTotal, null);
});

test('stale live observations are not admitted to a recommendation', async () => {
  const request = await requestFixture();
  const observations = await new WalmartFixtureReplayProvider({ now: () => Date.parse('2026-08-31T12:00:00Z') }).observe(request);
  assert.ok(observations.every((item) => item.freshness.status === 'stale'));
  const live = deterministicOptimize(request.requirements, observations);
  assert.equal(live.decisions.length, 0);
  assert.equal(live.basket.completeness, 'partial');
  assert.equal(live.basket.unmatchedRequirementCount, 3);
});
