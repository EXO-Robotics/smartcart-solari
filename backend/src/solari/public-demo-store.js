import { randomUUID } from 'node:crypto';
import { Redis } from '@upstash/redis';
import { SolariResearchError } from './errors.js';

function parseRecord(value) {
  if (typeof value !== 'string') return value && typeof value === 'object' ? value : null;
  try { return JSON.parse(value); } catch { return null; }
}

export class UpstashSolariPublicDemoStore {
  constructor({ url, token, redis, prefix = 'smartcart:solari:public-demo' } = {}) {
    if (!redis && (!url || !token)) {
      throw new SolariResearchError(
        'solari_public_demo_store_unavailable',
        'The public demo state store is not configured.',
        { status: 503 }
      );
    }
    this.redis = redis ?? new Redis({ url, token });
    this.prefix = prefix;
  }

  key(...parts) { return [this.prefix, ...parts].join(':'); }

  async runtimeEnabled(runtimeKey) {
    return await this.redis.get(runtimeKey) === 'enabled';
  }

  async admit({ visitorHash, now, perIpDailyLimit, globalDailyLimit, concurrencyLimit, dailyBudgetUnits, runBudgetUnits, leaseTtlSeconds }) {
    const day = new Date(now).toISOString().slice(0, 10);
    const leaseID = randomUUID();
    const keys = [
      this.key('quota-visitor-day', visitorHash, day),
      this.key('quota-global-day', day),
      this.key('budget-day', day),
      this.key('leases')
    ];
    const script = `
redis.call('ZREMRANGEBYSCORE',KEYS[4],'-inf',ARGV[6])
if tonumber(redis.call('GET',KEYS[1]) or '0') >= tonumber(ARGV[1]) then return {'visitor-daily'} end
if tonumber(redis.call('GET',KEYS[2]) or '0') >= tonumber(ARGV[2]) then return {'global-daily'} end
if tonumber(redis.call('GET',KEYS[3]) or '0') + tonumber(ARGV[5]) > tonumber(ARGV[4]) then return {'budget'} end
if tonumber(redis.call('ZCARD',KEYS[4])) >= tonumber(ARGV[3]) then return {'concurrency'} end
redis.call('INCR',KEYS[1]); redis.call('EXPIRE',KEYS[1],172800)
redis.call('INCR',KEYS[2]); redis.call('EXPIRE',KEYS[2],172800)
redis.call('INCRBY',KEYS[3],ARGV[5]); redis.call('EXPIRE',KEYS[3],172800)
redis.call('ZADD',KEYS[4],ARGV[7],ARGV[8]); redis.call('EXPIRE',KEYS[4],ARGV[9])
return {'allowed',ARGV[8]}`;
    const result = await this.redis.eval(script, keys, [
      perIpDailyLimit,
      globalDailyLimit,
      concurrencyLimit,
      dailyBudgetUnits,
      runBudgetUnits,
      now,
      now + leaseTtlSeconds * 1_000,
      leaseID,
      leaseTtlSeconds * 2
    ]);
    return { allowed: result?.[0] === 'allowed', reason: result?.[0], leaseID: result?.[1] };
  }

  async release(leaseID) {
    if (leaseID) await this.redis.zrem(this.key('leases'), leaseID);
  }

  async getCachedResult() {
    return parseRecord(await this.redis.get(this.key('last-verified-result')));
  }

  async putCachedResult(record, ttlSeconds) {
    const stored = await this.redis.set(
      this.key('last-verified-result'),
      JSON.stringify(record),
      { ex: ttlSeconds }
    );
    if (stored !== 'OK') {
      throw new SolariResearchError(
        'solari_public_demo_cache_unavailable',
        'The verified public demo result could not be cached.',
        { status: 503, retryable: true }
      );
    }
  }
}

// Injectable deterministic store for route and admission-policy tests only.
export class InMemorySolariPublicDemoStore {
  constructor({ now = Date.now, runtimeEnabled = true } = {}) {
    this.now = now;
    this.enabled = runtimeEnabled;
    this.quotas = new Map();
    this.leases = new Map();
    this.cached = null;
  }

  async runtimeEnabled() { return this.enabled; }

  async admit({ visitorHash, now, perIpDailyLimit, globalDailyLimit, concurrencyLimit, dailyBudgetUnits, runBudgetUnits, leaseTtlSeconds }) {
    for (const [id, expiresAt] of this.leases) if (expiresAt <= now) this.leases.delete(id);
    const day = new Date(now).toISOString().slice(0, 10);
    const visitorKey = `visitor:${visitorHash}:${day}`;
    const globalKey = `global:${day}`;
    const budgetKey = `budget:${day}`;
    if ((this.quotas.get(visitorKey) ?? 0) >= perIpDailyLimit) return { allowed: false, reason: 'visitor-daily' };
    if ((this.quotas.get(globalKey) ?? 0) >= globalDailyLimit) return { allowed: false, reason: 'global-daily' };
    if ((this.quotas.get(budgetKey) ?? 0) + runBudgetUnits > dailyBudgetUnits) return { allowed: false, reason: 'budget' };
    if (this.leases.size >= concurrencyLimit) return { allowed: false, reason: 'concurrency' };
    this.quotas.set(visitorKey, (this.quotas.get(visitorKey) ?? 0) + 1);
    this.quotas.set(globalKey, (this.quotas.get(globalKey) ?? 0) + 1);
    this.quotas.set(budgetKey, (this.quotas.get(budgetKey) ?? 0) + runBudgetUnits);
    const leaseID = randomUUID();
    this.leases.set(leaseID, now + leaseTtlSeconds * 1_000);
    return { allowed: true, reason: 'allowed', leaseID };
  }

  async release(leaseID) { this.leases.delete(leaseID); }
  async getCachedResult() { return this.cached ? structuredClone(this.cached) : null; }
  async putCachedResult(record) { this.cached = structuredClone(record); }
}
