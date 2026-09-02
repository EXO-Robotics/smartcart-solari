import { randomUUID, timingSafeEqual } from 'node:crypto';
import { ContractValidationError, createContractValidator } from '../contracts/contract-validator.js';
import { loadConfig } from '../config.js';
import { HttpError, readJson, validatePreparsedJsonBody } from '../lib/http.js';
import { createLogger } from '../lib/logger.js';
import { FixedWindowRateLimiter } from '../lib/rate-limiter.js';
import { SOLARI_REQUEST_SCHEMA_ID } from './constants.js';
import { createSolariBetaApi, isV2Envelope } from './beta-api.js';
import { SolariResearchError } from './errors.js';
import { createSolariResearchService } from './research-service.js';

function routeForRequest(url) {
  if (url.pathname === '/v1/solari/research') return { operation: 'research', lane: 'distribution' };
  if (url.pathname === '/v1/solari/access/challenges') return { operation: 'challenge', lane: 'distribution' };
  if (url.pathname === '/v1/solari/access/attestations') return { operation: 'attestation', lane: 'distribution' };
  if (url.pathname === '/dev/v1/solari/research') return { operation: 'research', lane: 'development' };
  if (url.pathname === '/dev/v1/solari/access/challenges') return { operation: 'challenge', lane: 'development' };
  if (url.pathname === '/dev/v1/solari/access/attestations') return { operation: 'attestation', lane: 'development' };
  if (['/api/solari.js', '/api/solari'].includes(url.pathname)) {
    const route = url.searchParams.get('route');
    if (['research', 'challenge', 'attestation'].includes(route)) return { operation: route, lane: 'distribution' };
    if (['dev-research', 'dev-challenge', 'dev-attestation'].includes(route)) {
      return { operation: route.slice(4), lane: 'development' };
    }
  }
  return null;
}

function clientKey(request, trustForwardedFor = false) {
  const forwarded = trustForwardedFor ? request.headers['x-forwarded-for'] : undefined;
  const value = typeof forwarded === 'string' && forwarded.trim()
    ? forwarded.split(',')[0].trim()
    : request.socket?.remoteAddress;
  return value || 'unknown';
}

function bearerToken(request) {
  const header = request.headers.authorization;
  if (typeof header !== 'string') return null;
  const match = /^Bearer ([A-Za-z0-9._~-]{32,256})$/.exec(header);
  return match?.[1] ?? null;
}

function validOperatorToken(request, configured) {
  const supplied = bearerToken(request);
  if (!supplied || typeof configured !== 'string' || configured.length < 32) return false;
  const lhs = Buffer.from(supplied);
  const rhs = Buffer.from(configured);
  return lhs.length === rhs.length && timingSafeEqual(lhs, rhs);
}

function send(response, status, payload, requestID, headers = {}) {
  if (response.destroyed || response.writableEnded) return;
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'x-smartcart-data-mode': payload.executionMode ?? (payload.error ? 'solari-error' : payload.schemaVersion?.includes('app-attest') || payload.schemaVersion?.includes('app-attestation') ? 'solari-app-attest' : 'solari-research-v1'),
    'x-request-id': requestID,
    ...headers
  });
  response.end(body);
}

export function createPublicSolariApi(options = {}) {
  const config = loadConfig(options.config);
  const logger = options.logger ?? createLogger({ level: config.logLevel, dataMode: 'solari-research-v1' });
  const validatorPromise = options.validator ? Promise.resolve(options.validator) : createContractValidator();
  const limiter = options.limiter ?? new FixedWindowRateLimiter({
    limit: config.solariRateLimitPerMinute,
    windowMs: 60_000,
    now: options.now ?? Date.now
  });
  const service = options.service ?? createSolariResearchService({
    config,
    validator: options.validator,
    now: options.now,
    fixtureProvider: options.fixtureProvider,
    browserProvider: options.browserProvider,
    sandboxOptimizer: options.sandboxOptimizer,
    demoHostLookup: options.demoHostLookup
  });
  const beta = options.betaApi ?? createSolariBetaApi({
    config,
    validator: options.validator,
    now: options.now,
    store: options.betaStore,
    verifier: options.appAttestVerifier,
    researchService: options.betaResearchService,
    browserProvider: options.browserProvider,
    sandboxOptimizer: options.sandboxOptimizer,
    demoHostLookup: options.demoHostLookup
  });
  const developmentBeta = options.developmentBetaApi ?? createSolariBetaApi({
    config: {
      ...config,
      solariBetaEnabled: config.solariBetaEnabled === true && config.solariDevelopmentLaneEnabled === true,
      solariBetaStorePrefix: config.solariDevelopmentStorePrefix,
      solariAppAttestAllowedValidationCategories: [3],
      solariAppAttestResearchPath: '/dev/v1/solari/research'
    },
    validator: options.validator,
    now: options.now,
    store: options.developmentBetaStore,
    verifier: options.developmentAppAttestVerifier,
    researchService: options.developmentBetaResearchService ?? options.betaResearchService,
    browserProvider: options.browserProvider,
    sandboxOptimizer: options.sandboxOptimizer,
    demoHostLookup: options.demoHostLookup
  });

  async function handler(request, response) {
    const traceID = randomUUID();
    const controller = new AbortController();
    const abort = () => controller.abort();
    const close = () => {
      if (request.aborted === true || request.complete === false) abort();
    };
    request.once('aborted', abort);
    request.once('close', close);
    try {
      const url = new URL(request.url ?? '/', 'https://smartcart.invalid');
      const route = routeForRequest(url);
      if (!route || request.method !== 'POST' || (
        route.lane === 'development' && config.solariDevelopmentLaneEnabled !== true
      )) {
        send(response, 404, { error: { code: 'route_not_found', message: 'Route does not exist.', retryable: false } }, traceID);
        return;
      }
      const rate = limiter.consume(clientKey(request, config.solariTrustForwardedFor));
      const rateHeaders = {
        'x-rate-limit-limit': String(rate.limit),
        'x-rate-limit-remaining': String(rate.remaining),
        'x-rate-limit-reset': String(Math.ceil(rate.resetAt / 1000))
      };
      if (!rate.allowed) {
        send(response, 429, { error: { code: 'rate_limited', message: 'Solari research request limit exceeded.', retryable: true } }, traceID, {
          ...rateHeaders, 'retry-after': String(rate.retryAfterSeconds)
        });
        return;
      }
      const bodyLimit = route.operation === 'challenge' ? config.solariMaxBodyBytes : config.solariBetaMaxBodyBytes;
      const payload = request.body && typeof request.body === 'object'
        ? validatePreparsedJsonBody(request, request.body, bodyLimit)
        : await readJson(request, bodyLimit);
      const activeBeta = route.lane === 'development' ? developmentBeta : beta;
      if (route.operation === 'challenge') {
        const result = await activeBeta.challenge(payload);
        send(response, result.status, result.payload, traceID, { ...rateHeaders, ...result.headers });
        return;
      }
      if (route.operation === 'attestation') {
        const result = await activeBeta.attestation(payload);
        send(response, result.status, result.payload, traceID, { ...rateHeaders, ...result.headers });
        return;
      }
      if (isV2Envelope(payload)) {
        const result = await activeBeta.researchEnvelope(payload, { signal: controller.signal });
        send(response, result.status, result.payload, traceID, { ...rateHeaders, ...result.headers });
        return;
      }
      if (route.lane === 'development') {
        throw new SolariResearchError(
          'app_attest_envelope_required',
          'The development lane accepts only an App Attest research envelope.',
          { status: 403 }
        );
      }
      validatePreparsedJsonBody(request, payload, config.solariMaxBodyBytes);
      const validator = await validatorPromise;
      validator.assert(SOLARI_REQUEST_SCHEMA_ID, payload);
      if (payload.executionMode === 'live' && config.solariBetaEnabled === true) {
        throw new SolariResearchError(
          'solari_execution_mode_conflict',
          'V1 operator-live execution cannot run on an App Attest beta deployment.',
          { status: 503 }
        );
      }
      if (payload.executionMode === 'live' && !(
        config.solariLiveExecutionEnabled === true
        && validOperatorToken(request, config.solariOperatorToken)
      )) {
        throw new SolariResearchError(
          'live_execution_not_authorized',
          'Live Solari execution is disabled or requires operator authorization.',
          { status: 403 }
        );
      }
      const result = await service.research(payload, { signal: controller.signal });
      send(response, 200, result, traceID, rateHeaders);
    } catch (error) {
      const contract = error instanceof ContractValidationError;
      const known = error instanceof SolariResearchError || error instanceof HttpError;
      const status = contract ? 400 : known ? error.status : 500;
      if (status >= 500) logger.error('solari_research_error', {
        errorName: error?.name ?? 'Error',
        errorCode: typeof error?.code === 'string' ? error.code : 'internal_error'
      });
      send(response, status, {
        error: {
          code: contract ? 'contract_validation_failed' : known ? error.code : 'internal_error',
          message: contract ? 'The request does not satisfy the required SmartCart contract.' : known ? error.message : 'Solari research could not complete the request.',
          retryable: error instanceof SolariResearchError ? error.retryable : false,
          ...(contract ? { issues: error.errors } : {})
        }
      }, traceID);
    } finally {
      request.removeListener('aborted', abort);
      request.removeListener('close', close);
    }
  }

  return { handler, config, services: { research: service, beta, developmentBeta, limiter } };
}
