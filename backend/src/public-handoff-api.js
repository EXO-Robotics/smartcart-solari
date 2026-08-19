import { createHash, randomUUID } from 'node:crypto';
import { ContractValidationError, createContractValidator } from './contracts/contract-validator.js';
import { loadConfig } from './config.js';
import { createHandoffClaimService } from './handoff/create-handoff-claim-service.js';
import { HandoffClaimError } from './handoff/handoff-claim-service.js';
import { HttpError, readJson, validatePreparsedJsonBody } from './lib/http.js';
import { createLogger } from './lib/logger.js';
import { FixedWindowRateLimiter } from './lib/rate-limiter.js';

const claimRequestSchemaId = 'https://schemas.smartcart.app/v1/handoff/smartcart-handoff-claim-request.schema.json';
const requestIdPattern = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/iu;

function traceId(request) {
  const supplied = request.headers['x-request-id'];
  return typeof supplied === 'string' && requestIdPattern.test(supplied)
    ? supplied
    : randomUUID();
}

function clientKey(request) {
  const forwarded = request.headers['x-forwarded-for'];
  const address = typeof forwarded === 'string' ? forwarded.split(',')[0].trim() : request.socket.remoteAddress;
  return createHash('sha256').update(address ?? 'unknown').digest('hex');
}

function sendJson(response, status, payload, { requestID, headers = {} } = {}) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    pragma: 'no-cache',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'x-smartcart-data-mode': 'bounded-handoff-v1',
    ...(requestID ? { 'x-request-id': requestID } : {}),
    ...headers
  });
  response.end(body);
}

function errorPayload(requestID, code, message, retryable = false) {
  return {
    schemaVersion: '1.0',
    resolverVersion: 'smartcart-handoff-v1',
    requestId: requestID,
    error: { code, message, retryable, issues: [] }
  };
}

export function createPublicHandoffApi(options = {}) {
  const config = loadConfig(options.config);
  const logger = options.logger ?? createLogger({ level: config.logLevel, dataMode: 'bounded-handoff-v1' });
  const validatorPromise = options.validator
    ? Promise.resolve(options.validator)
    : createContractValidator();
  let claimService = options.claimService ?? null;
  const ipLimiter = options.ipLimiter ?? new FixedWindowRateLimiter({
    limit: config.smartCartHandoffClaimRateLimitPerMinute,
    windowMs: 60_000,
    now: options.now ?? Date.now
  });
  const tokenLimiter = options.tokenLimiter ?? new FixedWindowRateLimiter({
    limit: config.smartCartHandoffTokenRateLimitPerMinute,
    windowMs: 60_000,
    now: options.now ?? Date.now
  });

  function service() {
    if (claimService === null) {
      claimService = createHandoffClaimService({
        config,
        validator: options.validator,
        now: options.now,
        randomBytesImpl: options.randomBytesImpl
      });
    }
    return claimService;
  }

  async function handler(request, response) {
    const requestID = traceId(request);
    const url = new URL(request.url ?? '/', 'https://smartcart.invalid');
    const route = (
      url.pathname === '/v1/handoffs/claim'
      || (
        ['/api/handoff.js', '/api/handoff'].includes(url.pathname)
        && url.searchParams.get('route') === 'claim'
      )
    ) ? 'claim' : null;
    const startedAt = options.now?.() ?? Date.now();
    response.on('finish', () => {
      logger.info('handoff_request', {
        requestId: requestID,
        route: route ?? 'unknown',
        method: request.method,
        status: response.statusCode,
        durationMs: (options.now?.() ?? Date.now()) - startedAt
      });
    });

    try {
      if (route !== 'claim' || request.method !== 'POST') {
        sendJson(response, 404, errorPayload(
          requestID,
          'route_not_found',
          'Route does not exist.'
        ), { requestID });
        return;
      }

      const ipRate = ipLimiter.consume(clientKey(request));
      if (!ipRate.allowed) {
        sendJson(response, 429, errorPayload(
          requestID,
          'rate_limited',
          'SmartCart handoff request limit exceeded.',
          true
        ), {
          requestID,
          headers: { 'retry-after': String(ipRate.retryAfterSeconds) }
        });
        return;
      }

      const payload = request.body && typeof request.body === 'object'
        ? validatePreparsedJsonBody(request, request.body, config.maxBodyBytes)
        : await readJson(request, config.maxBodyBytes);
      const validator = await validatorPromise;
      validator.assert(claimRequestSchemaId, payload);

      const resolvedService = service();
      const tokenRate = tokenLimiter.consume(resolvedService.tokenFingerprint(payload.data.claimToken));
      if (!tokenRate.allowed) {
        sendJson(response, 429, errorPayload(
          requestID,
          'rate_limited',
          'SmartCart handoff request limit exceeded.',
          true
        ), {
          requestID,
          headers: { 'retry-after': String(tokenRate.retryAfterSeconds) }
        });
        return;
      }

      const result = await resolvedService.claim({ token: payload.data.claimToken });
      sendJson(response, 200, { ...result, requestId: payload.requestId }, { requestID });
    } catch (error) {
      const isContractError = error instanceof ContractValidationError;
      const isHttpError = error instanceof HttpError;
      const isHandoffError = error instanceof HandoffClaimError;
      const status = isContractError ? 400 : isHttpError || isHandoffError ? error.status : 503;
      if (status >= 500) logger.error('handoff_error', { requestId: requestID, error });
      sendJson(response, status, errorPayload(
        requestID,
        isContractError
          ? 'contract_validation_failed'
          : isHttpError || isHandoffError
            ? error.code
            : 'handoff_configuration_unavailable',
        isContractError
          ? 'The request does not satisfy the SmartCart v1 contract.'
          : isHttpError || isHandoffError
            ? error.message
            : 'SmartCart handoff is not configured.',
        isHandoffError ? error.retryable : status >= 500
      ), { requestID });
    }
  }

  return {
    handler,
    config,
    get services() { return { claimService }; }
  };
}
