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
    disclosure: 'Credential-free local/demo service. No live auth, persistence, catalog, or affiliate integration.'
  });
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    logger.info('server_stopping', { signal });
    server.close(() => process.exit(0));
  });
}
