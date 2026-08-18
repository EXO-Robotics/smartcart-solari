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
    openFoodFactsBaseUrl: process.env.OPEN_FOOD_FACTS_BASE_URL ?? 'https://world.openfoodfacts.org',
    openFoodFactsUserAgent: process.env.OPEN_FOOD_FACTS_USER_AGENT
      ?? 'SmartCartBackend/0.1.0 (https://github.com/EXO-Robotics)',
    barcodeLookupTimeoutMs: integer('BARCODE_LOOKUP_TIMEOUT_MS', 5_000, { max: 30_000 }),
    barcodePositiveCacheTtlMs: integer('BARCODE_POSITIVE_CACHE_TTL_SECONDS', 86_400, { max: 31_536_000 }) * 1_000,
    barcodeNegativeCacheTtlMs: integer('BARCODE_NEGATIVE_CACHE_TTL_SECONDS', 900, { max: 86_400 }) * 1_000,
    barcodeProviderRateLimit: integer('BARCODE_PROVIDER_RATE_LIMIT_PER_MINUTE', 12, { max: 15 }),
    usdaFoodDataApiKey: process.env.USDA_FDC_API_KEY || undefined,
    usdaFoodDataBaseUrl: process.env.USDA_FDC_BASE_URL ?? 'https://api.nal.usda.gov/fdc/v1',
    usdaFoodDataTimeoutMs: integer('USDA_FDC_TIMEOUT_MS', 8_000, { max: 30_000 }),
    usdaFoodDataCacheTtlMs: integer('USDA_FDC_CACHE_TTL_SECONDS', 86_400, { max: 2_592_000 }) * 1_000,
    usdaFoodDataCacheMaxEntries: integer('USDA_FDC_CACHE_MAX_ENTRIES', 512, { max: 10_000 }),
    tripIntelligenceRateLimitPerMinute: integer('TRIP_INTELLIGENCE_RATE_LIMIT_PER_MINUTE', 30, { max: 1_000 }),
    mcpRateLimitPerMinute: integer('MCP_RATE_LIMIT_PER_MINUTE', 60, { max: 1_000 }),
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
