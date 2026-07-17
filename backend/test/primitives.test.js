import assert from 'node:assert/strict';
import test from 'node:test';
import { createLogger, redact } from '../src/lib/logger.js';
import { TtlCache } from '../src/lib/ttl-cache.js';

test('TTL cache expires values and sweeps expired entries', () => {
  let time = 1_000;
  const cache = new TtlCache({ defaultTtlMs: 50, now: () => time });
  cache.set('manifest', { id: 'demo' });
  assert.deepEqual(cache.get('manifest'), { id: 'demo' });
  time = 1_051;
  assert.equal(cache.get('manifest'), undefined);
  assert.equal(cache.size, 0);
});

test('structured logger redacts credentials and direct identifiers', () => {
  const lines = [];
  const logger = createLogger({ sink: (line) => lines.push(line), now: () => new Date(0) });
  logger.info('redaction_test', {
    authorization: 'Bearer super-secret-token',
    nested: { email: 'shopper@example.local', harmless: 'visible' },
    message: 'received Bearer abc.def.ghi'
  });
  const record = JSON.parse(lines[0]);
  assert.equal(record.authorization, '[REDACTED]');
  assert.equal(record.nested.email, '[REDACTED]');
  assert.equal(record.nested.harmless, 'visible');
  assert.equal(record.message, 'received Bearer [REDACTED]');
  assert.equal(record.dataMode, 'local-demo');
  assert.deepEqual(redact({ password: 'never-log-me' }), { password: '[REDACTED]' });
  assert.deepEqual(redact({ apiKey: 'instacart-secret' }), { apiKey: '[REDACTED]' });
});
