const UNIT_TO_OUNCES = Object.freeze({ ounce: 1, pound: 16 });

function round(value, places = 4) {
  const scale = 10 ** places;
  return Math.round((value + Number.EPSILON) * scale) / scale;
}

function requirementUnit(unit) {
  return unit === 'lb' ? 'pound' : unit === 'oz' ? 'ounce' : unit;
}

function baseQuantity(value, unit) {
  if (unit === 'count') return value;
  const scale = UNIT_TO_OUNCES[unit];
  return scale ? value * scale : null;
}

function candidateFor(requirement, observation, { allowStale }) {
  if (observation.requirementID !== requirement.id) return null;
  if (!allowStale && observation.freshness.status !== 'fresh') return null;
  if (observation.packageQuantity === null || observation.packageUnit === null) return null;
  const requestedUnit = requirementUnit(requirement.unit);
  const requiredBase = baseQuantity(requirement.requiredQuantity, requestedUnit);
  const packageBase = baseQuantity(observation.packageQuantity, observation.packageUnit);
  if (requiredBase === null || packageBase === null) return null;
  if ((requestedUnit === 'count') !== (observation.packageUnit === 'count')) return null;
  const packageCount = Math.ceil(requiredBase / packageBase);
  const coveredBase = packageCount * packageBase;
  const admittedPrice = observation.currency === 'USD' ? observation.visiblePrice : null;
  const lineTotal = admittedPrice === null
    ? null
    : round(packageCount * admittedPrice, 2);
  return {
    observation,
    packageCount,
    requiredBase,
    coveredBase,
    surplusBase: round(coveredBase - requiredBase),
    lineTotal
  };
}

function compareCandidates(lhs, rhs) {
  if ((lhs.lineTotal === null) !== (rhs.lineTotal === null)) return lhs.lineTotal === null ? 1 : -1;
  if (lhs.lineTotal !== null && lhs.lineTotal !== rhs.lineTotal) return lhs.lineTotal - rhs.lineTotal;
  if (lhs.surplusBase !== rhs.surplusBase) return lhs.surplusBase - rhs.surplusBase;
  return lhs.observation.retailerProductID.localeCompare(rhs.observation.retailerProductID);
}

export function bestCandidateSelection(requirement, observations, { allowStale = false } = {}) {
  const selected = observations
    .map((observation) => candidateFor(requirement, observation, { allowStale }))
    .filter(Boolean)
    .sort(compareCandidates)[0];
  return selected ? {
    requirementID: requirement.id,
    observationID: selected.observation.observationID,
    packageCount: selected.packageCount,
    lineTotal: selected.lineTotal
  } : null;
}

function decisionFromCandidate(requirement, selected) {
  const { observation } = selected;
  return {
    schemaVersion: 'basket-decision-v1',
    requirementID: requirement.id,
    observationID: observation.observationID,
    packageCount: selected.packageCount,
    requiredQuantity: requirement.requiredQuantity,
    coveredQuantity: round(observation.packageQuantity * selected.packageCount),
    quantityUnit: observation.packageUnit,
    surplusQuantity: observation.packageUnit === 'pound'
      ? round(selected.surplusBase / 16)
      : selected.surplusBase,
    lineTotal: selected.lineTotal,
    currency: selected.lineTotal === null ? null : 'USD',
    proteinGramsPerDollar: null,
    substitutionNote: observation.ambiguityReasons.length > 0 ? observation.ambiguityReasons[0] : null,
    rationale: [
      `${selected.packageCount} package${selected.packageCount === 1 ? '' : 's'} cover the reviewed requirement.`,
      selected.lineTotal === null
        ? 'No visible price was observed, so this line is excluded from the priced subtotal.'
        : 'Among admitted candidates with visible prices, this is the lowest observed adequate line total.'
    ],
    confidence: observation.confidence,
    ambiguityReasons: [...observation.ambiguityReasons]
  };
}

export function summarizeDecisions(requirements, decisions, method) {
  const priced = decisions.filter(({ lineTotal }) => lineTotal !== null);
  const missing = decisions.filter(({ lineTotal }) => lineTotal === null);
  const pricedSubtotal = priced.reduce((sum, decision) => round(sum + decision.lineTotal, 2), 0);
  const unmatchedRequirementCount = requirements.length - decisions.length;
  const complete = unmatchedRequirementCount === 0 && missing.length === 0 && priced.length === requirements.length;
  return {
    decisions,
    basket: {
      completeness: complete ? 'complete' : 'partial',
      observedSubtotal: priced.length > 0 ? pricedSubtotal : null,
      currency: priced.length > 0 ? 'USD' : null,
      pricedLineCount: priced.length,
      missingPriceLineCount: missing.length,
      unmatchedRequirementCount
    },
    optimizer: {
      method,
      algorithmVersion: 'smallest-sufficient-package-v1',
      independentlyVerified: method === 'solari-sandbox'
    }
  };
}

export function materializeSelection(requirement, observation, selection) {
  const candidate = candidateFor(requirement, observation, { allowStale: false });
  if (!candidate || candidate.packageCount !== selection.packageCount || candidate.lineTotal !== selection.lineTotal) return null;
  return decisionFromCandidate(requirement, candidate);
}

export function deterministicOptimize(requirements, observations, {
  allowStale = false,
  method = 'smartcart-deterministic-fixture-replay'
} = {}) {
  const decisions = [];
  for (const requirement of requirements) {
    const candidates = observations
      .map((observation) => candidateFor(requirement, observation, { allowStale }))
      .filter(Boolean)
      .sort(compareCandidates);
    const selected = candidates[0];
    if (!selected) continue;
    decisions.push(decisionFromCandidate(requirement, selected));
  }
  return summarizeDecisions(requirements, decisions, method);
}

export function optimizerFingerprint(result) {
  return JSON.stringify({
    selections: result.decisions.map((decision) => ({
      requirementID: decision.requirementID,
      observationID: decision.observationID,
      packageCount: decision.packageCount,
      lineTotal: decision.lineTotal
    })),
    basket: result.basket
  });
}
