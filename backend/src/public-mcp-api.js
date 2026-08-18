import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { loadConfig } from './config.js';
import { HttpError, readJson } from './lib/http.js';
import { createSmartCartMcpServer } from './mcp/server.js';

function jsonRpcError(response, status, message) {
  const body = JSON.stringify({
    jsonrpc: '2.0',
    error: { code: -32000, message },
    id: null
  });
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  });
  response.end(body);
}

export function createPublicMcpApi(options = {}) {
  const config = loadConfig(options.config);
  const createServer = options.createServer ?? (() => createSmartCartMcpServer(options));

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

    let body = request.body;
    try {
      if (!body || typeof body !== 'object') body = await readJson(request, config.maxBodyBytes);
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
