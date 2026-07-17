import { createHash } from 'node:crypto';
import { HttpError, assertString } from '../lib/http.js';
import { TtlCache } from '../lib/ttl-cache.js';

const OFFICIAL_HEALTH_FILTERS = new Map([
  ['ORGANIC', 'ORGANIC'],
  ['GLUTEN FREE', 'GLUTEN_FREE'],
  ['GLUTEN_FREE', 'GLUTEN_FREE'],
  ['FAT FREE', 'FAT_FREE'],
  ['FAT_FREE', 'FAT_FREE'],
  ['VEGAN', 'VEGAN'],
  ['KOSHER', 'KOSHER'],
  ['SUGAR FREE', 'SUGAR_FREE'],
  ['SUGAR_FREE', 'SUGAR_FREE'],
  ['LOW FAT', 'LOW_FAT'],
  ['LOW_FAT', 'LOW_FAT']
]);

// Canonical values are all listed by Instacart's Units of measurement reference.
const UNIT_ALIASES = new Map();
function units(canonical, aliases) {
  for (const alias of aliases) UNIT_ALIASES.set(alias, canonical);
}

units('cup', ['cup', 'cups', 'c']);
units('fl oz can', ['fl oz can']);
units('fl oz container', ['fl oz container']);
units('fl oz jar', ['fl oz jar']);
units('fl oz pouch', ['fl oz pouch']);
units('fl oz ounce', ['fl oz ounce']);
units('gallon', ['gallon', 'gallons', 'gal', 'gals']);
units('milliliter', ['milliliter', 'millilitre', 'milliliters', 'millilitres', 'ml', 'mls']);
units('liter', ['liter', 'litre', 'liters', 'litres', 'l']);
units('pint', ['pint', 'pints', 'pt', 'pts']);
units('pt container', ['pt container']);
units('quart', ['quart', 'quarts', 'qt', 'qts']);
units('tablespoon', ['tablespoon', 'tablespoons', 'tb', 'tbs', 'tbsp', 'tbsps']);
units('teaspoon', ['teaspoon', 'teaspoons', 'ts', 'tsp', 'tspn', 'tsps']);
units('gram', ['gram', 'grams', 'g', 'gs']);
units('kilogram', ['kilogram', 'kilograms', 'kg', 'kgs']);
units('lb bag', ['lb bag']);
units('lb can', ['lb can']);
units('lb container', ['lb container']);
units('per lb', ['per lb']);
units('ounce', ['ounce', 'ounces', 'oz']);
units('ounces bag', ['ounces bag', 'oz bag']);
units('ounces can', ['ounces can', 'oz can']);
units('ounces container', ['ounces container', 'oz container']);
units('pound', ['pound', 'pounds', 'lb', 'lbs']);
units('bunch', ['bunch', 'bunches']);
units('can', ['can', 'cans']);
units('each', ['each', 'ea', 'item', 'items', 'count']);
units('each', ['clove', 'cloves', 'slice', 'slices', 'piece', 'pieces', 'sprig', 'sprigs', 'stalk', 'stalks']);
units('ears', ['ear', 'ears']);
units('head', ['head', 'heads']);
units('large', ['large', 'lrg', 'lge', 'lg']);
units('medium', ['medium', 'med', 'md']);
units('package', ['package', 'packages', 'pkg', 'pkgs']);
units('packet', ['packet', 'packets']);
units('small', ['small', 'sm']);
units('small ears', ['small ear', 'small ears']);
units('small head', ['small head', 'small heads']);

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, stableValue(value[key])])
    );
  }
  return value;
}

function fingerprint(value) {
  return createHash('sha256').update(JSON.stringify(stableValue(value))).digest('hex');
}

function optionalString(value, name, max = 200) {
  if (value === undefined || value === null || value === '') return undefined;
  return assertString(value, name, { max });
}

function normalizePostalCode(value) {
  const postalCode = assertString(value, 'postalCode', { max: 10 }).toUpperCase();
  if (/^\d{5}(?:-\d{4})?$/.test(postalCode)) {
    return { postalCode, countryCode: 'US' };
  }
  const compact = postalCode.replace(/\s+/g, '');
  if (/^[A-Z]\d[A-Z]\d[A-Z]\d$/.test(compact)) {
    return { postalCode: `${compact.slice(0, 3)} ${compact.slice(3)}`, countryCode: 'CA' };
  }
  throw new HttpError(400, 'validation_error', 'postalCode must be a valid US or Canadian postal code');
}

function normalizeFulfillmentPreference(value) {
  const normalized = assertString(value, 'fulfillmentPreference', { max: 20 }).toLowerCase();
  if (!['pickup', 'delivery', 'decide_in_instacart'].includes(normalized)) {
    throw new HttpError(400, 'validation_error', 'fulfillmentPreference must be pickup, delivery, or decide_in_instacart');
  }
  return normalized;
}

function isExcluded(item, handoff) {
  const inclusion = String(handoff.inclusion ?? item.inclusion ?? '').toLowerCase();
  const pantryState = String(handoff.pantryState ?? item.pantryState ?? '').toLowerCase();
  const pantryDecision = String(handoff.pantryDecision ?? item.pantryDecision ?? '').toLowerCase();
  const excludedReason = String(handoff.excludedReason ?? item.excludedReason ?? '').toLowerCase();
  return inclusion === 'pantry' ||
    inclusion === 'optional-excluded' ||
    inclusion === 'optional_excluded' ||
    handoff.pantry === true ||
    item.pantry === true ||
    handoff.pantryExcluded === true ||
    pantryState === 'have enough' ||
    pantryState === 'haveenough' ||
    pantryDecision === 'useavailable' ||
    pantryDecision === 'use available' ||
    handoff.optionalExcluded === true ||
    item.optionalExcluded === true ||
    handoff.optionalSelected === false ||
    excludedReason === 'pantry' ||
    excludedReason === 'optional' ||
    item.includeInList === false;
}

function highConfidence(value) {
  if (typeof value === 'number') return Number.isFinite(value) && value >= 0.82;
  if (typeof value !== 'string') return false;
  return ['high', 'high confidence', 'confirmed'].includes(value.trim().toLowerCase());
}

function normalizeMeasurement(measurement, path) {
  if (!measurement || typeof measurement !== 'object' || Array.isArray(measurement)) {
    throw new HttpError(422, 'unsafe_manifest', `${path} must be a measurement object`);
  }
  if (typeof measurement.quantity !== 'number' || !Number.isFinite(measurement.quantity) || measurement.quantity <= 0) {
    throw new HttpError(422, 'unsafe_manifest', `${path}.quantity must be a confirmed positive number`);
  }
  const rawUnit = optionalString(measurement.unit, `${path}.unit`, 50)?.toLowerCase().replace(/\s+/g, ' ');
  const unit = rawUnit ? UNIT_ALIASES.get(rawUnit) : 'each';
  if (!unit) {
    throw new HttpError(422, 'unsupported_measurement', `${path}.unit is not supported by Instacart`);
  }
  return { quantity: measurement.quantity, unit };
}

function normalizeHealthFilters(filters) {
  if (filters === undefined || filters === null) return [];
  if (!Array.isArray(filters)) {
    throw new HttpError(422, 'unsafe_manifest', 'healthFilters must be an array');
  }
  return [...new Set(filters.flatMap((filter) => {
    if (typeof filter !== 'string') return [];
    const normalized = filter.trim().toUpperCase().replace(/-/g, ' ').replace(/\s+/g, ' ');
    return OFFICIAL_HEALTH_FILTERS.get(normalized) ?? OFFICIAL_HEALTH_FILTERS.get(normalized.replace(/ /g, '_')) ?? [];
  }))];
}

function normalizeUpc(handoff, path) {
  if (!handoff.exactUPC) return undefined;
  const reliable = handoff.upcExactAndReliable === true ||
    handoff.exactUPCReliable === true ||
    handoff.exactIdentityReliable === true ||
    String(handoff.upcReliability ?? '').toLowerCase() === 'exact';
  if (!reliable) return undefined;
  const upc = String(handoff.exactUPC).replace(/\D/g, '');
  if (!/^(?:\d{12}|\d{14})$/.test(upc)) {
    throw new HttpError(422, 'unsafe_manifest', `${path}.exactUPC must contain exactly 12 or 14 digits`);
  }
  return upc;
}

function normalizeLineItem(item, index) {
  const nested = item.instacart ?? item.commerce;
  const handoff = nested && typeof nested === 'object' && !Array.isArray(nested) ? nested : item;
  if (isExcluded(item, handoff)) return undefined;

  const path = `items[${index}]`;
  if (handoff.unresolvedAlternative !== false) {
    throw new HttpError(422, 'unsafe_manifest', `${path} has an unresolved or unverified alternative`);
  }
  if (handoff.quantityConfirmed !== true) {
    throw new HttpError(422, 'unsafe_manifest', `${path} quantity has not been explicitly confirmed`);
  }
  const confidence = handoff.quantityConfidence ?? handoff.confidence ?? item.quantityConfidence;
  // SmartCart's commerce upload treats quantityConfirmed as the review assertion and
  // may omit a separate confidence value. If confidence is supplied, it must be high.
  if (confidence !== undefined && !highConfidence(confidence)) {
    throw new HttpError(422, 'unsafe_manifest', `${path} quantity confidence is not high enough for handoff`);
  }

  const suppliedMeasurements = handoff.lineItemMeasurements ?? handoff.line_item_measurements ?? handoff.measurements;
  const rawMeasurements = suppliedMeasurements ?? [{ quantity: handoff.quantity, unit: handoff.unit }];
  if (!Array.isArray(rawMeasurements) || rawMeasurements.length < 1 || rawMeasurements.length > 10) {
    throw new HttpError(422, 'unsafe_manifest', `${path} must provide 1 to 10 confirmed measurements`);
  }
  const lineItem = {
    name: assertString(handoff.name ?? item.ingredientName, `${path}.name`, { max: 200 }),
    line_item_measurements: rawMeasurements.map((measurement, measurementIndex) =>
      normalizeMeasurement(measurement, `${path}.lineItemMeasurements[${measurementIndex}]`)
    )
  };
  const displayText = optionalString(handoff.displayText, `${path}.displayText`, 300);
  if (displayText) lineItem.display_text = displayText;

  const upc = normalizeUpc(handoff, path);
  if (upc) lineItem.upcs = [upc];
  const healthFilters = normalizeHealthFilters(handoff.healthFilters ?? handoff.health_filters);
  if (healthFilters.length > 0 && !upc) lineItem.filters = { health_filters: healthFilters };
  return lineItem;
}

function buildProductsLinkPayload(manifest) {
  const lineItems = manifest.items.map(normalizeLineItem).filter(Boolean);
  if (lineItems.length === 0) {
    throw new HttpError(422, 'unsafe_manifest', 'Manifest has no purchasable items after pantry and optional exclusions');
  }
  const seenUpcs = new Set();
  for (const item of lineItems) {
    const upc = item.upcs?.[0];
    if (upc && seenUpcs.has(upc)) {
      throw new HttpError(422, 'unsafe_manifest', 'Exact UPC values must not be duplicated across line items');
    }
    if (upc) seenUpcs.add(upc);
  }
  return {
    title: assertString(manifest.recipeTitle, 'manifest.recipeTitle', { max: 200 }),
    link_type: 'shopping_list',
    line_items: lineItems
  };
}

function safeProviderUrl(value, name) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new HttpError(502, 'invalid_provider_response', `${name} was not a valid URL`);
  }
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password) {
    throw new HttpError(502, 'invalid_provider_response', `${name} must be an HTTPS URL without credentials`);
  }
  return parsed;
}

async function providerJson(response, operation) {
  if (!response.ok) {
    throw new HttpError(502, 'instacart_provider_error', `Instacart ${operation} request failed`, {
      upstreamStatus: response.status
    });
  }
  try {
    return await response.json();
  } catch {
    throw new HttpError(502, 'invalid_provider_response', `Instacart ${operation} response was not valid JSON`);
  }
}

export class InstacartApiProvider {
  constructor({ apiKey, baseUrl, fetchFn = globalThis.fetch, timeoutMs = 10_000 } = {}) {
    this.apiKey = apiKey;
    this.baseUrl = safeProviderUrl(baseUrl, 'INSTACART_API_BASE_URL');
    this.fetchFn = fetchFn;
    this.timeoutMs = timeoutMs;
    this.name = 'instacart';
    this.presentationMode = 'in_app_safari';
  }

  headers(contentType = false) {
    if (!this.apiKey) {
      throw new HttpError(503, 'instacart_not_configured', 'Instacart handoff is not configured');
    }
    return {
      accept: 'application/json',
      authorization: `Bearer ${this.apiKey}`,
      ...(contentType ? { 'content-type': 'application/json' } : {})
    };
  }

  async request(path, options) {
    try {
      return await this.fetchFn(new URL(path, this.baseUrl), {
        ...options,
        signal: AbortSignal.timeout(this.timeoutMs)
      });
    } catch (error) {
      if (error instanceof HttpError) throw error;
      if (error?.name === 'TimeoutError' || error?.name === 'AbortError') {
        throw new HttpError(504, 'instacart_provider_timeout', 'Instacart request timed out');
      }
      throw new HttpError(502, 'instacart_provider_unavailable', 'Instacart request could not be completed');
    }
  }

  async resolveRetailer({ postalCode, countryCode, preferredRetailerKey }) {
    if (!preferredRetailerKey) return undefined;
    const query = new URLSearchParams({ postal_code: postalCode, country_code: countryCode });
    try {
      const response = await this.request(`/idp/v1/retailers?${query}`, {
        method: 'GET',
        headers: this.headers()
      });
      const body = await providerJson(response, 'retailer lookup');
      return Array.isArray(body.retailers) && body.retailers.some((retailer) =>
        retailer?.retailer_key === preferredRetailerKey
      ) ? preferredRetailerKey : undefined;
    } catch {
      // Retailer preference is advisory. A lookup outage or mismatch must not block a safe list.
      return undefined;
    }
  }

  async create(payload, context) {
    const response = await this.request('/idp/v1/products/products_link', {
      method: 'POST',
      headers: this.headers(true),
      body: JSON.stringify(payload)
    });
    const body = await providerJson(response, 'products link');
    const url = safeProviderUrl(body.products_link_url, 'products_link_url');
    const retailerKey = await this.resolveRetailer(context);
    if (retailerKey) url.searchParams.set('retailer_key', retailerKey);
    return url.toString();
  }
}

export class InstacartDemoProvider {
  constructor({ url }) {
    this.url = safeProviderUrl(url, 'INSTACART_DEMO_HANDOFF_URL').toString();
    this.name = 'instacart-demo';
    this.presentationMode = 'in_app_safari';
  }

  async create() {
    return this.url;
  }
}

export class InstacartHandoffService {
  #cache;
  #inFlight = new Map();

  constructor({ provider, cacheTtlMs = 86_400_000, now = Date.now } = {}) {
    this.provider = provider;
    this.now = now;
    this.#cache = new TtlCache({ defaultTtlMs: cacheTtlMs, now });
  }

  async create(manifest, input) {
    const { postalCode, countryCode } = normalizePostalCode(input.postalCode);
    const preferredRetailerKey = optionalString(input.preferredRetailerKey, 'preferredRetailerKey', 100);
    const fulfillmentPreference = normalizeFulfillmentPreference(input.fulfillmentPreference);
    const payload = buildProductsLinkPayload(manifest);
    const manifestFingerprint = fingerprint({
      manifest: { payload },
      preference: { postalCode, countryCode, preferredRetailerKey: preferredRetailerKey ?? null, fulfillmentPreference }
    });
    const cached = this.#cache.get(manifestFingerprint);
    if (cached) return structuredClone(cached);
    if (this.#inFlight.has(manifestFingerprint)) return structuredClone(await this.#inFlight.get(manifestFingerprint));

    const pending = (async () => {
      const url = await this.provider.create(payload, { postalCode, countryCode, preferredRetailerKey, fulfillmentPreference });
      const result = {
        provider: this.provider.name,
        url,
        manifestFingerprint,
        createdAt: new Date(this.now()).toISOString(),
        presentationMode: this.provider.presentationMode
      };
      this.#cache.set(manifestFingerprint, result);
      return result;
    })();
    this.#inFlight.set(manifestFingerprint, pending);
    try {
      return structuredClone(await pending);
    } finally {
      this.#inFlight.delete(manifestFingerprint);
    }
  }
}

export const instacartHandoffInternals = {
  buildProductsLinkPayload,
  normalizePostalCode,
  fingerprint
};
