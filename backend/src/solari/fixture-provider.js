import {
  FIXTURE_OBSERVED_AT,
  FIXTURE_PRODUCTS,
  MAX_OBSERVATION_AGE_SECONDS
} from './constants.js';

function freshness(observedAt, now, maxAgeSeconds = MAX_OBSERVATION_AGE_SECONDS) {
  const timestamp = Date.parse(observedAt);
  const current = now();
  if (!Number.isFinite(timestamp) || !Number.isFinite(current)) {
    return { status: 'unknown', ageSeconds: null, maxAgeSeconds };
  }
  if (timestamp > current + 300_000) return { status: 'future', ageSeconds: 0, maxAgeSeconds };
  const ageSeconds = Math.max(0, Math.floor((current - timestamp) / 1000));
  return { status: ageSeconds <= maxAgeSeconds ? 'fresh' : 'stale', ageSeconds, maxAgeSeconds };
}

export class WalmartFixtureReplayProvider {
  constructor({ now = Date.now } = {}) { this.now = now; }

  async observe(request) {
    return request.requirements.flatMap((requirement) => requirement.candidates.map((candidate) => {
      const fixture = FIXTURE_PRODUCTS[candidate.retailerProductID];
      return {
        schemaVersion: 'retailer-observation-v1',
        observationID: `obs-walmart-${candidate.retailerProductID}`,
        requirementID: requirement.id,
        retailerProductID: candidate.retailerProductID,
        sourceURL: candidate.sourceURL,
        title: fixture.title,
        packageDescription: fixture.packageDescription,
        packageQuantity: fixture.packageQuantity,
        packageUnit: fixture.packageUnit,
        visiblePrice: fixture.visiblePrice,
        currency: 'USD',
        observedAt: FIXTURE_OBSERVED_AT,
        confidence: fixture.confidence,
        ambiguityReasons: [...fixture.ambiguityReasons],
        proteinGramsPerPackage: null,
        collectionMethod: 'smartcart-seeded-fixture-replay',
        location: { kind: 'online-unspecified-store', label: 'Walmart.com; no store selected in fixture' },
        rawText: `${fixture.title}; ${fixture.packageDescription}; recorded visible price $${fixture.visiblePrice.toFixed(2)} USD. SmartCart seeded fixture replay, not a live retailer observation.`,
        freshness: freshness(FIXTURE_OBSERVED_AT, this.now)
      };
    }));
  }
}

export { freshness };
