import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { promisify } from 'node:util';
import { buildV4QualificationRequest, createV4QualificationReceipt, runV4Qualification } from '../scripts/qualify-solari-v4.mjs';
import { V4_PRODUCT_CATALOG } from '../src/solari/v4-constants.js';
import { createSolariV4ResearchService } from '../src/solari/v4-research-service.js';
import { SolariV4SandboxOptimizer } from '../src/solari/v4-sandbox-provider.js';

const execFileAsync = promisify(execFile);
const fixedNow = new Date('2026-09-01T16:00:00Z');
const request = await buildV4QualificationRequest({ now: fixedNow, requestID: '80000000-0000-4000-8000-000000000001' });
const baseURL = 'https://demo.example/solari-demo';

function toCanonical(value, unit) {
  if (unit === 'lb') return [value * 453.59237, 'gram'];
  if (unit === 'oz') return [value * 28.349523125, 'gram'];
  if (unit === 'fl oz') return [value * 29.5735295625, 'milliliter'];
  return [value, 'count'];
}

function observation(requirement, candidate, product) {
  const [packageQuantity, packageUnit] = toCanonical(product.packageQuantity, product.packageUnit);
  return {
    schemaVersion: 'retailer-observation-v4', observationID: `obs-${candidate.retailerProductID}`,
    requirementID: requirement.id, retailerProductID: candidate.retailerProductID, sourceURL: candidate.sourceURL,
    title: product.title, packageDescription: `${product.packageQuantity} ${product.packageUnit}`,
    packageQuantity, packageUnit, visiblePrice: product.visiblePrice, currency: 'USD',
    observedAt: fixedNow.toISOString(), confidence: 'high', ambiguityReasons: [], proteinGramsPerPackage: null,
    collectionMethod: 'solari-browser-controlled-demo', location: { kind: 'controlled-demo', label: 'SmartCart Demo Grocer synthetic catalog' },
    catalogEra: 'current-v4', syntheticPrice: true, freshness: { status: 'fresh', ageSeconds: 0, maxAgeSeconds: 86400 }
  };
}

async function qualifiedResult() {
  const sandbox = new SolariV4SandboxOptimizer({ apiKey: 'server-only', clientFactory: () => ({ create: async () => ({
    commands: { run: async (command, { args }) => { const { stdout, stderr } = await execFileAsync(command, args); return { exitCode: 0, stdout, stderr }; } }, kill: async () => {}
  }) }) });
  const service = createSolariV4ResearchService({
    config: { solariApiKey: 'server-only', solariDemoRetailerBaseUrl: baseURL, solariRequestTimeoutMs: 45_000 },
    now: () => fixedNow.getTime(), demoHostLookup: async () => [{ address: '93.184.216.34', family: 4 }],
    accessBoundary: 'operator-qualification',
    browserProvider: { observe: async (bounded, options) => {
      assert.equal(options.evidenceVersion, 'v4');
      return bounded.requirements.flatMap((requirement) => requirement.candidates.map((candidate) => observation(requirement, candidate, V4_PRODUCT_CATALOG[candidate.retailerProductID])));
    } }, sandboxOptimizer: sandbox
  });
  return service.research(request);
}

const result = await qualifiedResult();

test('V4 qualification receipt is sanitized, exact-request-bound, and truthfully operator-qualified', async () => {
  const receipt = await createV4QualificationReceipt(result, {
    request, qualifiedAt: '2026-09-01T16:01:00Z', commit: '0123456789abcdef0123456789abcdef01234567', workflowRunID: '33540000000', workflowRunAttempt: '1'
  });
  assert.deepEqual(receipt.submission, { repository: 'EXO-Robotics/smartcart-solari', commit: '0123456789abcdef0123456789abcdef01234567' });
  assert.deepEqual(receipt.workflow, { runID: '33540000000', runAttempt: '1' });
  assert.equal(receipt.execution.accessBoundary, 'operator-qualification');
  assert.equal(receipt.execution.assuranceScope, 'server-side-direct-service-receipt');
  assert.equal(receipt.execution.requestSha256, createHash('sha256').update(JSON.stringify(request)).digest('hex'));
  assert.equal(receipt.execution.resultSha256, createHash('sha256').update(JSON.stringify(result)).digest('hex'));
  assert.deepEqual(receipt.coverage, { researchedRequirementCount: 3, observationCount: 7 });
  assert.equal(receipt.selectedProductIDs.length, 3);
  assert.equal(receipt.optimizer.authority, 'solari-sandbox');
  assert.doesNotMatch(JSON.stringify(receipt), /rawText|pageBody|apiKey|operatorToken|authorization|bearer/i);
});

test('V4 qualification digest is derived only from the validated result and request', async () => {
  const receipt = await createV4QualificationReceipt(result, { request, sourceJSON: '{}', requestJSON: '{}' });
  assert.notEqual(receipt.execution.resultSha256, createHash('sha256').update('{}').digest('hex'));
  assert.notEqual(receipt.execution.requestSha256, createHash('sha256').update('{}').digest('hex'));
});

test('V4 qualification rejects App Attest, fixture, failed cleanup, changed evidence, and raw provider fields', async () => {
  const cases = [
    (value) => { value.provenance.accessBoundary = 'apple-app-attest'; },
    (value) => { value.provenance.fixtureReplay = true; },
    (value) => { value.provenance.resourceCleanup.browser = 'not-confirmed'; },
    (value) => { value.observations[0].retailerProductID = 'dg4-foreign'; },
    (value) => { value.observations[0].rawText = 'page body'; }
  ];
  for (const mutate of cases) {
    const changed = structuredClone(result); mutate(changed);
    await assert.rejects(() => createV4QualificationReceipt(changed, { request }), /V4 qualification failed/);
  }
});

test('V4 qualification rejects mismatched requests, absent credentials, and invented publication identity', async () => {
  const other = structuredClone(request); other.requestID = '80000000-0000-4000-8000-000000000002';
  await assert.rejects(() => createV4QualificationReceipt(result, { request: other }), /request identity/);
  await assert.rejects(() => runV4Qualification({ config: { solariApiKey: undefined, solariDemoRetailerBaseUrl: baseURL }, outputPath: '/tmp/not-written' }), /SOLARI_API_KEY/);
  const receipt = await createV4QualificationReceipt(result, { request, commit: 'bad', workflowRunID: 'bad value', workflowRunAttempt: '?' });
  assert.deepEqual(receipt.submission, { repository: 'EXO-Robotics/smartcart-solari', commit: null });
  assert.deepEqual(receipt.workflow, { runID: null, runAttempt: null });
});

test('V4 qualification request exercises mixed dimensions and the bounded DP policy', async () => {
  assert.equal(request.schemaVersion, 'solari-shopping-research-request-v4');
  assert.deepEqual(request.requirements.map(({ unit }) => unit), ['g', 'ml', 'count']);
  assert.equal(request.requirements.flatMap(({ candidateProductIDs }) => candidateProductIDs).length, 7);
  assert.deepEqual(request.optimizationPolicy, { objective: 'minimize-aggregate-relative-surplus', maxPremiumOverCheapest: 0.75, currency: 'USD', tieBreak: ['observed-subtotal', 'retailer-product-id'] });
  const generated = await buildV4QualificationRequest({ now: fixedNow });
  assert.match(generated.requestID, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  await assert.rejects(() => buildV4QualificationRequest({ requestID: 'qualification-prefixed-id' }), /request ID must be a UUID/);
});
