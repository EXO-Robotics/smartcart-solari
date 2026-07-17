import { createServer } from './app.js';
import { createLogger } from './lib/logger.js';
import { loadConfig } from './config.js';

const config = loadConfig();
const logger = createLogger({ level: config.logLevel });
const { server } = createServer({ config, logger });

server.on('error', (error) => {
  logger.error('server_error', { error });
  process.exitCode = 1;
});

server.listen(config.port, config.host, () => {
  logger.info('server_started', {
    host: config.host,
    port: config.port,
    disclosure: config.instacartDemoHandoffUrl
      ? 'Local/demo service with an explicit non-live Instacart demo handoff URL.'
      : config.instacartApiKey
        ? 'Local/demo auth and persistence with a configured server-side Instacart handoff provider.'
        : 'Credential-free local/demo service. Instacart handoff is unavailable until explicitly configured.'
  });
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    logger.info('server_stopping', { signal });
    server.close(() => process.exit(0));
  });
}
