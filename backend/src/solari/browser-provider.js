import { Solari } from '@solarisdk/browser';
import { freshness } from './fixture-provider.js';
import { SolariResearchError } from './errors.js';

function normalizeUnit(value) {
  const unit = String(value ?? '').trim().toLowerCase();
  if (['oz', 'ounce', 'ounces'].includes(unit)) return 'ounce';
  if (['lb', 'lbs', 'pound', 'pounds'].includes(unit)) return 'pound';
  if (['count', 'ct', 'each'].includes(unit)) return 'count';
  return null;
}

function finitePositive(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : null;
}

function dollarsFromCents(value) {
  const cents = Number(value);
  return Number.isSafeInteger(cents) && cents >= 0 ? cents / 100 : null;
}

function boundedRawText(value) {
  const text = String(value ?? '').replace(/\s+/g, ' ').trim();
  return text.slice(0, 12_000) || 'No visible product text was returned by the admitted page.';
}

function confidenceFor(extracted) {
  if (extracted.title && extracted.packageQuantity && extracted.packageUnit && extracted.visiblePrice !== null) return 'high';
  if (extracted.title && (extracted.packageQuantity || extracted.visiblePrice !== null)) return 'medium';
  return 'low';
}

function ambiguitiesFor(extracted) {
  const reasons = [];
  if (!extracted.title) reasons.push('A product title could not be normalized from the visible page.');
  if (!extracted.packageQuantity || !extracted.packageUnit) reasons.push('Package quantity or unit could not be normalized.');
  if (extracted.visiblePrice === null) reasons.push('No visible USD price could be normalized; price remains unknown.');
  return reasons;
}

export class SolariBrowserProvider {
  constructor({
    apiKey,
    baseURL,
    timeoutMs = 15_000,
    now = Date.now,
    solariFactory = (options) => new Solari(options)
  } = {}) {
    this.apiKey = apiKey;
    this.baseURL = baseURL;
    this.timeoutMs = timeoutMs;
    this.now = now;
    this.solariFactory = solariFactory;
  }

  async observe(request) {
    if (!this.apiKey) {
      throw new SolariResearchError('solari_unavailable', 'Solari is unavailable because the server-side API key is not configured.', { status: 503 });
    }
    const client = this.solariFactory({ apiKey: this.apiKey, ...(this.baseURL ? { baseUrl: this.baseURL } : {}), timeoutMs: this.timeoutMs });
    let browser;
    try {
      browser = await client.launch({
        stealth: false,
        recording: false,
        captcha: false,
        proxy: 'off',
        retries: 0,
        probe: false
      });
      const observations = [];
      for (const requirement of request.requirements) {
        for (const candidate of requirement.candidates) {
          const page = await browser.newPage();
          try {
            await page.goto(candidate.sourceURL, { waitUntil: 'domcontentloaded', timeout: this.timeoutMs });
            if (typeof page.url !== 'function' || new URL(page.url()).href !== new URL(candidate.sourceURL).href) {
              throw new SolariResearchError('retailer_redirect_not_allowed', 'The admitted page redirected outside its exact candidate URL.', { status: 502 });
            }
            if (request.retailerID === 'smartcart-demo-grocer') {
              await page.waitForSelector('[data-solari-product="true"]', { timeout: this.timeoutMs });
            }
            const data = await page.evaluate(() => {
              const root = document.querySelector('[data-solari-product="true"]');
              const meta = (selector) => document.querySelector(selector)?.getAttribute('content') ?? null;
              const jsonLd = [...document.querySelectorAll('script[type="application/ld+json"]')]
                .map((node) => { try { return JSON.parse(node.textContent ?? ''); } catch { return null; } })
                .flatMap((entry) => Array.isArray(entry) ? entry : [entry])
                .find((entry) => entry && (entry['@type'] === 'Product' || entry.sku));
              return {
                productID: root?.dataset.productId ?? jsonLd?.sku ?? null,
                title: root?.dataset.productName ?? jsonLd?.name ?? meta('meta[property="og:title"]'),
                packageQuantity: root?.dataset.packageValue ?? null,
                packageUnit: root?.dataset.packageUnit ?? null,
                priceCents: root?.dataset.priceCents ?? null,
                price: jsonLd?.offers?.price ?? meta('meta[itemprop="price"]'),
                currency: root?.dataset.currency ?? jsonLd?.offers?.priceCurrency ?? meta('meta[itemprop="priceCurrency"]'),
                rawText: document.body?.innerText ?? ''
              };
            });
            if (typeof page.url !== 'function' || new URL(page.url()).href !== new URL(candidate.sourceURL).href) {
              throw new SolariResearchError('retailer_redirect_not_allowed', 'The admitted page redirected outside its exact candidate URL after rendering.', { status: 502 });
            }
            if (typeof data.productID !== 'string' || data.productID !== candidate.retailerProductID) {
              throw new SolariResearchError('retailer_product_mismatch', 'The admitted page did not match its expected product ID.', { status: 502 });
            }
            const packageQuantity = finitePositive(data.packageQuantity);
            const packageUnit = normalizeUnit(data.packageUnit);
            const visiblePrice = data.priceCents !== null ? dollarsFromCents(data.priceCents) : finitePositive(data.price);
            const currency = visiblePrice === null || data.currency !== 'USD' ? null : 'USD';
            const normalizedPrice = currency === 'USD' ? visiblePrice : null;
            const extracted = { title: data.title ? String(data.title).trim().slice(0, 500) : null, packageQuantity, packageUnit, visiblePrice: normalizedPrice };
            const observedAt = new Date(this.now()).toISOString();
            observations.push({
              schemaVersion: 'retailer-observation-v1',
              observationID: `obs-${request.requestID.toLowerCase()}-${candidate.retailerProductID}`,
              requirementID: requirement.id,
              retailerProductID: candidate.retailerProductID,
              sourceURL: candidate.sourceURL,
              title: extracted.title,
              packageDescription: packageQuantity && packageUnit ? `${packageQuantity} ${packageUnit}` : null,
              packageQuantity,
              packageUnit,
              visiblePrice: normalizedPrice,
              currency,
              observedAt,
              confidence: confidenceFor(extracted),
              ambiguityReasons: ambiguitiesFor(extracted),
              proteinGramsPerPackage: null,
              collectionMethod: request.retailerID === 'smartcart-demo-grocer'
                ? 'solari-browser-controlled-demo'
                : 'solari-browser-authorized-retailer',
              location: request.retailerID === 'smartcart-demo-grocer'
                ? { kind: 'controlled-demo', label: 'SmartCart Demo Grocer synthetic catalog' }
                : { kind: 'online-unspecified-store', label: request.storeReference },
              rawText: boundedRawText(data.rawText),
              freshness: freshness(observedAt, this.now)
            });
          } finally {
            await page.close().catch(() => {});
          }
        }
      }
      return observations;
    } finally {
      if (browser) await browser.close().catch(() => {});
      await client.close().catch(() => {});
    }
  }
}
