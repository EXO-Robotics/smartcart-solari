import { createContractValidator } from '../contracts/contract-validator.js';
import { SolariBrowserProvider } from './browser-provider.js';
import { SolariResearchError } from './errors.js';
import { freshness } from './fixture-provider.js';
import { assertPublicDemoBaseURL } from './url-policy.js';
import {
  controlledV4ProductURL, V4_DEMO_ID, V4_GROUP_ALIASES, V4_MAX_CANDIDATES_PER_REQUIREMENT,
  V4_MAX_OBSERVATIONS, V4_MAX_PREMIUM_OVER_CHEAPEST, V4_MAX_REQUIREMENTS,
  V4_PRODUCT_CATALOG, V4_STORE_REFERENCE
} from './v4-constants.js';
import { SolariV4SandboxOptimizer } from './v4-sandbox-provider.js';

export const V4_REQUEST_SCHEMA_ID = 'https://schemas.smartcart.app/v4/solari/basket-research-request.schema.json';
export const V4_RESULT_SCHEMA_ID = 'https://schemas.smartcart.app/v4/solari/basket-research-result.schema.json';
export const V4_OBSERVATION_SCHEMA_ID = 'https://schemas.smartcart.app/v4/solari/retailer-observation.schema.json';

const EXPECTED_POLICY = Object.freeze({
  objective: 'minimize-aggregate-relative-surplus',
  maxPremiumOverCheapest: V4_MAX_PREMIUM_OVER_CHEAPEST,
  currency: 'USD',
  tieBreak: ['observed-subtotal', 'retailer-product-id']
});
const DIMENSION_UNIT = Object.freeze({ mass: 'g', volume: 'ml', count: 'count' });

function structuredObservation(value) {
  return {
    schemaVersion: 'retailer-observation-v4', observationID: value.observationID,
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

function observationsAtCompletion(observations, completedAtMilliseconds) {
  return observations.map((observation) => ({
    ...observation,
    freshness: freshness(observation.observedAt, () => completedAtMilliseconds, observation.freshness.maxAgeSeconds)
  }));
}

function policyMatches(policy) {
  return policy?.objective === EXPECTED_POLICY.objective
    && policy.maxPremiumOverCheapest === EXPECTED_POLICY.maxPremiumOverCheapest
    && policy.currency === EXPECTED_POLICY.currency
    && Array.isArray(policy.tieBreak) && policy.tieBreak.length === 2
    && policy.tieBreak.every((value, index) => value === EXPECTED_POLICY.tieBreak[index]);
}

function semanticMatch(group, name) {
  const normalized = name.toLowerCase();
  return V4_GROUP_ALIASES[group].some((alias) => normalized.includes(alias));
}

export function assertBoundedV4Request(request, baseURL) {
  if (request.demoID !== V4_DEMO_ID || request.retailerID !== 'smartcart-demo-grocer'
    || request.executionMode !== 'live' || request.storeReference !== V4_STORE_REFERENCE
    || !policyMatches(request.optimizationPolicy)) {
    throw new SolariResearchError('v4_policy_not_allowed', 'The V4 beta admits only its owned Demo Grocer relative-surplus policy.', { status: 400 });
  }
  if (!Array.isArray(request.requirements) || request.requirements.length < 1 || request.requirements.length > V4_MAX_REQUIREMENTS) {
    throw new SolariResearchError('v4_requirement_bounds', 'V4 research requires between 1 and 12 reviewed shopping requirements.', { status: 400 });
  }
  const requirementIDs = new Set(), ingredientIDs = new Set(), products = new Set();
  let observationCount = 0;
  for (const requirement of request.requirements) {
    const requirementID = requirement.id.toLowerCase(), ingredientID = requirement.ingredientID.toLowerCase();
    if (requirementIDs.has(requirementID) || ingredientIDs.has(ingredientID)) {
      throw new SolariResearchError('duplicate_requirement_identity', 'Requirement and ingredient IDs must be unique.', { status: 400 });
    }
    requirementIDs.add(requirementID); ingredientIDs.add(ingredientID);
    if (!Array.isArray(requirement.candidateProductIDs) || requirement.candidateProductIDs.length < 1
      || requirement.candidateProductIDs.length > V4_MAX_CANDIDATES_PER_REQUIREMENT) {
      throw new SolariResearchError('v4_candidate_bounds', 'Each V4 requirement must contain between one and three candidate product IDs.', { status: 400 });
    }
    observationCount += requirement.candidateProductIDs.length;
    const catalogEntries = requirement.candidateProductIDs.map((id) => V4_PRODUCT_CATALOG[id]);
    if (catalogEntries.some((entry) => !entry)) {
      throw new SolariResearchError('v4_candidate_not_admitted', 'An unknown V4 product ID was rejected before Browser launch.', { status: 400 });
    }
    const groups = new Set(catalogEntries.map(({ group }) => group));
    const dimensions = new Set(catalogEntries.map(({ dimension }) => dimension));
    const [group] = groups, [dimension] = dimensions;
    if (groups.size !== 1 || dimensions.size !== 1 || !semanticMatch(group, requirement.name)
      || requirement.unit !== DIMENSION_UNIT[dimension]) {
      throw new SolariResearchError('v4_candidate_semantics_mismatch', 'V4 candidates must share one semantic group and dimension compatible with the reviewed requirement.', { status: 400 });
    }
    for (const id of requirement.candidateProductIDs) {
      if (products.has(id)) throw new SolariResearchError('duplicate_candidate', 'Candidate product IDs must be unique across the request.', { status: 400 });
      products.add(id);
    }
  }
  if (observationCount > V4_MAX_OBSERVATIONS) {
    throw new SolariResearchError('v4_observation_bounds', 'V4 research admits at most 24 product observations.', { status: 400 });
  }
  return {
    ...request,
    requirements: request.requirements.map(({ candidateProductIDs, ...requirement }) => ({
      ...requirement,
      candidates: candidateProductIDs.map((retailerProductID) => ({ retailerProductID, sourceURL: controlledV4ProductURL(baseURL, retailerProductID) }))
    }))
  };
}

function assertObservationSet(bounded, observations, validator) {
  const expected = new Map(bounded.requirements.flatMap((requirement) => requirement.candidates.map((candidate) => [
    `${requirement.id}\n${candidate.retailerProductID}`, candidate.sourceURL
  ])));
  const seen = new Set(), observationIDs = new Set();
  if (observations.length !== expected.size) throw new SolariResearchError('v4_evidence_set_incomplete', 'V4 Browser evidence did not contain the exact admitted candidate set.', { status: 502 });
  for (const observation of observations) {
    validator.assert(V4_OBSERVATION_SCHEMA_ID, observation);
    const identity = `${observation.requirementID}\n${observation.retailerProductID}`;
    if (!expected.has(identity) || expected.get(identity) !== observation.sourceURL || seen.has(identity)
      || observationIDs.has(observation.observationID) || observation.freshness.status !== 'fresh'
      || observation.catalogEra !== 'current-v4' || observation.syntheticPrice !== true) {
      throw new SolariResearchError('v4_evidence_not_admitted', 'V4 Browser evidence was stale, duplicated, or outside the admitted V4 ID and URL set.', { status: 502 });
    }
    seen.add(identity); observationIDs.add(observation.observationID);
  }
}

export function createSolariV4ResearchService(options = {}) {
  const config = options.config ?? {}, now = options.now ?? Date.now, clock = options.deadlineClock ?? Date.now;
  const accessBoundary = options.accessBoundary ?? 'apple-app-attest';
  if (!['apple-app-attest', 'operator-qualification'].includes(accessBoundary)) throw new Error('Unsupported V4 access boundary.');
  const validatorPromise = options.validator ? Promise.resolve(options.validator) : createContractValidator();
  const browser = options.browserProvider ?? new SolariBrowserProvider({ apiKey: config.solariApiKey, baseURL: config.solariBrowserBaseUrl, timeoutMs: config.solariBrowserTimeoutMs, now });
  const sandbox = options.sandboxOptimizer ?? new SolariV4SandboxOptimizer({ apiKey: config.solariApiKey, baseURL: config.solariSandboxBaseUrl, timeoutMs: config.solariSandboxTimeoutMs });
  async function research(request, { signal } = {}) {
    if (!config.solariApiKey) throw new SolariResearchError('solari_unavailable', 'Solari is unavailable because the server-side API key is not configured.', { status: 503 });
    if (!config.solariDemoRetailerBaseUrl) throw new SolariResearchError('controlled_demo_unavailable', 'The owned Demo Grocer base URL is not configured.', { status: 503 });
    await assertPublicDemoBaseURL(config.solariDemoRetailerBaseUrl, { lookup: options.demoHostLookup });
    const bounded = assertBoundedV4Request(request, config.solariDemoRetailerBaseUrl);
    const deadlineAt = clock() + config.solariRequestTimeoutMs;
    const browserObservations = await browser.observe(bounded, { deadlineAt, clock, signal, evidenceVersion: 'v4' });
    const observations = browserObservations.map(structuredObservation);
    const validator = await validatorPromise;
    assertObservationSet(bounded, observations, validator);
    const optimized = await sandbox.optimize(bounded.requirements, observations, request.optimizationPolicy, { deadlineAt, clock, signal });
    const completedAtMilliseconds = now();
    const completedObservations = observationsAtCompletion(observations, completedAtMilliseconds);
    assertObservationSet(bounded, completedObservations, validator);
    const result = {
      schemaVersion: 'solari-shopping-research-result-v4', requestID: request.requestID, demoID: V4_DEMO_ID,
      retailerID: 'smartcart-demo-grocer', completedAt: new Date(completedAtMilliseconds).toISOString(), executionMode: 'live', status: optimized.basket.completeness,
      observations: completedObservations, decisions: optimized.decisions, basket: optimized.basket,
      comparison: optimized.comparison, optimizer: optimized.optimizer,
      provenance: { browser: 'solari-browser', sandbox: 'solari-sandbox', fixtureReplay: false, accessBoundary, resourceCleanup: { browser: 'enforced-before-response', sandbox: 'enforced-before-response' } },
      trust: { priceClaim: 'observed-visible-price-not-guaranteed', accountAccessed: false, cartModified: false, checkoutAutomated: false, userControlsHandoff: true, limitations: ['Visible Demo Grocer prices are timestamped synthetic observations, not guarantees or checkout quotes.', 'Availability, tax, fees, fulfillment, and checkout totals remain unknown.', 'No account, cart, or checkout action was performed.'] }
    };
    validator.assert(V4_RESULT_SCHEMA_ID, result);
    return result;
  }
  return { research };
}
