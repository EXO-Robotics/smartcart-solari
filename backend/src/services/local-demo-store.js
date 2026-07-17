import { randomBytes, randomUUID } from 'node:crypto';
import { HttpError, assertString } from '../lib/http.js';
import { TtlCache } from '../lib/ttl-cache.js';

const FULFILLMENT_MODES = new Set(['Pickup', 'Delivery']);
const HANDOFF_PROGRESS = new Set(['notStarted', 'inProgress', 'completed']);
const ITEM_STATUSES = new Set(['waiting', 'added', 'skipped']);
const SENSITIVE_ANALYTICS_KEY = /email|phone|address|name|token|secret|password|cookie|authorization/i;
const MAX_ACCOUNTS = 1_000;
const MAX_MANIFESTS = 10_000;

function clone(value) {
  return structuredClone(value);
}

function positiveInteger(value, name, max = 100_000) {
  if (!Number.isSafeInteger(value) || value < 1 || value > max) {
    throw new HttpError(400, 'validation_error', `${name} must be a positive integer no greater than ${max}`);
  }
  return value;
}

function validateItems(items) {
  if (!Array.isArray(items) || items.length > 500) {
    throw new HttpError(400, 'validation_error', 'items must be an array with at most 500 entries');
  }
  return items.map((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      throw new HttpError(400, 'validation_error', `items[${index}] must be an object`);
    }
    const product = item.product;
    if (!product || typeof product !== 'object' || Array.isArray(product)) {
      throw new HttpError(400, 'validation_error', `items[${index}].product must be an object`);
    }
    const status = item.status ?? 'waiting';
    if (!ITEM_STATUSES.has(status)) {
      throw new HttpError(400, 'validation_error', `items[${index}].status is unsupported`);
    }
    return {
      ...clone(item),
      id: item.id ? assertString(item.id, `items[${index}].id`, { max: 100 }) : randomUUID(),
      ingredientID: assertString(item.ingredientID, `items[${index}].ingredientID`, { max: 100 }),
      ingredientName: assertString(item.ingredientName, `items[${index}].ingredientName`, { max: 200 }),
      requestedQuantity: assertString(item.requestedQuantity, `items[${index}].requestedQuantity`, { max: 100 }),
      purchaseQuantity: positiveInteger(item.purchaseQuantity, `items[${index}].purchaseQuantity`, 1_000),
      product: { ...clone(product), dataMode: 'local-demo-client-supplied-never-live' },
      status
    };
  });
}

function normalizeManifest(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new HttpError(400, 'validation_error', 'manifest must be an object');
  }
  const fulfillmentMode = input.fulfillmentMode ?? 'Pickup';
  const handoffProgress = input.handoffProgress ?? 'notStarted';
  if (!FULFILLMENT_MODES.has(fulfillmentMode)) {
    throw new HttpError(400, 'validation_error', 'fulfillmentMode must be Pickup or Delivery');
  }
  if (!HANDOFF_PROGRESS.has(handoffProgress)) {
    throw new HttpError(400, 'validation_error', 'handoffProgress is unsupported');
  }
  return {
    recipeID: assertString(input.recipeID, 'recipeID', { max: 100 }),
    recipeTitle: assertString(input.recipeTitle, 'recipeTitle', { max: 200 }),
    retailerID: assertString(input.retailerID, 'retailerID', { max: 100 }),
    storeID: assertString(input.storeID, 'storeID', { max: 100 }),
    storeName: assertString(input.storeName, 'storeName', { max: 200 }),
    desiredServings: positiveInteger(input.desiredServings, 'desiredServings', 10_000),
    fulfillmentMode,
    items: validateItems(input.items),
    handoffProgress
  };
}

export class LocalDemoStore {
  #accounts = new Map();
  #sessions;
  #manifests = new Map();
  #analytics = [];
  #now;
  #sessionTtlMs;

  constructor({ sessionTtlMs = 3_600_000, now = Date.now } = {}) {
    this.#now = now;
    this.#sessionTtlMs = sessionTtlMs;
    this.#sessions = new TtlCache({ defaultTtlMs: sessionTtlMs, now });
  }

  createAccount({ displayName, email }) {
    if (this.#accounts.size >= MAX_ACCOUNTS) {
      throw new HttpError(503, 'local_demo_capacity_reached', 'Local/demo account capacity has been reached');
    }
    const normalizedEmail = assertString(email, 'email', { max: 254 }).toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalizedEmail)) {
      throw new HttpError(400, 'validation_error', 'email must have a valid local/demo format');
    }
    for (const account of this.#accounts.values()) {
      if (account.email === normalizedEmail) throw new HttpError(409, 'account_exists', 'Local/demo account already exists');
    }
    const account = {
      id: randomUUID(),
      displayName: assertString(displayName, 'displayName', { max: 100 }),
      email: normalizedEmail,
      createdAt: new Date(this.#now()).toISOString(),
      dataMode: 'local-demo'
    };
    this.#accounts.set(account.id, account);
    return clone(account);
  }

  createSession({ accountId }) {
    const account = this.#accounts.get(assertString(accountId, 'accountId', { max: 100 }));
    if (!account) throw new HttpError(401, 'invalid_demo_account', 'Local/demo account was not found');
    const token = randomBytes(32).toString('base64url');
    this.#sessions.set(token, { accountId: account.id });
    return {
      token,
      tokenType: 'Bearer',
      expiresInSeconds: Math.floor(this.#sessionTtlMs / 1_000),
      account: clone(account),
      dataMode: 'local-demo'
    };
  }

  authenticate(token) {
    const session = token ? this.#sessions.get(token) : undefined;
    if (!session) throw new HttpError(401, 'invalid_session', 'A valid local/demo bearer session is required');
    const account = this.#accounts.get(session.accountId);
    if (!account) throw new HttpError(401, 'invalid_session', 'Local/demo session account no longer exists');
    return clone(account);
  }

  deleteSession(token) {
    return this.#sessions.delete(token);
  }

  createManifest(accountId, input) {
    if (this.#manifests.size >= MAX_MANIFESTS) {
      throw new HttpError(503, 'local_demo_capacity_reached', 'Local/demo manifest capacity has been reached');
    }
    const now = new Date(this.#now()).toISOString();
    const manifest = {
      id: randomUUID(),
      accountId,
      ...normalizeManifest(input),
      version: 1,
      createdAt: now,
      updatedAt: now,
      lastSyncedAt: null,
      dataMode: 'local-demo'
    };
    this.#manifests.set(manifest.id, manifest);
    return clone(manifest);
  }

  getManifest(accountId, id) {
    const manifest = this.#manifests.get(id);
    if (!manifest || manifest.accountId !== accountId) throw new HttpError(404, 'manifest_not_found', 'Local/demo manifest was not found');
    return clone(manifest);
  }

  updateManifest(accountId, id, input, expectedVersion) {
    const current = this.getManifest(accountId, id);
    if (!Number.isSafeInteger(expectedVersion)) {
      throw new HttpError(400, 'validation_error', 'expectedVersion must be an integer');
    }
    if (current.version !== expectedVersion) {
      throw new HttpError(409, 'version_conflict', 'Local/demo manifest has a newer version', { manifest: current });
    }
    const normalized = normalizeManifest({ ...current, ...input });
    const updated = {
      ...current,
      ...normalized,
      version: current.version + 1,
      updatedAt: new Date(this.#now()).toISOString()
    };
    this.#manifests.set(id, updated);
    return clone(updated);
  }

  syncManifest(accountId, id, { baseVersion, manifest: incoming }) {
    const current = this.getManifest(accountId, id);
    if (!Number.isSafeInteger(baseVersion)) {
      throw new HttpError(400, 'validation_error', 'baseVersion must be an integer');
    }
    if (current.version !== baseVersion) {
      throw new HttpError(409, 'sync_conflict', 'Local/demo manifest sync requires client reconciliation', {
        serverManifest: current,
        resolution: 'client-must-merge-and-retry'
      });
    }
    const normalized = normalizeManifest(incoming);
    const timestamp = new Date(this.#now()).toISOString();
    const updated = {
      ...current,
      ...normalized,
      version: current.version + 1,
      updatedAt: timestamp,
      lastSyncedAt: timestamp
    };
    this.#manifests.set(id, updated);
    return clone(updated);
  }

  ingestAnalytics(accountId, events) {
    if (!Array.isArray(events) || events.length < 1 || events.length > 100) {
      throw new HttpError(400, 'validation_error', 'events must contain 1 to 100 local/demo events');
    }
    const accepted = events.map((event, index) => {
      if (!event || typeof event !== 'object' || Array.isArray(event)) {
        throw new HttpError(400, 'validation_error', `events[${index}] must be an object`);
      }
      const properties = event.properties ?? {};
      if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
        throw new HttpError(400, 'validation_error', `events[${index}].properties must be an object`);
      }
      const keys = Object.keys(properties);
      if (keys.length > 50 || keys.some((key) => SENSITIVE_ANALYTICS_KEY.test(key))) {
        throw new HttpError(400, 'sensitive_analytics_data_rejected', 'Analytics properties must be limited and contain no direct identifiers or credentials');
      }
      const encoded = JSON.stringify(properties);
      if (Buffer.byteLength(encoded) > 16_384) {
        throw new HttpError(400, 'validation_error', `events[${index}].properties is too large`);
      }
      const occurredAt = event.occurredAt ?? new Date(this.#now()).toISOString();
      if (typeof occurredAt !== 'string' || occurredAt.length > 50 || !Number.isFinite(Date.parse(occurredAt))) {
        throw new HttpError(400, 'validation_error', `events[${index}].occurredAt must be an ISO date-time string`);
      }
      return {
        id: randomUUID(),
        accountId,
        name: assertString(event.name, `events[${index}].name`, { max: 100 }),
        occurredAt: new Date(occurredAt).toISOString(),
        receivedAt: new Date(this.#now()).toISOString(),
        properties: clone(properties),
        dataMode: 'local-demo'
      };
    });
    this.#analytics.push(...accepted);
    if (this.#analytics.length > 10_000) this.#analytics.splice(0, this.#analytics.length - 10_000);
    return accepted.map(({ id }) => id);
  }
}
