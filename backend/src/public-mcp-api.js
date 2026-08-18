import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { loadConfig } from './config.js';
import { HttpError, readJson, validatePreparsedJsonBody } from './lib/http.js';
import { FixedWindowRateLimiter } from './lib/rate-limiter.js';
import { createSmartCartMcpServer } from './mcp/server.js';
import { SmartCartPluginService } from './mcp/smartcart-plugin-service.js';

function jsonRpcError(response, status, message, headers = {}) {
  const body = JSON.stringify({
    jsonrpc: '2.0',
    error: { code: -32000, message },
    id: null
  });
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...headers
  });
  response.end(body);
}

export function createPublicMcpApi(options = {}) {
  const config = loadConfig(options.config);
  const createServer = options.createServer ?? (() => {
    const pluginService = options.pluginService ?? new SmartCartPluginService({ ...options, config });
    return () => createSmartCartMcpServer({ ...options, pluginService });
  })();
  const limiter = options.limiter ?? new FixedWindowRateLimiter({
    limit: config.mcpRateLimitPerMinute,
    windowMs: 60_000,
    now: options.now ?? Date.now
  });

  async function handler(request, response) {
    const url = new URL(request.url ?? '/', 'https://smartcart.invalid');
    const routed = url.pathname === '/mcp'
      || (
        ['/api/mcp.js', '/api/mcp'].includes(url.pathname)
        && url.searchParams.get('route') === 'mcp'
      );
    if (!routed || request.method !== 'POST') {
      jsonRpcError(response, 405, 'Method not allowed. Use POST /mcp.');
      return;
    }

    const rate = limiter.consume('mcp');
    const rateHeaders = {
      'x-rate-limit-limit': String(rate.limit),
      'x-rate-limit-remaining': String(rate.remaining),
      'x-rate-limit-reset': String(Math.ceil(rate.resetAt / 1_000))
    };
    if (!rate.allowed) {
      jsonRpcError(
        response,
        429,
        'SmartCart MCP request limit exceeded.',
        { ...rateHeaders, 'retry-after': String(rate.retryAfterSeconds) }
      );
      return;
    }

    let body = request.body;
    try {
      body = body && typeof body === 'object'
        ? validatePreparsedJsonBody(request, body, config.maxBodyBytes)
        : await readJson(request, config.maxBodyBytes);
    } catch (error) {
      jsonRpcError(
        response,
        error instanceof HttpError ? error.status : 400,
        error instanceof HttpError ? error.message : 'Invalid JSON-RPC request.'
      );
      return;
    }

    const server = createServer();
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true
    });
    try {
      await server.connect(transport);
      response.setHeader('x-rate-limit-limit', rateHeaders['x-rate-limit-limit']);
      response.setHeader('x-rate-limit-remaining', rateHeaders['x-rate-limit-remaining']);
      response.setHeader('x-rate-limit-reset', rateHeaders['x-rate-limit-reset']);
      await transport.handleRequest(request, response, body);
    } catch {
      if (!response.headersSent) jsonRpcError(response, 500, 'Internal MCP error.');
    } finally {
      await transport.close();
      await server.close();
    }
  }

  return { handler, config };
}
