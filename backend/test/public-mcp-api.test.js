import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { once } from 'node:events';
import { createServer } from 'node:http';
import test from 'node:test';
import { createSmartCartMcpServer } from '../src/mcp/server.js';
import { createPublicMcpApi } from '../src/public-mcp-api.js';

async function listen(pluginService, options = {}) {
  const { handler } = createPublicMcpApi({
    createServer: () => createSmartCartMcpServer({ pluginService }),
    config: { host: '127.0.0.1', port: 0, ...(options.config ?? {}) },
    limiter: options.limiter
  });
  const httpServer = createServer(handler);
  httpServer.listen(0, '127.0.0.1');
  await once(httpServer, 'listening');
  const address = httpServer.address();
  return {
    url: new URL(`http://127.0.0.1:${address.port}/mcp`),
    async close() {
      httpServer.close();
      await once(httpServer, 'close');
    }
  };
}

test('stateless Streamable HTTP MCP lists and invokes SmartCart tools', async () => {
  const service = await listen({
    analyzeRecipe({ title }) {
      return { schemaVersion: '1.0', data: { title, ingredients: [] } };
    }
  });
  const client = new Client({ name: 'smartcart-http-test', version: '1.0.0' });
  try {
    await client.connect(new StreamableHTTPClientTransport(service.url));
    const tools = await client.listTools();
    assert.equal(tools.tools.length, 5);
    const result = await client.callTool({
      name: 'analyze_recipe',
      arguments: { recipe_text: '1 lb chicken', title: 'HTTP test', servings: 2 }
    });
    assert.equal(result.isError, undefined);
    assert.equal(result.structuredContent.operation, 'analyze_recipe');
    assert.equal(result.structuredContent.analysis.data.title, 'HTTP test');
  } finally {
    await client.close();
    await service.close();
  }
});

test('MCP endpoint rejects non-POST methods', async () => {
  const service = await listen({});
  try {
    const response = await fetch(service.url);
    assert.equal(response.status, 405);
    const payload = await response.json();
    assert.equal(payload.jsonrpc, '2.0');
    assert.equal(payload.error.message, 'Method not allowed. Use POST /mcp.');
  } finally {
    await service.close();
  }
});

test('MCP endpoint emits JSON-RPC 429 before starting a tool server', async () => {
  let servers = 0;
  const { handler } = createPublicMcpApi({
    createServer() { servers += 1; return createSmartCartMcpServer({ pluginService: {} }); },
    limiter: {
      consume() {
        return { allowed: false, limit: 1, remaining: 0, resetAt: 60_000, retryAfterSeconds: 60 };
      }
    },
    config: { host: '127.0.0.1', port: 0 }
  });
  const httpServer = createServer(handler);
  httpServer.listen(0, '127.0.0.1');
  await once(httpServer, 'listening');
  const address = httpServer.address();
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}/mcp`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}'
    });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get('retry-after'), '60');
    assert.equal(response.headers.get('x-rate-limit-remaining'), '0');
    const payload = await response.json();
    assert.equal(payload.jsonrpc, '2.0');
    assert.equal(payload.error.message, 'SmartCart MCP request limit exceeded.');
    assert.equal(servers, 0);
  } finally {
    httpServer.close();
    await once(httpServer, 'close');
  }
});

test('MCP endpoint rejects an oversized body pre-parsed by the Vercel runtime', async () => {
  let servers = 0;
  const { handler } = createPublicMcpApi({
    createServer() { servers += 1; return createSmartCartMcpServer({ pluginService: {} }); },
    config: { host: '127.0.0.1', port: 0, maxBodyBytes: 128 }
  });
  const httpServer = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    request.body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    await handler(request, response);
  });
  httpServer.listen(0, '127.0.0.1');
  await once(httpServer, 'listening');
  const address = httpServer.address();
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}/mcp`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, padding: 'x'.repeat(512) })
    });
    assert.equal(response.status, 413);
    const payload = await response.json();
    assert.equal(payload.error.message, 'JSON body is too large');
    assert.equal(servers, 0);
  } finally {
    httpServer.close();
    await once(httpServer, 'close');
  }
});
