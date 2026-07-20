import { FixedWindowRateLimiter } from '../lib/rate-limiter.js';
import { TtlCache } from '../lib/ttl-cache.js';

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
    const fields = 'code,product_name,brands,quantity';
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
      if (!response.ok) throw new Error(`open_food_facts_http_${response.status}`);

      const payload = await response.json();
      const name = payload?.product?.product_name?.trim();
      if (!name) return null;
      return {
        name,
        brand: payload.product.brands?.trim() || null,
        quantity: payload.product.quantity?.trim() || null,
        imageURL: null
      };
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
    if (!rate.allowed) throw new Error('open_food_facts_rate_limited');

    const product = await this.#provider.resolve(barcode);
    if (!product) {
      return this.#cache.set(barcode, { status: 'not_found', barcode }, this.#negativeTtlMs);
    }

    return this.#cache.set(barcode, {
      status: 'resolved',
      barcode,
      product,
      source: 'open_food_facts',
      verified: false
    }, this.#positiveTtlMs);
  }
}
