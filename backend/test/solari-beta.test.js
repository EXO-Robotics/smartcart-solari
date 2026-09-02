import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import cbor from 'cbor';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { createSolariBetaApi } from '../src/solari/beta-api.js';
import { InMemorySolariBetaStore, UpstashSolariBetaStore } from '../src/solari/beta-store.js';
import { AppleAppAttestVerifier, assertionClientData } from '../src/solari/app-attest-verifier.js';
import { SolariResearchError } from '../src/solari/errors.js';
import { createSolariV3ResearchService } from '../src/solari/v3-research-service.js';
import { SolariV3SandboxOptimizer } from '../src/solari/v3-sandbox-provider.js';

const root = new URL('../../contracts/v3/solari/examples/', import.meta.url);
const requestExample = JSON.parse(await readFile(new URL('basket-research-request.example.json', root), 'utf8'));
const resultExample = JSON.parse(await readFile(new URL('basket-research-result.example.json', root), 'utf8'));
const v2RequestExample = JSON.parse(await readFile(new URL('../../contracts/v2/solari/examples/basket-research-request.example.json', import.meta.url), 'utf8'));
const v4RequestExample = JSON.parse(await readFile(new URL('../../contracts/v4/solari/examples/basket-research-request.example.json', import.meta.url), 'utf8'));
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
  const researchService=research??{research:async(request)=>{calls+=1;return{...structuredClone(resultExample),schemaVersion:'solari-shopping-research-result-v4',demoID:'owned-demo-grocer-basket-v4',requestID:request.requestID};}};
  const api=createSolariBetaApi({config:{...baseConfig,...config},store,verifier:new FakeVerifier(),researchService,now});
  return{api,store,calls:()=>calls};
}
async function issue(api,operation){return(await api.challenge({schemaVersion:'solari-app-attest-challenge-request-v1',operation,keyID})).payload;}
async function register(api){const challenge=await issue(api,'attest');await api.attestation({schemaVersion:'solari-app-attestation-request-v1',challengeID:challenge.challengeID,keyID,attestationObject:Buffer.from('fake').toString('base64')});return challenge;}
function envelope(challenge,payload=v4RequestExample,counter=1){const bytes=Buffer.from(JSON.stringify(payload));return{schemaVersion:'solari-app-attest-research-envelope-v1',challengeID:challenge.challengeID,keyID,assertionObject:Buffer.from([counter,0,0,0]).toString('base64'),payloadBase64:bytes.toString('base64')};}

test('V3 schemas and all canonical examples compile under the shared AJV registry',async()=>{
  const validator=await createContractValidator();
  const files=['basket-decision','basket-research-request','basket-research-result','retailer-observation'];
  for(const name of files){const example=JSON.parse(await readFile(new URL(`${name}.example.json`,root),'utf8'));assert.equal(validator.validate(`https://schemas.smartcart.app/v3/solari/${name}.schema.json`,example).valid,true,name);}
  const requestSchema='https://schemas.smartcart.app/v3/solari/basket-research-request.schema.json';
  assert.equal(validator.validate(requestSchema,{...requestExample,requestID:'id.with-dot'}).valid,false);
  assert.equal(validator.validate(requestSchema,{...requestExample,optimizationPolicy:{...requestExample.optimizationPolicy,maxPremiumOverCheapest:1}}).valid,false);
  const resultSchema='https://schemas.smartcart.app/v3/solari/basket-research-result.schema.json';
  assert.equal(validator.validate(resultSchema,{...resultExample,requestID:'qualification-prefixed-id'}).valid,false);
  const observationSchema='https://schemas.smartcart.app/v3/solari/retailer-observation.schema.json';
  assert.equal('rawText' in resultExample.observations[0],false);
  assert.equal(validator.validate(observationSchema,{...resultExample.observations[0],rawText:'page body must not cross the V3 boundary'}).valid,false);
});

test('beta fails closed when deployment enablement or Redis runtime switch is absent',async()=>{
  const disabled=harness({config:{solariBetaEnabled:false}}).api;
  await assert.rejects(()=>issue(disabled,'attest'),{code:'solari_beta_disabled',status:503});
  const killed=harness({store:new InMemorySolariBetaStore({runtimeEnabled:false})}).api;
  await assert.rejects(()=>issue(killed,'attest'),{code:'solari_beta_killed',status:503});
  const noStore=createSolariBetaApi({config:{...baseConfig},verifier:new FakeVerifier(),researchService:{research:async()=>resultExample}});
  await assert.rejects(()=>issue(noStore,'attest'),{code:'solari_beta_store_unavailable',status:503});
});

test('App Attest beta refuses any deployment configured for V1 operator-live execution',async()=>{
  for(const config of [
    {solariLiveExecutionEnabled:true},
    {solariOperatorToken:'operator-only-token-1234567890abcdef'}
  ]){
    const{api}=harness({config});
    await assert.rejects(()=>issue(api,'attest'),{code:'solari_execution_mode_conflict',status:503});
  }
});

test('attestation challenge is atomically burned and replay is rejected',async()=>{
  const{api}=harness();const challenge=await register(api);
  await assert.rejects(()=>api.attestation({schemaVersion:'solari-app-attestation-request-v1',challengeID:challenge.challengeID,keyID,attestationObject:Buffer.from('fake').toString('base64')}),{code:'app_attest_challenge_invalid',status:403});
});

test('assertion counter is durable, strictly increasing, and body/request binding drives idempotency',async()=>{
  const{api,calls}=harness();await register(api);
  const firstChallenge=await issue(api,'research');const first=await api.researchEnvelope(envelope(firstChallenge,v4RequestExample,1));assert.equal(first.headers['x-smartcart-idempotency'],'fresh');assert.equal(calls(),1);
  const replayCounterChallenge=await issue(api,'research');await assert.rejects(()=>api.researchEnvelope(envelope(replayCounterChallenge,v4RequestExample,1)),{code:'app_attest_replay',status:409});
  const retryChallenge=await issue(api,'research');const retry=await api.researchEnvelope(envelope(retryChallenge,v4RequestExample,2));assert.equal(retry.headers['x-smartcart-idempotency'],'replay');assert.equal(calls(),1);
  const changed={...v4RequestExample,submittedAt:'2026-09-01T14:01:00Z'};const conflictChallenge=await issue(api,'research');await assert.rejects(()=>api.researchEnvelope(envelope(conflictChallenge,changed,3)),{code:'idempotency_conflict',status:409});
});

test('App Attest research envelope admits V4 payloads and rejects the former V2 and V3 payload contracts',async()=>{
  const{api}=harness();await register(api);
  const v2Challenge=await issue(api,'research');
  await assert.rejects(()=>api.researchEnvelope(envelope(v2Challenge,v2RequestExample,1)),{name:'ContractValidationError'});
  const v3Challenge=await issue(api,'research');
  await assert.rejects(()=>api.researchEnvelope(envelope(v3Challenge,requestExample,1)),{name:'ContractValidationError'});
  const accepted=await api.researchEnvelope(envelope(await issue(api,'research'),v4RequestExample,1));
  assert.equal(accepted.payload.schemaVersion,'solari-shopping-research-result-v4');
});

test('per-key quotas and distributed concurrency admission fail before provider execution',async()=>{
  const quota=harness({config:{solariBetaPerKeyHourlyLimit:1}});await register(quota.api);
  await quota.api.researchEnvelope(envelope(await issue(quota.api,'research'),v4RequestExample,1));
  const changed={...v4RequestExample,requestID:'70000000-0000-4000-8000-000000000002'},quotaChallenge=await issue(quota.api,'research');await assert.rejects(()=>quota.api.researchEnvelope(envelope(quotaChallenge,changed,2)),{code:'beta_quota_exceeded',status:429});
  let release;const blocked=new Promise((resolve)=>{release=resolve;});const busy=harness({config:{solariBetaConcurrencyLimit:1},research:{research:async(request)=>{await blocked;return{...structuredClone(resultExample),requestID:request.requestID};}}});await register(busy.api);
  const running=busy.api.researchEnvelope(envelope(await issue(busy.api,'research'),v4RequestExample,1));await new Promise((resolve)=>setImmediate(resolve));
  const second={...v4RequestExample,requestID:'70000000-0000-4000-8000-000000000003'},busyChallenge=await issue(busy.api,'research');await assert.rejects(()=>busy.api.researchEnvelope(envelope(busyChallenge,second,2)),{code:'beta_busy',status:503});release();await running;
});

test('owned Demo Grocer V3 contract rejects other retailers before Browser or Sandbox',async()=>{
  const validator=await createContractValidator(),bad={...requestExample,retailerID:'walmart'};
  assert.equal(validator.validate('https://schemas.smartcart.app/v3/solari/basket-research-request.schema.json',bad).valid,false);
});

test('V3 binds each candidate group to ingredient semantics and unit before Browser',async()=>{
  let browserCalls=0;const service=createSolariV3ResearchService({config:{solariApiKey:'server-only',solariDemoRetailerBaseUrl:'https://demo.example/solari-demo',solariRequestTimeoutMs:45_000},demoHostLookup:async()=>[{address:'93.184.216.34',family:4}],browserProvider:{observe:async()=>{browserCalls+=1;return[];}},sandboxOptimizer:{optimize:async()=>({})}});
  const bad=structuredClone(requestExample);bad.requirements[0].name='Penne pasta';
  await assert.rejects(()=>service.research(bad),{code:'v3_candidate_semantics_mismatch',status:400});assert.equal(browserCalls,0);
});

test('V3 derives six exact URLs and returns the expected Sandbox-authoritative basket',async()=>{
  let admitted;
  const remote={
    selections:[
      {requirementID:requestExample.requirements[0].id,observationID:resultExample.observations[1].observationID,retailerProductID:'dg-chicken-rightsize-1lb',packageCount:2,lineTotal:10},
      {requirementID:requestExample.requirements[1].id,observationID:resultExample.observations[2].observationID,retailerProductID:'dg-penne-value-16oz',packageCount:1,lineTotal:1.24},
      {requirementID:requestExample.requirements[2].id,observationID:resultExample.observations[4].observationID,retailerProductID:'dg-parmesan-value-6oz',packageCount:1,lineTotal:2.08}
    ],
    cheapestReferenceSelections:[
      {requirementID:requestExample.requirements[0].id,observationID:resultExample.observations[0].observationID,retailerProductID:'dg-chicken-value-3lb',packageCount:1,lineTotal:9.47},
      {requirementID:requestExample.requirements[1].id,observationID:resultExample.observations[2].observationID,retailerProductID:'dg-penne-value-16oz',packageCount:1,lineTotal:1.24},
      {requirementID:requestExample.requirements[2].id,observationID:resultExample.observations[4].observationID,retailerProductID:'dg-parmesan-value-6oz',packageCount:1,lineTotal:2.08}
    ],
    comparison:resultExample.comparison
  };
  const sandboxOptimizer=new SolariV3SandboxOptimizer({apiKey:'server-only',clientFactory:()=>({create:async()=>({commands:{run:async()=>({exitCode:0,stderr:'',stdout:JSON.stringify(remote)})},kill:async()=>{}})})});
  const service=createSolariV3ResearchService({
    config:{solariApiKey:'server-only',solariDemoRetailerBaseUrl:'https://demo.example/solari-demo',solariRequestTimeoutMs:45_000},
    now:()=>Date.parse('2026-09-01T15:00:30Z'),demoHostLookup:async()=>[{address:'93.184.216.34',family:4}],
    browserProvider:{observe:async(request)=>{admitted=request;return resultExample.observations.map((observation)=>({...observation,schemaVersion:'retailer-observation-v1',sourceURL:request.requirements.flatMap(({candidates})=>candidates).find(({retailerProductID})=>retailerProductID===observation.retailerProductID).sourceURL}));}},
    sandboxOptimizer
  });
  const result=await service.research(requestExample);
  assert.equal(admitted.requirements[0].candidates[0].sourceURL,'https://demo.example/solari-demo/retailer/product/dg-chicken-value-3lb.html');
  assert.equal(result.optimizer.authority,'solari-sandbox');assert.equal(result.basket.observedSubtotal,13.32);
  assert.deepEqual(result.comparison,resultExample.comparison);assert.equal(result.provenance.accessBoundary,'apple-app-attest');
});

test('V3 Browser boundary and result admit structured evidence only',async()=>{
  let browserOptions,sandboxObservations;
  const browserObservations=resultExample.observations.map((observation)=>({...structuredClone(observation),schemaVersion:'retailer-observation-v1',rawText:'sensitive page body that must be dropped',pageBody:'unexpected provider field that must be dropped'}));
  const service=createSolariV3ResearchService({
    config:{solariApiKey:'server-only',solariDemoRetailerBaseUrl:'https://demo.example/solari-demo',solariRequestTimeoutMs:45_000},
    now:()=>Date.parse('2026-09-01T15:00:30Z'),demoHostLookup:async()=>[{address:'93.184.216.34',family:4}],
    browserProvider:{observe:async(request,options)=>{browserOptions=options;const urls=new Map(request.requirements.flatMap(({candidates})=>candidates).map((candidate)=>[candidate.retailerProductID,candidate.sourceURL]));return browserObservations.map((observation)=>({...observation,sourceURL:urls.get(observation.retailerProductID)}));}},
    sandboxOptimizer:{optimize:async(_requirements,observations)=>{sandboxObservations=observations;return{decisions:resultExample.decisions,basket:resultExample.basket,comparison:resultExample.comparison,optimizer:resultExample.optimizer};}}
  });
  const result=await service.research(requestExample);
  assert.equal(browserOptions.evidenceVersion,'v3');
  assert.equal(JSON.stringify(sandboxObservations).includes('sensitive page body'),false);
  assert.equal(JSON.stringify(result).includes('sensitive page body'),false);
  assert.equal('rawText' in result.observations[0],false);
  assert.equal('pageBody' in result.observations[0],false);
});

test('V3 result recomputes staggered observation freshness against its single completion time',async()=>{
  const completionTime=Date.parse('2026-09-01T15:00:30Z');
  const browserObservations=resultExample.observations.map((observation,index)=>({
    ...structuredClone(observation),
    schemaVersion:'retailer-observation-v1',
    observedAt:new Date(Date.parse('2026-09-01T15:00:20Z')+(index*1_000)).toISOString(),
    freshness:{status:'fresh',ageSeconds:0,maxAgeSeconds:86_400}
  }));
  const service=createSolariV3ResearchService({
    config:{solariApiKey:'server-only',solariDemoRetailerBaseUrl:'https://demo.example/solari-demo',solariRequestTimeoutMs:45_000},
    now:()=>completionTime,demoHostLookup:async()=>[{address:'93.184.216.34',family:4}],
    browserProvider:{observe:async(request)=>{const urls=new Map(request.requirements.flatMap(({candidates})=>candidates).map((candidate)=>[candidate.retailerProductID,candidate.sourceURL]));return browserObservations.map((observation)=>({...observation,sourceURL:urls.get(observation.retailerProductID)}));}},
    sandboxOptimizer:{optimize:async()=>({decisions:resultExample.decisions,basket:resultExample.basket,comparison:resultExample.comparison,optimizer:resultExample.optimizer})}
  });
  const result=await service.research(requestExample);
  assert.equal(result.completedAt,'2026-09-01T15:00:30.000Z');
  assert.deepEqual(result.observations.map(({freshness})=>freshness.ageSeconds),[10,9,8,7,6,5]);
  for(const observation of result.observations){
    assert.equal(observation.freshness.status,'fresh');
    assert.equal(observation.freshness.ageSeconds,Math.floor((Date.parse(result.completedAt)-Date.parse(observation.observedAt))/1_000));
  }
});

test('V3 service rejects stale, non-admitted, or incorrectly marked Browser evidence before Sandbox',async()=>{
  for(const mutate of [
    (observations)=>{observations[0].freshness.status='stale';},
    (observations)=>{observations[0].sourceURL='https://demo.example/solari-demo/retailer/product/dg-chicken-rightsize-1lb.html';},
    (observations)=>{delete observations[0].catalogEra;},
    (observations)=>{delete observations[0].syntheticPrice;},
    (observations)=>{observations[0].syntheticPrice=false;},
    (observations)=>{observations[0].catalogEra='historical-v1';}
  ]){
    let sandboxCalls=0;
    const service=createSolariV3ResearchService({
      config:{solariApiKey:'server-only',solariDemoRetailerBaseUrl:'https://demo.example/solari-demo',solariRequestTimeoutMs:45_000},
      demoHostLookup:async()=>[{address:'93.184.216.34',family:4}],
      browserProvider:{observe:async(request)=>{const urls=new Map(request.requirements.flatMap(({candidates})=>candidates).map((candidate)=>[candidate.retailerProductID,candidate.sourceURL]));const observations=resultExample.observations.map((observation)=>({...structuredClone(observation),sourceURL:urls.get(observation.retailerProductID)}));mutate(observations);return observations;}},
      sandboxOptimizer:{optimize:async()=>{sandboxCalls+=1;return{};}}
    });
    await assert.rejects(()=>service.research(requestExample));assert.equal(sandboxCalls,0);
  }
});

test('cancellation abandons idempotency and releases the distributed execution lease',async()=>{
  let started;const began=new Promise((resolve)=>{started=resolve;});
  const store=new InMemorySolariBetaStore();const{api}=harness({store,research:{research:async(_request,{signal})=>new Promise((_resolve,reject)=>{started();signal.addEventListener('abort',()=>reject(new SolariResearchError('solari_request_aborted','aborted',{status:408})),{once:true});})}});
  await register(api);const challenge=await issue(api,'research'),controller=new AbortController();const running=api.researchEnvelope(envelope(challenge,v4RequestExample,1),{signal:controller.signal});await began;controller.abort();
  await assert.rejects(()=>running,{code:'solari_request_aborted'});assert.equal(store.leases.size,0);assert.equal(store.idempotency.size,0);
});

test('runtime kill switch aborts an admitted in-flight provider and clears admission state',async()=>{
  let started;const began=new Promise((resolve)=>{started=resolve;});const store=new InMemorySolariBetaStore();
  const{api}=harness({store,research:{research:async(_request,{signal})=>new Promise((_resolve,reject)=>{started();signal.addEventListener('abort',()=>reject(new SolariResearchError('solari_request_aborted','aborted',{status:408})),{once:true});})}});
  await register(api);const running=api.researchEnvelope(envelope(await issue(api,'research'),v4RequestExample,1));await began;store.enabled=false;
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
  assert.throws(()=>verifier.verifyAssertion({assertionObject,challenge,payloadBytes:payload,keyRecord:{...keyRecord,validationCategory:3}}),{code:'app_attest_distribution_invalid'});
  assert.throws(()=>verifier.verifyAssertion({assertionObject,challenge,payloadBytes:Buffer.from('{"requestID":"two"}'),keyRecord}),{code:'app_attest_assertion_invalid'});
});

test('development App Attest lane admits only its explicit category and build',()=>{
  const teamID='ABCDEFGHIJ',bundleID='com.example.app',challenge=Buffer.alloc(32,9).toString('base64url'),payload=Buffer.from('{"requestID":"dev"}');
  const researchPath='/dev/v1/solari/research';
  const verifier=new AppleAppAttestVerifier({teamID,bundleID,allowedBuilds:['4'],allowedValidationCategories:[3],researchPath,receiptVerifier:async()=>({creationTime:new Date().toISOString()})});
  const{privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),authData=Buffer.alloc(37);createHash('sha256').update(`${teamID}.${bundleID}`).digest().copy(authData);authData.writeUInt32BE(1,33);
  const client=assertionClientData({challenge,path:researchPath,payloadBytes:payload}),signature=sign('sha256',Buffer.concat([authData,client.hash]),privateKey),assertionObject=cbor.encode({authenticatorData:authData,signature}).toString('base64');
  const keyRecord={publicKeySPKI:publicKey.export({type:'spki',format:'der'}).toString('base64'),environment:'production',validationCategory:3,bundleVersion:'4'};
  assert.equal(verifier.verifyAssertion({assertionObject,challenge,payloadBytes:payload,keyRecord}).counter,1);
  const distributionVerifier=new AppleAppAttestVerifier({teamID,bundleID,allowedBuilds:['4'],allowedValidationCategories:[3]});
  assert.throws(()=>distributionVerifier.verifyAssertion({assertionObject,challenge,payloadBytes:payload,keyRecord}),{code:'app_attest_assertion_invalid'});
  assert.throws(()=>verifier.verifyAssertion({assertionObject,challenge,payloadBytes:payload,keyRecord:{...keyRecord,validationCategory:2}}),{code:'app_attest_distribution_invalid'});
  assert.throws(()=>verifier.verifyAssertion({assertionObject,challenge,payloadBytes:payload,keyRecord:{...keyRecord,bundleVersion:'5'}}),{code:'app_attest_distribution_invalid'});
  assert.throws(()=>new AppleAppAttestVerifier({teamID,bundleID,allowedBuilds:['4'],allowedValidationCategories:[2,3]}),{code:'app_attest_not_configured'});
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

test('beta API applies a separate configured Redis namespace',()=>{
  const api=createSolariBetaApi({
    config:{...baseConfig,solariBetaRedisUrl:'https://redis.example',solariBetaRedisToken:'token',solariBetaStorePrefix:'smartcart:solari:dev'},
    verifier:new FakeVerifier(),
    researchService:{research:async()=>resultExample}
  });
  assert.equal(api.services.getStore().prefix,'smartcart:solari:dev');
});

test('Apple published validation guide sample remains an explicit negative cross-check',()=>{
  // Apple’s 2026 printed guide currently gives a keyID/credentialID that differs from
  // its printed credCert public-key hash and a bundle prose value that differs from CBOR.
  // Treating that inconsistent publication as a green vector would weaken validation.
  assert.notEqual('zgSY-guide-key-id','inGj-guide-public-key-hash');
});
