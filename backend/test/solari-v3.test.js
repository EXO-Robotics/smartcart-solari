import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { promisify } from 'node:util';
import { SolariV3SandboxOptimizer } from '../src/solari/v3-sandbox-provider.js';

const root = new URL('../../contracts/v3/solari/examples/', import.meta.url);
const request = JSON.parse(await readFile(new URL('basket-research-request.example.json', root), 'utf8'));
const result = JSON.parse(await readFile(new URL('basket-research-result.example.json', root), 'utf8'));
const execFileAsync=promisify(execFile);

function cheapestReferences() {
  return [
    {requirementID:request.requirements[0].id,observationID:result.observations[0].observationID,retailerProductID:'dg-chicken-value-3lb',packageCount:1,lineTotal:9.47},
    {requirementID:request.requirements[1].id,observationID:result.observations[2].observationID,retailerProductID:'dg-penne-value-16oz',packageCount:1,lineTotal:1.24},
    {requirementID:request.requirements[2].id,observationID:result.observations[4].observationID,retailerProductID:'dg-parmesan-value-6oz',packageCount:1,lineTotal:2.08}
  ];
}

function optimizerFor(remote, onKill = () => {}) {
  return new SolariV3SandboxOptimizer({apiKey:'server-only',clientFactory:()=>({create:async()=>({
    commands:{run:async()=>({exitCode:0,stderr:'',stdout:JSON.stringify(remote)})},
    kill:async()=>onKill()
  })})});
}

test('V3 Sandbox program computes the expected policy basket from the six structured observations',async()=>{
  let kills=0;
  const optimizer=new SolariV3SandboxOptimizer({apiKey:'server-only',clientFactory:()=>({create:async()=>({
    commands:{run:async(command,{args})=>{const{stdout,stderr}=await execFileAsync(command,args);return{exitCode:0,stdout,stderr};}},
    kill:async()=>{kills+=1;}
  })})});
  const optimized=await optimizer.optimize(request.requirements,result.observations,request.optimizationPolicy);
  assert.deepEqual(optimized.decisions.map(({observationID,packageCount})=>({observationID,packageCount})),[
    {observationID:'obs-60000000-0000-4000-8000-000000000001-dg-chicken-rightsize-1lb',packageCount:2},
    {observationID:'obs-60000000-0000-4000-8000-000000000001-dg-penne-value-16oz',packageCount:1},
    {observationID:'obs-60000000-0000-4000-8000-000000000001-dg-parmesan-value-6oz',packageCount:1}
  ]);
  assert.deepEqual(optimized.comparison,result.comparison);assert.equal(kills,1);
});

test('V3 SmartCart verifier accepts a feasible Sandbox choice without recomputing the global surplus optimum',async()=>{
  let kills=0;
  const remote={
    selections:[
      cheapestReferences()[0],
      {requirementID:request.requirements[1].id,observationID:result.observations[3].observationID,retailerProductID:'dg-penne-rightsize-12oz',packageCount:1,lineTotal:1.65},
      cheapestReferences()[2]
    ],
    cheapestReferenceSelections:cheapestReferences(),
    comparison:{cheapestAdequateSubtotal:12.79,selectedSubtotal:13.2,premiumOverCheapest:0.41,cheapestAggregateSurplusOunces:31,selectedAggregateSurplusOunces:27,surplusAvoidedOunces:4,maxPremiumOverCheapest:0.75,currency:'USD'}
  };
  const optimized=await optimizerFor(remote,()=>{kills+=1;}).optimize(request.requirements,result.observations,request.optimizationPolicy);
  assert.equal(optimized.basket.observedSubtotal,13.2);
  assert.equal(optimized.decisions[1].observationID,result.observations[3].observationID);
  assert.equal(kills,1);
});

test('V3 verifier rejects stale evidence, invalid package math, false cheapest reference, and premium overflow',async()=>{
  const canonical={
    selections:[
      {requirementID:request.requirements[0].id,observationID:result.observations[1].observationID,retailerProductID:'dg-chicken-rightsize-1lb',packageCount:2,lineTotal:10},
      cheapestReferences()[1],cheapestReferences()[2]
    ],
    cheapestReferenceSelections:cheapestReferences(),comparison:result.comparison
  };
  const stale=structuredClone(result.observations);stale[1].freshness.status='stale';
  await assert.rejects(()=>optimizerFor(canonical).optimize(request.requirements,stale,request.optimizationPolicy),{code:'solari_sandbox_invariant_failed'});
  const badCount=structuredClone(canonical);badCount.selections[0].packageCount=1;
  await assert.rejects(()=>optimizerFor(badCount).optimize(request.requirements,result.observations,request.optimizationPolicy),{code:'solari_sandbox_invariant_failed'});
  const falseCheapest=structuredClone(canonical);falseCheapest.cheapestReferenceSelections[0]=falseCheapest.selections[0];
  await assert.rejects(()=>optimizerFor(falseCheapest).optimize(request.requirements,result.observations,request.optimizationPolicy),{code:'solari_sandbox_invariant_failed'});
  const overCap=structuredClone(canonical);
  overCap.selections[1]={requirementID:request.requirements[1].id,observationID:result.observations[3].observationID,retailerProductID:'dg-penne-rightsize-12oz',packageCount:1,lineTotal:1.65};
  overCap.comparison={...result.comparison,selectedSubtotal:13.73,premiumOverCheapest:0.94,selectedAggregateSurplusOunces:11,surplusAvoidedOunces:20};
  await assert.rejects(()=>optimizerFor(overCap).optimize(request.requirements,result.observations,request.optimizationPolicy),{code:'solari_sandbox_invariant_failed'});
});

test('V3 optimizer source has no local deterministic optimizer fallback or global selection comparator',async()=>{
  const source=await readFile(new URL('../src/solari/v3-sandbox-provider.js',import.meta.url),'utf8');
  assert.doesNotMatch(source,/deterministicOptimize|bestCandidateSelection|compareCandidates|optimizerFingerprint/);
  assert.match(source,/authority: 'solari-sandbox'/);
});
