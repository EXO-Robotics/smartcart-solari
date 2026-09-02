import { createServer as createNodeServer } from 'node:http';
import { loadConfig } from './config.js';
import { assertString, HttpError, localDemoMeta, readJson, requestId, sendJson } from './lib/http.js';
import { createLogger } from './lib/logger.js';
import { FixedWindowRateLimiter } from './lib/rate-limiter.js';
import { AffiliateLinkService, LocalDemoAffiliateProvider } from './services/affiliate-links.js';
import {
  BarcodeCatalogService,
  BarcodeProviderError,
  OpenFoodFactsBarcodeProvider
} from './services/barcode-catalog.js';
import { LocalDemoStore } from './services/local-demo-store.js';
import { LocalDemoOAuthPkce } from './services/oauth-pkce.js';
import { RecipePageExtractor } from './services/recipe-page-extractor.js';
import { RecipePageFetcher } from './services/recipe-page-fetcher.js';
import {
  InstacartApiProvider,
  InstacartDemoProvider,
  InstacartHandoffService
} from './services/instacart-handoff.js';
import { createPublicSolariApi } from './solari/public-api.js';

function bearerToken(request) {
  const header = request.headers.authorization;
  if (typeof header !== 'string') return undefined;
  const match = /^Bearer ([A-Za-z0-9._~+/=-]+)$/.exec(header);
  return match?.[1];
}

function corsHeaders(origin, allowedOrigins) {
  if (!origin || !allowedOrigins.includes(origin)) return {};
  return {
    'access-control-allow-origin': origin,
    vary: 'Origin',
    'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type,x-request-id',
    'access-control-max-age': '600'
  };
}

function clientKey(request) {
  const address = request.socket.remoteAddress ?? 'unknown';
  return address.replace(/^::ffff:/, '');
}

function routeMatch(pathname, expression) {
  const match = expression.exec(pathname);
  return match?.groups ?? null;
}

function requestPathForLogging(requestUrl) {
  const path = requestUrl?.split('?')[0];
  return path?.replace(/^\/v1\/barcodes\/[^/]+$/, '/v1/barcodes/:gtin');
}

export function createApp(options = {}) {
  const config = loadConfig(options.config);
  if (config.env === 'production' && config.instacartDemoHandoffUrl) {
    throw new Error('INSTACART_DEMO_HANDOFF_URL cannot be used in production');
  }
  const logger = options.logger ?? createLogger({ level: config.logLevel });
  const now = options.now ?? Date.now;
  const store = options.store ?? new LocalDemoStore({ sessionTtlMs: config.sessionTtlMs, now });
  const oauth = options.oauth ?? new LocalDemoOAuthPkce({
    ttlMs: config.oauthStateTtlMs,
    clientId: config.oauthClientId,
    redirectUri: config.oauthRedirectUri,
    now
  });
  const affiliate = options.affiliate ?? new AffiliateLinkService({
    provider: new LocalDemoAffiliateProvider({ campaign: config.affiliateCampaign }),
    cacheTtlMs: config.cacheTtlMs,
    now
  });
  const limiter = options.limiter ?? new FixedWindowRateLimiter({
    limit: config.rateLimitMax,
    windowMs: config.rateLimitWindowMs,
    now
  });
  const recipePageFetcher = options.recipePageFetcher ?? new RecipePageFetcher({
    timeoutMs: config.recipePageTimeoutMs,
    maxBytes: config.recipePageMaxBytes,
    maxRedirects: config.recipePageMaxRedirects
  });
  const recipePageExtractor = options.recipePageExtractor ?? new RecipePageExtractor();
  const instacartProvider = options.instacartProvider ?? (
    config.instacartDemoHandoffUrl
      ? new InstacartDemoProvider({ url: config.instacartDemoHandoffUrl })
      : new InstacartApiProvider({
          apiKey: config.instacartApiKey,
          baseUrl: config.instacartApiBaseUrl,
          timeoutMs: config.instacartTimeoutMs
        })
  );
  const instacartHandoff = options.instacartHandoff ?? new InstacartHandoffService({
    provider: instacartProvider,
    cacheTtlMs: config.instacartHandoffCacheTtlMs,
    now
  });
  const barcodeCatalog = options.barcodeCatalog ?? new BarcodeCatalogService({
    provider: new OpenFoodFactsBarcodeProvider({
      baseUrl: config.openFoodFactsBaseUrl,
      userAgent: config.openFoodFactsUserAgent,
      timeoutMs: config.barcodeLookupTimeoutMs
    }),
    positiveTtlMs: config.barcodePositiveCacheTtlMs,
    negativeTtlMs: config.barcodeNegativeCacheTtlMs,
    rateLimit: config.barcodeProviderRateLimit,
    now
  });
  const solariApi = options.solariApi ?? createPublicSolariApi({
    config,
    logger,
    now,
    service: options.solariResearchService,
    fixtureProvider: options.solariFixtureProvider,
    browserProvider: options.solariBrowserProvider,
    sandboxOptimizer: options.solariSandboxOptimizer
  });

  async function handler(request, response) {
    const id = requestId(request);
    const startedAt = now();
    const origin = request.headers.origin;
    const cors = corsHeaders(origin, config.allowedOrigins);
    response.on('finish', () => {
      logger.info('http_request', {
        requestId: id,
        method: request.method,
        path: requestPathForLogging(request.url),
        status: response.statusCode,
        durationMs: now() - startedAt,
        remoteAddress: clientKey(request)
      });
    });

    try {
      const url = new URL(request.url ?? '/', 'http://smartcart.local');
      const method = request.method ?? 'GET';
      if ([
        '/v1/solari/research',
        '/v1/solari/access/challenges',
        '/v1/solari/access/attestations',
        '/dev/v1/solari/research',
        '/dev/v1/solari/access/challenges',
        '/dev/v1/solari/access/attestations'
      ].includes(url.pathname)) {
        await solariApi.handler(request, response);
        return;
      }
      const rate = limiter.consume(`${clientKey(request)}:${url.pathname}`);
      const rateHeaders = {
        'x-rate-limit-limit': String(rate.limit),
        'x-rate-limit-remaining': String(rate.remaining),
        'x-rate-limit-reset': String(Math.ceil(rate.resetAt / 1_000))
      };
      const headers = { ...cors, ...rateHeaders, 'x-request-id': id };

      if (origin && !config.allowedOrigins.includes(origin)) {
        throw new HttpError(403, 'origin_not_allowed', 'Origin is not allowed by this local/demo service');
      }
      if (!rate.allowed) {
        sendJson(response, 429, {
          error: { code: 'rate_limited', message: 'Local/demo request limit exceeded', requestId: id },
          meta: localDemoMeta()
        }, { ...headers, 'retry-after': String(rate.retryAfterSeconds) });
        return;
      }
      if (method === 'OPTIONS') {
        response.writeHead(204, headers);
        response.end();
        return;
      }

      if ((method === 'GET' || method === 'HEAD') && url.pathname === '/health') {
        const payload = {
          status: 'ok',
          service: 'smartcart-local-demo-backend',
          version: '0.1.0',
          timestamp: new Date(now()).toISOString(),
          meta: localDemoMeta()
        };
        if (method === 'HEAD') {
          response.writeHead(200, { ...headers, 'x-smartcart-data-mode': 'local-demo' });
          response.end();
        } else {
          sendJson(response, 200, payload, headers);
        }
        return;
      }

      const barcodeRoute = routeMatch(url.pathname, /^\/v1\/barcodes\/(?<gtin>\d{8,14})$/);
      if (method === 'GET' && barcodeRoute) {
        const result = await barcodeCatalog.resolve(barcodeRoute.gtin);
        if (result.status === 'invalid') {
          throw new HttpError(400, 'invalid_gtin', 'A valid GTIN-8, UPC-A, EAN-13, or GTIN-14 is required');
        }
        sendJson(response, 200, result, headers);
        return;
      }

      if (method === 'POST' && url.pathname === '/v1/demo/accounts') {
        const body = await readJson(request, config.maxBodyBytes);
        const account = store.createAccount(body);
        sendJson(response, 201, { account, meta: localDemoMeta() }, headers);
        return;
      }

      if (method === 'POST' && url.pathname === '/v1/demo/sessions') {
        const body = await readJson(request, config.maxBodyBytes);
        const session = store.createSession(body);
        sendJson(response, 201, { session, meta: localDemoMeta() }, headers);
        return;
      }

      const token = bearerToken(request);
      if (method === 'POST' && url.pathname === '/api/handoffs/instacart') {
        const account = store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const shoppingManifestId = assertString(body.shoppingManifestId, 'shoppingManifestId', { max: 100 });
        const manifest = store.getManifest(account.id, shoppingManifestId);
        const handoff = await instacartHandoff.create(manifest, body);
        sendJson(response, 200, {
          ...handoff,
          meta: localDemoMeta({
            outboundProvider: handoff.provider,
            presentationMode: handoff.presentationMode
          })
        }, headers);
        return;
      }

      if (method === 'POST' && url.pathname === '/v1/recipe-pages/extract') {
        store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const targetUrl = assertString(body.url, 'url', { max: 2_048 });
        const page = await recipePageFetcher.fetch(targetUrl);
        const recipe = recipePageExtractor.extract(page.html);
        sendJson(response, 200, {
          page: {
            originalUrl: page.originalUrl,
            finalUrl: page.finalUrl,
            redirectCount: page.redirectCount,
            contentType: page.contentType,
            charset: page.charset,
            byteLength: page.byteLength
          },
          recipe,
          meta: localDemoMeta({ recipePageSource: 'user-requested-third-party-page' })
        }, headers);
        return;
      }

      if (method === 'DELETE' && url.pathname === '/v1/demo/sessions/current') {
        if (!token) throw new HttpError(401, 'invalid_session', 'A local/demo bearer session is required');
        store.authenticate(token);
        store.deleteSession(token);
        sendJson(response, 200, { revoked: true, meta: localDemoMeta() }, headers);
        return;
      }

      if (method === 'GET' && url.pathname === '/v1/demo/account') {
        const account = store.authenticate(token);
        sendJson(response, 200, { account, meta: localDemoMeta() }, headers);
        return;
      }

      const oauthStart = routeMatch(url.pathname, /^\/v1\/oauth\/(?<provider>[a-z0-9-]+)\/start$/);
      if (method === 'POST' && oauthStart) {
        const account = store.authenticate(token);
        const result = oauth.start({ accountId: account.id, provider: oauthStart.provider });
        sendJson(response, 201, { oauth: result, meta: localDemoMeta() }, headers);
        return;
      }

      const oauthCallback = routeMatch(url.pathname, /^\/v1\/oauth\/(?<provider>[a-z0-9-]+)\/callback$/);
      if (method === 'POST' && oauthCallback) {
        const account = store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const result = oauth.complete({ accountId: account.id, provider: oauthCallback.provider, ...body });
        sendJson(response, 200, { oauth: result, meta: localDemoMeta() }, headers);
        return;
      }

      if (method === 'POST' && url.pathname === '/v1/manifests') {
        const account = store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const manifest = store.createManifest(account.id, body.manifest ?? body);
        sendJson(response, 201, { manifest, meta: localDemoMeta() }, headers);
        return;
      }

      const manifestRoute = routeMatch(url.pathname, /^\/v1\/manifests\/(?<id>[0-9a-f-]{36})$/i);
      if (manifestRoute && method === 'GET') {
        const account = store.authenticate(token);
        const manifest = store.getManifest(account.id, manifestRoute.id);
        sendJson(response, 200, { manifest, meta: localDemoMeta() }, headers);
        return;
      }
      if (manifestRoute && method === 'PATCH') {
        const account = store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const manifest = store.updateManifest(
          account.id,
          manifestRoute.id,
          body.manifest ?? {},
          body.expectedVersion
        );
        sendJson(response, 200, { manifest, meta: localDemoMeta() }, headers);
        return;
      }

      const syncRoute = routeMatch(url.pathname, /^\/v1\/manifests\/(?<id>[0-9a-f-]{36})\/sync$/i);
      if (syncRoute && method === 'POST') {
        const account = store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const manifest = store.syncManifest(account.id, syncRoute.id, body);
        sendJson(response, 200, {
          manifest,
          sync: { status: 'accepted-local-demo', conflictPolicy: 'client-must-merge-and-retry' },
          meta: localDemoMeta()
        }, headers);
        return;
      }

      if (method === 'POST' && url.pathname === '/v1/analytics/events') {
        const account = store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const eventIds = store.ingestAnalytics(account.id, body.events);
        sendJson(response, 202, {
          accepted: eventIds.length,
          eventIds,
          disclosure: 'Events are held only in bounded local/demo memory and are never transmitted.',
          meta: localDemoMeta()
        }, headers);
        return;
      }

      if (method === 'POST' && url.pathname === '/v1/affiliate-links') {
        store.authenticate(token);
        const body = await readJson(request, config.maxBodyBytes);
        const link = affiliate.create(body);
        sendJson(response, 200, { link, meta: localDemoMeta() }, headers);
        return;
      }

      throw new HttpError(404, 'route_not_found', 'Route does not exist');
    } catch (error) {
      const status = error instanceof HttpError
        ? error.status
        : error instanceof BarcodeProviderError
          ? error.httpStatus
          : 500;
      const code = error instanceof HttpError || error instanceof BarcodeProviderError
        ? error.code
        : 'internal_error';
      const message = error instanceof HttpError || error instanceof BarcodeProviderError
        ? error.message
        : 'Unexpected local/demo server error';
      if (status >= 500) logger.error('http_error', { requestId: id, error });
      sendJson(response, status, {
        error: {
          code,
          message,
          requestId: id,
          ...(error instanceof HttpError && error.details ? { details: error.details } : {})
        },
        meta: localDemoMeta()
      }, { ...cors, 'x-request-id': id });
    }
  }

  return {
    handler,
    config,
    services: {
      store,
      oauth,
      affiliate,
      limiter,
      recipePageFetcher,
      recipePageExtractor,
      instacartHandoff,
      barcodeCatalog,
      solariResearch: solariApi.services.research
    }
  };
}

export function createServer(options = {}) {
  const app = createApp(options);
  return { ...app, server: createNodeServer(app.handler) };
}
