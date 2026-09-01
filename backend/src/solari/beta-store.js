import { createHash, randomUUID } from 'node:crypto';
import { Redis } from '@upstash/redis';
import { SolariResearchError } from './errors.js';

const PREFIX = 'smartcart:solari:beta';

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function parseRecord(value) {
  if (typeof value !== 'string') return value && typeof value === 'object' ? value : null;
  try { return JSON.parse(value); } catch { return null; }
}

export class UpstashSolariBetaStore {
  constructor({ url, token, redis, prefix = PREFIX } = {}) {
    if (!redis && (!url || !token)) throw new SolariResearchError(
      'solari_beta_store_unavailable',
      'The beta state store is not configured.',
      { status: 503 }
    );
    this.redis = redis ?? new Redis({ url, token });
    this.prefix = prefix;
  }

  key(...parts) { return [this.prefix, ...parts].join(':'); }

  async runtimeEnabled(runtimeKey) {
    return await this.redis.get(runtimeKey) === 'enabled';
  }

  async putChallenge(record, ttlSeconds) {
    const stored = await this.redis.set(this.key('challenge', record.challengeID), JSON.stringify(record), {
      nx: true,
      ex: ttlSeconds
    });
    if (stored !== 'OK') throw new SolariResearchError('challenge_collision', 'Could not issue an App Attest challenge.', { status: 503 });
  }

  async consumeChallenge(challengeID) {
    const value = await this.redis.getdel(this.key('challenge', challengeID));
    return parseRecord(value);
  }

  async putAttestedKey(keyIDHash, record) {
    const script = `
if redis.call('EXISTS',KEYS[1]) ~= 0 or redis.call('EXISTS',KEYS[2]) ~= 0 then return 0 end
redis.call('SET',KEYS[1],ARGV[1]); redis.call('SET',KEYS[2],'0'); return 1`;
    const stored = Number(await this.redis.eval(script, [
      this.key('attested-key', keyIDHash), this.key('counter', keyIDHash)
    ], [JSON.stringify(record)]));
    if (stored !== 1) throw new SolariResearchError('app_attest_key_already_registered', 'This App Attest key is already registered.', { status: 409 });
  }

  async getAttestedKey(keyIDHash) {
    return parseRecord(await this.redis.get(this.key('attested-key', keyIDHash)));
  }

  async getCounter(keyIDHash) {
    const value = await this.redis.get(this.key('counter', keyIDHash));
    const counter = Number(value);
    return Number.isSafeInteger(counter) && counter >= 0 ? counter : null;
  }

  async advanceCounter(keyIDHash, expected, next) {
    const script = `
local current = redis.call('GET', KEYS[1])
if not current or tonumber(current) ~= tonumber(ARGV[1]) then return 0 end
if tonumber(ARGV[2]) <= tonumber(current) then return 0 end
redis.call('SET', KEYS[1], ARGV[2])
return 1`;
    return Number(await this.redis.eval(script, [this.key('counter', keyIDHash)], [expected, next])) === 1;
  }

  async reserveIdempotency(keyIDHash, requestID, payloadDigest, owner, ttlSeconds) {
    const key = this.key('idempotency', keyIDHash, digest(requestID));
    const script = `
if redis.call('EXISTS', KEYS[1]) == 0 then
  redis.call('HSET', KEYS[1], 'digest', ARGV[1], 'state', 'pending', 'owner', ARGV[2])
  redis.call('EXPIRE', KEYS[1], ARGV[3])
  return {'reserved'}
end
local d=redis.call('HGET',KEYS[1],'digest')
if d ~= ARGV[1] then return {'conflict'} end
local s=redis.call('HGET',KEYS[1],'state')
if s == 'complete' then return {'complete',redis.call('HGET',KEYS[1],'result')} end
return {'pending'}`;
    const result = await this.redis.eval(script, [key], [payloadDigest, owner, ttlSeconds]);
    return { status: result?.[0], result: parseRecord(result?.[1]) };
  }

  async completeIdempotency(keyIDHash, requestID, owner, result, ttlSeconds) {
    const key = this.key('idempotency', keyIDHash, digest(requestID));
    const script = `
if redis.call('HGET',KEYS[1],'owner') ~= ARGV[1] then return 0 end
redis.call('HSET',KEYS[1],'state','complete','result',ARGV[2])
redis.call('HDEL',KEYS[1],'owner')
redis.call('EXPIRE',KEYS[1],ARGV[3])
return 1`;
    return Number(await this.redis.eval(script, [key], [owner, JSON.stringify(result), ttlSeconds])) === 1;
  }

  async abandonIdempotency(keyIDHash, requestID, owner) {
    const key = this.key('idempotency', keyIDHash, digest(requestID));
    const script = `if redis.call('HGET',KEYS[1],'owner') == ARGV[1] then return redis.call('DEL',KEYS[1]) end return 0`;
    await this.redis.eval(script, [key], [owner]);
  }

  async admit({ keyIDHash, now, hourlyLimit, dailyLimit, globalDailyLimit, concurrencyLimit, leaseTtlSeconds }) {
    const hour = new Date(now).toISOString().slice(0, 13);
    const day = new Date(now).toISOString().slice(0, 10);
    const leaseID = randomUUID();
    const keys = [
      this.key('quota-hour', keyIDHash, hour),
      this.key('quota-day', keyIDHash, day),
      this.key('quota-global', day),
      this.key('leases')
    ];
    const script = `
redis.call('ZREMRANGEBYSCORE',KEYS[4],'-inf',ARGV[5])
if tonumber(redis.call('GET',KEYS[1]) or '0') >= tonumber(ARGV[1]) then return {'hourly'} end
if tonumber(redis.call('GET',KEYS[2]) or '0') >= tonumber(ARGV[2]) then return {'daily'} end
if tonumber(redis.call('GET',KEYS[3]) or '0') >= tonumber(ARGV[3]) then return {'global'} end
if tonumber(redis.call('ZCARD',KEYS[4])) >= tonumber(ARGV[4]) then return {'concurrency'} end
redis.call('INCR',KEYS[1]); redis.call('EXPIRE',KEYS[1],7200)
redis.call('INCR',KEYS[2]); redis.call('EXPIRE',KEYS[2],172800)
redis.call('INCR',KEYS[3]); redis.call('EXPIRE',KEYS[3],172800)
redis.call('ZADD',KEYS[4],ARGV[6],ARGV[7]); redis.call('EXPIRE',KEYS[4],ARGV[8])
return {'allowed',ARGV[7]}`;
    const result = await this.redis.eval(script, keys, [
      hourlyLimit, dailyLimit, globalDailyLimit, concurrencyLimit, now,
      now + leaseTtlSeconds * 1000, leaseID, leaseTtlSeconds * 2
    ]);
    return { allowed: result?.[0] === 'allowed', reason: result?.[0], leaseID: result?.[1] };
  }

  async release(leaseID) {
    if (leaseID) await this.redis.zrem(this.key('leases'), leaseID);
  }
}

// This implementation is deliberately injectable and intended only for unit tests.
export class InMemorySolariBetaStore {
  constructor({ now = Date.now, runtimeEnabled = true } = {}) {
    this.now = now;
    this.enabled = runtimeEnabled;
    this.challenges = new Map(); this.keys = new Map(); this.counters = new Map();
    this.idempotency = new Map(); this.leases = new Map(); this.quotas = new Map();
  }
  async runtimeEnabled() { return this.enabled; }
  async putChallenge(record, ttlSeconds) { this.challenges.set(record.challengeID, { record, expiresAt: this.now() + ttlSeconds * 1000 }); }
  async consumeChallenge(id) { const item = this.challenges.get(id); this.challenges.delete(id); return item && item.expiresAt >= this.now() ? item.record : null; }
  async putAttestedKey(hash, record) { if (this.keys.has(hash)) throw new SolariResearchError('app_attest_key_already_registered','This App Attest key is already registered.',{status:409}); this.keys.set(hash, record); this.counters.set(hash, 0); }
  async getAttestedKey(hash) { return this.keys.get(hash) ?? null; }
  async getCounter(hash) { return this.counters.has(hash) ? this.counters.get(hash) : null; }
  async advanceCounter(hash, expected, next) { if (this.counters.get(hash) !== expected || next <= expected) return false; this.counters.set(hash, next); return true; }
  async reserveIdempotency(hash, id, bodyDigest, owner) { const key=`${hash}:${id}`; const item=this.idempotency.get(key); if (!item) { this.idempotency.set(key,{digest:bodyDigest,state:'pending',owner}); return {status:'reserved'}; } if(item.digest!==bodyDigest)return{status:'conflict'}; return item.state==='complete'?{status:'complete',result:item.result}:{status:'pending'}; }
  async completeIdempotency(hash,id,owner,result){const key=`${hash}:${id}`;const item=this.idempotency.get(key);if(!item||item.owner!==owner)return false;this.idempotency.set(key,{...item,state:'complete',result});return true;}
  async abandonIdempotency(hash,id,owner){const key=`${hash}:${id}`;if(this.idempotency.get(key)?.owner===owner)this.idempotency.delete(key);}
  async admit({keyIDHash,now,hourlyLimit,dailyLimit,globalDailyLimit,concurrencyLimit,leaseTtlSeconds}){for(const[id,expiry]of this.leases)if(expiry<=now)this.leases.delete(id);const hour=new Date(now).toISOString().slice(0,13),day=new Date(now).toISOString().slice(0,10);const names=[[`h:${keyIDHash}:${hour}`,hourlyLimit,'hourly'],[`d:${keyIDHash}:${day}`,dailyLimit,'daily'],[`g:${day}`,globalDailyLimit,'global']];for(const[name,limit,reason]of names)if((this.quotas.get(name)??0)>=limit)return{allowed:false,reason};if(this.leases.size>=concurrencyLimit)return{allowed:false,reason:'concurrency'};for(const[name]of names)this.quotas.set(name,(this.quotas.get(name)??0)+1);const leaseID=randomUUID();this.leases.set(leaseID,now+leaseTtlSeconds*1000);return{allowed:true,reason:'allowed',leaseID};}
  async release(id){this.leases.delete(id);}
}

export function keyIDHash(keyID) { return digest(Buffer.from(keyID, 'base64')); }
