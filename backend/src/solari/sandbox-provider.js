import { SandboxClient } from '@solarisdk/sandbox';
import {
  bestCandidateSelection,
  materializeSelection,
  summarizeDecisions
} from './optimizer.js';
import { SolariResearchError } from './errors.js';
import { runWithinDeadline, timeoutWithinDeadline } from './deadline.js';

const PYTHON_OPTIMIZER = String.raw`
import json, math, sys
p=json.loads(sys.argv[1]); out=[]
scale={'ounce':1,'pound':16,'count':1}
for r in p['requirements']:
  candidates=[]
  ru={'oz':'ounce','lb':'pound','count':'count'}[r['unit']]
  required=r['requiredQuantity']*scale[ru]
  for o in p['observations']:
    if o['requirementID']!=r['id'] or o['packageQuantity'] is None or o['packageUnit'] is None: continue
    if (ru=='count')!=(o['packageUnit']=='count'): continue
    package=o['packageQuantity']*scale[o['packageUnit']]
    count=math.ceil(required/package); line=None if o['visiblePrice'] is None or o['currency']!='USD' else round(count*o['visiblePrice']+1e-9,2)
    candidates.append((line is None, 0 if line is None else line, count*package-required, o['retailerProductID'], o['observationID'], count))
  if candidates:
    chosen=sorted(candidates)[0]
    out.append({'requirementID':r['id'],'observationID':chosen[4],'packageCount':chosen[5],'lineTotal':None if chosen[0] else chosen[1]})
priced=[x for x in out if x['lineTotal'] is not None]; missing=[x for x in out if x['lineTotal'] is None]
unmatched=len(p['requirements'])-len(out); complete=unmatched==0 and len(missing)==0 and len(priced)==len(p['requirements'])
basket={'completeness':'complete' if complete else 'partial','observedSubtotal':round(sum(x['lineTotal'] for x in priced)+1e-9,2) if priced else None,'currency':'USD' if priced else None,'pricedLineCount':len(priced),'missingPriceLineCount':len(missing),'unmatchedRequirementCount':unmatched}
print(json.dumps({'selections':out,'basket':basket},separators=(',',':')))
`;

function publicPayload(requirements, observations) {
  return {
    requirements: requirements.map(({ id, requiredQuantity, unit }) => ({ id, requiredQuantity, unit })),
    observations: observations.map((observation) => ({
      requirementID: observation.requirementID,
      observationID: observation.observationID,
      retailerProductID: observation.retailerProductID,
      packageQuantity: observation.packageQuantity,
      packageUnit: observation.packageUnit,
      visiblePrice: observation.visiblePrice,
      currency: observation.currency
    }))
  };
}

export class SolariSandboxOptimizer {
  constructor({
    apiKey,
    baseURL = 'https://api.getsolari.com',
    timeoutMs = 10_000,
    clientFactory = (options) => new SandboxClient(options)
  } = {}) {
    this.apiKey = apiKey;
    this.baseURL = baseURL;
    this.timeoutMs = timeoutMs;
    this.clientFactory = clientFactory;
  }

  async optimize(requirements, observations, { deadlineAt, clock = Date.now, signal } = {}) {
    if (!this.apiKey) {
      throw new SolariResearchError('solari_unavailable', 'Solari is unavailable because the server-side API key is not configured.', { status: 503 });
    }
    const client = this.clientFactory({
      apiKey: this.apiKey,
      baseUrl: this.baseURL,
      callTimeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock)
    });
    let sandbox;
    try {
      sandbox = await runWithinDeadline(() => client.create({
        template: 'base',
        timeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock),
        lifecycle: { onTimeout: 'kill', autoResume: false },
        metadata: { purpose: 'smartcart-public-basket-optimization-v1' }
      }), { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal });
      const result = await runWithinDeadline(
        () => sandbox.commands.run('python3', {
          args: ['-c', PYTHON_OPTIMIZER, JSON.stringify(publicPayload(requirements, observations))],
          timeoutMs: timeoutWithinDeadline(this.timeoutMs, deadlineAt, clock)
        }),
        { configuredTimeoutMs: this.timeoutMs, deadlineAt, clock, signal }
      );
      if (result.exitCode !== 0 || result.stderr.trim()) {
        throw new SolariResearchError('solari_sandbox_failed', 'Solari Sandbox could not complete the bounded optimizer.', { status: 502 });
      }
      let remote;
      try { remote = JSON.parse(result.stdout); } catch {
        throw new SolariResearchError('solari_sandbox_invalid_output', 'Solari Sandbox returned invalid optimizer output.', { status: 502 });
      }
      if (!remote || !Array.isArray(remote.selections) || !remote.basket || typeof remote.basket !== 'object') {
        throw new SolariResearchError('solari_sandbox_invalid_output', 'Solari Sandbox omitted the required selection or basket output.', { status: 502 });
      }
      const selectionByRequirement = new Map();
      for (const selection of remote.selections) {
        if (!selection || typeof selection.requirementID !== 'string' || selectionByRequirement.has(selection.requirementID)) {
          throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox returned duplicate or malformed selections.', { status: 502 });
        }
        selectionByRequirement.set(selection.requirementID, selection);
      }
      const expectedCount = requirements.filter((requirement) => bestCandidateSelection(requirement, observations) !== null).length;
      if (remote.selections.length !== expectedCount) {
        throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox did not return exactly one selection for each matchable requirement.', { status: 502 });
      }
      const decisions = requirements.flatMap((requirement) => {
        const selection = selectionByRequirement.get(requirement.id);
        const expected = bestCandidateSelection(requirement, observations);
        if (selection === undefined && expected === null) return [];
        if (JSON.stringify(selection) !== JSON.stringify(expected)) {
          throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox selection was not the lowest-cost adequate admitted candidate.', { status: 502 });
        }
        const observation = observations.find(({ observationID }) => observationID === selection.observationID);
        const decision = observation
          ? materializeSelection(requirement, observation, selection)
          : null;
        if (!decision) {
          throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox selected evidence that failed package or price invariants.', { status: 502 });
        }
        return [decision];
      });
      const verified = summarizeDecisions(requirements, decisions, 'solari-sandbox');
      if (JSON.stringify(remote.basket) !== JSON.stringify(verified.basket)) {
        throw new SolariResearchError('solari_sandbox_invariant_failed', 'Solari Sandbox basket summary failed independent arithmetic verification.', { status: 502 });
      }
      return verified;
    } finally {
      if (sandbox) {
        try {
          await sandbox.kill();
        } catch {
          throw new SolariResearchError(
            'solari_sandbox_cleanup_failed',
            'Solari Sandbox cleanup was not confirmed.',
            { status: 502 }
          );
        }
      }
    }
  }
}
