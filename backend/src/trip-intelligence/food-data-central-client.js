import { TtlCache } from '../lib/ttl-cache.js';

const DEFAULT_BASE_URL = 'https://api.nal.usda.gov/fdc/v1';
const MAX_RESPONSE_BYTES = 1_048_576;
const DEFAULT_CACHE_TTL_MS = 86_400_000;
const DEFAULT_CACHE_MAX_ENTRIES = 512;

export class FoodDataCentralError extends Error {
  constructor(code, message, { status = null, retryable = false } = {}) {
    super(message);
    this.name = 'FoodDataCentralError';
    this.code = code;
    this.status = status;
    this.retryable = retryable;
  }
}

function requireApiKey(apiKey) {
  if (typeof apiKey !== 'string' || apiKey.trim().length === 0) {
    throw new FoodDataCentralError(
      'usda_configuration_missing',
      'USDA FoodData Central is not configured.'
    );
  }
  return apiKey.trim();
}

function nutrientRecord(nutrient) {
  const id = nutrient.nutrientId ?? nutrient.nutrient?.id;
  const value = nutrient.value ?? nutrient.amount;
  const unitName = nutrient.unitName ?? nutrient.nutrient?.unitName;
  if (!Number.isFinite(id) || !Number.isFinite(value) || typeof unitName !== 'string') return null;
  return { nutrientId: id, value, unitName: unitName.toUpperCase() };
}

function normalizedFood(food) {
  if (!Number.isSafeInteger(food?.fdcId) || typeof food?.description !== 'string') {
    throw new FoodDataCentralError(
      'usda_response_invalid',
      'USDA FoodData Central returned an invalid food record.'
    );
  }

  return {
    fdcId: food.fdcId,
    description: food.description,
    dataType: typeof food.dataType === 'string' ? food.dataType : null,
    publishedDate: typeof food.publishedDate === 'string' ? food.publishedDate : null,
    nutrients: (food.foodNutrients ?? []).map(nutrientRecord).filter(Boolean),
    portions: (food.foodPortions ?? []).flatMap((portion) => {
      const amount = Number(portion.amount);
      const gramWeight = Number(portion.gramWeight);
      const modifier = typeof portion.modifier === 'string' ? portion.modifier.trim() : '';
      const measureUnit = typeof portion.measureUnit?.name === 'string'
        ? portion.measureUnit.name.trim()
        : '';
      if (!(amount > 0) || !(gramWeight > 0) || (modifier.length === 0 && measureUnit.length === 0)) {
        return [];
      }
      return [{ amount, gramWeight, modifier, measureUnit }];
    })
  };
}

async function readJson(response) {
  const declaredLength = Number(response.headers.get('content-length'));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
    throw new FoodDataCentralError(
      'usda_response_too_large',
      'USDA FoodData Central returned an unexpectedly large response.',
      { status: response.status }
    );
  }
  const reader = response.body?.getReader();
  if (!reader) {
    throw new FoodDataCentralError(
      'usda_response_invalid',
      'USDA FoodData Central returned an empty response.',
      { status: response.status }
    );
  }
  const decoder = new TextDecoder();
  let bytes = 0;
  let text = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new FoodDataCentralError(
        'usda_response_too_large',
        'USDA FoodData Central returned an unexpectedly large response.',
        { status: response.status }
      );
    }
    text += decoder.decode(value, { stream: true });
  }
  text += decoder.decode();
  try {
    return JSON.parse(text);
  } catch {
    throw new FoodDataCentralError(
      'usda_response_invalid',
      'USDA FoodData Central returned invalid JSON.',
      { status: response.status }
    );
  }
}

export class FoodDataCentralClient {
  constructor({
    apiKey,
    fetchImpl = globalThis.fetch,
    baseUrl = DEFAULT_BASE_URL,
    timeoutMs = 8_000,
    cacheTtlMs = DEFAULT_CACHE_TTL_MS,
    cacheMaxEntries = DEFAULT_CACHE_MAX_ENTRIES,
    cache = new TtlCache({ defaultTtlMs: cacheTtlMs })
  }) {
    this.apiKey = requireApiKey(apiKey);
    if (typeof fetchImpl !== 'function') throw new TypeError('fetchImpl is required');
    if (!Number.isFinite(cacheTtlMs) || cacheTtlMs <= 0) {
      throw new TypeError('cacheTtlMs must be positive');
    }
    if (!Number.isSafeInteger(cacheMaxEntries) || cacheMaxEntries <= 0) {
      throw new TypeError('cacheMaxEntries must be a positive integer');
    }
    this.fetchImpl = fetchImpl;
    this.baseUrl = baseUrl.replace(/\/+$/u, '');
    this.timeoutMs = timeoutMs;
    this.cache = cache;
    this.cacheTtlMs = cacheTtlMs;
    this.cacheMaxEntries = cacheMaxEntries;
    this.inFlight = new Map();
  }

  async cached(key, load) {
    const cached = this.cache.get(key);
    if (cached !== undefined) return structuredClone(cached);

    let pending = this.inFlight.get(key);
    if (pending === undefined) {
      pending = load();
      this.inFlight.set(key, pending);
    }
    try {
      const value = await pending;
      if (this.cache.size < this.cacheMaxEntries) {
        this.cache.set(key, structuredClone(value), this.cacheTtlMs);
      }
      return structuredClone(value);
    } finally {
      if (this.inFlight.get(key) === pending) this.inFlight.delete(key);
    }
  }

  async request(path, options = {}) {
    const url = new URL(`${this.baseUrl}/${path.replace(/^\/+/, '')}`);
    url.searchParams.set('api_key', this.apiKey);
    let response;
    try {
      response = await this.fetchImpl(url, {
        ...options,
        signal: AbortSignal.timeout(this.timeoutMs),
        headers: { 'content-type': 'application/json', ...(options.headers ?? {}) }
      });
    } catch (error) {
      throw new FoodDataCentralError(
        error?.name === 'TimeoutError' ? 'usda_timeout' : 'usda_unavailable',
        'USDA FoodData Central is temporarily unavailable.',
        { retryable: true }
      );
    }

    if (!response.ok) {
      throw new FoodDataCentralError(
        response.status === 429 ? 'usda_rate_limited' : 'usda_request_failed',
        'USDA FoodData Central could not complete the request.',
        { status: response.status, retryable: response.status === 429 || response.status >= 500 }
      );
    }
    return readJson(response);
  }

  async searchFoods(query, { pageSize = 5 } = {}) {
    if (typeof query !== 'string' || query.trim().length === 0) return [];
    const normalizedQuery = query.trim();
    const boundedPageSize = Math.max(1, Math.min(10, pageSize));
    return this.cached(`search:${normalizedQuery.toLocaleLowerCase('en-US')}:${boundedPageSize}`, async () => {
      const payload = await this.request('foods/search', {
        method: 'POST',
        body: JSON.stringify({
          query: normalizedQuery,
          dataType: ['Foundation', 'SR Legacy'],
          pageSize: boundedPageSize
        })
      });
      if (!Array.isArray(payload.foods)) {
        throw new FoodDataCentralError('usda_response_invalid', 'USDA search results were invalid.');
      }
      return payload.foods.map(normalizedFood);
    });
  }

  async foodDetails(fdcId) {
    if (!Number.isSafeInteger(fdcId) || fdcId <= 0) throw new TypeError('fdcId must be positive');
    return this.cached(`food:${fdcId}`, async () => (
      normalizedFood(await this.request(`food/${fdcId}`))
    ));
  }
}
