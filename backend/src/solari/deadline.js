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

function abortedError() {
  return new SolariResearchError(
    'solari_request_aborted',
    'The bounded Solari research request was cancelled.',
    { status: 408, retryable: true }
  );
}

export async function runWithinDeadline(
  operation,
  { configuredTimeoutMs, deadlineAt, clock = Date.now, signal } = {}
) {
  if (signal?.aborted) throw abortedError();
  const timeoutMs = timeoutWithinDeadline(configuredTimeoutMs, deadlineAt, clock);
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);
      callback(value);
    };
    const onAbort = () => finish(reject, abortedError());
    const timer = setTimeout(() => finish(reject, new SolariResearchError(
      'solari_request_timeout',
      'The bounded Solari research deadline expired.',
      { status: 504, retryable: true }
    )), timeoutMs);
    signal?.addEventListener('abort', onAbort, { once: true });
    if (signal?.aborted) {
      onAbort();
      return;
    }
    Promise.resolve()
      .then(operation)
      .then((value) => finish(resolve, value), (error) => finish(reject, error));
  });
}
