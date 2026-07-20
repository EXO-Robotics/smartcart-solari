import { loadConfig } from './config.js';
import { requestId } from './lib/http.js';
import { createLogger } from './lib/logger.js';
import {
  BarcodeCatalogService,
  BarcodeProviderError,
  OpenFoodFactsBarcodeProvider
} from './services/barcode-catalog.js';

const serviceName = 'smartcart-barcode-catalog';
const serviceVersion = '0.1.0';

function sendJson(response, status, payload, { requestID, method = 'GET' } = {}) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'x-smartcart-data-mode': 'crowdsourced-catalog',
    ...(requestID ? { 'x-request-id': requestID } : {})
  });
  response.end(method === 'HEAD' ? undefined : body);
}

function routeForRequest(url) {
  if (url.pathname === '/api/index.js' || url.pathname === '/api/index') {
    const internalRoute = url.searchParams.get('route');
    if (internalRoute === 'health') return { kind: 'health' };
    if (internalRoute === 'barcode') {
      return { kind: 'barcode', gtin: url.searchParams.get('gtin') ?? '' };
    }
  }
  if (url.pathname === '/health') return { kind: 'health' };
  const barcode = /^\/v1\/barcodes\/(?<gtin>[^/]+)$/.exec(url.pathname);
  if (barcode) return { kind: 'barcode', gtin: barcode.groups.gtin };
  return null;
}

function logPath(route) {
  if (route?.kind === 'health') return '/health';
  if (route?.kind === 'barcode') return '/v1/barcodes/:gtin';
  return '/route-not-found';
}

export function createPublicBarcodeApi(options = {}) {
  const config = loadConfig(options.config);
  const logger = options.logger ?? createLogger({
    level: config.logLevel,
    dataMode: 'crowdsourced-catalog'
  });
  const now = options.now ?? Date.now;
  const barcodeCatalog = options.barcodeCatalog ?? new BarcodeCatalogService({
    provider: new OpenFoodFactsBarcodeProvider({
      fetchImpl: options.fetchImpl,
      baseUrl: config.openFoodFactsBaseUrl,
      userAgent: config.openFoodFactsUserAgent,
      timeoutMs: config.barcodeLookupTimeoutMs
    }),
    positiveTtlMs: config.barcodePositiveCacheTtlMs,
    negativeTtlMs: config.barcodeNegativeCacheTtlMs,
    rateLimit: config.barcodeProviderRateLimit,
    now
  });

  async function handler(request, response) {
    const id = requestId(request);
    const startedAt = now();
    const method = request.method ?? 'GET';
    const url = new URL(request.url ?? '/', 'https://smartcart.invalid');
    const route = routeForRequest(url);

    response.on('finish', () => {
      logger.info('http_request', {
        requestId: id,
        method,
        path: logPath(route),
        status: response.statusCode,
        durationMs: now() - startedAt
      });
    });

    try {
      if (route?.kind === 'health' && (method === 'GET' || method === 'HEAD')) {
        sendJson(response, 200, {
          status: 'ok',
          service: serviceName,
          version: serviceVersion,
          timestamp: new Date(now()).toISOString()
        }, { requestID: id, method });
        return;
      }

      if (route?.kind === 'barcode' && method === 'GET') {
        const result = await barcodeCatalog.resolve(route.gtin);
        if (result.status === 'invalid') {
          sendJson(response, 400, {
            error: {
              code: 'invalid_gtin',
              message: 'A valid GTIN-8, UPC-A, EAN-13, or GTIN-14 is required',
              requestId: id
            }
          }, { requestID: id });
          return;
        }
        sendJson(response, 200, result, { requestID: id });
        return;
      }

      sendJson(response, 404, {
        error: { code: 'route_not_found', message: 'Route does not exist', requestId: id }
      }, { requestID: id, method });
    } catch (error) {
      const providerFailure = error instanceof BarcodeProviderError;
      const status = providerFailure ? error.httpStatus : 500;
      if (status >= 500) logger.error('http_error', { requestId: id, error });
      sendJson(response, status, {
        error: {
          code: providerFailure ? error.code : 'internal_error',
          message: providerFailure ? error.message : 'Unexpected barcode catalog error',
          requestId: id
        }
      }, { requestID: id, method });
    }
  }

  return { handler, config, services: { barcodeCatalog } };
}
