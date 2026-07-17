import { createHash } from 'node:crypto';
import { HttpError, assertString } from '../lib/http.js';
import { TtlCache } from '../lib/ttl-cache.js';

export class LocalDemoAffiliateProvider {
  constructor({ campaign }) {
    this.campaign = campaign;
    this.name = 'local-demo';
  }

  create(target, { retailerId }) {
    const url = new URL(target);
    url.searchParams.set('smartcart_affiliate', 'local-demo');
    url.searchParams.set('smartcart_campaign', this.campaign);
    url.searchParams.set('smartcart_retailer', retailerId);
    return url.toString();
  }
}

export class AffiliateLinkService {
  #provider;
  #cache;

  constructor({ provider, cacheTtlMs = 300_000, now = Date.now }) {
    this.#provider = provider;
    this.#cache = new TtlCache({ defaultTtlMs: cacheTtlMs, now });
  }

  create({ targetUrl, retailerId }) {
    const target = assertString(targetUrl, 'targetUrl', { max: 2_048 });
    const retailer = assertString(retailerId, 'retailerId', { max: 100 });
    let parsed;
    try {
      parsed = new URL(target);
    } catch {
      throw new HttpError(400, 'invalid_target_url', 'targetUrl must be a valid HTTPS URL');
    }
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password) {
      throw new HttpError(400, 'invalid_target_url', 'targetUrl must be HTTPS and contain no embedded credentials');
    }
    const cacheKey = createHash('sha256').update(`${target}\0${retailer}`).digest('hex');
    const cached = this.#cache.get(cacheKey);
    if (cached) return { ...cached, cache: 'hit' };
    const result = {
      targetUrl: parsed.toString(),
      affiliateUrl: this.#provider.create(parsed, { retailerId: retailer }),
      provider: this.#provider.name,
      disclosure: 'Local/demo affiliate decoration only. No live attribution, pricing, inventory, cart, or checkout.',
      dataMode: 'local-demo'
    };
    this.#cache.set(cacheKey, result);
    return { ...result, cache: 'miss' };
  }
}
