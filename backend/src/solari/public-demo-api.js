import { createHmac, randomUUID } from 'node:crypto';
import { ContractValidationError, createContractValidator } from '../contracts/contract-validator.js';
import { loadConfig } from '../config.js';
import { HttpError, readJson, validatePreparsedJsonBody } from '../lib/http.js';
import { createLogger } from '../lib/logger.js';
import { SolariResearchError } from './errors.js';
import { InMemorySolariPublicDemoStore, UpstashSolariPublicDemoStore } from './public-demo-store.js';
import {
  assertPublicDemoRequest,
  createV4PublicDemoRequest
} from './v4-public-demo-request.js';
import { createSolariV4ResearchService, V4_RESULT_SCHEMA_ID } from './v4-research-service.js';

const DIRECT_PATH = '/public-demo/v1/solari/research';
const API_PATHS = new Set(['/api/solari-public-demo.js', '/api/solari-public-demo']);

function isRoute(url) {
  return url.pathname === DIRECT_PATH
    || (API_PATHS.has(url.pathname) && url.searchParams.get('route') === 'research');
}

function corsHeaders(origin) {
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'Content-Type',
    'access-control-max-age': '600',
    vary: 'Origin'
  };
}

function send(response, status, payload, traceID, headers = {}) {
  if (response.destroyed || response.writableEnded) return;
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'x-smartcart-data-mode': 'solari-public-demo',
    'x-request-id': traceID,
    ...headers
  });
  response.end(body);
}

function clientAddress(request) {
  const forwarded = request.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) return forwarded.split(',')[0].trim();
  return request.socket?.remoteAddress || 'unknown';
}

function visitorHash(request, secret) {
  return createHmac('sha256', secret).update(clientAddress(request)).digest('hex');
}

function requireConfig(config, { injectedStore = false } = {}) {
  if (config.solariPublicDemoEnabled !== true) {
    throw new SolariResearchError('route_not_found', 'Route does not exist.', { status: 404 });
  }
  let configuredOrigin;
  try { configuredOrigin = new URL(config.solariPublicDemoOrigin); } catch { configuredOrigin = null; }
  if (!configuredOrigin || configuredOrigin.protocol !== 'https:' || configuredOrigin.origin !== config.solariPublicDemoOrigin) {
    throw new SolariResearchError('solari_public_demo_origin_invalid', 'The public demo origin is not configured as one exact HTTPS origin.', { status: 503 });
  }
  if (typeof config.solariPublicDemoIpHmacSecret !== 'string' || config.solariPublicDemoIpHmacSecret.length < 32) {
    throw new SolariResearchError('solari_public_demo_identity_unavailable', 'The public demo privacy key is not configured.', { status: 503 });
  }
  if (!injectedStore && (!config.solariBetaRedisUrl || !config.solariBetaRedisToken)) {
    throw new SolariResearchError('solari_public_demo_store_unavailable', 'The public demo state store is not configured.', { status: 503 });
  }
}

function withoutExpiredReplay(result, now) {
  const copy = structuredClone(result);
  const replay = copy?.provenance?.browserReplay;
  if (replay && Date.parse(replay.expiresAt) <= now) delete copy.provenance.browserReplay;
  return copy;
}

function publicResponse(result, deliveryMode, fallbackReason, now) {
  return {
    schemaVersion: 'smartcart-solari-public-demo-response-v1',
    deliveryMode,
    generatedAt: new Date(now).toISOString(),
    ...(fallbackReason ? { fallbackReason } : {}),
    result: withoutExpiredReplay(result, now)
  };
}

export function createSolariPublicDemoApi(options = {}) {
  const config = loadConfig(options.config);
  const now = options.now ?? Date.now;
  const logger = options.logger ?? createLogger({ level: config.logLevel, dataMode: 'solari-public-demo' });
  const validatorPromise = options.validator ? Promise.resolve(options.validator) : createContractValidator();
  let store = options.store ?? null;
  const research = options.researchService ?? createSolariV4ResearchService({
    ...options,
    config,
    accessBoundary: 'public-demo'
  });

  function getStore() {
    requireConfig(config, { injectedStore: Boolean(store) });
    store ??= new UpstashSolariPublicDemoStore({
      url: config.solariBetaRedisUrl,
      token: config.solariBetaRedisToken,
      prefix: config.solariPublicDemoStorePrefix
    });
    return store;
  }

  async function cached(fallbackReason) {
    const record = await getStore().getCachedResult();
    if (!record?.result) return null;
    const validator = await validatorPromise;
    validator.assert(V4_RESULT_SCHEMA_ID, withoutExpiredReplay(record.result, now()));
    return publicResponse(record.result, 'cached-verified-run', fallbackReason, now());
  }

  async function handler(request, response) {
    const traceID = randomUUID();
    const controller = new AbortController();
    const abort = () => controller.abort();
    const close = () => { if (request.aborted === true || request.complete === false) abort(); };
    request.once('aborted', abort);
    request.once('close', close);
    let origin;
    let leaseID;
    try {
      const url = new URL(request.url ?? '/', 'https://smartcart.invalid');
      if (!isRoute(url)) throw new SolariResearchError('route_not_found', 'Route does not exist.', { status: 404 });
      requireConfig(config, { injectedStore: Boolean(store) });
      origin = request.headers.origin;
      if (origin !== config.solariPublicDemoOrigin) {
        throw new SolariResearchError('public_demo_origin_not_allowed', 'This origin is not allowed to invoke the public demo.', { status: 403 });
      }
      const responseCors = corsHeaders(origin);
      if (request.method === 'OPTIONS') {
        response.writeHead(204, { ...responseCors, 'cache-control': 'no-store' });
        response.end();
        return;
      }
      if (request.method !== 'POST') throw new SolariResearchError('route_not_found', 'Route does not exist.', { status: 404 });
      const payload = request.body && typeof request.body === 'object'
        ? validatePreparsedJsonBody(request, request.body, config.solariPublicDemoMaxBodyBytes)
        : await readJson(request, config.solariPublicDemoMaxBodyBytes);
      assertPublicDemoRequest(payload);

      if (!await getStore().runtimeEnabled(config.solariPublicDemoRuntimeKey, {
        bootstrap: config.solariPublicDemoRuntimeBootstrapEnabled
      })) {
        const fallback = await cached('runtime-disabled');
        if (fallback) { send(response, 200, fallback, traceID, responseCors); return; }
        throw new SolariResearchError('solari_public_demo_killed', 'Live public demo execution is disabled by the runtime switch.', { status: 503 });
      }

      const admission = await getStore().admit({
        visitorHash: visitorHash(request, config.solariPublicDemoIpHmacSecret),
        now: now(),
        perIpDailyLimit: config.solariPublicDemoPerIpDailyLimit,
        globalDailyLimit: config.solariPublicDemoGlobalDailyLimit,
        concurrencyLimit: config.solariPublicDemoConcurrencyLimit,
        dailyBudgetUnits: config.solariPublicDemoDailyBudgetUnits,
        runBudgetUnits: config.solariPublicDemoRunBudgetUnits,
        leaseTtlSeconds: config.solariPublicDemoLeaseTtlSeconds
      });
      if (!admission.allowed) {
        const fallback = await cached(admission.reason);
        if (fallback) { send(response, 200, fallback, traceID, responseCors); return; }
        const busy = admission.reason === 'concurrency';
        throw new SolariResearchError(
          busy ? 'solari_public_demo_busy' : 'solari_public_demo_quota_reached',
          busy ? 'The public demo is currently busy.' : 'The live public demo allowance has been reached.',
          { status: busy ? 503 : 429, retryable: true }
        );
      }
      leaseID = admission.leaseID;

      const monitored = new AbortController();
      let killed = false;
      let checking = false;
      const forwardAbort = () => monitored.abort();
      request.signal?.addEventListener?.('abort', forwardAbort, { once: true });
      controller.signal.addEventListener('abort', forwardAbort, { once: true });
      if (controller.signal.aborted) forwardAbort();
      const killMonitor = setInterval(async () => {
        if (checking || monitored.signal.aborted) return;
        checking = true;
        try {
          if (!await getStore().runtimeEnabled(config.solariPublicDemoRuntimeKey)) {
            killed = true;
            monitored.abort();
          }
        } catch {
          killed = true;
          monitored.abort();
        } finally { checking = false; }
      }, config.solariPublicDemoKillPollMs);

      let result;
      try {
        const generatedRequest = createV4PublicDemoRequest({ now });
        result = await research.research(generatedRequest, { signal: monitored.signal });
      } catch (error) {
        if (killed) throw new SolariResearchError('solari_public_demo_killed', 'Live public demo execution was stopped by the runtime switch.', { status: 503 });
        const fallback = await cached('provider-unavailable');
        if (fallback) { send(response, 200, fallback, traceID, responseCors); return; }
        throw error;
      } finally {
        clearInterval(killMonitor);
        controller.signal.removeEventListener('abort', forwardAbort);
      }

      const validator = await validatorPromise;
      validator.assert(V4_RESULT_SCHEMA_ID, result);
      if (result.provenance?.accessBoundary !== 'public-demo' || !result.provenance?.browserReplay
        || result.runtimeStats?.costTelemetry?.status !== 'unavailable') {
        throw new SolariResearchError('solari_public_demo_result_invalid', 'The public demo result omitted required recording or runtime provenance.', { status: 502 });
      }
      await getStore().putCachedResult({ storedAt: new Date(now()).toISOString(), result }, config.solariPublicDemoCacheTtlSeconds);
      send(response, 200, publicResponse(result, 'live', null, now()), traceID, {
        ...responseCors,
        'x-smartcart-live-execution': 'fresh'
      });
    } catch (error) {
      const contract = error instanceof ContractValidationError;
      const known = error instanceof SolariResearchError || error instanceof HttpError;
      const status = contract ? 502 : known ? error.status : 500;
      if (status >= 500) logger.error('solari_public_demo_error', {
        errorName: error?.name ?? 'Error',
        errorCode: typeof error?.code === 'string' ? error.code : 'internal_error'
      });
      send(response, status, {
        error: {
          code: contract ? 'public_demo_contract_validation_failed' : known ? error.code : 'internal_error',
          message: contract ? 'The Solari result did not satisfy the SmartCart evidence contract.' : known ? error.message : 'The public Solari demo could not complete.',
          retryable: error instanceof SolariResearchError ? error.retryable : false
        }
      }, traceID, origin === config.solariPublicDemoOrigin ? corsHeaders(origin) : {});
    } finally {
      if (leaseID) {
        try { await getStore().release(leaseID); } catch (error) {
          logger.error('solari_public_demo_release_error', { errorName: error?.name ?? 'Error' });
        }
      }
      request.removeListener('aborted', abort);
      request.removeListener('close', close);
    }
  }

  return { handler, config, services: { getStore, research } };
}

export { InMemorySolariPublicDemoStore };
