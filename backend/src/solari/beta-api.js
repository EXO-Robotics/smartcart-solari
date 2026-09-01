import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { ContractValidationError, createContractValidator } from '../contracts/contract-validator.js';
import { AppleAppAttestVerifier, appAttestEncoding } from './app-attest-verifier.js';
import { keyIDHash, UpstashSolariBetaStore } from './beta-store.js';
import {
  createSolariBetaResearchService,
  V2_ATTESTATION_REQUEST_SCHEMA_ID,
  V2_CHALLENGE_REQUEST_SCHEMA_ID,
  V2_ENVELOPE_SCHEMA_ID,
  V2_REQUEST_SCHEMA_ID
} from './beta-research-service.js';
import { SolariResearchError } from './errors.js';

function payloadBytes(value,maxBytes){const bytes=appAttestEncoding.strictBase64(value,maxBytes,'payloadBase64');try{const parsed=JSON.parse(bytes.toString('utf8'));if(!parsed||typeof parsed!=='object'||Array.isArray(parsed))throw new Error();return{bytes,parsed};}catch{throw new SolariResearchError('invalid_v2_payload','payloadBase64 must contain one UTF-8 JSON object.',{status:400});}}
function requireBetaConfig(config,{injectedStore=false}={}){
  if(config.solariBetaEnabled!==true)throw new SolariResearchError('solari_beta_disabled','The private Solari beta is disabled.',{status:503});
  if(!injectedStore&&(!config.solariBetaRedisUrl||!config.solariBetaRedisToken))throw new SolariResearchError('solari_beta_store_unavailable','The beta state store is not configured.',{status:503});
}

export function createSolariBetaApi(options={}){
  const config=options.config??{},now=options.now??Date.now,validatorPromise=options.validator?Promise.resolve(options.validator):createContractValidator();
  let store=options.store??null,verifier=options.verifier??null;
  const research=options.researchService??createSolariBetaResearchService({...options,config});
  function getStore(){requireBetaConfig(config,{injectedStore:Boolean(store)});store??=new UpstashSolariBetaStore({url:config.solariBetaRedisUrl,token:config.solariBetaRedisToken});return store;}
  function getVerifier(){verifier??=new AppleAppAttestVerifier({teamID:config.solariAppAttestTeamId,bundleID:config.solariAppAttestBundleId,allowedBuilds:config.solariAppAttestAllowedBuilds,now});return verifier;}
  async function assertRuntimeEnabled(){if(!await getStore().runtimeEnabled(config.solariBetaRuntimeKey))throw new SolariResearchError('solari_beta_killed','Solari beta live execution is disabled by the runtime switch.',{status:503});}
  async function challenge(payload){
    await assertRuntimeEnabled();const validator=await validatorPromise;validator.assert(V2_CHALLENGE_REQUEST_SCHEMA_ID,payload);
    const keyBytes=appAttestEncoding.strictBase64(payload.keyID,64,'keyID');if(keyBytes.length!==32)throw new SolariResearchError('app_attest_malformed','keyID must decode to 32 bytes.',{status:400});
    const challengeID=randomUUID(),challenge=randomBytes(32).toString('base64url'),issuedAt=now(),expiresAt=issuedAt+config.solariAppAttestChallengeTtlSeconds*1000;
    await getStore().putChallenge({challengeID,challenge,operation:payload.operation,keyIDHash:keyIDHash(payload.keyID),issuedAt,expiresAt},config.solariAppAttestChallengeTtlSeconds);
    return{status:201,payload:{schemaVersion:'solari-app-attest-challenge-result-v1',challengeID,challenge,expiresAt:new Date(expiresAt).toISOString()}};
  }
  async function attestation(payload){
    await assertRuntimeEnabled();const validator=await validatorPromise;validator.assert(V2_ATTESTATION_REQUEST_SCHEMA_ID,payload);
    const hash=keyIDHash(payload.keyID),challenge=await getStore().consumeChallenge(payload.challengeID);
    if(!challenge||challenge.operation!=='attest'||challenge.keyIDHash!==hash||challenge.expiresAt<now())throw new SolariResearchError('app_attest_challenge_invalid','The App Attest challenge is absent, expired, mismatched, or already consumed.',{status:403});
    const record=await getVerifier().verifyAttestation({...payload,challenge:challenge.challenge});
    await getStore().putAttestedKey(hash,{...record,keyIDHash:hash,createdAt:new Date(now()).toISOString(),revokedAt:null});
    return{status:201,payload:{schemaVersion:'solari-app-attestation-result-v1',keyID:payload.keyID,status:'accepted'}};
  }
  async function researchEnvelope(envelope,{signal}={}){
    await assertRuntimeEnabled();const validator=await validatorPromise;validator.assert(V2_ENVELOPE_SCHEMA_ID,envelope);
    const decoded=payloadBytes(envelope.payloadBase64,config.solariMaxBodyBytes);validator.assert(V2_REQUEST_SCHEMA_ID,decoded.parsed);
    const hash=keyIDHash(envelope.keyID),challenge=await getStore().consumeChallenge(envelope.challengeID);
    if(!challenge||challenge.operation!=='research'||challenge.keyIDHash!==hash||challenge.expiresAt<now())throw new SolariResearchError('app_attest_challenge_invalid','The App Attest challenge is absent, expired, mismatched, or already consumed.',{status:403});
    const keyRecord=await getStore().getAttestedKey(hash);if(!keyRecord||keyRecord.revokedAt)throw new SolariResearchError('app_attest_key_unknown','The App Attest key is unknown or revoked.',{status:403});
    const current=await getStore().getCounter(hash);if(current===null)throw new SolariResearchError('app_attest_key_unknown','The App Attest counter is unavailable.',{status:403});
    const assertion=getVerifier().verifyAssertion({assertionObject:envelope.assertionObject,challenge:challenge.challenge,payloadBytes:decoded.bytes,keyRecord});
    if(assertion.counter<=current||!await getStore().advanceCounter(hash,current,assertion.counter))throw new SolariResearchError('app_attest_replay','The App Attest assertion counter was replayed.',{status:409});
    const owner=randomUUID(),idem=await getStore().reserveIdempotency(hash,decoded.parsed.requestID,assertion.bodyDigest,owner,config.solariBetaIdempotencyTtlSeconds);
    if(idem.status==='conflict')throw new SolariResearchError('idempotency_conflict','requestID was already used with different payload bytes.',{status:409});
    if(idem.status==='pending')throw new SolariResearchError('request_in_progress','The same request is already running.',{status:409,retryable:true});
    if(idem.status==='complete')return{status:200,payload:idem.result,headers:{'x-smartcart-idempotency':'replay'}};
    let leaseID,complete=false;
    try{
      const admission=await getStore().admit({keyIDHash:hash,now:now(),hourlyLimit:config.solariBetaPerKeyHourlyLimit,dailyLimit:config.solariBetaPerKeyDailyLimit,globalDailyLimit:config.solariBetaGlobalDailyLimit,concurrencyLimit:config.solariBetaConcurrencyLimit,leaseTtlSeconds:config.solariBetaLeaseTtlSeconds});
      if(!admission.allowed){const concurrency=admission.reason==='concurrency';throw new SolariResearchError(concurrency?'beta_busy':'beta_quota_exceeded',concurrency?'All bounded Solari beta execution slots are busy.':'The Solari beta quota was reached.',{status:concurrency?503:429,retryable:true});}
      leaseID=admission.leaseID;
      const monitored=new AbortController();let killed=false,checking=false;
      const forwardAbort=()=>monitored.abort();signal?.addEventListener('abort',forwardAbort,{once:true});if(signal?.aborted)forwardAbort();
      const killMonitor=setInterval(async()=>{if(checking||monitored.signal.aborted)return;checking=true;try{if(!await getStore().runtimeEnabled(config.solariBetaRuntimeKey)){killed=true;monitored.abort();}}catch{killed=true;monitored.abort();}finally{checking=false;}},config.solariBetaKillPollMs);
      let result;
      try{result=await research.research(decoded.parsed,{signal:monitored.signal});}
      catch(error){if(killed)throw new SolariResearchError('solari_beta_killed','Solari beta live execution was stopped by the runtime switch.',{status:503});throw error;}
      finally{clearInterval(killMonitor);signal?.removeEventListener('abort',forwardAbort);}
      if(!await getStore().completeIdempotency(hash,decoded.parsed.requestID,owner,result,config.solariBetaIdempotencyTtlSeconds))throw new SolariResearchError('idempotency_commit_failed','The beta result could not be committed atomically.',{status:503,retryable:true});
      complete=true;return{status:200,payload:result,headers:{'x-smartcart-idempotency':'fresh'}};
    }finally{await getStore().release(leaseID);if(!complete)await getStore().abandonIdempotency(hash,decoded.parsed.requestID,owner);}
  }
  return{challenge,attestation,researchEnvelope,services:{getStore,getVerifier,research}};
}

export function isV2Envelope(payload){return payload?.schemaVersion==='solari-app-attest-research-envelope-v1';}
export { ContractValidationError };
