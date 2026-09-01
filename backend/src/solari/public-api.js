import { randomUUID, timingSafeEqual } from 'node:crypto';
import { ContractValidationError, createContractValidator } from '../contracts/contract-validator.js';
import { loadConfig } from '../config.js';
import { HttpError, readJson, validatePreparsedJsonBody } from '../lib/http.js';
import { createLogger } from '../lib/logger.js';
import { FixedWindowRateLimiter } from '../lib/rate-limiter.js';
import { SOLARI_REQUEST_SCHEMA_ID } from './constants.js';
import { SolariResearchError } from './errors.js';
import { createSolariResearchService } from './research-service.js';

function routeForRequest(url) {
  if (url.pathname === '/v1/solari/research') return true;
  return ['/api/solari.js', '/api/solari'].includes(url.pathname) && url.searchParams.get('route') === 'research';
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
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'x-smartcart-data-mode': payload.executionMode ?? (payload.error ? 'solari-error' : 'solari-research-v1'),
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

  async function handler(request, response) {
    const traceID = randomUUID();
    try {
      const url = new URL(request.url ?? '/', 'https://smartcart.invalid');
      if (!routeForRequest(url) || request.method !== 'POST') {
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
      const payload = request.body && typeof request.body === 'object'
        ? validatePreparsedJsonBody(request, request.body, config.solariMaxBodyBytes)
        : await readJson(request, config.solariMaxBodyBytes);
      const validator = await validatorPromise;
      validator.assert(SOLARI_REQUEST_SCHEMA_ID, payload);
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
      const result = await service.research(payload);
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
          message: contract ? 'The request does not satisfy BasketResearchRequestV1.' : known ? error.message : 'Solari research could not complete the request.',
          retryable: error instanceof SolariResearchError ? error.retryable : false,
          ...(contract ? { issues: error.errors } : {})
        }
      }, traceID);
    }
  }

  return { handler, config, services: { research: service, limiter } };
}
