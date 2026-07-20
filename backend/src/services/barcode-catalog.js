import { FixedWindowRateLimiter } from '../lib/rate-limiter.js';
import { TtlCache } from '../lib/ttl-cache.js';

const providerFailureDefinitions = Object.freeze({
  rate_limited: {
    httpStatus: 429,
    message: 'The barcode catalog provider is rate limited'
  },
  timed_out: {
    httpStatus: 504,
    message: 'The barcode catalog provider timed out'
  },
  unavailable: {
    httpStatus: 503,
    message: 'The barcode catalog provider is unavailable'
  },
  upstream_error: {
    httpStatus: 502,
    message: 'The barcode catalog provider returned an upstream error'
  },
  malformed_response: {
    httpStatus: 502,
    message: 'The barcode catalog provider returned a malformed response'
  }
});

export class BarcodeProviderError extends Error {
  constructor(kind, { cause, upstreamStatus } = {}) {
    const definition = providerFailureDefinitions[kind];
    if (!definition) throw new TypeError(`Unsupported barcode provider failure: ${kind}`);
    super(definition.message, { cause });
    this.name = 'BarcodeProviderError';
    this.kind = kind;
    this.code = `barcode_provider_${kind}`;
    this.httpStatus = definition.httpStatus;
    this.upstreamStatus = upstreamStatus;
  }
}

export function validatedProductImageURL(value) {
  if (typeof value !== 'string' || value.trim() === '') return null;
  try {
    const url = new URL(value.trim());
    if (url.protocol !== 'https:' || url.username || url.password) return null;
    return url.href;
  } catch {
    return null;
  }
}

function optionalTrimmedString(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function publicProductIdentity(product) {
  const name = optionalTrimmedString(product?.name);
  if (!name) throw new BarcodeProviderError('malformed_response');
  return {
    name,
    brand: optionalTrimmedString(product.brand),
    quantity: optionalTrimmedString(product.quantity),
    imageURL: validatedProductImageURL(product.imageURL)
  };
}

export function normalizeGtin(value) {
  const digits = String(value ?? '').trim();
  if (!/^\d+$/.test(digits) || ![8, 12, 13, 14].includes(digits.length)) return null;

  const body = digits.slice(0, -1);
  const expected = body
    .split('')
    .reverse()
    .reduce((sum, digit, index) => sum + Number(digit) * (index % 2 === 0 ? 3 : 1), 0);
  const checkDigit = String((10 - (expected % 10)) % 10);
  if (digits.at(-1) !== checkDigit) return null;
  return digits.padStart(14, '0');
}

export class OpenFoodFactsBarcodeProvider {
  constructor({
    fetchImpl = fetch,
    baseUrl = 'https://world.openfoodfacts.org',
    userAgent,
    timeoutMs = 5_000
  } = {}) {
    this.fetchImpl = fetchImpl;
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.userAgent = userAgent;
    this.timeoutMs = timeoutMs;
  }

  async resolve(canonicalGtin14) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    const fields = 'code,product_name,brands,quantity,image_front_url';
    const url = `${this.baseUrl}/api/v3/product/${canonicalGtin14}?fields=${fields}&product_type=food&cc=us&lc=en`;

    try {
      const response = await this.fetchImpl(url, {
        headers: {
          accept: 'application/json',
          'user-agent': this.userAgent
        },
        signal: controller.signal
      });
      if (response.status === 404) return null;
      if (response.status === 429) {
        throw new BarcodeProviderError('rate_limited', { upstreamStatus: response.status });
      }
      if (response.status === 408 || response.status === 504) {
        throw new BarcodeProviderError('timed_out', { upstreamStatus: response.status });
      }
      if (!response.ok) {
        throw new BarcodeProviderError('upstream_error', { upstreamStatus: response.status });
      }

      let payload;
      try {
        payload = await response.json();
      } catch (error) {
        throw new BarcodeProviderError('malformed_response', { cause: error });
      }
      const name = optionalTrimmedString(payload?.product?.product_name);
      if (!name) throw new BarcodeProviderError('malformed_response');
      return {
        name,
        brand: optionalTrimmedString(payload.product.brands),
        quantity: optionalTrimmedString(payload.product.quantity),
        imageURL: validatedProductImageURL(payload.product.image_front_url)
      };
    } catch (error) {
      if (error instanceof BarcodeProviderError) throw error;
      if (error?.name === 'AbortError') {
        throw new BarcodeProviderError('timed_out', { cause: error });
      }
      throw new BarcodeProviderError('unavailable', { cause: error });
    } finally {
      clearTimeout(timeout);
    }
  }
}

export class BarcodeCatalogService {
  #provider;
  #cache;
  #inFlight = new Map();
  #positiveTtlMs;
  #negativeTtlMs;
  #limiter;

  constructor({
    provider,
    cache = new TtlCache(),
    positiveTtlMs = 86_400_000,
    negativeTtlMs = 900_000,
    rateLimit = 12,
    rateLimitWindowMs = 60_000,
    now = Date.now
  } = {}) {
    this.#provider = provider;
    this.#cache = cache;
    this.#positiveTtlMs = positiveTtlMs;
    this.#negativeTtlMs = negativeTtlMs;
    this.#limiter = new FixedWindowRateLimiter({ limit: rateLimit, windowMs: rateLimitWindowMs, now });
  }

  async resolve(rawGtin) {
    const barcode = normalizeGtin(rawGtin);
    if (!barcode) return { status: 'invalid', barcode: String(rawGtin ?? '') };

    const cached = this.#cache.get(barcode);
    if (cached) return cached;
    if (this.#inFlight.has(barcode)) return this.#inFlight.get(barcode);

    const work = this.#resolveUncached(barcode).finally(() => this.#inFlight.delete(barcode));
    this.#inFlight.set(barcode, work);
    return work;
  }

  async #resolveUncached(barcode) {
    const rate = this.#limiter.consume('open-food-facts');
    if (!rate.allowed) throw new BarcodeProviderError('rate_limited');

    const product = await this.#provider.resolve(barcode);
    if (!product) {
      return this.#cache.set(barcode, { status: 'not_found', barcode }, this.#negativeTtlMs);
    }

    return this.#cache.set(barcode, {
      status: 'resolved',
      barcode,
      product: publicProductIdentity(product),
      source: 'open_food_facts',
      verified: false
    }, this.#positiveTtlMs);
  }
}
