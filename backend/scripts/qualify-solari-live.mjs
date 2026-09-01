import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { SOLARI_RESULT_SCHEMA_ID } from '../src/solari/constants.js';
import { buildSolariDemoRequest } from './build-solari-demo-request.mjs';

const DEFAULT_RETAILER_BASE_URL = 'https://exo-robotics.github.io/smartcart-solari/website/solari-demo';
const DEFAULT_ENDPOINT = 'http://127.0.0.1:8787/v1/solari/research';
const REPOSITORY = 'EXO-Robotics/smartcart-solari';
const EXPECTED_PRODUCT_IDS = ['10307238', '10414680', '10452414', '10534084', '47088917', '623835750'];
const EXPECTED_SELECTIONS = Object.freeze({
  '20000000-0000-0000-0000-000000000001': { productID: '10414680', packageCount: 1, lineTotal: 9.47 },
  '20000000-0000-0000-0000-000000000002': { productID: '10534084', packageCount: 1, lineTotal: 1.24 },
  '20000000-0000-0000-0000-000000000003': { productID: '10452414', packageCount: 1, lineTotal: 2.08 }
});

function invariant(condition, message) {
  if (!condition) throw new Error(`Live qualification failed: ${message}`);
}

export function assertQualificationEndpoint(value) {
  const url = new URL(value);
  invariant(
    url.href === DEFAULT_ENDPOINT,
    'the qualification client may call only the loopback SmartCart research endpoint'
  );
  return url.href;
}

function sanitizeObservation(observation) {
  const {
    rawText: _rawText,
    ...publicEvidence
  } = observation;
  return publicEvidence;
}

function safeWorkflowValue(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._/-]{1,160}$/.test(value) ? value : null;
}

export async function createLiveQualificationReceipt({
  status,
  dataMode,
  response,
  responseText,
  retailerBaseURL = DEFAULT_RETAILER_BASE_URL,
  commit = process.env.GITHUB_SHA,
  workflowRunID = process.env.GITHUB_RUN_ID,
  workflowRunAttempt = process.env.GITHUB_RUN_ATTEMPT,
  qualifiedAt = new Date().toISOString()
}) {
  invariant(status === 200, `expected HTTP 200, received ${status}`);
  invariant(dataMode === 'live', `expected x-smartcart-data-mode live, received ${dataMode ?? 'missing'}`);

  const validator = await createContractValidator();
  const validation = validator.validate(SOLARI_RESULT_SCHEMA_ID, response);
  invariant(validation.valid, 'response does not satisfy BasketResearchResultV1');
  invariant(response.executionMode === 'live', 'response is not live execution');
  invariant(response.retailerID === 'smartcart-demo-grocer', 'response is not the owned Demo Grocer');
  invariant(response.provenance.browser === 'solari-browser', 'Solari Browser provenance is absent');
  invariant(response.provenance.sandbox === 'solari-sandbox', 'Solari Sandbox provenance is absent');
  invariant(response.provenance.fixtureReplay === false, 'fixture replay cannot qualify as live evidence');
  invariant(response.provenance.resourceCleanup?.browser === 'enforced-before-response', 'Browser cleanup enforcement is absent');
  invariant(response.provenance.resourceCleanup?.sandbox === 'enforced-before-response', 'Sandbox cleanup enforcement is absent');
  invariant(response.optimizer.method === 'solari-sandbox', 'Sandbox is not the named optimizer');
  invariant(response.optimizer.independentlyVerified === true, 'Sandbox output was not independently verified');
  invariant(response.observations.length === 6, 'the bounded six-candidate research set is incomplete');
  invariant(response.decisions.length === 3, 'the three shopping requirements were not all decided');
  invariant(response.status === 'complete' && response.basket.completeness === 'complete', 'basket is incomplete');
  invariant(response.basket.pricedLineCount === 3, 'all three chosen lines must have visible prices');
  invariant(response.basket.observedSubtotal === 12.79 && response.basket.currency === 'USD', 'the frozen demo basket is not exactly $12.79 USD');
  invariant(response.trust.priceClaim === 'observed-visible-price-not-guaranteed', 'price disclosure is incorrect');
  invariant(response.trust.accountAccessed === false, 'a retailer account was accessed');
  invariant(response.trust.cartModified === false, 'a retailer cart was modified');
  invariant(response.trust.checkoutAutomated === false, 'checkout was automated');
  invariant(response.trust.userControlsHandoff === true, 'user-controlled handoff was not preserved');

  const admittedBase = new URL(retailerBaseURL);
  const observedProductIDs = response.observations.map(({ retailerProductID }) => retailerProductID).sort();
  invariant(JSON.stringify(observedProductIDs) === JSON.stringify(EXPECTED_PRODUCT_IDS), 'the exact six admitted product IDs were not observed');
  const observationsByID = new Map(response.observations.map((observation) => [observation.observationID, observation]));
  for (const decision of response.decisions) {
    const expected = EXPECTED_SELECTIONS[decision.requirementID];
    const observation = observationsByID.get(decision.observationID);
    invariant(expected && observation, 'a decision does not reference the frozen demo evidence set');
    invariant(observation.retailerProductID === expected.productID, 'Sandbox selected an unexpected product ID');
    invariant(decision.packageCount === expected.packageCount, 'Sandbox selected an unexpected package count');
    invariant(decision.lineTotal === expected.lineTotal, 'Sandbox returned an unexpected line total');
  }
  for (const observation of response.observations) {
    const source = new URL(observation.sourceURL);
    invariant(source.origin === admittedBase.origin, 'an observation came from an unowned origin');
    invariant(source.pathname.startsWith(`${admittedBase.pathname.replace(/\/$/, '')}/retailer/product/`), 'an observation came from an unadmitted route');
    invariant(observation.collectionMethod === 'solari-browser-controlled-demo', 'an observation lacks controlled Browser provenance');
    invariant(observation.location?.kind === 'controlled-demo', 'an observation is mislabeled as a real retailer location');
    invariant(observation.visiblePrice !== null && observation.currency === 'USD', 'a selected research candidate lacks a visible USD price');
  }

  const completedAt = Date.parse(response.completedAt);
  const observedTimes = response.observations.map(({ observedAt }) => Date.parse(observedAt));
  invariant(Number.isFinite(completedAt) && observedTimes.every(Number.isFinite), 'timestamps are invalid');
  invariant(observedTimes.every((time) => Math.abs(completedAt - time) <= 10 * 60 * 1000), 'observations are not from the completed live run');

  const sourceHash = createHash('sha256').update(responseText).digest('hex');
  return {
    receiptVersion: 'smartcart-solari-live-qualification-v1',
    qualifiedAt,
    submission: {
      repository: REPOSITORY,
      commit: typeof commit === 'string' && /^[0-9a-f]{40}$/.test(commit) ? commit : null
    },
    workflow: {
      runID: safeWorkflowValue(workflowRunID),
      runAttempt: safeWorkflowValue(workflowRunAttempt)
    },
    useCase: {
      meal: 'Chicken Parmesan Pasta',
      pantryExcluded: ['olive oil', 'garlic'],
      retailer: 'SmartCart Demo Grocer synthetic catalog',
      retailerBaseURL: admittedBase.href.replace(/\/$/, ''),
      finalAuthority: 'user-controlled-retailer-handoff'
    },
    execution: {
      requestID: response.requestID,
      responseCompletedAt: response.completedAt,
      dataMode,
      responseSha256: sourceHash,
      assuranceScope: 'first-party-execution-receipt',
      browser: 'solari-browser-provider-completed',
      sandbox: 'solari-sandbox-provider-completed',
      fixtureReplay: false,
      resourceCleanup: {
        browserPagesSessionAndClient: 'first-party-enforced-before-success-response',
        sandbox: 'first-party-enforced-before-success-response'
      }
    },
    evidence: response.observations.map(sanitizeObservation),
    decisions: response.decisions,
    basket: response.basket,
    optimizer: response.optimizer,
    trust: response.trust
  };
}

export async function runLiveQualification({
  endpoint = process.env.SOLARI_QUALIFICATION_ENDPOINT ?? DEFAULT_ENDPOINT,
  operatorToken = process.env.SOLARI_OPERATOR_TOKEN,
  retailerBaseURL = process.env.SOLARI_DEMO_RETAILER_BASE_URL ?? DEFAULT_RETAILER_BASE_URL,
  outputPath = process.env.SOLARI_QUALIFICATION_OUTPUT
} = {}) {
  const admittedEndpoint = assertQualificationEndpoint(endpoint);
  invariant(typeof operatorToken === 'string' && /^[A-Za-z0-9._~-]{32,256}$/.test(operatorToken), 'operator token is missing or malformed');
  invariant(typeof outputPath === 'string' && outputPath.length > 0, 'SOLARI_QUALIFICATION_OUTPUT is required');

  const request = await buildSolariDemoRequest(retailerBaseURL);
  const response = await fetch(admittedEndpoint, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${operatorToken}`,
      'content-type': 'application/json'
    },
    body: JSON.stringify(request),
    signal: AbortSignal.timeout(120_000)
  });
  const responseText = await response.text();
  let payload;
  try {
    payload = JSON.parse(responseText);
  } catch {
    throw new Error(`Live qualification failed: endpoint returned non-JSON HTTP ${response.status}`);
  }
  if (!response.ok) {
    const code = typeof payload?.error?.code === 'string' ? payload.error.code : 'unknown_error';
    throw new Error(`Live qualification failed: endpoint returned HTTP ${response.status} (${code})`);
  }

  const receipt = await createLiveQualificationReceipt({
    status: response.status,
    dataMode: response.headers.get('x-smartcart-data-mode'),
    response: payload,
    responseText,
    retailerBaseURL
  });
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
  return { receipt, outputPath };
}

async function main() {
  const { receipt, outputPath } = await runLiveQualification();
  process.stdout.write(`LIVE_SOLARI_QUALIFICATION=PASS\n`);
  process.stdout.write(`RECEIPT=${outputPath}\n`);
  process.stdout.write(`REQUEST_ID=${receipt.execution.requestID}\n`);
  process.stdout.write(`BASKET_SUBTOTAL=${receipt.basket.observedSubtotal}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
