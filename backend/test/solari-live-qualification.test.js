import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  assertQualificationEndpoint,
  createLiveQualificationReceipt
} from '../scripts/qualify-solari-live.mjs';

const resultPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../contracts/fixtures/v1/solari/chicken-parmesan-walmart-result.json'
);
const retailerBaseURL = 'https://exo-robotics.github.io/smartcart-solari/website/solari-demo';

async function liveResult() {
  const result = JSON.parse(await readFile(resultPath, 'utf8'));
  result.retailerID = 'smartcart-demo-grocer';
  result.executionMode = 'live';
  result.completedAt = '2026-09-01T12:00:30Z';
  result.optimizer = {
    method: 'solari-sandbox',
    algorithmVersion: 'smallest-sufficient-package-v1',
    independentlyVerified: true
  };
  result.provenance = {
    browser: 'solari-browser', sandbox: 'solari-sandbox', fixtureReplay: false,
    resourceCleanup: { browser: 'enforced-before-response', sandbox: 'enforced-before-response' }
  };
  result.trust = {
    priceClaim: 'observed-visible-price-not-guaranteed',
    accountAccessed: false,
    cartModified: false,
    checkoutAutomated: false,
    userControlsHandoff: true,
    limitations: [
      'Visible prices are timestamped observations, not guarantees or checkout quotes.',
      'No account, cart, or checkout action was performed.'
    ]
  };
  for (const observation of result.observations) {
    observation.sourceURL = `${retailerBaseURL}/retailer/product/${observation.retailerProductID}.html`;
    observation.observedAt = '2026-09-01T12:00:00Z';
    observation.collectionMethod = 'solari-browser-controlled-demo';
    observation.location = { kind: 'controlled-demo', label: 'SmartCart Demo Grocer synthetic catalog' };
    observation.freshness = { status: 'fresh', ageSeconds: 30, maxAgeSeconds: 86400 };
  }
  return result;
}

test('live qualifier creates a public receipt only for real Browser plus Sandbox provenance', async () => {
  const response = await liveResult();
  const responseText = JSON.stringify(response);
  const receipt = await createLiveQualificationReceipt({
    status: 200,
    dataMode: 'live',
    response,
    responseText,
    retailerBaseURL,
    commit: 'a'.repeat(40),
    workflowRunID: '12345',
    workflowRunAttempt: '1',
    qualifiedAt: '2026-09-01T12:01:00Z'
  });
  assert.equal(receipt.execution.assuranceScope, 'first-party-execution-receipt');
  assert.equal(receipt.execution.browser, 'solari-browser-provider-completed');
  assert.equal(receipt.execution.sandbox, 'solari-sandbox-provider-completed');
  assert.equal(receipt.basket.observedSubtotal, 12.79);
  assert.equal(receipt.evidence.length, 6);
  assert.ok(receipt.evidence.every((observation) => !('rawText' in observation)));
  assert.doesNotMatch(JSON.stringify(receipt), /authorization|operatorToken|apiKey|cdpEndpoint|wsEndpoint/i);
});

test('live qualifier rejects fixture replay, missing provenance, and misleading trust state', async () => {
  const fixture = JSON.parse(await readFile(resultPath, 'utf8'));
  await assert.rejects(() => createLiveQualificationReceipt({
    status: 200,
    dataMode: 'recorded_fixture',
    response: fixture,
    responseText: JSON.stringify(fixture),
    retailerBaseURL
  }), /expected x-smartcart-data-mode live/);

  const noSandbox = await liveResult();
  noSandbox.provenance.sandbox = 'not-run-fixture-replay';
  await assert.rejects(() => createLiveQualificationReceipt({
    status: 200,
    dataMode: 'live',
    response: noSandbox,
    responseText: JSON.stringify(noSandbox),
    retailerBaseURL
  }), /Solari Sandbox provenance is absent|does not satisfy/);

  const unsafe = await liveResult();
  unsafe.trust.cartModified = true;
  await assert.rejects(() => createLiveQualificationReceipt({
    status: 200,
    dataMode: 'live',
    response: unsafe,
    responseText: JSON.stringify(unsafe),
    retailerBaseURL
  }), /does not satisfy|retailer cart was modified/);
});

test('live qualifier rejects changed Sandbox selections and basket totals', async () => {
  const changedSelection = await liveResult();
  const parmesanDecision = changedSelection.decisions.find(
    ({ requirementID }) => requirementID === '20000000-0000-0000-0000-000000000003'
  );
  const shreddedParmesan = changedSelection.observations.find(
    ({ retailerProductID }) => retailerProductID === '623835750'
  );
  parmesanDecision.observationID = shreddedParmesan.observationID;
  parmesanDecision.lineTotal = shreddedParmesan.visiblePrice;
  changedSelection.basket.observedSubtotal = 14.69;
  await assert.rejects(() => createLiveQualificationReceipt({
    status: 200,
    dataMode: 'live',
    response: changedSelection,
    responseText: JSON.stringify(changedSelection),
    retailerBaseURL
  }), /frozen demo basket is not exactly|unexpected product ID/);

  const changedSubtotal = await liveResult();
  changedSubtotal.basket.observedSubtotal = 12.8;
  await assert.rejects(() => createLiveQualificationReceipt({
    status: 200,
    dataMode: 'live',
    response: changedSubtotal,
    responseText: JSON.stringify(changedSubtotal),
    retailerBaseURL
  }), /frozen demo basket is not exactly|does not satisfy/);
});

test('live qualifier can call only the loopback SmartCart endpoint', () => {
  assert.equal(
    assertQualificationEndpoint('http://127.0.0.1:8787/v1/solari/research'),
    'http://127.0.0.1:8787/v1/solari/research'
  );
  for (const endpoint of [
    'https://smartcart-barcode-api-omega.vercel.app/v1/solari/research',
    'http://localhost:8787/v1/solari/research',
    'http://127.0.0.1:8787/v1/demo/accounts'
  ]) assert.throws(() => assertQualificationEndpoint(endpoint));
});
