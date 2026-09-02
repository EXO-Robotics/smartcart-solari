function integer(name, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const value = process.env[name];
  if (value === undefined || value === '') return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer from ${min} to ${max}`);
  }
  return parsed;
}

function boolean(name, fallback = false) {
  const value = process.env[name];
  if (value === undefined || value === '') return fallback;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw new Error(`${name} must be exactly true or false`);
}

function integerList(name, fallback, { allowedValues } = {}) {
  const value = process.env[name];
  const parts = value === undefined || value === ''
    ? fallback.map(String)
    : value.split(',').map((entry) => entry.trim()).filter(Boolean);
  const parsed = parts.map((entry) => {
    if (!/^\d+$/.test(entry)) throw new Error(`${name} must be a comma-separated integer allowlist`);
    return Number.parseInt(entry, 10);
  });
  if (parsed.length === 0 || parsed.some((entry) => (
    !Number.isSafeInteger(entry) || (allowedValues && !allowedValues.includes(entry))
  ))) {
    throw new Error(`${name} contains an unsupported validation category`);
  }
  return [...new Set(parsed)];
}

function keyPrefix(name, fallback) {
  const value = process.env[name] ?? fallback;
  if (!/^[A-Za-z0-9:_-]{1,96}$/.test(value)) {
    throw new Error(`${name} must be a 1-96 character Redis key prefix`);
  }
  return value;
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
    solariApiKey: process.env.SOLARI_API_KEY || undefined,
    solariBrowserBaseUrl: process.env.SOLARI_BROWSER_BASE_URL || undefined,
    solariSandboxBaseUrl: process.env.SOLARI_SANDBOX_BASE_URL ?? 'https://api.getsolari.com',
    solariDemoRetailerBaseUrl: process.env.SOLARI_DEMO_RETAILER_BASE_URL || undefined,
    solariBrowserTimeoutMs: integer('SOLARI_BROWSER_TIMEOUT_MS', 6_000, { min: 1_000, max: 20_000 }),
    solariSandboxTimeoutMs: integer('SOLARI_SANDBOX_TIMEOUT_MS', 10_000, { min: 1_000, max: 20_000 }),
    solariRequestTimeoutMs: integer('SOLARI_REQUEST_TIMEOUT_MS', 45_000, { min: 5_000, max: 120_000 }),
    solariMaxBodyBytes: integer('SOLARI_MAX_BODY_BYTES', 32_768, { min: 4_096, max: 65_536 }),
    solariRateLimitPerMinute: integer('SOLARI_RATE_LIMIT_PER_MINUTE', 5, { max: 30 }),
    solariTrustForwardedFor: boolean('SOLARI_TRUST_FORWARDED_FOR', false),
    solariLiveExecutionEnabled: boolean('SOLARI_LIVE_EXECUTION_ENABLED', false),
    solariOperatorToken: process.env.SOLARI_OPERATOR_TOKEN || undefined,
    solariRetailerResearchAuthorized: boolean('SOLARI_RETAILER_RESEARCH_AUTHORIZED', false),
    solariWalmartWrittenAuthorizationReference: process.env.SOLARI_WALMART_WRITTEN_AUTHORIZATION_REFERENCE || undefined,
    solariBetaEnabled: boolean('SOLARI_BETA_ENABLED', false),
    solariDevelopmentLaneEnabled: boolean('SOLARI_DEVELOPMENT_LANE_ENABLED', false),
    solariBetaRedisUrl: process.env.KV_REST_API_URL || undefined,
    solariBetaRedisToken: process.env.KV_REST_API_TOKEN || undefined,
    solariBetaStorePrefix: keyPrefix('SOLARI_BETA_STORE_PREFIX', 'smartcart:solari:beta'),
    solariDevelopmentStorePrefix: keyPrefix('SOLARI_DEVELOPMENT_STORE_PREFIX', 'smartcart:solari:dev'),
    solariBetaRuntimeKey: process.env.SOLARI_BETA_RUNTIME_KEY ?? 'smartcart:solari:beta:runtime-enabled',
    solariAppAttestTeamId: process.env.SOLARI_APP_ATTEST_TEAM_ID || undefined,
    solariAppAttestBundleId: process.env.SOLARI_APP_ATTEST_BUNDLE_ID || undefined,
    solariAppAttestAllowedBuilds: (process.env.SOLARI_APP_ATTEST_ALLOWED_BUILDS ?? '')
      .split(',').map((value) => value.trim()).filter(Boolean),
    solariAppAttestAllowedValidationCategories: integerList(
      'SOLARI_APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES',
      [2],
      { allowedValues: [2, 3, 4] }
    ),
    solariAppAttestResearchPath: '/v1/solari/research',
    solariAppAttestChallengeTtlSeconds: integer('SOLARI_APP_ATTEST_CHALLENGE_TTL_SECONDS', 120, { min: 30, max: 300 }),
    solariBetaPerKeyHourlyLimit: integer('SOLARI_BETA_PER_KEY_HOURLY_LIMIT', 3, { max: 100 }),
    solariBetaPerKeyDailyLimit: integer('SOLARI_BETA_PER_KEY_DAILY_LIMIT', 10, { max: 1_000 }),
    solariBetaGlobalDailyLimit: integer('SOLARI_BETA_GLOBAL_DAILY_LIMIT', 100, { max: 100_000 }),
    solariBetaConcurrencyLimit: integer('SOLARI_BETA_CONCURRENCY_LIMIT', 2, { max: 20 }),
    solariBetaIdempotencyTtlSeconds: integer('SOLARI_BETA_IDEMPOTENCY_TTL_SECONDS', 900, { min: 60, max: 86_400 }),
    solariBetaLeaseTtlSeconds: integer('SOLARI_BETA_LEASE_TTL_SECONDS', 60, { min: 10, max: 180 }),
    solariBetaMaxBodyBytes: integer('SOLARI_BETA_MAX_BODY_BYTES', 65_536, { min: 16_384, max: 131_072 }),
    solariBetaKillPollMs: integer('SOLARI_BETA_KILL_POLL_MS', 1_000, { min: 250, max: 5_000 }),
    solariPublicDemoEnabled: boolean('SOLARI_PUBLIC_DEMO_ENABLED', false),
    solariPublicDemoOrigin: process.env.SOLARI_PUBLIC_DEMO_ORIGIN || undefined,
    solariPublicDemoIpHmacSecret: process.env.SOLARI_PUBLIC_DEMO_IP_HMAC_SECRET || undefined,
    solariPublicDemoStorePrefix: keyPrefix('SOLARI_PUBLIC_DEMO_STORE_PREFIX', 'smartcart:solari:public-demo'),
    solariPublicDemoRuntimeKey: process.env.SOLARI_PUBLIC_DEMO_RUNTIME_KEY
      ?? 'smartcart:solari:public-demo:runtime-enabled',
    solariPublicDemoRuntimeBootstrapEnabled: boolean('SOLARI_PUBLIC_DEMO_RUNTIME_BOOTSTRAP_ENABLED', false),
    solariPublicDemoPerIpDailyLimit: integer('SOLARI_PUBLIC_DEMO_PER_IP_DAILY_LIMIT', 1, { max: 10 }),
    solariPublicDemoGlobalDailyLimit: integer('SOLARI_PUBLIC_DEMO_GLOBAL_DAILY_LIMIT', 25, { max: 10_000 }),
    solariPublicDemoConcurrencyLimit: integer('SOLARI_PUBLIC_DEMO_CONCURRENCY_LIMIT', 1, { max: 5 }),
    solariPublicDemoDailyBudgetUnits: integer('SOLARI_PUBLIC_DEMO_DAILY_BUDGET_UNITS', 25, { max: 10_000 }),
    solariPublicDemoRunBudgetUnits: integer('SOLARI_PUBLIC_DEMO_RUN_BUDGET_UNITS', 1, { max: 100 }),
    solariPublicDemoLeaseTtlSeconds: integer('SOLARI_PUBLIC_DEMO_LEASE_TTL_SECONDS', 60, { min: 10, max: 180 }),
    solariPublicDemoCacheTtlSeconds: integer('SOLARI_PUBLIC_DEMO_CACHE_TTL_SECONDS', 86_400, { min: 60, max: 604_800 }),
    solariPublicDemoKillPollMs: integer('SOLARI_PUBLIC_DEMO_KILL_POLL_MS', 1_000, { min: 250, max: 5_000 }),
    solariPublicDemoMaxBodyBytes: integer('SOLARI_PUBLIC_DEMO_MAX_BODY_BYTES', 512, { min: 128, max: 4_096 }),
    mcpRateLimitPerMinute: integer('MCP_RATE_LIMIT_PER_MINUTE', 60, { max: 1_000 }),
    smartCartHandoffBaseUrl: process.env.SMARTCART_HANDOFF_BASE_URL || undefined,
    smartCartHandoffTtlMs: integer('SMARTCART_HANDOFF_TTL_SECONDS', 600, { min: 60, max: 600 }) * 1_000,
    smartCartHandoffMaxPayloadBytes: integer('SMARTCART_HANDOFF_MAX_PAYLOAD_BYTES', 131_072, {
      min: 1_024,
      max: 262_144
    }),
    smartCartHandoffMaxTokenCharacters: integer('SMARTCART_HANDOFF_MAX_TOKEN_CHARACTERS', 24_000, {
      min: 1_024,
      max: 24_000
    }),
    smartCartHandoffClaimRateLimitPerMinute: integer(
      'SMARTCART_HANDOFF_CLAIM_RATE_LIMIT_PER_MINUTE',
      30,
      { max: 1_000 }
    ),
    smartCartHandoffTokenRateLimitPerMinute: integer(
      'SMARTCART_HANDOFF_TOKEN_RATE_LIMIT_PER_MINUTE',
      6,
      { max: 100 }
    ),
    smartCartHandoffTokenSecret: process.env.HANDOFF_TOKEN_SECRET || undefined,
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
