import { createContractValidator } from '../contracts/contract-validator.js';
import { SolariBrowserProvider } from './browser-provider.js';
import {
  SOLARI_OBSERVATION_SCHEMA_ID,
  SOLARI_DECISION_SCHEMA_ID,
  SOLARI_RESULT_SCHEMA_ID
} from './constants.js';
import { SolariResearchError } from './errors.js';
import { WalmartFixtureReplayProvider } from './fixture-provider.js';
import { deterministicOptimize } from './optimizer.js';
import { SolariSandboxOptimizer } from './sandbox-provider.js';
import { assertCanonicalDemoRequest, assertPublicDemoBaseURL } from './url-policy.js';

export function createSolariResearchService(options = {}) {
  const config = options.config ?? {};
  const validatorPromise = options.validator ? Promise.resolve(options.validator) : createContractValidator();
  const now = options.now ?? Date.now;
  const fixtureProvider = options.fixtureProvider ?? new WalmartFixtureReplayProvider({ now });
  const browserProvider = options.browserProvider ?? new SolariBrowserProvider({
    apiKey: config.solariApiKey,
    baseURL: config.solariBrowserBaseUrl,
    timeoutMs: config.solariBrowserTimeoutMs,
    now
  });
  const sandboxOptimizer = options.sandboxOptimizer ?? new SolariSandboxOptimizer({
    apiKey: config.solariApiKey,
    baseURL: config.solariSandboxBaseUrl,
    timeoutMs: config.solariSandboxTimeoutMs
  });

  function assertInternalContract(validator, schemaID, value, code, message) {
    if (!validator.validate(schemaID, value).valid) {
      throw new SolariResearchError(code, message, { status: 502 });
    }
  }

  async function research(request) {
    if (request.executionMode === 'live' && request.retailerID === 'smartcart-demo-grocer') {
      await assertPublicDemoBaseURL(config.solariDemoRetailerBaseUrl, { lookup: options.demoHostLookup });
    }
    assertCanonicalDemoRequest(request, { demoRetailerBaseURL: config.solariDemoRetailerBaseUrl });
    const validator = await validatorPromise;
    let observations;
    let optimized;
    let fixtureReplay;

    if (request.executionMode === 'recorded_fixture') {
      if (request.retailerID !== 'walmart') {
        throw new SolariResearchError('fixture_scope_not_allowed', 'The recorded fixture is available only for the bounded Walmart demo.', { status: 400 });
      }
      observations = await fixtureProvider.observe(request);
      for (const observation of observations) assertInternalContract(
        validator,
        SOLARI_OBSERVATION_SCHEMA_ID,
        observation,
        'fixture_observation_contract_failed',
        'The recorded fixture does not satisfy RetailerObservationV1.'
      );
      optimized = deterministicOptimize(request.requirements, observations, {
        allowStale: true,
        method: 'smartcart-deterministic-fixture-replay'
      });
      fixtureReplay = true;
    } else {
      if (request.retailerID === 'walmart' && !(
        config.solariRetailerResearchAuthorized === true
        && typeof config.solariWalmartWrittenAuthorizationReference === 'string'
        && config.solariWalmartWrittenAuthorizationReference.trim().length >= 8
      )) {
        throw new SolariResearchError(
          'retailer_research_not_authorized',
          'Live Walmart research is disabled without an explicit written-authorization gate.',
          { status: 403 }
        );
      }
      if (request.retailerID === 'smartcart-demo-grocer' && !config.solariDemoRetailerBaseUrl) {
        throw new SolariResearchError('controlled_demo_unavailable', 'The controlled Demo Grocer base URL is not configured.', { status: 503 });
      }
      observations = await browserProvider.observe(request);
      for (const observation of observations) {
        const validation = validator.validate(SOLARI_OBSERVATION_SCHEMA_ID, observation);
        if (!validation.valid) {
          throw new SolariResearchError(
            'solari_browser_invalid_observation',
            'Solari Browser returned evidence that does not satisfy RetailerObservationV1.',
            { status: 502 }
          );
        }
      }
      optimized = await sandboxOptimizer.optimize(request.requirements, observations);
      fixtureReplay = false;
    }

    for (const decision of optimized.decisions) assertInternalContract(
      validator,
      SOLARI_DECISION_SCHEMA_ID,
      decision,
      'basket_decision_contract_failed',
      'The verified basket decision does not satisfy BasketDecisionV1.'
    );
    const response = {
      schemaVersion: 'solari-shopping-research-result-v1',
      requestID: request.requestID,
      demoID: request.demoID,
      retailerID: request.retailerID,
      completedAt: new Date(now()).toISOString(),
      executionMode: request.executionMode,
      status: optimized.basket.completeness,
      observations,
      decisions: optimized.decisions,
      basket: optimized.basket,
      optimizer: optimized.optimizer,
      provenance: {
        browser: fixtureReplay ? 'not-run-fixture-replay' : 'solari-browser',
        sandbox: fixtureReplay ? 'not-run-fixture-replay' : 'solari-sandbox',
        fixtureReplay
      },
      trust: {
        priceClaim: fixtureReplay ? 'recorded-fixture-not-live' : 'observed-visible-price-not-guaranteed',
        accountAccessed: false,
        cartModified: false,
        checkoutAutomated: false,
        userControlsHandoff: true,
        limitations: fixtureReplay
          ? [
              'Prices are dated SmartCart seed data from 2026-07-16, not a live Solari Browser run.',
              'Availability, tax, fees, fulfillment, and current checkout totals are unknown.',
              'No reviewed nutrition evidence is present, so protein per dollar is intentionally omitted.'
            ]
          : [
              'Visible prices are timestamped observations, not guarantees or checkout quotes.',
              'Availability, tax, fees, fulfillment, and checkout totals remain unknown.',
              'No account, cart, or checkout action was performed.'
            ]
      }
    };
    assertInternalContract(
      validator,
      SOLARI_RESULT_SCHEMA_ID,
      response,
      'solari_result_contract_failed',
      'The research result does not satisfy BasketResearchResultV1.'
    );
    return response;
  }

  return { research };
}
