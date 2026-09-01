import { createContractValidator } from '../contracts/contract-validator.js';
import { SolariBrowserProvider } from './browser-provider.js';
import { controlledDemoProductURL } from './constants.js';
import { SolariResearchError } from './errors.js';
import { assertPublicDemoBaseURL } from './url-policy.js';
import {
  V3_DEMO_ID,
  V3_MAX_PREMIUM_OVER_CHEAPEST,
  V3_PRODUCT_REQUIREMENT,
  V3_STORE_REFERENCE
} from './v3-constants.js';
import { SolariV3SandboxOptimizer } from './v3-sandbox-provider.js';

export const V3_REQUEST_SCHEMA_ID = 'https://schemas.smartcart.app/v3/solari/basket-research-request.schema.json';
export const V3_RESULT_SCHEMA_ID = 'https://schemas.smartcart.app/v3/solari/basket-research-result.schema.json';
export const V3_OBSERVATION_SCHEMA_ID = 'https://schemas.smartcart.app/v3/solari/retailer-observation.schema.json';

const EXPECTED_POLICY = Object.freeze({
  objective: 'minimize-package-surplus',
  maxPremiumOverCheapest: V3_MAX_PREMIUM_OVER_CHEAPEST,
  currency: 'USD',
  tieBreak: ['observed-subtotal', 'retailer-product-id']
});

function structuredObservation(value) {
  return {
    schemaVersion: 'retailer-observation-v3', observationID: value.observationID,
    requirementID: value.requirementID, retailerProductID: value.retailerProductID,
    sourceURL: value.sourceURL, title: value.title, packageDescription: value.packageDescription,
    packageQuantity: value.packageQuantity, packageUnit: value.packageUnit,
    visiblePrice: value.visiblePrice, currency: value.currency, observedAt: value.observedAt,
    confidence: value.confidence, ambiguityReasons: value.ambiguityReasons,
    proteinGramsPerPackage: value.proteinGramsPerPackage,
    collectionMethod: value.collectionMethod, location: value.location,
    catalogEra: value.catalogEra, syntheticPrice: value.syntheticPrice, freshness: value.freshness
  };
}

function assertBoundedRequest(request, baseURL) {
  const policy = request.optimizationPolicy;
  const policyMatches = policy?.objective === EXPECTED_POLICY.objective
    && policy.maxPremiumOverCheapest === EXPECTED_POLICY.maxPremiumOverCheapest
    && policy.currency === EXPECTED_POLICY.currency
    && Array.isArray(policy.tieBreak)
    && policy.tieBreak.length === 2
    && policy.tieBreak[0] === EXPECTED_POLICY.tieBreak[0]
    && policy.tieBreak[1] === EXPECTED_POLICY.tieBreak[1];
  if (request.demoID !== V3_DEMO_ID || request.retailerID !== 'smartcart-demo-grocer' || request.executionMode !== 'live' || request.storeReference !== V3_STORE_REFERENCE || !policyMatches) {
    throw new SolariResearchError('v3_policy_not_allowed', 'The V3 beta admits only its fixed owned Demo Grocer optimization policy.', { status: 400 });
  }
  const requirementIDs = new Set(), ingredientIDs = new Set(), products = new Set(), groupsSeen = new Set();
  for (const requirement of request.requirements) {
    const requirementID = requirement.id.toLowerCase(), ingredientID = requirement.ingredientID.toLowerCase();
    if (requirementIDs.has(requirementID) || ingredientIDs.has(ingredientID)) throw new SolariResearchError('duplicate_requirement_identity', 'Requirement and ingredient IDs must be unique.', { status: 400 });
    requirementIDs.add(requirementID); ingredientIDs.add(ingredientID);
    const groups = new Set(requirement.candidateProductIDs.map((id) => V3_PRODUCT_REQUIREMENT[id]));
    if (groups.has(undefined) || groups.size !== 1) throw new SolariResearchError('v3_candidate_group_mismatch', 'Each requirement must use one admitted V3 product group.', { status: 400 });
    const group = [...groups][0], name = requirement.name.toLowerCase();
    const semanticMatch = group === 'chicken' ? name.includes('chicken') && requirement.unit === 'lb'
      : group === 'penne' ? (name.includes('penne') || name.includes('pasta')) && requirement.unit === 'oz'
        : name.includes('parmesan') && requirement.unit === 'oz';
    const quantityMatches = group === 'chicken' ? requirement.requiredQuantity === 1.5
      : group === 'penne' ? requirement.requiredQuantity === 12
        : requirement.requiredQuantity === 3;
    if (!semanticMatch || !quantityMatches || groupsSeen.has(group)) throw new SolariResearchError('v3_candidate_semantics_mismatch', 'V3 candidates must cover each canonical ingredient and reviewed quantity exactly once.', { status: 400 });
    groupsSeen.add(group);
    for (const id of requirement.candidateProductIDs) {
      if (products.has(id)) throw new SolariResearchError('duplicate_candidate', 'Candidate product IDs must be unique across the request.', { status: 400 });
      products.add(id);
    }
  }
  if (groupsSeen.size !== 3 || products.size !== 6) throw new SolariResearchError('v3_candidate_set_incomplete', 'The fixed V3 demo requires all three ingredient groups and six candidates.', { status: 400 });
  return {
    ...request,
    requirements: request.requirements.map(({ candidateProductIDs, ...requirement }) => ({
      ...requirement,
      candidates: candidateProductIDs.map((retailerProductID) => ({ retailerProductID, sourceURL: controlledDemoProductURL(baseURL, retailerProductID) }))
    }))
  };
}

function assertObservationSet(bounded, observations, validator) {
  const expected = new Map(bounded.requirements.flatMap((requirement) => requirement.candidates.map((candidate) => [
    `${requirement.id}\n${candidate.retailerProductID}`,
    candidate.sourceURL
  ])));
  const seen = new Set(), observationIDs = new Set();
  if (observations.length !== expected.size) throw new SolariResearchError('v3_evidence_set_incomplete', 'V3 Browser evidence did not contain the exact six admitted candidates.', { status: 502 });
  for (const observation of observations) {
    validator.assert(V3_OBSERVATION_SCHEMA_ID, observation);
    const identity = `${observation.requirementID}\n${observation.retailerProductID}`;
    if (!expected.has(identity) || expected.get(identity) !== observation.sourceURL || seen.has(identity) || observationIDs.has(observation.observationID) || observation.freshness.status !== 'fresh' || observation.catalogEra !== 'current-v3' || observation.syntheticPrice !== true) {
      throw new SolariResearchError('v3_evidence_not_admitted', 'V3 Browser evidence was stale, duplicated, or outside the exact admitted ID and URL set.', { status: 502 });
    }
    seen.add(identity); observationIDs.add(observation.observationID);
  }
}

export function createSolariV3ResearchService(options = {}) {
  const config = options.config ?? {}, now = options.now ?? Date.now, clock = options.deadlineClock ?? Date.now;
  const accessBoundary = options.accessBoundary ?? 'apple-app-attest';
  if (!['apple-app-attest', 'operator-qualification'].includes(accessBoundary)) throw new Error('Unsupported V3 access boundary.');
  const validatorPromise = options.validator ? Promise.resolve(options.validator) : createContractValidator();
  const browser = options.browserProvider ?? new SolariBrowserProvider({ apiKey: config.solariApiKey, baseURL: config.solariBrowserBaseUrl, timeoutMs: config.solariBrowserTimeoutMs, now });
  const sandbox = options.sandboxOptimizer ?? new SolariV3SandboxOptimizer({ apiKey: config.solariApiKey, baseURL: config.solariSandboxBaseUrl, timeoutMs: config.solariSandboxTimeoutMs });
  async function research(request, { signal } = {}) {
    if (!config.solariApiKey) throw new SolariResearchError('solari_unavailable', 'Solari is unavailable because the server-side API key is not configured.', { status: 503 });
    if (!config.solariDemoRetailerBaseUrl) throw new SolariResearchError('controlled_demo_unavailable', 'The owned Demo Grocer base URL is not configured.', { status: 503 });
    await assertPublicDemoBaseURL(config.solariDemoRetailerBaseUrl, { lookup: options.demoHostLookup });
    const bounded = assertBoundedRequest(request, config.solariDemoRetailerBaseUrl), deadlineAt = clock() + config.solariRequestTimeoutMs;
    const browserObservations = await browser.observe(bounded, { deadlineAt, clock, signal, evidenceVersion: 'v3' });
    const observations = browserObservations.map(structuredObservation);
    const validator = await validatorPromise;
    assertObservationSet(bounded, observations, validator);
    const optimized = await sandbox.optimize(bounded.requirements, observations, request.optimizationPolicy, { deadlineAt, clock, signal });
    const result = {
      schemaVersion: 'solari-shopping-research-result-v3', requestID: request.requestID, demoID: V3_DEMO_ID,
      retailerID: 'smartcart-demo-grocer', completedAt: new Date(now()).toISOString(), executionMode: 'live', status: optimized.basket.completeness,
      observations, decisions: optimized.decisions, basket: optimized.basket, comparison: optimized.comparison, optimizer: optimized.optimizer,
      provenance: { browser: 'solari-browser', sandbox: 'solari-sandbox', fixtureReplay: false, accessBoundary, resourceCleanup: { browser: 'enforced-before-response', sandbox: 'enforced-before-response' } },
      trust: { priceClaim: 'observed-visible-price-not-guaranteed', accountAccessed: false, cartModified: false, checkoutAutomated: false, userControlsHandoff: true, limitations: ['Visible Demo Grocer prices are timestamped synthetic observations, not guarantees or checkout quotes.', 'Availability, tax, fees, fulfillment, and checkout totals remain unknown.', 'No account, cart, or checkout action was performed.'] }
    };
    validator.assert(V3_RESULT_SCHEMA_ID, result); return result;
  }
  return { research };
}
