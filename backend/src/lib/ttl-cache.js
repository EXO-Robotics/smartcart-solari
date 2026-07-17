export class TtlCache {
  #entries = new Map();
  #defaultTtlMs;
  #now;

  constructor({ defaultTtlMs = 300_000, now = Date.now } = {}) {
    this.#defaultTtlMs = defaultTtlMs;
    this.#now = now;
  }

  set(key, value, ttlMs = this.#defaultTtlMs) {
    if (!Number.isFinite(ttlMs) || ttlMs <= 0) throw new TypeError('ttlMs must be positive');
    this.#entries.set(key, { value, expiresAt: this.#now() + ttlMs });
    return value;
  }

  get(key) {
    const entry = this.#entries.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt <= this.#now()) {
      this.#entries.delete(key);
      return undefined;
    }
    return entry.value;
  }

  has(key) {
    return this.get(key) !== undefined;
  }

  delete(key) {
    return this.#entries.delete(key);
  }

  sweep() {
    const before = this.#entries.size;
    for (const key of this.#entries.keys()) this.get(key);
    return before - this.#entries.size;
  }

  get size() {
    this.sweep();
    return this.#entries.size;
  }
}
