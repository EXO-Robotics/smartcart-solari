import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../src/config.js';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { createSolariV3ResearchService, V3_RESULT_SCHEMA_ID } from '../src/solari/v3-research-service.js';

const requestExampleURL = new URL('../../contracts/v3/solari/examples/basket-research-request.example.json', import.meta.url);
const REPOSITORY = 'EXO-Robotics/smartcart-solari';
const EXPECTED_IDS = ['dg-chicken-rightsize-1lb', 'dg-chicken-value-3lb', 'dg-parmesan-rightsize-3oz', 'dg-parmesan-value-6oz', 'dg-penne-rightsize-12oz', 'dg-penne-value-16oz'];

function invariant(condition, message) {
  if (!condition) throw new Error(`V3 qualification failed: ${message}`);
}

function safeWorkflowValue(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._/-]{1,160}$/.test(value) ? value : null;
}

export async function buildV3QualificationRequest({ now = new Date(), requestID = randomUUID() } = {}) {
  invariant(typeof requestID === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestID), 'request ID must be a UUID');
  const request = JSON.parse(await readFile(requestExampleURL, 'utf8'));
  request.requestID = requestID.toLowerCase();
  request.submittedAt = now.toISOString();
  return request;
}

export async function createV3QualificationReceipt(result, {
  qualifiedAt = new Date().toISOString(),
  commit = process.env.GITHUB_SHA,
  workflowRunID = process.env.GITHUB_RUN_ID,
  workflowRunAttempt = process.env.GITHUB_RUN_ATTEMPT
} = {}) {
  const validator = await createContractValidator();
  invariant(validator.validate(V3_RESULT_SCHEMA_ID, result).valid, 'result does not satisfy BasketResearchResultV3');
  const sourceJSON = JSON.stringify(result);
  invariant(result.provenance.accessBoundary === 'operator-qualification', 'direct qualification must not claim App Attest');
  invariant(result.provenance.browser === 'solari-browser' && result.provenance.sandbox === 'solari-sandbox', 'Browser and Sandbox provenance are both required');
  invariant(result.provenance.fixtureReplay === false, 'fixture replay cannot qualify');
  invariant(result.provenance.resourceCleanup.browser === 'enforced-before-response' && result.provenance.resourceCleanup.sandbox === 'enforced-before-response', 'provider cleanup must complete before qualification');
  invariant(result.optimizer.authority === 'solari-sandbox' && result.optimizer.verification === 'smartcart-policy-invariants-no-local-global-argmin' && result.optimizer.policyInvariantsVerified === true, 'optimizer authority or scoped policy verification is incorrect');
  invariant(result.basket.observedSubtotal === 13.32 && result.comparison.cheapestAdequateSubtotal === 12.79 && result.comparison.premiumOverCheapest === 0.53, 'price comparison does not match the bounded V3 catalog');
  invariant(result.comparison.selectedAggregateSurplusOunces === 15 && result.comparison.cheapestAggregateSurplusOunces === 31 && result.comparison.surplusAvoidedOunces === 16, 'surplus comparison does not match the bounded V3 catalog');
  invariant(JSON.stringify(result.observations.map(({ retailerProductID }) => retailerProductID).sort()) === JSON.stringify(EXPECTED_IDS), 'the exact six V3 candidates were not observed');
  const selectedProductIDs = result.decisions.map((decision) => result.observations.find(({ observationID }) => observationID === decision.observationID)?.retailerProductID);
  invariant(JSON.stringify(selectedProductIDs) === JSON.stringify(['dg-chicken-rightsize-1lb', 'dg-penne-value-16oz', 'dg-parmesan-value-6oz']), 'Sandbox did not return the expected bounded V3 basket');
  invariant(!/rawText|pageBody/i.test(sourceJSON), 'raw page text crossed the structured qualification boundary');
  return {
    receiptVersion: 'smartcart-solari-v3-qualification-v1', qualifiedAt,
    submission: {
      repository: REPOSITORY,
      commit: typeof commit === 'string' && /^[0-9a-f]{40}$/.test(commit) ? commit : null
    },
    workflow: {
      runID: safeWorkflowValue(workflowRunID),
      runAttempt: safeWorkflowValue(workflowRunAttempt)
    },
    execution: {
      requestID: result.requestID, completedAt: result.completedAt,
      assuranceScope: 'server-side-direct-service-receipt', accessBoundary: 'operator-qualification',
      browser: 'solari-browser-provider-completed', sandbox: 'solari-sandbox-provider-completed',
      resourceCleanup: { browser: 'enforced-before-receipt', sandbox: 'enforced-before-receipt' },
      resultSha256: createHash('sha256').update(sourceJSON).digest('hex')
    },
    selectedProductIDs,
    basket: result.basket, comparison: result.comparison, optimizer: result.optimizer,
    evidence: result.observations, decisions: result.decisions, trust: result.trust
  };
}

export async function runV3Qualification({ config = loadConfig(), outputPath = process.env.SOLARI_V3_QUALIFICATION_OUTPUT, now = new Date() } = {}) {
  invariant(typeof config.solariApiKey === 'string' && config.solariApiKey.length > 0, 'server-side SOLARI_API_KEY is required');
  invariant(typeof config.solariDemoRetailerBaseUrl === 'string' && config.solariDemoRetailerBaseUrl.length > 0, 'SOLARI_DEMO_RETAILER_BASE_URL is required');
  invariant(typeof outputPath === 'string' && outputPath.length > 0, 'SOLARI_V3_QUALIFICATION_OUTPUT is required');
  const request = await buildV3QualificationRequest({ now });
  const service = createSolariV3ResearchService({ config, accessBoundary: 'operator-qualification' });
  const result = await service.research(request, { signal: AbortSignal.timeout(config.solariRequestTimeoutMs) });
  const receipt = await createV3QualificationReceipt(result);
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
  return { receipt, outputPath };
}

async function main() {
  const { receipt, outputPath } = await runV3Qualification();
  process.stdout.write('SOLARI_V3_QUALIFICATION=PASS\n');
  process.stdout.write(`RECEIPT=${outputPath}\n`);
  process.stdout.write(`REQUEST_ID=${receipt.execution.requestID}\n`);
  process.stdout.write(`BASKET_SUBTOTAL=${receipt.basket.observedSubtotal}\n`);
  process.stdout.write(`SURPLUS_AVOIDED_OUNCES=${receipt.comparison.surplusAvoidedOunces}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
