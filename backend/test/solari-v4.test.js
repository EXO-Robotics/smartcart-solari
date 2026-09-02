import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { promisify } from 'node:util';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { SolariBrowserProvider } from '../src/solari/browser-provider.js';
import { V4_PRODUCT_CATALOG } from '../src/solari/v4-constants.js';
import { assertBoundedV4Request, createSolariV4ResearchService } from '../src/solari/v4-research-service.js';
import { SolariV4SandboxOptimizer } from '../src/solari/v4-sandbox-provider.js';

const execFileAsync = promisify(execFile);
const requestExample = JSON.parse(await readFile(new URL('../../contracts/v4/solari/examples/basket-research-request.example.json', import.meta.url), 'utf8'));
const baseURL = 'https://demo.example/solari-demo';
const policy = requestExample.optimizationPolicy;
const uuid = (value) => `${String(value).padStart(8, '0')}-0000-4000-8000-000000000001`;

function requirement(index, name, requiredQuantity, unit, candidateProductIDs) {
  return { id: uuid(1000 + index), ingredientID: uuid(2000 + index), name, requestedQuantityText: `${requiredQuantity} ${unit}`, requiredQuantity, unit, candidateProductIDs };
}

function request(requirements) { return { ...structuredClone(requestExample), requirements }; }

test('V4 request schema and admission support 1, 2, and N requirements while enforcing all bounds before Browser', async () => {
  const validator = await createContractValidator();
  assert.equal(validator.validate('https://schemas.smartcart.app/v4/solari/basket-research-request.schema.json', requestExample).valid, true);
  const one = [requirement(1, 'Chicken breast', 680, 'g', ['dg4-chicken-value-3lb'])];
  const two = [...one, requirement(2, 'Olive oil', 30, 'ml', ['dg4-olive-oil-value-17floz'])];
  const many = [...two, requirement(3, 'Garlic cloves', 2, 'count', ['dg4-garlic-bulb-8ct']), requirement(4, 'Penne pasta', 340, 'g', ['dg4-penne-value-16oz']), requirement(5, 'Heavy cream', 240, 'ml', ['dg4-heavy-cream-value-16floz'])];
  for (const requirements of [one, two, many]) assert.equal(assertBoundedV4Request(request(requirements), baseURL).requirements.length, requirements.length);

  const unknown = request([requirement(1, 'Chicken breast', 680, 'g', ['dg4-unknown'])]);
  assert.throws(() => assertBoundedV4Request(unknown, baseURL), { code: 'v4_candidate_not_admitted' });
  const wrongDimension = request([requirement(1, 'Olive oil', 30, 'g', ['dg4-olive-oil-value-17floz'])]);
  assert.throws(() => assertBoundedV4Request(wrongDimension, baseURL), { code: 'v4_candidate_semantics_mismatch' });
  const tooMany = request(Array.from({ length: 13 }, (_, index) => requirement(index, 'Chicken breast', 100, 'g', ['dg4-chicken-value-3lb'])));
  assert.throws(() => assertBoundedV4Request(tooMany, baseURL), { code: 'v4_requirement_bounds' });
  const overObservations = request(Array.from({ length: 9 }, (_, index) => requirement(index, 'Chicken breast', 100, 'g', ['dg4-chicken-value-3lb', 'dg4-chicken-organic-1-5lb', 'dg4-chicken-free-range-3lb'])));
  assert.throws(() => assertBoundedV4Request(overObservations, baseURL));
});

test('V4 Browser normalizes supported mass, volume, and count package units into canonical evidence', async () => {
  const requirements = [
    { ...requirement(1, 'Chicken breast', 680, 'g', []), candidates: [{ retailerProductID: 'dg4-chicken-value-3lb', sourceURL: `${baseURL}/retailer-v4/product/dg4-chicken-value-3lb.html` }] },
    { ...requirement(2, 'Olive oil', 30, 'ml', []), candidates: [{ retailerProductID: 'dg4-olive-oil-value-17floz', sourceURL: `${baseURL}/retailer-v4/product/dg4-olive-oil-value-17floz.html` }] },
    { ...requirement(3, 'Garlic cloves', 2, 'count', []), candidates: [{ retailerProductID: 'dg4-garlic-bulb-8ct', sourceURL: `${baseURL}/retailer-v4/product/dg4-garlic-bulb-8ct.html` }] }
  ];
  const facts = {
    'dg4-chicken-value-3lb': ['3', 'lb', '947'],
    'dg4-olive-oil-value-17floz': ['17', 'fl oz', '612'],
    'dg4-garlic-bulb-8ct': ['8', 'count', '78']
  };
  let currentURL;
  const page = {
    async goto(url) { currentURL = url; }, url() { return currentURL; }, async waitForSelector() {},
    async evaluate() { const id = /\/([^/]+)\.html$/.exec(currentURL)[1]; const [packageQuantity, packageUnit, priceCents] = facts[id]; return { productID: id, title: id, packageQuantity, packageUnit, priceCents, currency: 'USD', catalogEra: 'current-v4', syntheticPrice: 'true' }; },
    async close() {}
  };
  const provider = new SolariBrowserProvider({ apiKey: 'server-only', now: () => Date.parse('2026-09-01T16:00:00Z'), solariFactory: () => ({ async launch() { return { async newPage() { return page; }, async close() {} }; }, async close() {} }) });
  const observations = await provider.observe({ ...requestExample, requirements }, { evidenceVersion: 'v4' });
  assert.deepEqual(observations.map(({ packageUnit }) => packageUnit), ['gram', 'milliliter', 'count']);
  assert.equal(observations[0].packageQuantity, 1360.77711);
  assert.ok(Math.abs(observations[1].packageQuantity - 502.7500025625) < 1e-9);
  assert.equal(observations[2].packageQuantity, 8);
  assert.ok(observations.every(({ catalogEra, syntheticPrice }) => catalogEra === 'current-v4' && syntheticPrice === true));
});

test('V4 Browser conversion matrix covers every admitted package-unit family', async () => {
  const cases = [
    ['dg4-chicken-value-3lb', 'oz', 'gram', 28.349523125], ['dg4-chicken-organic-1-5lb', 'lb', 'gram', 453.59237],
    ['dg4-chicken-free-range-3lb', 'g', 'gram', 1], ['dg4-penne-value-16oz', 'kg', 'gram', 1000],
    ['dg4-olive-oil-value-17floz', 'fl oz', 'milliliter', 29.5735295625], ['dg4-olive-oil-organic-17floz', 'ml', 'milliliter', 1],
    ['dg4-olive-oil-smooth-16floz', 'l', 'milliliter', 1000], ['dg4-heavy-cream-value-16floz', 'cup', 'milliliter', 236.5882365],
    ['dg4-heavy-cream-organic-16floz', 'tbsp', 'milliliter', 14.78676478125], ['dg4-parmesan-value-6oz', 'tsp', 'milliliter', 4.92892159375],
    ['dg4-garlic-bulb-8ct', 'ct', 'count', 1]
  ];
  let currentURL;
  const facts = new Map(cases.map(([id, unit]) => [id, unit]));
  const page = { async goto(url) { currentURL = url; }, url() { return currentURL; }, async waitForSelector() {}, async evaluate() { const id = /\/([^/]+)\.html$/.exec(currentURL)[1]; return { productID: id, title: id, packageQuantity: '1', packageUnit: facts.get(id), priceCents: '100', currency: 'USD', catalogEra: 'current-v4', syntheticPrice: 'true' }; }, async close() {} };
  const requirements = cases.map(([id], index) => ({ ...requirement(index, `Ingredient ${index}`, 1, 'g', []), candidates: [{ retailerProductID: id, sourceURL: `${baseURL}/retailer-v4/product/${id}.html` }] }));
  const provider = new SolariBrowserProvider({ apiKey: 'server-only', solariFactory: () => ({ async launch() { return { async newPage() { return page; }, async close() {} }; }, async close() {} }) });
  const observations = await provider.observe({ ...requestExample, requirements }, { evidenceVersion: 'v4' });
  observations.forEach((value, index) => { assert.equal(value.packageUnit, cases[index][2]); assert.ok(Math.abs(value.packageQuantity - cases[index][3]) < 1e-9); });
});

function observation(requirementValue, retailerProductID, packageQuantity, packageUnit, visiblePrice) {
  return {
    schemaVersion: 'retailer-observation-v4', observationID: `obs-${retailerProductID}`,
    requirementID: requirementValue.id, retailerProductID,
    sourceURL: requirementValue.candidates.find((candidate) => candidate.retailerProductID === retailerProductID).sourceURL,
    title: retailerProductID, packageDescription: `${packageQuantity} ${packageUnit}`,
    packageQuantity, packageUnit, visiblePrice, currency: 'USD', observedAt: '2026-09-01T16:00:00Z',
    confidence: 'high', ambiguityReasons: [], proteinGramsPerPackage: null,
    collectionMethod: 'solari-browser-controlled-demo', location: { kind: 'controlled-demo', label: 'SmartCart Demo Grocer synthetic catalog' },
    catalogEra: 'current-v4', syntheticPrice: true, freshness: { status: 'fresh', ageSeconds: 0, maxAgeSeconds: 86400 }
  };
}

test('V4 Sandbox uses exact premium-cents dynamic programming across mixed dimensions', async () => {
  const bounded = assertBoundedV4Request(request([
    requirement(1, 'Chicken breast', 100, 'g', ['dg4-chicken-value-3lb', 'dg4-chicken-organic-1-5lb']),
    requirement(2, 'Olive oil', 100, 'ml', ['dg4-olive-oil-value-17floz', 'dg4-olive-oil-organic-17floz'])
  ]), baseURL);
  const observations = [
    observation(bounded.requirements[0], 'dg4-chicken-value-3lb', 200, 'gram', 1),
    observation(bounded.requirements[0], 'dg4-chicken-organic-1-5lb', 100, 'gram', 1.5),
    observation(bounded.requirements[1], 'dg4-olive-oil-value-17floz', 200, 'milliliter', 1),
    observation(bounded.requirements[1], 'dg4-olive-oil-organic-17floz', 100, 'milliliter', 1.25)
  ];
  let kills = 0;
  const optimizer = new SolariV4SandboxOptimizer({ apiKey: 'server-only', clientFactory: () => ({ create: async () => ({ commands: { run: async (command, { args }) => { const { stdout, stderr } = await execFileAsync(command, args); return { exitCode: 0, stdout, stderr }; } }, kill: async () => { kills += 1; } }) }) });
  const result = await optimizer.optimize(bounded.requirements, observations, policy);
  assert.deepEqual(result.decisions.map(({ retailerProductID }) => retailerProductID), ['dg4-chicken-organic-1-5lb', 'dg4-olive-oil-organic-17floz']);
  assert.deepEqual(result.comparison, { cheapestAdequateSubtotal: 2, selectedSubtotal: 2.75, premiumOverCheapest: 0.75, cheapestAggregateRelativeSurplus: 2, selectedAggregateRelativeSurplus: 0, relativeSurplusAvoided: 2, maxPremiumOverCheapest: 0.75, currency: 'USD' });
  assert.equal(result.optimizer.algorithmVersion, 'relative-surplus-premium-dp-v1');
  assert.equal(kills, 1);
});

test('V4 Sandbox cancellation kills its acquired resource', async () => {
  const bounded = assertBoundedV4Request(request([requirement(1, 'Chicken breast', 100, 'g', ['dg4-chicken-value-3lb'])]), baseURL);
  const observations = [observation(bounded.requirements[0], 'dg4-chicken-value-3lb', 200, 'gram', 1)];
  let started; const began = new Promise((resolve) => { started = resolve; }); let kills = 0;
  const optimizer = new SolariV4SandboxOptimizer({ apiKey: 'server-only', clientFactory: () => ({ create: async () => ({ commands: { run: async () => { started(); return new Promise(() => {}); } }, kill: async () => { kills += 1; } }) }) });
  const controller = new AbortController();
  const running = optimizer.optimize(bounded.requirements, observations, policy, { signal: controller.signal });
  await began; controller.abort();
  await assert.rejects(() => running, { code: 'solari_request_aborted' });
  assert.equal(kills, 1);
});

test('V4 service returns schema-valid Browser evidence and Sandbox-authoritative mixed-dimension decisions', async () => {
  const toCanonical = (value, unit) => unit === 'lb' ? [value * 453.59237, 'gram']
    : unit === 'oz' ? [value * 28.349523125, 'gram']
      : unit === 'fl oz' ? [value * 29.5735295625, 'milliliter'] : [value, 'count'];
  const sandbox = new SolariV4SandboxOptimizer({ apiKey: 'server-only', clientFactory: () => ({ create: async () => ({ commands: { run: async (command, { args }) => { const { stdout, stderr } = await execFileAsync(command, args); return { exitCode: 0, stdout, stderr }; } }, kill: async () => {} }) }) });
  const service = createSolariV4ResearchService({
    config: { solariApiKey: 'server-only', solariDemoRetailerBaseUrl: baseURL, solariRequestTimeoutMs: 45_000 },
    now: () => Date.parse('2026-09-01T16:00:00Z'), demoHostLookup: async () => [{ address: '93.184.216.34', family: 4 }],
    browserProvider: { observe: async (bounded, options) => {
      assert.equal(options.evidenceVersion, 'v4');
      return bounded.requirements.flatMap((requirementValue) => requirementValue.candidates.map((candidate) => {
        const catalog = V4_PRODUCT_CATALOG[candidate.retailerProductID];
        const [packageQuantity, packageUnit] = toCanonical(catalog.packageQuantity, catalog.packageUnit);
        return observation(requirementValue, candidate.retailerProductID, packageQuantity, packageUnit, catalog.visiblePrice);
      }));
    } }, sandboxOptimizer: sandbox
  });
  const result = await service.research(requestExample);
  assert.equal(result.schemaVersion, 'solari-shopping-research-result-v4');
  assert.equal(result.observations.length, requestExample.requirements.flatMap(({ candidateProductIDs }) => candidateProductIDs).length);
  assert.equal(result.decisions.length, requestExample.requirements.length);
  assert.deepEqual(new Set(result.decisions.map(({ quantityUnit }) => quantityUnit)), new Set(['gram', 'milliliter', 'count']));
  assert.equal(result.optimizer.authority, 'solari-sandbox');
  assert.equal(result.provenance.fixtureReplay, false);
});

test('V4 public-demo service requires recorded Browser provenance and emits honest runtime stats', async () => {
  const toCanonical = (value, unit) => unit === 'lb' ? [value * 453.59237, 'gram']
    : unit === 'oz' ? [value * 28.349523125, 'gram']
      : unit === 'fl oz' ? [value * 29.5735295625, 'milliliter'] : [value, 'count'];
  const sandbox = new SolariV4SandboxOptimizer({ apiKey: 'server-only', clientFactory: () => ({ create: async () => ({ commands: { run: async (command, { args }) => { const { stdout, stderr } = await execFileAsync(command, args); return { exitCode: 0, stdout, stderr }; } }, kill: async () => {} }) }) });
  let recordedCalls = 0;
  let runtime = 1_000;
  const service = createSolariV4ResearchService({
    accessBoundary: 'public-demo',
    config: { solariApiKey: 'server-only', solariDemoRetailerBaseUrl: baseURL, solariRequestTimeoutMs: 45_000 },
    now: () => Date.parse('2026-09-02T14:00:00Z'),
    runtimeClock: () => { const value = runtime; runtime += 10_661; return value; },
    demoHostLookup: async () => [{ address: '93.184.216.34', family: 4 }],
    browserProvider: {
      observe: async () => { throw new Error('unrecorded path must not run'); },
      observeRecorded: async (bounded) => {
        recordedCalls += 1;
        return {
          observations: bounded.requirements.flatMap((requirementValue) => requirementValue.candidates.map((candidate) => {
            const catalog = V4_PRODUCT_CATALOG[candidate.retailerProductID];
            const [packageQuantity, packageUnit] = toCanonical(catalog.packageQuantity, catalog.packageUnit);
            return observation(requirementValue, candidate.retailerProductID, packageQuantity, packageUnit, catalog.visiblePrice);
          })),
          replay: { url: 'https://replay.example/run.ndjson?sig=test', expiresAt: '2026-09-02T14:10:00.000Z' }
        };
      }
    },
    sandboxOptimizer: sandbox
  });
  const publicResult = await service.research(requestExample);
  assert.equal(recordedCalls, 1);
  assert.equal(publicResult.provenance.accessBoundary, 'public-demo');
  assert.equal(publicResult.provenance.browserReplay.status, 'available');
  assert.equal(publicResult.runtimeStats.wallTimeMs, 10_661);
  assert.equal(publicResult.runtimeStats.browserObservationCount, 16);
  assert.equal(publicResult.runtimeStats.sandboxDecisionCount, 8);
  assert.equal(publicResult.runtimeStats.skippedRequirementCount, 0);
  assert.deepEqual(publicResult.runtimeStats.costTelemetry, { status: 'unavailable' });
  const cachedAfterReplayExpiry = structuredClone(publicResult);
  delete cachedAfterReplayExpiry.provenance.browserReplay;
  const validator = await createContractValidator();
  assert.equal(validator.validate('https://schemas.smartcart.app/v4/solari/basket-research-result.schema.json', cachedAfterReplayExpiry).valid, true);
});
