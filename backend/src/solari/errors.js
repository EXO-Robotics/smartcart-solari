export class SolariResearchError extends Error {
  constructor(code, message, { status = 503, retryable = false, details } = {}) {
    super(message);
    this.name = 'SolariResearchError';
    this.code = code;
    this.status = status;
    this.retryable = retryable;
    this.details = details;
  }
}
