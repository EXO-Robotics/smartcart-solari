import { SandboxClient } from '@solarisdk/sandbox';
import { acquireWithinDeadline, runWithinDeadline, timeoutWithinDeadline } from './deadline.js';
import { SolariResearchError } from './errors.js';

const PYTHON_V3_OPTIMIZER = String.raw`
import itertools, json, math, sys
p=json.loads(sys.argv[1]); scale={'ounce':1,'pound':16,'count':1}; groups=[]
for r in p['requirements']:
  ru={'oz':'ounce','lb':'pound','count':'count'}[r['unit']]; required=r['requiredQuantity']*scale[ru]; candidates=[]
  for o in p['observations']:
    if o['requirementID']!=r['id'] or o['freshness']!='fresh' or o['packageQuantity'] is None or o['packageUnit'] is None or o['visiblePrice'] is None or o['currency']!='USD': continue
    if (ru=='count')!=(o['packageUnit']=='count'): continue
    package=o['packageQuantity']*scale[o['packageUnit']]; count=math.ceil(required/package)
    candidates.append({'requirementID':r['id'],'observationID':o['observationID'],'retailerProductID':o['retailerProductID'],'packageCount':count,'lineTotal':round(count*o['visiblePrice']+1e-9,2),'surplusOunces':round(count*package-required,4)})
  if not candidates: raise ValueError('no adequate priced candidate')
  groups.append(candidates)
baskets=[]
for combo in itertools.product(*groups):
  baskets.append({'selections':list(combo),'subtotal':round(sum(x['lineTotal'] for x in combo)+1e-9,2),'surplus':round(sum(x['surplusOunces'] for x in combo),4),'ids':[x['retailerProductID'] for x in combo]})
cheapest=sorted(baskets,key=lambda x:(x['subtotal'],x['ids']))[0]
cap=round(cheapest['subtotal']+p['optimizationPolicy']['maxPremiumOverCheapest']+1e-9,2)
eligible=[x for x in baskets if x['subtotal']<=cap]
selected=sorted(eligible,key=lambda x:(x['surplus'],x['subtotal'],x['ids']))[0]
def public(xs): return [{k:v for k,v in x.items() if k!='surplusOunces'} for x in xs]
comparison={'cheapestAdequateSubtotal':cheapest['subtotal'],'selectedSubtotal':selected['subtotal'],'premiumOverCheapest':round(selected['subtotal']-cheapest['subtotal']+1e-9,2),'cheapestAggregateSurplusOunces':cheapest['surplus'],'selectedAggregateSurplusOunces':selected['surplus'],'surplusAvoidedOunces':round(cheapest['surplus']-selected['surplus'],4),'maxPremiumOverCheapest':p['optimizationPolicy']['maxPremiumOverCheapest'],'currency':'USD'}
print(json.dumps({'selections':public(selected['selections']),'cheapestReferenceSelections':public(cheapest['selections']),'comparison':comparison},separators=(',',':')))
`;

const UNIT_SCALE = Object.freeze({ ounce: 1, pound: 16, count: 1 });
const round = (value, places = 4) => Math.round((value + Number.EPSILON) * (10 ** places)) / (10 ** places);
const requestedUnit = (unit) => unit === 'lb' ? 'pound' : unit === 'oz' ? 'ounce' : unit;

function candidateFacts(requirement, observation) {
  if (observation.requirementID !== requirement.id || observation.freshness?.status !== 'fresh') return null;
  const candidates = requirement.candidates ?? requirement.candidateProductIDs?.map((retailerProductID) => ({ retailerProductID }));
  const admitted = candidates?.find(({ retailerProductID }) => retailerProductID === observation.retailerProductID);
  if (!admitted || (admitted.sourceURL && admitted.sourceURL !== observation.sourceURL)) return null;
  if (observation.packageQuantity === null || observation.packageUnit === null || observation.visiblePrice === null || observation.currency !== 'USD') return null;
  const unit = requestedUnit(requirement.unit);
  if ((unit === 'count') !== (observation.packageUnit === 'count')) return null;
  const requiredBase = requirement.requiredQuantity * UNIT_SCALE[unit];
  const packageBase = observation.packageQuantity * UNIT_SCALE[observation.packageUnit];
  if (!Number.isFinite(requiredBase) || !Number.isFinite(packageBase) || packageBase <= 0) return null;
  const packageCount = Math.ceil(requiredBase / packageBase);
  return {
    packageCount,
    coveredQuantity: round(observation.packageQuantity * packageCount),
    surplusQuantity: observation.packageUnit === 'pound' ? round((packageCount * packageBase - requiredBase) / 16) : round(packageCount * packageBase - requiredBase),
    surplusOunces: round(packageCount * packageBase - requiredBase),
    lineTotal: round(packageCount * observation.visiblePrice, 2)
  };
}

function assertSelection(requirement, observation, selection) {
  const facts = observation ? candidateFacts(requirement, observation) : null;
  if (!facts || selection.requirementID !== requirement.id || selection.observationID !== observation.observationID || selection.retailerProductID !== observation.retailerProductID || selection.packageCount !== facts.packageCount || selection.lineTotal !== facts.lineTotal) {
    throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox selected evidence that failed admitted coverage or arithmetic invariants.', { status: 502 });
  }
  return facts;
}

function publicPayload(requirements, observations, optimizationPolicy) {
  return {
    optimizationPolicy,
    requirements: requirements.map(({ id, requiredQuantity, unit }) => ({ id, requiredQuantity, unit })),
    observations: observations.map((observation) => ({
      requirementID: observation.requirementID,
      observationID: observation.observationID,
      retailerProductID: observation.retailerProductID,
      packageQuantity: observation.packageQuantity,
      packageUnit: observation.packageUnit,
      visiblePrice: observation.visiblePrice,
      currency: observation.currency,
      freshness: observation.freshness.status
    }))
  };
}

function selectionMap(selections, requirements, label) {
  if (!Array.isArray(selections) || selections.length !== requirements.length) throw new SolariResearchError('solari_sandbox_invariant_failed', `Solari Sandbox omitted the ${label} basket.`, { status: 502 });
  const map = new Map();
  for (const selection of selections) {
    if (!selection || typeof selection.requirementID !== 'string' || map.has(selection.requirementID)) throw new SolariResearchError('solari_sandbox_invariant_failed', `Solari Sandbox returned malformed ${label} selections.`, { status: 502 });
    map.set(selection.requirementID, selection);
  }
  return map;
}

export class SolariV3SandboxOptimizer {
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
        lifecycle: { onTimeout: 'kill', autoResume: false }, metadata: { purpose: 'smartcart-owned-demo-surplus-policy-v3' }
      }), async (lateSandbox) => { await lateSandbox.kill(); }, { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal });
      const result = await runWithinDeadline(() => sandbox.commands.run('python3', {
        args: ['-c', PYTHON_V3_OPTIMIZER, JSON.stringify(publicPayload(requirements, observations, optimizationPolicy))],
        timeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock)
      }), { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal });
      if (result.exitCode !== 0 || result.stderr.trim()) throw new SolariResearchError('solari_sandbox_failed', 'Solari Sandbox could not complete the bounded V3 optimizer.', { status: 502 });
      let remote;
      try { remote = JSON.parse(result.stdout); } catch { throw new SolariResearchError('solari_sandbox_invalid_output', 'Solari Sandbox returned invalid V3 optimizer output.', { status: 502 }); }
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
          if (candidateValue && (candidateValue.lineTotal < cheapestFacts.lineTotal || (candidateValue.lineTotal === cheapestFacts.lineTotal && candidate.retailerProductID.localeCompare(referenceObservation.retailerProductID) < 0))) {
            throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox cheapest reference is not the stable lowest-price adequate reference.', { status: 502 });
          }
        }
        referenceFacts.push(cheapestFacts);
        decisions.push({
          schemaVersion: 'basket-decision-v3', requirementID: requirement.id, observationID: observation.observationID,
          packageCount: facts.packageCount, requiredQuantity: requirement.requiredQuantity, coveredQuantity: facts.coveredQuantity,
          quantityUnit: observation.packageUnit, surplusQuantity: facts.surplusQuantity, surplusOunces: facts.surplusOunces,
          lineTotal: facts.lineTotal, currency: 'USD', proteinGramsPerDollar: null,
          substitutionNote: observation.ambiguityReasons.length ? observation.ambiguityReasons[0] : null,
          rationale: [`${facts.packageCount} package${facts.packageCount === 1 ? '' : 's'} cover the reviewed requirement.`, 'Solari Sandbox selected this line under the bounded surplus-within-price-cap policy.'],
          confidence: observation.confidence, ambiguityReasons: [...observation.ambiguityReasons]
        });
      }
      const selectedSubtotal = round(decisions.reduce((sum, decision) => sum + decision.lineTotal, 0), 2);
      const cheapestAdequateSubtotal = round(referenceFacts.reduce((sum, facts) => sum + facts.lineTotal, 0), 2);
      const selectedAggregateSurplusOunces = round(decisions.reduce((sum, decision) => sum + decision.surplusOunces, 0));
      const cheapestAggregateSurplusOunces = round(referenceFacts.reduce((sum, facts) => sum + facts.surplusOunces, 0));
      const comparison = {
        cheapestAdequateSubtotal, selectedSubtotal,
        premiumOverCheapest: round(selectedSubtotal - cheapestAdequateSubtotal, 2),
        cheapestAggregateSurplusOunces, selectedAggregateSurplusOunces,
        surplusAvoidedOunces: round(cheapestAggregateSurplusOunces - selectedAggregateSurplusOunces),
        maxPremiumOverCheapest: optimizationPolicy.maxPremiumOverCheapest, currency: 'USD'
      };
      if (comparison.premiumOverCheapest < 0 || comparison.premiumOverCheapest > optimizationPolicy.maxPremiumOverCheapest || JSON.stringify(remote.comparison) !== JSON.stringify(comparison)) {
        throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox comparison or premium-cap arithmetic failed verification.', { status: 502 });
      }
      return {
        decisions,
        basket: { completeness: 'complete', observedSubtotal: selectedSubtotal, currency: 'USD', pricedLineCount: decisions.length, missingPriceLineCount: 0, unmatchedRequirementCount: requirements.length - decisions.length },
        comparison,
        optimizer: { method: 'solari-sandbox', algorithmVersion: 'surplus-within-price-cap-v1', objective: 'minimize-package-surplus', authority: 'solari-sandbox', verification: 'smartcart-policy-invariants-no-local-global-argmin', policyInvariantsVerified: true }
      };
    } finally {
      if (sandbox) {
        try { await sandbox.kill(); } catch { throw new SolariResearchError('solari_sandbox_cleanup_failed', 'Solari Sandbox cleanup was not confirmed.', { status: 502 }); }
      }
    }
  }
}
