import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  randomUUID
} from 'node:crypto';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import { ContractValidationError, createContractValidator } from '../contracts/contract-validator.js';

const payloadSchemaId = 'https://schemas.smartcart.app/v1/handoff/smartcart-handoff-payload.schema.json';
const createResultSchemaId = 'https://schemas.smartcart.app/v1/handoff/smartcart-handoff-create-result.schema.json';
const tokenPattern = /^v1\.[A-Za-z0-9_-]+$/u;
const authenticatedContext = Buffer.from('smartcart-handoff:v1:smartcart-ios', 'utf8');
const ivBytes = 12;
const tagBytes = 16;

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function containsBlockingIssue(analysis) {
  return analysis?.data?.issues?.some((issue) => issue.severity === 'blocking') ?? true;
}

function secretKey(secret) {
  if (typeof secret !== 'string' || secret.length < 32) {
    throw new TypeError('HANDOFF_TOKEN_SECRET must encode exactly 32 random bytes.');
  }
  let key;
  try {
    key = Buffer.from(secret, 'base64url');
  } catch {
    throw new TypeError('HANDOFF_TOKEN_SECRET must encode exactly 32 random bytes.');
  }
  if (key.length !== 32) {
    throw new TypeError('HANDOFF_TOKEN_SECRET must encode exactly 32 random bytes.');
  }
  return key;
}

function requiredNumericReviewIds(recipe) {
  if (recipe.sourceType !== 'image_transcription') return [];
  return recipe.analysis.data.ingredients
    .filter((ingredient) => ingredient.quantity?.kind === 'numeric')
    .map((ingredient) => ingredient.ingredientId)
    .sort();
}

function validateRecipeLimits(recipes) {
  if (!Array.isArray(recipes) || recipes.length < 1 || recipes.length > 5) return false;
  const maximumServings = recipes.length === 1 ? 24 : 48;
  return recipes.every((recipe) => (
    Number.isSafeInteger(recipe?.analysis?.data?.servings)
    && recipe.analysis.data.servings > 0
    && recipe.analysis.data.servings <= maximumServings
  ));
}

export class HandoffClaimError extends Error {
  constructor(status, code, message, { retryable = false } = {}) {
    super(message);
    this.name = 'HandoffClaimError';
    this.status = status;
    this.code = code;
    this.retryable = retryable;
  }
}

export class HandoffClaimService {
  #key;
  #validatorPromise;
  #baseUrl;
  #ttlMs;
  #maxPayloadBytes;
  #maxTokenCharacters;
  #now;
  #randomBytes;

  constructor({
    secret,
    validator,
    baseUrl,
    ttlMs = 600_000,
    maxPayloadBytes = 131_072,
    maxTokenCharacters = 24_000,
    now = Date.now,
    randomBytesImpl = randomBytes
  }) {
    this.#key = secretKey(secret);
    this.#validatorPromise = validator ? Promise.resolve(validator) : createContractValidator();
    this.#baseUrl = new URL(baseUrl);
    if (
      this.#baseUrl.protocol !== 'https:'
      || this.#baseUrl.username
      || this.#baseUrl.password
      || this.#baseUrl.search
      || this.#baseUrl.hash
      || !['', '/'].includes(this.#baseUrl.pathname)
    ) throw new TypeError('SmartCart handoff base URL must be an HTTPS origin.');
    if (!Number.isSafeInteger(ttlMs) || ttlMs < 60_000 || ttlMs > 600_000) {
      throw new TypeError('SmartCart handoff TTL must be from 60 to 600 seconds.');
    }
    this.#ttlMs = ttlMs;
    this.#maxPayloadBytes = maxPayloadBytes;
    this.#maxTokenCharacters = maxTokenCharacters;
    this.#now = now;
    this.#randomBytes = randomBytesImpl;
  }

  tokenFingerprint(token) {
    if (typeof token !== 'string' || !tokenPattern.test(token) || token.length > this.#maxTokenCharacters) {
      throw new HandoffClaimError(400, 'handoff_claim_invalid', 'The SmartCart handoff is unavailable.');
    }
    return sha256(token);
  }

  #seal(payloadJson) {
    const compressed = deflateRawSync(Buffer.from(payloadJson, 'utf8'), { level: 9 });
    const iv = this.#randomBytes(ivBytes);
    if (!Buffer.isBuffer(iv) || iv.length !== ivBytes) throw new TypeError('Invalid handoff IV source.');
    const cipher = createCipheriv('aes-256-gcm', this.#key, iv);
    cipher.setAAD(authenticatedContext);
    const ciphertext = Buffer.concat([cipher.update(compressed), cipher.final()]);
    const token = `v1.${Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64url')}`;
    if (token.length > this.#maxTokenCharacters) {
      throw new HandoffClaimError(
        413,
        'handoff_token_too_large',
        'This grocery plan is too large to send to SmartCart.'
      );
    }
    return token;
  }

  #unseal(token) {
    this.tokenFingerprint(token);
    const encoded = token.slice(3);
    let sealed;
    try {
      sealed = Buffer.from(encoded, 'base64url');
    } catch {
      throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
    }
    if (sealed.toString('base64url') !== encoded || sealed.length <= ivBytes + tagBytes) {
      throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
    }
    const iv = sealed.subarray(0, ivBytes);
    const tag = sealed.subarray(ivBytes, ivBytes + tagBytes);
    const ciphertext = sealed.subarray(ivBytes + tagBytes);
    try {
      const decipher = createDecipheriv('aes-256-gcm', this.#key, iv);
      decipher.setAAD(authenticatedContext);
      decipher.setAuthTag(tag);
      const compressed = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      return inflateRawSync(compressed, { maxOutputLength: this.#maxPayloadBytes }).toString('utf8');
    } catch {
      throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
    }
  }

  async create({ recipes }) {
    if (!validateRecipeLimits(recipes)) {
      throw new HandoffClaimError(
        409,
        'handoff_limits_exceeded',
        'SmartCart handoffs support one recipe with up to 24 servings or up to five Meal Prep recipes with 48 servings each.'
      );
    }
    if (
      recipes.some((recipe) => containsBlockingIssue(recipe.analysis))
      || recipes.reduce(
        (total, recipe) => total + (recipe.analysis.data.ingredients?.length ?? 0),
        0
      ) > 500
    ) {
      throw new HandoffClaimError(
        409,
        'handoff_not_safe',
        'Resolve every blocking ingredient before creating a SmartCart handoff.'
      );
    }

    const validator = await this.#validatorPromise;
    for (const recipe of recipes) {
      validator.assert(
        'https://schemas.smartcart.app/v1/recipe/recipe-analysis-result.schema.json',
        recipe.analysis
      );
      const requiredIds = requiredNumericReviewIds(recipe);
      const suppliedIds = [...recipe.quantityReviewIngredientIds].sort();
      if (JSON.stringify(requiredIds) !== JSON.stringify(suppliedIds)) {
        throw new HandoffClaimError(
          409,
          'handoff_review_contract_invalid',
          'Every numeric quantity transcribed from an image must be confirmed in SmartCart.'
        );
      }
    }

    const recipesJson = JSON.stringify(recipes);
    const issuedAtMs = this.#now();
    const expiresAtMs = issuedAtMs + this.#ttlMs;
    const payload = {
      schemaVersion: '1.0',
      resolverVersion: 'smartcart-handoff-v1',
      requestId: randomUUID(),
      data: {
        claimId: randomUUID(),
        audience: 'smartcart-ios',
        payloadDigest: sha256(recipesJson),
        issuedAt: new Date(issuedAtMs).toISOString(),
        expiresAt: new Date(expiresAtMs).toISOString(),
        recipes: structuredClone(recipes)
      }
    };
    validator.assert(payloadSchemaId, payload);
    const payloadJson = JSON.stringify(payload);
    if (Buffer.byteLength(payloadJson) > this.#maxPayloadBytes) {
      throw new HandoffClaimError(
        413,
        'handoff_payload_too_large',
        'This grocery plan is too large to send to SmartCart.'
      );
    }

    const token = this.#seal(payloadJson);
    const claimUrl = new URL('/t', this.#baseUrl);
    claimUrl.hash = token;
    const result = {
      schemaVersion: '1.0',
      resolverVersion: 'smartcart-handoff-v1',
      requestId: randomUUID(),
      data: {
        claimUrl: claimUrl.href,
        expiresAt: payload.data.expiresAt
      }
    };
    validator.assert(createResultSchemaId, result);
    return result;
  }

  async claim({ token }) {
    const payloadJson = this.#unseal(token);
    let payload;
    try {
      payload = JSON.parse(payloadJson);
    } catch {
      throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
    }
    try {
      const validator = await this.#validatorPromise;
      validator.assert(payloadSchemaId, payload);
    } catch (error) {
      if (!(error instanceof ContractValidationError)) throw error;
      throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
    }
    if (payload.data.audience !== 'smartcart-ios' || Date.parse(payload.data.expiresAt) <= this.#now()) {
      throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
    }
    if (sha256(JSON.stringify(payload.data.recipes)) !== payload.data.payloadDigest) {
      throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
    }
    for (const recipe of payload.data.recipes) {
      if (
        JSON.stringify(requiredNumericReviewIds(recipe))
        !== JSON.stringify([...recipe.quantityReviewIngredientIds].sort())
      ) {
        throw new HandoffClaimError(410, 'handoff_unavailable', 'The SmartCart handoff is unavailable.');
      }
    }
    return payload;
  }
}
