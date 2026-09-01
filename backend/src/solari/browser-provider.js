import { Solari } from '@solarisdk/browser';
import { freshness } from './fixture-provider.js';
import { SolariResearchError } from './errors.js';
import { acquireWithinDeadline, runWithinDeadline, timeoutWithinDeadline } from './deadline.js';

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

function confidenceFor(extracted, ambiguityReasons) {
  if (
    ambiguityReasons.length === 0
    && extracted.title
    && extracted.packageQuantity
    && extracted.packageUnit
    && extracted.visiblePrice !== null
  ) return 'high';
  if (extracted.title && (extracted.packageQuantity || extracted.visiblePrice !== null)) return 'medium';
  return 'low';
}

function ambiguitiesFor(extracted, requirement) {
  const reasons = [];
  if (!extracted.title) reasons.push('A product title could not be normalized from the visible page.');
  if (!extracted.packageQuantity || !extracted.packageUnit) reasons.push('Package quantity or unit could not be normalized.');
  if (extracted.visiblePrice === null) reasons.push('No visible USD price could be normalized; price remains unknown.');
  const title = extracted.title?.toLowerCase() ?? '';
  const requested = requirement.name.toLowerCase();
  if (/\bgluten[ -]?free\b/.test(title) && !/\bgluten[ -]?free\b/.test(requested)) {
    reasons.push('Gluten-free attribute was not requested by this recipe.');
  }
  if (/\bfinely shredded\b/.test(requested) && /\bshredded\b/.test(title) && !/\bfinely shredded\b/.test(title)) {
    reasons.push('Shred size is not stated as finely shredded.');
  }
  return reasons;
}

async function closeBrowserResources(page, browser, client) {
  const attempts = [
    ...(page ? [['page', () => page.close()]] : []),
    ...(browser ? [['browser', () => browser.close()]] : []),
    ['client', () => client.close()]
  ];
  const failures = [];
  for (const [resource, close] of attempts) {
    try {
      await close();
    } catch {
      failures.push(resource);
    }
  }
  if (failures.length > 0) {
    throw new SolariResearchError(
      'solari_browser_cleanup_failed',
      `Solari Browser cleanup was not confirmed for: ${failures.join(', ')}.`,
      { status: 502 }
    );
  }
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

  async observe(request, { deadlineAt, clock = Date.now, signal, evidenceVersion = 'v1' } = {}) {
    if (!this.apiKey) {
      throw new SolariResearchError('solari_unavailable', 'Solari is unavailable because the server-side API key is not configured.', { status: 503 });
    }
    const client = this.solariFactory({
      apiKey: this.apiKey,
      ...(this.baseURL ? { baseUrl: this.baseURL } : {}),
      timeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock)
    });
    let browser;
    let activePage;
    let clientClosedEarly = false;
    try {
      browser = await acquireWithinDeadline(() => client.launch({
        stealth: false,
        recording: false,
        captcha: false,
        proxy: 'off',
        retries: 0,
        probe: false
      }), async (lateBrowser) => { await lateBrowser.close(); }, {
        configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal,
        onCancel: async () => { await client.close(); clientClosedEarly = true; }
      });
      const observations = [];
      for (const requirement of request.requirements) {
        for (const candidate of requirement.candidates) {
          const page = await runWithinDeadline(
            () => browser.newPage(),
            { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal }
          );
          activePage = page;
          try {
            await runWithinDeadline(
              () => page.goto(candidate.sourceURL, {
                waitUntil: 'domcontentloaded',
                timeout: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock)
              }),
              { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal }
            );
            if (typeof page.url !== 'function' || new URL(page.url()).href !== new URL(candidate.sourceURL).href) {
              throw new SolariResearchError('retailer_redirect_not_allowed', 'The admitted page redirected outside its exact candidate URL.', { status: 502 });
            }
            if (request.retailerID === 'smartcart-demo-grocer') {
              await runWithinDeadline(
                () => page.waitForSelector('[data-solari-product="true"]', {
                  timeout: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock)
                }),
                { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal }
              );
            }
            const data = await runWithinDeadline(() => page.evaluate((includeRawText) => {
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
                catalogEra: root?.dataset.catalogEra ?? null,
                syntheticPrice: root?.dataset.syntheticPrice ?? null,
                ...(includeRawText ? { rawText: document.body?.innerText ?? '' } : {})
              };
            }, evidenceVersion === 'v1'), { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal });
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
            const ambiguityReasons = ambiguitiesFor(extracted, requirement);
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
              confidence: confidenceFor(extracted, ambiguityReasons),
              ambiguityReasons,
              proteinGramsPerPackage: null,
              collectionMethod: request.retailerID === 'smartcart-demo-grocer'
                ? 'solari-browser-controlled-demo'
                : 'solari-browser-authorized-retailer',
              location: request.retailerID === 'smartcart-demo-grocer'
                ? { kind: 'controlled-demo', label: 'SmartCart Demo Grocer synthetic catalog' }
                : { kind: 'online-unspecified-store', label: request.storeReference },
              ...(evidenceVersion === 'v3' ? {
                catalogEra: data.catalogEra,
                syntheticPrice: data.syntheticPrice === 'true'
              } : {}),
              ...(evidenceVersion === 'v1' ? { rawText: boundedRawText(data.rawText) } : {}),
              freshness: freshness(observedAt, this.now)
            });
          } finally {
            await closeBrowserResources(page, null, { close: async () => {} });
            activePage = null;
          }
        }
      }
      return observations;
    } finally {
      await closeBrowserResources(activePage, browser, clientClosedEarly ? { close: async () => {} } : client);
    }
  }
}
