const REDACTED = '[REDACTED]';
const SENSITIVE_KEY = /authorization|cookie|token|secret|password|email|code|verifier|challenge|credential|api[-_]?key/i;
const BEARER = /Bearer\s+[A-Za-z0-9._~+/=-]+/gi;

export function redact(value, seen = new WeakSet()) {
  if (typeof value === 'string') return value.replace(BEARER, 'Bearer [REDACTED]');
  if (value === null || typeof value !== 'object') return value;
  if (value instanceof Error) {
    return {
      name: value.name,
      message: redact(value.message, seen),
      ...(value.stack ? { stack: redact(value.stack, seen) } : {})
    };
  }
  if (seen.has(value)) return '[CIRCULAR]';
  seen.add(value);

  if (Array.isArray(value)) return value.map((entry) => redact(entry, seen));
  return Object.fromEntries(
    Object.entries(value).map(([key, entry]) => [
      key,
      SENSITIVE_KEY.test(key) ? REDACTED : redact(entry, seen)
    ])
  );
}

export function createLogger({ level = 'info', sink = console.log, now = () => new Date() } = {}) {
  const priorities = { debug: 10, info: 20, warn: 30, error: 40, silent: 100 };
  const threshold = priorities[level] ?? priorities.info;

  function write(logLevel, message, context = {}) {
    if (priorities[logLevel] < threshold) return;
    sink(
      JSON.stringify({
        timestamp: now().toISOString(),
        level: logLevel,
        message,
        ...redact(context),
        dataMode: 'local-demo'
      })
    );
  }

  return {
    debug: (message, context) => write('debug', message, context),
    info: (message, context) => write('info', message, context),
    warn: (message, context) => write('warn', message, context),
    error: (message, context) => write('error', message, context)
  };
}
