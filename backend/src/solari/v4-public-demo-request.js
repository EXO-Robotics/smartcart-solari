import { randomUUID } from 'node:crypto';
import {
  V4_DEMO_ID,
  V4_MAX_PREMIUM_OVER_CHEAPEST,
  V4_STORE_REFERENCE
} from './v4-constants.js';
import { SolariResearchError } from './errors.js';

export const PUBLIC_DEMO_REQUEST_SCHEMA_VERSION = 'smartcart-solari-public-demo-request-v1';
export const PUBLIC_DEMO_MEAL_ID = 'chicken-pasta-eight-item-v1';

const REQUIREMENTS = Object.freeze([
  ['1', 'Chicken breast', '680 g', 680, 'g', ['dg4-chicken-value-3lb', 'dg4-chicken-organic-1-5lb', 'dg4-chicken-free-range-3lb']],
  ['2', 'Olive oil', '30 ml', 30, 'ml', ['dg4-olive-oil-value-17floz', 'dg4-olive-oil-organic-17floz', 'dg4-olive-oil-smooth-16floz']],
  ['3', 'Penne pasta', '340 g', 340, 'g', ['dg4-penne-value-16oz', 'dg4-penne-glutenfree-24oz']],
  ['4', 'Heavy cream', '240 ml', 240, 'ml', ['dg4-heavy-cream-value-16floz', 'dg4-heavy-cream-organic-16floz']],
  ['5', 'Parmesan cheese', '85 g', 85, 'g', ['dg4-parmesan-value-6oz', 'dg4-parmesan-frigo-5oz', 'dg4-parmesan-kraft-6oz']],
  ['6', 'Garlic cloves', '2 cloves', 2, 'count', ['dg4-garlic-bulb-8ct']],
  ['7', 'Lemons', '2 lemons', 2, 'count', ['dg4-lemon-each-1ct']],
  ['8', 'Parsley', '1 bunch', 1, 'count', ['dg4-parsley-bunch-1ct']]
]);

export function assertPublicDemoRequest(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || Object.keys(value).length !== 2
    || value.schemaVersion !== PUBLIC_DEMO_REQUEST_SCHEMA_VERSION
    || value.mealID !== PUBLIC_DEMO_MEAL_ID) {
    throw new SolariResearchError(
      'public_demo_request_not_allowed',
      'The public demo accepts only its fixed eight-item meal selector.',
      { status: 400 }
    );
  }
  return value;
}

export function createV4PublicDemoRequest({ now = Date.now, id = randomUUID } = {}) {
  return {
    schemaVersion: 'solari-shopping-research-request-v4',
    requestID: id(),
    demoID: V4_DEMO_ID,
    submittedAt: new Date(now()).toISOString(),
    retailerID: 'smartcart-demo-grocer',
    executionMode: 'live',
    storeReference: V4_STORE_REFERENCE,
    optimizationPolicy: {
      objective: 'minimize-aggregate-relative-surplus',
      maxPremiumOverCheapest: V4_MAX_PREMIUM_OVER_CHEAPEST,
      currency: 'USD',
      tieBreak: ['observed-subtotal', 'retailer-product-id']
    },
    requirements: REQUIREMENTS.map(([suffix, name, requestedQuantityText, requiredQuantity, unit, candidateProductIDs]) => ({
      id: `71000000-0000-4000-8000-00000000000${suffix}`,
      ingredientID: `72000000-0000-4000-8000-00000000000${suffix}`,
      name,
      requestedQuantityText,
      requiredQuantity,
      unit,
      candidateProductIDs: [...candidateProductIDs]
    }))
  };
}
