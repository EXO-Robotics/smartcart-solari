import { SolariResearchError } from './errors.js';

export function timeoutWithinDeadline(configuredTimeoutMs, deadlineAt, clock = Date.now) {
  if (!Number.isFinite(deadlineAt)) return configuredTimeoutMs;
  const remaining = Math.floor(deadlineAt - clock());
  if (remaining <= 0) {
    throw new SolariResearchError(
      'solari_request_timeout',
      'The bounded Solari research deadline expired.',
      { status: 504, retryable: true }
    );
  }
  return Math.max(1, Math.min(configuredTimeoutMs, remaining));
}
