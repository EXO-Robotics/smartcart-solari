import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../src/config.js';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { createSolariV4ResearchService, V4_REQUEST_SCHEMA_ID, V4_RESULT_SCHEMA_ID } from '../src/solari/v4-research-service.js';

const requestExampleURL = new URL('../../contracts/v4/solari/examples/basket-research-request.example.json', import.meta.url);
const REPOSITORY = 'EXO-Robotics/smartcart-solari';

function invariant(condition, message) {
  if (!condition) throw new Error(`V4 qualification failed: ${message}`);
}

function safeWorkflowValue(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._/-]{1,160}$/.test(value) ? value : null;
}

function digest(value) {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

export async function buildV4QualificationRequest({ now = new Date(), requestID = randomUUID() } = {}) {
  invariant(typeof requestID === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestID), 'request ID must be a UUID');
  const request = JSON.parse(await readFile(requestExampleURL, 'utf8'));
  request.requestID = requestID.toLowerCase();
  request.submittedAt = now.toISOString();
  return request;
}

export async function createV4QualificationReceipt(result, {
  request,
  qualifiedAt = new Date().toISOString(),
  commit = process.env.GITHUB_SHA,
  workflowRunID = process.env.GITHUB_RUN_ID,
  workflowRunAttempt = process.env.GITHUB_RUN_ATTEMPT
} = {}) {
  const validator = await createContractValidator();
  invariant(request && validator.validate(V4_REQUEST_SCHEMA_ID, request).valid, 'request does not satisfy BasketResearchRequestV4');
  invariant(validator.validate(V4_RESULT_SCHEMA_ID, result).valid, 'result does not satisfy BasketResearchResultV4');
  invariant(result.requestID === request.requestID, 'result request identity does not match the qualified request');
  invariant(Date.parse(result.completedAt) >= Date.parse(request.submittedAt), 'result completion predates request submission');
  invariant(result.provenance.accessBoundary === 'operator-qualification', 'direct qualification must not claim App Attest');
  invariant(result.provenance.browser === 'solari-browser' && result.provenance.sandbox === 'solari-sandbox', 'Browser and Sandbox provenance are both required');
  invariant(result.provenance.fixtureReplay === false, 'fixture replay cannot qualify');
  invariant(result.provenance.resourceCleanup.browser === 'enforced-before-response' && result.provenance.resourceCleanup.sandbox === 'enforced-before-response', 'provider cleanup must complete before qualification');
  invariant(result.optimizer.authority === 'solari-sandbox'
    && result.optimizer.algorithmVersion === 'relative-surplus-premium-dp-v1'
    && result.optimizer.verification === 'smartcart-policy-invariants-no-local-global-argmin'
    && result.optimizer.policyInvariantsVerified === true, 'optimizer authority or scoped policy verification is incorrect');
  invariant(result.status === 'complete' && result.basket.completeness === 'complete', 'only a complete V4 research result can qualify');
  invariant(result.basket.pricedLineCount === request.requirements.length && result.basket.missingPriceLineCount === 0 && result.basket.unmatchedRequirementCount === 0, 'qualified basket coverage is incomplete');

  const expectedEvidence = request.requirements.flatMap((requirement) => requirement.candidateProductIDs.map((retailerProductID) => `${requirement.id}\n${retailerProductID}`)).sort();
  const actualEvidence = result.observations.map((observation) => `${observation.requirementID}\n${observation.retailerProductID}`).sort();
  invariant(JSON.stringify(actualEvidence) === JSON.stringify(expectedEvidence), 'Browser did not return the exact admitted V4 evidence set');
  invariant(new Set(result.observations.map(({ observationID }) => observationID)).size === result.observations.length, 'observation identities are not unique');
  invariant(new Set(result.decisions.map(({ requirementID }) => requirementID)).size === request.requirements.length, 'Sandbox did not return exactly one decision per requirement');
  invariant(result.decisions.every((decision) => result.observations.some((observation) => observation.observationID === decision.observationID
    && observation.requirementID === decision.requirementID && observation.retailerProductID === decision.retailerProductID)), 'Sandbox decisions are not bound to admitted Browser evidence');

  const resultJSON = JSON.stringify(result);
  invariant(!/rawText|pageBody|apiKey|operatorToken|authorization|bearer/i.test(resultJSON), 'raw page text or credential-shaped fields crossed the structured qualification boundary');
  const selectedProductIDs = result.decisions.map(({ retailerProductID }) => retailerProductID);
  return {
    receiptVersion: 'smartcart-solari-v4-qualification-v1', qualifiedAt,
    submission: { repository: REPOSITORY, commit: typeof commit === 'string' && /^[0-9a-f]{40}$/.test(commit) ? commit : null },
    workflow: { runID: safeWorkflowValue(workflowRunID), runAttempt: safeWorkflowValue(workflowRunAttempt) },
    execution: {
      requestID: result.requestID, submittedAt: request.submittedAt, completedAt: result.completedAt,
      assuranceScope: 'server-side-direct-service-receipt', accessBoundary: 'operator-qualification',
      browser: 'solari-browser-provider-completed', sandbox: 'solari-sandbox-provider-completed',
      resourceCleanup: { browser: 'enforced-before-receipt', sandbox: 'enforced-before-receipt' },
      requestSha256: digest(request), resultSha256: digest(result)
    },
    coverage: { researchedRequirementCount: request.requirements.length, observationCount: result.observations.length },
    selectedProductIDs,
    basket: result.basket, comparison: result.comparison, optimizer: result.optimizer,
    evidence: result.observations, decisions: result.decisions, trust: result.trust
  };
}

export async function runV4Qualification({
  config = loadConfig(), outputPath = process.env.SOLARI_V4_QUALIFICATION_OUTPUT,
  now = new Date(), researchService
} = {}) {
  invariant(typeof config.solariApiKey === 'string' && config.solariApiKey.length > 0, 'server-side SOLARI_API_KEY is required');
  invariant(typeof config.solariDemoRetailerBaseUrl === 'string' && config.solariDemoRetailerBaseUrl.length > 0, 'SOLARI_DEMO_RETAILER_BASE_URL is required');
  invariant(typeof outputPath === 'string' && outputPath.length > 0, 'SOLARI_V4_QUALIFICATION_OUTPUT is required');
  const request = await buildV4QualificationRequest({ now });
  const service = researchService ?? createSolariV4ResearchService({ config, accessBoundary: 'operator-qualification' });
  const result = await service.research(request, { signal: AbortSignal.timeout(config.solariRequestTimeoutMs) });
  const receipt = await createV4QualificationReceipt(result, { request });
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
  return { receipt, outputPath };
}

async function main() {
  const { receipt, outputPath } = await runV4Qualification();
  process.stdout.write('SOLARI_V4_QUALIFICATION=PASS\n');
  process.stdout.write(`RECEIPT=${outputPath}\n`);
  process.stdout.write(`REQUEST_ID=${receipt.execution.requestID}\n`);
  process.stdout.write(`RESEARCHED_REQUIREMENTS=${receipt.coverage.researchedRequirementCount}\n`);
  process.stdout.write(`OBSERVATIONS=${receipt.coverage.observationCount}\n`);
  process.stdout.write(`BASKET_SUBTOTAL=${receipt.basket.observedSubtotal}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
