function integer(name, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const value = process.env[name];
  if (value === undefined || value === '') return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer from ${min} to ${max}`);
  }
  return parsed;
}

export function loadConfig(overrides = {}) {
  const env = overrides.env ?? process.env.NODE_ENV ?? 'development';
  const config = {
    env,
    host: process.env.HOST ?? '127.0.0.1',
    port: integer('PORT', 8787, { max: 65_535 }),
    logLevel: process.env.LOG_LEVEL ?? 'info',
    allowedOrigins: (process.env.ALLOWED_ORIGINS ?? 'http://localhost:3000,http://127.0.0.1:3000')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    sessionTtlMs: integer('SESSION_TTL_SECONDS', 3_600) * 1_000,
    oauthStateTtlMs: integer('OAUTH_STATE_TTL_SECONDS', 600) * 1_000,
    cacheTtlMs: integer('CACHE_TTL_SECONDS', 300) * 1_000,
    rateLimitWindowMs: integer('RATE_LIMIT_WINDOW_SECONDS', 60) * 1_000,
    rateLimitMax: integer('RATE_LIMIT_MAX_REQUESTS', 120),
    maxBodyBytes: integer('MAX_BODY_BYTES', 262_144, { max: 5_242_880 }),
    recipePageTimeoutMs: integer('RECIPE_PAGE_TIMEOUT_MS', 10_000, { max: 60_000 }),
    recipePageMaxBytes: integer('RECIPE_PAGE_MAX_BYTES', 2_097_152, { max: 10_485_760 }),
    recipePageMaxRedirects: integer('RECIPE_PAGE_MAX_REDIRECTS', 5, { max: 10 }),
    instacartApiKey: process.env.INSTACART_API_KEY || undefined,
    instacartApiBaseUrl: process.env.INSTACART_API_BASE_URL ?? (
      env === 'production' ? 'https://connect.instacart.com' : 'https://connect.dev.instacart.tools'
    ),
    instacartDemoHandoffUrl: process.env.INSTACART_DEMO_HANDOFF_URL || undefined,
    instacartTimeoutMs: integer('INSTACART_TIMEOUT_MS', 10_000, { max: 60_000 }),
    instacartHandoffCacheTtlMs: integer('INSTACART_HANDOFF_CACHE_TTL_SECONDS', 86_400, { max: 31_536_000 }) * 1_000,
    oauthClientId: process.env.OAUTH_DEMO_CLIENT_ID ?? 'smartcart-local-demo-client',
    oauthRedirectUri:
      process.env.OAUTH_DEMO_REDIRECT_URI ?? 'http://127.0.0.1:8787/v1/oauth/demo/callback',
    affiliateCampaign: process.env.AFFILIATE_DEMO_CAMPAIGN ?? 'smartcart-local-demo'
  };

  return { ...config, ...overrides };
}
