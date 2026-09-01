export const SOLARI_REQUEST_SCHEMA_ID = 'https://schemas.smartcart.app/v1/solari/basket-research-request.schema.json';
export const SOLARI_RESULT_SCHEMA_ID = 'https://schemas.smartcart.app/v1/solari/basket-research-result.schema.json';
export const SOLARI_OBSERVATION_SCHEMA_ID = 'https://schemas.smartcart.app/v1/solari/retailer-observation.schema.json';
export const SOLARI_DECISION_SCHEMA_ID = 'https://schemas.smartcart.app/v1/solari/basket-decision.schema.json';

export const DEMO_ID = 'chicken-parmesan-pasta-v1';
export const FIXTURE_OBSERVED_AT = '2026-07-16T12:00:00Z';
export const MAX_OBSERVATION_AGE_SECONDS = 86_400;

export const PRODUCT_REQUIREMENT = Object.freeze({
  '10414680': 'chicken',
  '10534084': 'penne',
  '623835750': 'penne',
  '10452414': 'parmesan',
  '10307238': 'parmesan',
  '47088917': 'parmesan'
});

export const WALMART_PRODUCT_URLS = Object.freeze(Object.fromEntries(
  Object.keys(PRODUCT_REQUIREMENT).map((id) => [id, `https://www.walmart.com/ip/${id}`])
));

export const FIXTURE_PRODUCTS = Object.freeze({
  '10414680': {
    title: 'All Natural Boneless Skinless Chicken Breasts',
    packageDescription: '3 lb frozen bag', packageQuantity: 3, packageUnit: 'pound',
    visiblePrice: 9.47, confidence: 'high', ambiguityReasons: []
  },
  '10534084': {
    title: 'Penne Pasta', packageDescription: '16 oz box', packageQuantity: 16, packageUnit: 'ounce',
    visiblePrice: 1.24, confidence: 'high', ambiguityReasons: []
  },
  '623835750': {
    title: 'Gluten Free Penne Pasta', packageDescription: '2 x 12 oz', packageQuantity: 24, packageUnit: 'ounce',
    visiblePrice: 11.98, confidence: 'medium',
    ambiguityReasons: ['Gluten-free attribute was not requested by this recipe.']
  },
  '10452414': {
    title: 'Finely Shredded Parmesan Cheese', packageDescription: '6 oz bag', packageQuantity: 6, packageUnit: 'ounce',
    visiblePrice: 2.08, confidence: 'high', ambiguityReasons: []
  },
  '10307238': {
    title: 'Shredded Parmesan Cheese', packageDescription: '5 oz cup', packageQuantity: 5, packageUnit: 'ounce',
    visiblePrice: 3.28, confidence: 'medium',
    ambiguityReasons: ['Shred size is not stated as finely shredded.']
  },
  '47088917': {
    title: 'Finely Shredded Parmesan Cheese', packageDescription: '6 oz bag', packageQuantity: 6, packageUnit: 'ounce',
    visiblePrice: 4.98, confidence: 'high', ambiguityReasons: []
  }
});

export const CANONICAL_REQUIREMENTS = Object.freeze([
  { key: 'chicken', name: 'Boneless skinless chicken breast', requiredQuantity: 1.5, unit: 'lb', productIDs: ['10414680'] },
  { key: 'penne', name: 'Penne pasta', requiredQuantity: 12, unit: 'oz', productIDs: ['10534084', '623835750'] },
  { key: 'parmesan', name: 'Finely shredded Parmesan', requiredQuantity: 3, unit: 'oz', productIDs: ['10452414', '10307238', '47088917'] }
]);

export function controlledDemoProductURL(baseURL, productID) {
  const url = new URL(baseURL);
  const basePath = url.pathname.replace(/\/+$/, '');
  url.pathname = `${basePath}/retailer/product/${productID}.html`;
  url.search = '';
  url.hash = '';
  return url.href;
}
