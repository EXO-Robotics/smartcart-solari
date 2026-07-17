import { createHash, randomBytes } from 'node:crypto';
import { HttpError, assertString } from '../lib/http.js';
import { TtlCache } from '../lib/ttl-cache.js';

const PROVIDER = /^[a-z0-9][a-z0-9-]{0,49}$/;

function sha256Base64Url(value) {
  return createHash('sha256').update(value).digest('base64url');
}

export class LocalDemoOAuthPkce {
  #states;
  #clientId;
  #redirectUri;

  constructor({ ttlMs = 600_000, clientId, redirectUri, now = Date.now }) {
    this.#states = new TtlCache({ defaultTtlMs: ttlMs, now });
    this.#clientId = clientId;
    this.#redirectUri = redirectUri;
  }

  start({ accountId, provider }) {
    const normalizedProvider = assertString(provider, 'provider', { max: 50 }).toLowerCase();
    if (!PROVIDER.test(normalizedProvider)) throw new HttpError(400, 'unsupported_provider_name', 'provider must use lowercase letters, numbers, and hyphens');
    const state = randomBytes(24).toString('base64url');
    const codeVerifier = randomBytes(48).toString('base64url');
    const codeChallenge = sha256Base64Url(codeVerifier);
    this.#states.set(state, { accountId, provider: normalizedProvider, codeChallenge });
    const query = new URLSearchParams({
      response_type: 'code',
      client_id: this.#clientId,
      redirect_uri: this.#redirectUri,
      state,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256'
    });
    return {
      provider: normalizedProvider,
      state,
      codeVerifier,
      codeChallenge,
      authorizationUrl: `http://127.0.0.1/local-demo-oauth/${normalizedProvider}/authorize?${query}`,
      disclosure: 'Local/demo PKCE scaffold only. No provider request or token exchange occurs.',
      dataMode: 'local-demo'
    };
  }

  complete({ accountId, provider, state, code, codeVerifier }) {
    const normalizedProvider = assertString(provider, 'provider', { max: 50 }).toLowerCase();
    const normalizedState = assertString(state, 'state', { max: 200 });
    assertString(code, 'code', { max: 500 });
    const verifier = assertString(codeVerifier, 'codeVerifier', { min: 43, max: 128 });
    const pending = this.#states.get(normalizedState);
    this.#states.delete(normalizedState);
    if (!pending || pending.accountId !== accountId || pending.provider !== normalizedProvider) {
      throw new HttpError(400, 'invalid_oauth_state', 'OAuth state is expired, mismatched, or already used');
    }
    if (sha256Base64Url(verifier) !== pending.codeChallenge) {
      throw new HttpError(400, 'invalid_pkce_verifier', 'PKCE verifier does not match the local/demo challenge');
    }
    return {
      provider: normalizedProvider,
      connected: true,
      connectionId: `local-demo-${normalizedProvider}-${accountId}`,
      disclosure: 'Simulated local/demo connection. No live provider identity or tokens exist.',
      dataMode: 'local-demo'
    };
  }
}
