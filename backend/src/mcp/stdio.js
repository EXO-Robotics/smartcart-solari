#!/usr/bin/env node
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createSmartCartMcpServer } from './server.js';

async function main() {
  const server = createSmartCartMcpServer();
  await server.connect(new StdioServerTransport());
  console.error('SmartCart Trip Intelligence MCP server ready on stdio.');
}

main().catch((error) => {
  console.error('SmartCart MCP server failed:', error);
  process.exitCode = 1;
});
