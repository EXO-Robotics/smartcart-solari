export class FixedWindowRateLimiter {
  #buckets = new Map();
  #limit;
  #windowMs;
  #now;

  constructor({ limit = 120, windowMs = 60_000, now = Date.now } = {}) {
    this.#limit = limit;
    this.#windowMs = windowMs;
    this.#now = now;
  }

  consume(key) {
    const now = this.#now();
    let bucket = this.#buckets.get(key);
    if (!bucket || bucket.resetAt <= now) {
      bucket = { count: 0, resetAt: now + this.#windowMs };
      this.#buckets.set(key, bucket);
    }
    bucket.count += 1;
    return {
      allowed: bucket.count <= this.#limit,
      limit: this.#limit,
      remaining: Math.max(0, this.#limit - bucket.count),
      resetAt: bucket.resetAt,
      retryAfterSeconds: Math.max(1, Math.ceil((bucket.resetAt - now) / 1_000))
    };
  }
}
