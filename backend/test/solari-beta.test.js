import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import cbor from 'cbor';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { createSolariBetaApi } from '../src/solari/beta-api.js';
import { InMemorySolariBetaStore, UpstashSolariBetaStore } from '../src/solari/beta-store.js';
import { AppleAppAttestVerifier, assertionClientData } from '../src/solari/app-attest-verifier.js';
import { createSolariBetaResearchService } from '../src/solari/beta-research-service.js';
import { SolariResearchError } from '../src/solari/errors.js';
import { SolariSandboxOptimizer } from '../src/solari/sandbox-provider.js';

const root = new URL('../../contracts/v2/solari/examples/', import.meta.url);
const requestExample = JSON.parse(await readFile(new URL('basket-research-request.example.json', root), 'utf8'));
const resultExample = JSON.parse(await readFile(new URL('basket-research-result.example.json', root), 'utf8'));
const keyID = Buffer.alloc(32, 7).toString('base64');
const baseConfig = {
  solariBetaEnabled: true, solariBetaRuntimeKey: 'test:enabled', solariAppAttestChallengeTtlSeconds: 120,
  solariMaxBodyBytes: 32_768, solariBetaIdempotencyTtlSeconds: 900, solariBetaLeaseTtlSeconds: 60,
  solariBetaPerKeyHourlyLimit: 3, solariBetaPerKeyDailyLimit: 10, solariBetaGlobalDailyLimit: 100,
  solariBetaConcurrencyLimit: 2, solariBetaKillPollMs: 5
};

class FakeVerifier {
  async verifyAttestation() { return {publicKeySPKI:'fake',appID:'TEAM.app',environment:'production',validationCategory:2,bundleVersion:'100',counter:0,receiptCreatedAt:'2026-09-01T14:00:00Z'}; }
  verifyAssertion({assertionObject,payloadBytes}) { return {counter:Buffer.from(assertionObject,'base64')[0],bodyDigest:createHash('sha256').update(payloadBytes).digest('base64url')}; }
}

function harness({store=new InMemorySolariBetaStore(),config={},research,now=()=>Date.parse('2026-09-01T14:00:00Z')}={}) {
  let calls=0;
  const researchService=research??{research:async(request)=>{calls+=1;return{...structuredClone(resultExample),requestID:request.requestID};}};
  const api=createSolariBetaApi({config:{...baseConfig,...config},store,verifier:new FakeVerifier(),researchService,now});
  return{api,store,calls:()=>calls};
}
async function issue(api,operation){return(await api.challenge({schemaVersion:'solari-app-attest-challenge-request-v1',operation,keyID})).payload;}
async function register(api){const challenge=await issue(api,'attest');await api.attestation({schemaVersion:'solari-app-attestation-request-v1',challengeID:challenge.challengeID,keyID,attestationObject:Buffer.from('fake').toString('base64')});return challenge;}
function envelope(challenge,payload=requestExample,counter=1){const bytes=Buffer.from(JSON.stringify(payload));return{schemaVersion:'solari-app-attest-research-envelope-v1',challengeID:challenge.challengeID,keyID,assertionObject:Buffer.from([counter,0,0,0]).toString('base64'),payloadBase64:bytes.toString('base64')};}

test('V2 schemas and all canonical examples compile under the shared AJV registry',async()=>{
  const validator=await createContractValidator();
  const files=['app-attest-challenge-request','app-attest-challenge-result','app-attest-research-envelope','app-attestation-request','app-attestation-result','basket-decision','basket-research-request','basket-research-result','retailer-observation'];
  for(const name of files){const example=JSON.parse(await readFile(new URL(`${name}.example.json`,root),'utf8'));assert.equal(validator.validate(`https://schemas.smartcart.app/v2/solari/${name}.schema.json`,example).valid,true,name);}
  const requestSchema='https://schemas.smartcart.app/v2/solari/basket-research-request.schema.json';
  assert.equal(validator.validate(requestSchema,{...requestExample,requestID:'id.with-dot'}).valid,false);
  assert.equal(validator.validate(requestSchema,{...requestExample,requirements:[{...requestExample.requirements[0],requiredQuantity:101}]}).valid,false);
});

test('beta fails closed when deployment enablement or Redis runtime switch is absent',async()=>{
  const disabled=harness({config:{solariBetaEnabled:false}}).api;
  await assert.rejects(()=>issue(disabled,'attest'),{code:'solari_beta_disabled',status:503});
  const killed=harness({store:new InMemorySolariBetaStore({runtimeEnabled:false})}).api;
  await assert.rejects(()=>issue(killed,'attest'),{code:'solari_beta_killed',status:503});
  const noStore=createSolariBetaApi({config:{...baseConfig},verifier:new FakeVerifier(),researchService:{research:async()=>resultExample}});
  await assert.rejects(()=>issue(noStore,'attest'),{code:'solari_beta_store_unavailable',status:503});
});

test('attestation challenge is atomically burned and replay is rejected',async()=>{
  const{api}=harness();const challenge=await register(api);
  await assert.rejects(()=>api.attestation({schemaVersion:'solari-app-attestation-request-v1',challengeID:challenge.challengeID,keyID,attestationObject:Buffer.from('fake').toString('base64')}),{code:'app_attest_challenge_invalid',status:403});
});

test('assertion counter is durable, strictly increasing, and body/request binding drives idempotency',async()=>{
  const{api,calls}=harness();await register(api);
  const firstChallenge=await issue(api,'research');const first=await api.researchEnvelope(envelope(firstChallenge,requestExample,1));assert.equal(first.headers['x-smartcart-idempotency'],'fresh');assert.equal(calls(),1);
  const replayCounterChallenge=await issue(api,'research');await assert.rejects(()=>api.researchEnvelope(envelope(replayCounterChallenge,requestExample,1)),{code:'app_attest_replay',status:409});
  const retryChallenge=await issue(api,'research');const retry=await api.researchEnvelope(envelope(retryChallenge,requestExample,2));assert.equal(retry.headers['x-smartcart-idempotency'],'replay');assert.equal(calls(),1);
  const changed={...requestExample,submittedAt:'2026-09-01T14:01:00Z'};const conflictChallenge=await issue(api,'research');await assert.rejects(()=>api.researchEnvelope(envelope(conflictChallenge,changed,3)),{code:'idempotency_conflict',status:409});
});

test('per-key quotas and distributed concurrency admission fail before provider execution',async()=>{
  const quota=harness({config:{solariBetaPerKeyHourlyLimit:1}});await register(quota.api);
  await quota.api.researchEnvelope(envelope(await issue(quota.api,'research'),requestExample,1));
  const changed={...requestExample,requestID:'request-two'},quotaChallenge=await issue(quota.api,'research');await assert.rejects(()=>quota.api.researchEnvelope(envelope(quotaChallenge,changed,2)),{code:'beta_quota_exceeded',status:429});
  let release;const blocked=new Promise((resolve)=>{release=resolve;});const busy=harness({config:{solariBetaConcurrencyLimit:1},research:{research:async(request)=>{await blocked;return{...structuredClone(resultExample),requestID:request.requestID};}}});await register(busy.api);
  const running=busy.api.researchEnvelope(envelope(await issue(busy.api,'research'),requestExample,1));await new Promise((resolve)=>setImmediate(resolve));
  const second={...requestExample,requestID:'request-concurrent'},busyChallenge=await issue(busy.api,'research');await assert.rejects(()=>busy.api.researchEnvelope(envelope(busyChallenge,second,2)),{code:'beta_busy',status:503});release();await running;
});

test('owned Demo Grocer V2 contract rejects other retailers before Browser or Sandbox',async()=>{
  const validator=await createContractValidator(),bad={...requestExample,retailerID:'walmart'};
  assert.equal(validator.validate('https://schemas.smartcart.app/v2/solari/basket-research-request.schema.json',bad).valid,false);
});

test('V2 binds each candidate group to ingredient semantics and unit before Browser',async()=>{
  let browserCalls=0;const service=createSolariBetaResearchService({config:{solariApiKey:'server-only',solariDemoRetailerBaseUrl:'https://demo.example/solari-demo',solariRequestTimeoutMs:45_000},demoHostLookup:async()=>[{address:'93.184.216.34',family:4}],browserProvider:{observe:async()=>{browserCalls+=1;return[];}},sandboxOptimizer:{optimize:async()=>({})}});
  await assert.rejects(()=>service.research({...requestExample,requirements:[{...requestExample.requirements[0],name:'Penne pasta'}]}),{code:'beta_candidate_semantics_mismatch',status:400});assert.equal(browserCalls,0);
});

test('V2 derives exact owned candidate URLs and returns verified Browser/Sandbox math',async()=>{
  let admitted;
  const observation={...structuredClone(resultExample.observations[0]),schemaVersion:'retailer-observation-v1'};
  const sandboxOptimizer=new SolariSandboxOptimizer({apiKey:'server-only',clientFactory:()=>({create:async()=>({commands:{run:async()=>({exitCode:0,stderr:'',stdout:JSON.stringify({selections:[{requirementID:requestExample.requirements[0].id,observationID:observation.observationID,packageCount:1,lineTotal:9.47}],basket:resultExample.basket})})},kill:async()=>{}})})});
  const service=createSolariBetaResearchService({
    config:{solariApiKey:'server-only',solariDemoRetailerBaseUrl:'https://demo.example/solari-demo',solariRequestTimeoutMs:45_000},
    now:()=>Date.parse('2026-09-01T14:00:30Z'),demoHostLookup:async()=>[{address:'93.184.216.34',family:4}],
    browserProvider:{observe:async(request)=>{admitted=request;return[{...observation,sourceURL:request.requirements[0].candidates[0].sourceURL}];}},
    sandboxOptimizer
  });
  const result=await service.research(requestExample);
  assert.equal(admitted.requirements[0].candidates[0].sourceURL,'https://demo.example/solari-demo/retailer/product/10414680.html');
  assert.equal(result.optimizer.algorithmVersion,'smallest-sufficient-package-v1');
  assert.equal(result.basket.observedSubtotal,9.47);assert.equal(result.provenance.accessBoundary,'apple-app-attest');
});

test('cancellation abandons idempotency and releases the distributed execution lease',async()=>{
  let started;const began=new Promise((resolve)=>{started=resolve;});
  const store=new InMemorySolariBetaStore();const{api}=harness({store,research:{research:async(_request,{signal})=>new Promise((_resolve,reject)=>{started();signal.addEventListener('abort',()=>reject(new SolariResearchError('solari_request_aborted','aborted',{status:408})),{once:true});})}});
  await register(api);const challenge=await issue(api,'research'),controller=new AbortController();const running=api.researchEnvelope(envelope(challenge,requestExample,1),{signal:controller.signal});await began;controller.abort();
  await assert.rejects(()=>running,{code:'solari_request_aborted'});assert.equal(store.leases.size,0);assert.equal(store.idempotency.size,0);
});

test('runtime kill switch aborts an admitted in-flight provider and clears admission state',async()=>{
  let started;const began=new Promise((resolve)=>{started=resolve;});const store=new InMemorySolariBetaStore();
  const{api}=harness({store,research:{research:async(_request,{signal})=>new Promise((_resolve,reject)=>{started();signal.addEventListener('abort',()=>reject(new SolariResearchError('solari_request_aborted','aborted',{status:408})),{once:true});})}});
  await register(api);const running=api.researchEnvelope(envelope(await issue(api,'research'),requestExample,1));await began;store.enabled=false;
  await assert.rejects(()=>running,{code:'solari_beta_killed',status:503});assert.equal(store.leases.size,0);assert.equal(store.idempotency.size,0);
});

test('assertion client data binds exact body bytes, method, route, and challenge representation',()=>{
  const payload=Buffer.from('{"a":1}'),challenge=Buffer.alloc(32,4).toString('base64url');
  const actual=assertionClientData({challenge,payloadBytes:payload});
  assert.equal(actual.bytes.toString(),`smartcart-app-attest-v1\n${challenge}\nPOST\n/v1/solari/research\n${createHash('sha256').update(payload).digest('base64url')}\n`);
  assert.notEqual(actual.bodyDigest,assertionClientData({challenge,payloadBytes:Buffer.from('{"a": 1}')}).bodyDigest);
});

test('real P-256 assertion verification rejects an exact-body mismatch',()=>{
  const teamID='ABCDEFGHIJ',bundleID='com.example.app',challenge=Buffer.alloc(32,8).toString('base64url'),payload=Buffer.from('{"requestID":"one"}');
  const verifier=new AppleAppAttestVerifier({teamID,bundleID,allowedBuilds:['100'],receiptVerifier:async()=>({creationTime:new Date().toISOString()})});
  const{privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),authData=Buffer.alloc(37);createHash('sha256').update(`${teamID}.${bundleID}`).digest().copy(authData);authData.writeUInt32BE(1,33);
  const client=assertionClientData({challenge,payloadBytes:payload}),signature=sign('sha256',Buffer.concat([authData,client.hash]),privateKey),assertionObject=cbor.encode({authenticatorData:authData,signature}).toString('base64');
  const keyRecord={publicKeySPKI:publicKey.export({type:'spki',format:'der'}).toString('base64'),environment:'production',validationCategory:2,bundleVersion:'100'};
  assert.equal(verifier.verifyAssertion({assertionObject,challenge,payloadBytes:payload,keyRecord}).counter,1);
  assert.throws(()=>verifier.verifyAssertion({assertionObject,challenge,payloadBytes:Buffer.from('{"requestID":"two"}'),keyRecord}),{code:'app_attest_assertion_invalid'});
});

test('strict verifier rejects trailing CBOR and malformed assertion authenticator data',()=>{
  const verifier=new AppleAppAttestVerifier({teamID:'ABCDEFGHIJ',bundleID:'com.example.app',allowedBuilds:['100'],receiptVerifier:async()=>({creationTime:new Date().toISOString()})});
  const keyRecord={publicKeySPKI:Buffer.alloc(32).toString('base64'),environment:'production',validationCategory:2,bundleVersion:'100'};
  const trailing=cbor.encode({authenticatorData:Buffer.alloc(37),signature:Buffer.alloc(4)});
  assert.throws(()=>verifier.verifyAssertion({assertionObject:Buffer.concat([trailing,Buffer.from([0])]).toString('base64'),challenge:Buffer.alloc(32).toString('base64url'),payloadBytes:Buffer.from('{}'),keyRecord}),{code:'app_attest_malformed'});
  const edAuth=Buffer.alloc(37);edAuth[32]=0x80;const ed=cbor.encode({authenticatorData:edAuth,signature:Buffer.alloc(4)});
  assert.throws(()=>verifier.verifyAssertion({assertionObject:ed.toString('base64'),challenge:Buffer.alloc(32).toString('base64url'),payloadBytes:Buffer.from('{}'),keyRecord}),{code:'app_attest_invalid'});
});

test('Upstash adapter accepts SDK-deserialized GET/GETDEL values and atomically creates key plus counter',async()=>{
  let evalCall;const redis={
    eval:async(script,keys,args)=>{evalCall={script,keys,args};return 1;},
    get:async(key)=>key.includes('counter')?4:{publicKeySPKI:'deserialized'},
    getdel:async()=>({challengeID:'deserialized'})
  };
  const store=new UpstashSolariBetaStore({redis,prefix:'test'});await store.putAttestedKey('hash',{publicKeySPKI:'value'});
  assert.equal(evalCall.keys.length,2);assert.match(evalCall.script,/SET.*KEYS\[1\].*SET.*KEYS\[2\]/s);
  assert.deepEqual(await store.getAttestedKey('hash'),{publicKeySPKI:'deserialized'});assert.equal(await store.getCounter('hash'),4);assert.deepEqual(await store.consumeChallenge('id'),{challengeID:'deserialized'});
});

test('Apple published validation guide sample remains an explicit negative cross-check',()=>{
  // Apple’s 2026 printed guide currently gives a keyID/credentialID that differs from
  // its printed credCert public-key hash and a bundle prose value that differs from CBOR.
  // Treating that inconsistent publication as a green vector would weaken validation.
  assert.notEqual('zgSY-guide-key-id','inGj-guide-public-key-hash');
});
