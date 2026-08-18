import { randomUUID } from 'node:crypto';
import { ContractValidationError, createContractValidator } from './contracts/contract-validator.js';
import { loadConfig } from './config.js';
import { HttpError, readJson } from './lib/http.js';
import { createLogger } from './lib/logger.js';
import { createTripIntelligenceService } from './trip-intelligence/create-trip-intelligence-service.js';
import { FoodDataCentralError } from './trip-intelligence/food-data-central-client.js';

const requestSchemaId = 'https://schemas.smartcart.app/v1/nutrition/recipe-nutrition-request.schema.json';
const responseSchemaId = 'https://schemas.smartcart.app/v1/nutrition/recipe-nutrition-estimate.schema.json';
const serviceVersion = '0.1.0';

function traceId(request) {
  const supplied = request.headers['x-request-id'];
  return typeof supplied === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(supplied)
    ? supplied
    : randomUUID();
}

function routeForRequest(url) {
  if (
    url.pathname === '/v1/intelligence/nutrition/recipes/estimate'
    || (
      ['/api/intelligence.js', '/api/intelligence'].includes(url.pathname)
      && url.searchParams.get('route') === 'recipe-nutrition'
    )
  ) return 'recipe-nutrition';
  return null;
}

function sendJson(response, status, payload, { requestID } = {}) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'x-smartcart-data-mode': 'trip-intelligence-v1',
    ...(requestID ? { 'x-request-id': requestID } : {})
  });
  response.end(body);
}

function validationIssue(error) {
  return {
    code: 'contract_validation_failed',
    severity: 'blocking',
    message: 'The request does not satisfy the SmartCart v1 contract.',
    field: error.errors?.[0]?.instancePath || null,
    evidenceIds: []
  };
}

function statusForProviderError(error) {
  if (error.code === 'usda_rate_limited') return 429;
  if (error.code === 'usda_timeout') return 504;
  if (error.code === 'usda_configuration_missing') return 503;
  return error.status && error.status >= 400 ? Math.min(error.status, 599) : 503;
}

export function createPublicTripIntelligenceApi(options = {}) {
  const config = loadConfig(options.config);
  const logger = options.logger ?? createLogger({ level: config.logLevel, dataMode: 'trip-intelligence-v1' });
  const validatorPromise = options.validator
    ? Promise.resolve(options.validator)
    : createContractValidator();
  let service = options.tripIntelligenceService ?? null;

  function resolvedService() {
    if (service === null) {
      service = createTripIntelligenceService({ config });
    }
    return service;
  }

  async function handler(request, response) {
    const requestID = traceId(request);
    const url = new URL(request.url ?? '/', 'https://smartcart.invalid');
    const route = routeForRequest(url);
    try {
      if (route !== 'recipe-nutrition' || request.method !== 'POST') {
        sendJson(response, 404, {
          schemaVersion: '1.0',
          resolverVersion: 'trip-intelligence-api-v1',
          requestId: requestID,
          error: {
            code: 'route_not_found',
            message: 'Route does not exist.',
            retryable: false,
            issues: []
          }
        }, { requestID });
        return;
      }

      const payload = await readJson(request, config.maxBodyBytes);
      const validator = await validatorPromise;
      validator.assert(requestSchemaId, payload);
      const result = await resolvedService().estimateRecipeNutrition(payload.data);
      const responsePayload = {
        schemaVersion: '1.0',
        resolverVersion: result.resolverVersion,
        requestId: payload.requestId,
        data: result.data
      };
      validator.assert(responseSchemaId, responsePayload);
      sendJson(response, 200, responsePayload, { requestID });
    } catch (error) {
      const isContractError = error instanceof ContractValidationError;
      const isHttpError = error instanceof HttpError;
      const isProviderError = error instanceof FoodDataCentralError;
      const status = isContractError
        ? 400
        : isHttpError
          ? error.status
          : isProviderError
            ? statusForProviderError(error)
            : 500;
      if (status >= 500) logger.error('trip_intelligence_error', { requestId: requestID, error });
      sendJson(response, status, {
        schemaVersion: '1.0',
        resolverVersion: 'trip-intelligence-api-v1',
        requestId: requestID,
        error: {
          code: isContractError
            ? 'contract_validation_failed'
            : isHttpError || isProviderError
              ? error.code
              : 'internal_error',
          message: isContractError
            ? 'The request does not satisfy the SmartCart v1 contract.'
            : isHttpError || isProviderError
              ? error.message
              : 'Trip Intelligence could not complete the request.',
          retryable: isProviderError ? error.retryable : false,
          issues: isContractError ? [validationIssue(error)] : []
        }
      }, { requestID });
    }
  }

  return {
    handler,
    config,
    serviceVersion,
    get services() { return { tripIntelligence: service }; }
  };
}
