import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { buildV3QualificationRequest, createV3QualificationReceipt, runV3Qualification } from '../scripts/qualify-solari-v3.mjs';

const resultURL=new URL('../../contracts/v3/solari/examples/basket-research-result.example.json',import.meta.url);

test('V3 qualification receipt is sanitized and truthfully labeled operator-qualification',async()=>{
  const result=JSON.parse(await readFile(resultURL,'utf8'));result.provenance.accessBoundary='operator-qualification';
  const receipt=await createV3QualificationReceipt(result,{
    qualifiedAt:'2026-09-01T15:01:00Z',
    commit:'0123456789abcdef0123456789abcdef01234567',
    workflowRunID:'33520000000',
    workflowRunAttempt:'1'
  });
  assert.deepEqual(receipt.submission,{repository:'EXO-Robotics/smartcart-solari',commit:'0123456789abcdef0123456789abcdef01234567'});
  assert.deepEqual(receipt.workflow,{runID:'33520000000',runAttempt:'1'});
  assert.equal(receipt.execution.resultSha256,createHash('sha256').update(JSON.stringify(result)).digest('hex'));
  assert.equal(receipt.execution.accessBoundary,'operator-qualification');
  assert.equal(receipt.execution.assuranceScope,'server-side-direct-service-receipt');
  assert.equal(receipt.optimizer.policyInvariantsVerified,true);
  assert.equal('independentlyVerified' in receipt.optimizer,false);
  assert.deepEqual(receipt.selectedProductIDs,['dg-chicken-rightsize-1lb','dg-penne-value-16oz','dg-parmesan-value-6oz']);
  assert.equal(receipt.basket.observedSubtotal,13.32);assert.equal(receipt.comparison.surplusAvoidedOunces,16);
  assert.doesNotMatch(JSON.stringify(receipt),/rawText|pageBody|apiKey|operatorToken/);
});

test('V3 qualification digest is derived only from the validated result',async()=>{
  const result=JSON.parse(await readFile(resultURL,'utf8'));result.provenance.accessBoundary='operator-qualification';
  const receipt=await createV3QualificationReceipt(result,{sourceJSON:'{}'});
  assert.equal(receipt.execution.resultSha256,createHash('sha256').update(JSON.stringify(result)).digest('hex'));
  assert.notEqual(receipt.execution.resultSha256,createHash('sha256').update('{}').digest('hex'));
});

test('V3 qualification receipt rejects malformed publication identity instead of inventing it',async()=>{
  const result=JSON.parse(await readFile(resultURL,'utf8'));result.provenance.accessBoundary='operator-qualification';
  const receipt=await createV3QualificationReceipt(result,{commit:'not-a-commit',workflowRunID:'bad value',workflowRunAttempt:'?'});
  assert.deepEqual(receipt.submission,{repository:'EXO-Robotics/smartcart-solari',commit:null});
  assert.deepEqual(receipt.workflow,{runID:null,runAttempt:null});
});

test('V3 qualification never accepts App Attest provenance or runs without server credentials',async()=>{
  const result=JSON.parse(await readFile(resultURL,'utf8'));
  await assert.rejects(()=>createV3QualificationReceipt(result),/must not claim App Attest/);
  await assert.rejects(()=>runV3Qualification({config:{solariApiKey:undefined,solariDemoRetailerBaseUrl:'https://demo.example'},outputPath:'/tmp/not-written'}),/SOLARI_API_KEY/);
});

test('V3 qualification request uses the frozen bounded policy',async()=>{
  const request=await buildV3QualificationRequest({now:new Date('2026-09-01T15:00:00Z'),requestID:'70000000-0000-4000-8000-000000000001'});
  assert.equal(request.schemaVersion,'solari-shopping-research-request-v3');
  assert.equal(request.requestID,'70000000-0000-4000-8000-000000000001');
  assert.deepEqual(request.optimizationPolicy,{objective:'minimize-package-surplus',maxPremiumOverCheapest:0.75,currency:'USD',tieBreak:['observed-subtotal','retailer-product-id']});
  assert.equal(request.requirements.flatMap(({candidateProductIDs})=>candidateProductIDs).length,6);
  const generated=await buildV3QualificationRequest({now:new Date('2026-09-01T15:00:00Z')});
  assert.match(generated.requestID,/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  const normalized=await buildV3QualificationRequest({requestID:'70000000-0000-4000-8000-00000000000A'});
  assert.equal(normalized.requestID,'70000000-0000-4000-8000-00000000000a');
  await assert.rejects(()=>buildV3QualificationRequest({requestID:'qualification-prefixed-id'}),/request ID must be a UUID/);
});
