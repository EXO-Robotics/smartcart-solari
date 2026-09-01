import { SandboxClient } from '@solarisdk/sandbox';
import { acquireWithinDeadline, runWithinDeadline, timeoutWithinDeadline } from './deadline.js';
import { SolariResearchError } from './errors.js';

const PYTHON_V4_OPTIMIZER = String.raw`
import json, math, sys
from decimal import Decimal, ROUND_HALF_UP
p=json.loads(sys.argv[1]); groups=[]
expected={'g':'gram','ml':'milliliter','count':'count'}
def cents(value): return int((Decimal(str(value))*Decimal(100)).quantize(Decimal('1'),rounding=ROUND_HALF_UP))
def rounded(value): return round(value+1e-12,6)
for r in p['requirements']:
  candidates=[]
  for o in p['observations']:
    if o['requirementID']!=r['id'] or o['freshness']!='fresh' or o['packageQuantity'] is None or o['packageUnit']!=expected[r['unit']] or o['visiblePrice'] is None or o['currency']!='USD': continue
    count=math.ceil((r['requiredQuantity']/o['packageQuantity'])-1e-12)
    covered=count*o['packageQuantity']; line_cents=count*cents(o['visiblePrice'])
    candidates.append({'requirementID':r['id'],'observationID':o['observationID'],'retailerProductID':o['retailerProductID'],'packageCount':count,'lineTotalCents':line_cents,'relativeSurplus':rounded((covered-r['requiredQuantity'])/r['requiredQuantity'])})
  if not candidates: raise ValueError('no adequate priced candidate')
  candidates.sort(key=lambda x:(x['lineTotalCents'],x['retailerProductID']))
  groups.append((candidates,candidates[0]))
baseline=sum(base['lineTotalCents'] for _,base in groups)
limit=int((Decimal(str(p['optimizationPolicy']['maxPremiumOverCheapest']))*Decimal(100)).quantize(Decimal('1'),rounding=ROUND_HALF_UP))
states={0:{'selections':[],'surplus':0.0,'ids':[]}}
for candidates,base in groups:
  next_states={}
  for used,state in states.items():
    for candidate in candidates:
      premium=used+candidate['lineTotalCents']-base['lineTotalCents']
      if premium<0 or premium>limit: continue
      value={'selections':state['selections']+[candidate],'surplus':state['surplus']+candidate['relativeSurplus'],'ids':state['ids']+[candidate['retailerProductID']]}
      old=next_states.get(premium)
      if old is None or (rounded(value['surplus']),value['ids'])<(rounded(old['surplus']),old['ids']): next_states[premium]=value
  states=next_states
selected_premium,selected=min(states.items(),key=lambda item:(rounded(item[1]['surplus']),baseline+item[0],item[1]['ids']))
references=[base for _,base in groups]
def public(xs): return [{k:(v/100 if k=='lineTotalCents' else v) for k,v in x.items() if k not in ('relativeSurplus',) and k!='lineTotalCents'}|{'lineTotal':x['lineTotalCents']/100} for x in xs]
cheapest_surplus=rounded(sum(x['relativeSurplus'] for x in references)); selected_surplus=rounded(selected['surplus'])
comparison={'cheapestAdequateSubtotal':baseline/100,'selectedSubtotal':(baseline+selected_premium)/100,'premiumOverCheapest':selected_premium/100,'cheapestAggregateRelativeSurplus':cheapest_surplus,'selectedAggregateRelativeSurplus':selected_surplus,'relativeSurplusAvoided':rounded(cheapest_surplus-selected_surplus),'maxPremiumOverCheapest':p['optimizationPolicy']['maxPremiumOverCheapest'],'currency':'USD'}
print(json.dumps({'selections':public(selected['selections']),'cheapestReferenceSelections':public(references),'comparison':comparison},separators=(',',':')))
`;

const EXPECTED_UNIT = Object.freeze({ g: 'gram', ml: 'milliliter', count: 'count' });
const round = (value, places = 6) => Math.round((value + Number.EPSILON) * (10 ** places)) / (10 ** places);

function candidateFacts(requirement, observation) {
  if (observation?.requirementID !== requirement.id || observation.freshness?.status !== 'fresh') return null;
  const admitted = requirement.candidates?.find(({ retailerProductID, sourceURL }) =>
    retailerProductID === observation.retailerProductID && sourceURL === observation.sourceURL);
  if (!admitted || observation.packageQuantity === null || observation.packageUnit !== EXPECTED_UNIT[requirement.unit]
    || observation.visiblePrice === null || observation.currency !== 'USD') return null;
  const required = requirement.requiredQuantity;
  const packageQuantity = observation.packageQuantity;
  if (!Number.isFinite(required) || required <= 0 || !Number.isFinite(packageQuantity) || packageQuantity <= 0) return null;
  const packageCount = Math.ceil((required / packageQuantity) - 1e-12);
  const coveredQuantity = round(packageCount * packageQuantity);
  return {
    packageCount,
    coveredQuantity,
    surplusQuantity: round(coveredQuantity - required),
    relativeSurplus: round((coveredQuantity - required) / required),
    lineTotal: round(packageCount * observation.visiblePrice, 2)
  };
}

function assertSelection(requirement, observation, selection) {
  const facts = candidateFacts(requirement, observation);
  if (!facts || selection?.requirementID !== requirement.id || selection.observationID !== observation.observationID
    || selection.retailerProductID !== observation.retailerProductID || selection.packageCount !== facts.packageCount
    || selection.lineTotal !== facts.lineTotal) {
    throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox selected V4 evidence that failed admitted coverage, dimensions, or package arithmetic.', { status: 502 });
  }
  return facts;
}

function selectionMap(selections, requirements, label) {
  if (!Array.isArray(selections) || selections.length !== requirements.length) {
    throw new SolariResearchError('solari_sandbox_invariant_failed', `Solari Sandbox omitted the V4 ${label} basket.`, { status: 502 });
  }
  const map = new Map();
  for (const selection of selections) {
    if (!selection || typeof selection.requirementID !== 'string' || map.has(selection.requirementID)) {
      throw new SolariResearchError('solari_sandbox_invariant_failed', `Solari Sandbox returned malformed V4 ${label} selections.`, { status: 502 });
    }
    map.set(selection.requirementID, selection);
  }
  return map;
}

function publicPayload(requirements, observations, optimizationPolicy) {
  return {
    optimizationPolicy,
    requirements: requirements.map(({ id, requiredQuantity, unit }) => ({ id, requiredQuantity, unit })),
    observations: observations.map((observation) => ({
      requirementID: observation.requirementID, observationID: observation.observationID,
      retailerProductID: observation.retailerProductID, packageQuantity: observation.packageQuantity,
      packageUnit: observation.packageUnit, visiblePrice: observation.visiblePrice,
      currency: observation.currency, freshness: observation.freshness.status
    }))
  };
}

export class SolariV4SandboxOptimizer {
  constructor({ apiKey, baseURL = 'https://api.getsolari.com', timeoutMs = 10_000, clientFactory = (options) => new SandboxClient(options) } = {}) {
    this.apiKey = apiKey; this.baseURL = baseURL; this.timeoutMs = timeoutMs; this.clientFactory = clientFactory;
  }

  async optimize(requirements, observations, optimizationPolicy, { deadlineAt, clock = Date.now, signal } = {}) {
    if (!this.apiKey) throw new SolariResearchError('solari_unavailable', 'Solari is unavailable because the server-side API key is not configured.', { status: 503 });
    const client = this.clientFactory({ apiKey: this.apiKey, baseUrl: this.baseURL, callTimeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock) });
    let sandbox;
    try {
      sandbox = await acquireWithinDeadline(() => client.create({
        template: 'base', timeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock),
        lifecycle: { onTimeout: 'kill', autoResume: false }, metadata: { purpose: 'smartcart-owned-demo-relative-surplus-policy-v4' }
      }), async (lateSandbox) => { await lateSandbox.kill(); }, { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal });
      const result = await runWithinDeadline(() => sandbox.commands.run('python3', {
        args: ['-c', PYTHON_V4_OPTIMIZER, JSON.stringify(publicPayload(requirements, observations, optimizationPolicy))],
        timeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock)
      }), { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal });
      if (result.exitCode !== 0 || result.stderr.trim()) throw new SolariResearchError('solari_sandbox_failed', 'Solari Sandbox could not complete the bounded V4 optimizer.', { status: 502 });
      let remote;
      try { remote = JSON.parse(result.stdout); } catch { throw new SolariResearchError('solari_sandbox_invalid_output', 'Solari Sandbox returned invalid V4 optimizer output.', { status: 502 }); }

      const selectedByRequirement = selectionMap(remote?.selections, requirements, 'selected');
      const cheapestByRequirement = selectionMap(remote?.cheapestReferenceSelections, requirements, 'cheapest reference');
      const observationsByID = new Map(observations.map((observation) => [observation.observationID, observation]));
      const decisions = [], referenceFacts = [];
      for (const requirement of requirements) {
        const selection = selectedByRequirement.get(requirement.id);
        const observation = observationsByID.get(selection?.observationID);
        const facts = assertSelection(requirement, observation, selection);
        const reference = cheapestByRequirement.get(requirement.id);
        const referenceObservation = observationsByID.get(reference?.observationID);
        const cheapestFacts = assertSelection(requirement, referenceObservation, reference);
        for (const candidate of observations.filter(({ requirementID }) => requirementID === requirement.id)) {
          const candidateValue = candidateFacts(requirement, candidate);
          if (candidateValue && (candidateValue.lineTotal < cheapestFacts.lineTotal
            || (candidateValue.lineTotal === cheapestFacts.lineTotal && candidate.retailerProductID.localeCompare(referenceObservation.retailerProductID) < 0))) {
            throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox V4 cheapest reference is not the stable lowest-price adequate reference.', { status: 502 });
          }
        }
        referenceFacts.push(cheapestFacts);
        decisions.push({
          schemaVersion: 'basket-decision-v4', requirementID: requirement.id, observationID: observation.observationID,
          retailerProductID: observation.retailerProductID, packageCount: facts.packageCount,
          requiredQuantity: requirement.requiredQuantity, coveredQuantity: facts.coveredQuantity,
          quantityUnit: observation.packageUnit, surplusQuantity: facts.surplusQuantity, relativeSurplus: facts.relativeSurplus,
          lineTotal: facts.lineTotal, currency: 'USD', proteinGramsPerDollar: null,
          substitutionNote: observation.ambiguityReasons.length ? observation.ambiguityReasons[0] : null,
          rationale: [`${facts.packageCount} package${facts.packageCount === 1 ? ' covers' : 's cover'} the reviewed requirement.`, 'Solari Sandbox selected this line under the bounded relative-surplus-within-price-cap policy.'],
          confidence: observation.confidence, ambiguityReasons: [...observation.ambiguityReasons]
        });
      }
      const selectedSubtotal = round(decisions.reduce((sum, decision) => sum + decision.lineTotal, 0), 2);
      const cheapestAdequateSubtotal = round(referenceFacts.reduce((sum, facts) => sum + facts.lineTotal, 0), 2);
      const selectedAggregateRelativeSurplus = round(decisions.reduce((sum, decision) => sum + decision.relativeSurplus, 0));
      const cheapestAggregateRelativeSurplus = round(referenceFacts.reduce((sum, facts) => sum + facts.relativeSurplus, 0));
      const comparison = {
        cheapestAdequateSubtotal, selectedSubtotal,
        premiumOverCheapest: round(selectedSubtotal - cheapestAdequateSubtotal, 2),
        cheapestAggregateRelativeSurplus, selectedAggregateRelativeSurplus,
        relativeSurplusAvoided: round(cheapestAggregateRelativeSurplus - selectedAggregateRelativeSurplus),
        maxPremiumOverCheapest: optimizationPolicy.maxPremiumOverCheapest, currency: 'USD'
      };
      if (comparison.premiumOverCheapest < 0 || comparison.premiumOverCheapest > optimizationPolicy.maxPremiumOverCheapest
        || comparison.relativeSurplusAvoided < 0 || JSON.stringify(remote.comparison) !== JSON.stringify(comparison)) {
        throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox V4 comparison or premium-cap arithmetic failed verification.', { status: 502 });
      }
      return {
        decisions,
        basket: { completeness: 'complete', observedSubtotal: selectedSubtotal, currency: 'USD', pricedLineCount: decisions.length, missingPriceLineCount: 0, unmatchedRequirementCount: 0 },
        comparison,
        optimizer: { method: 'solari-sandbox', algorithmVersion: 'relative-surplus-premium-dp-v1', objective: 'minimize-aggregate-relative-surplus', authority: 'solari-sandbox', verification: 'smartcart-policy-invariants-no-local-global-argmin', policyInvariantsVerified: true }
      };
    } finally {
      if (sandbox) {
        try { await sandbox.kill(); } catch { throw new SolariResearchError('solari_sandbox_cleanup_failed', 'Solari Sandbox cleanup was not confirmed.', { status: 502 }); }
      }
    }
  }
}
