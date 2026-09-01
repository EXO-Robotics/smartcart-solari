export const V3_DEMO_ID = 'owned-demo-grocer-basket-v3';
export const V3_STORE_REFERENCE = 'smartcart-demo-grocer-owned-catalog-v2';
export const V3_MAX_PREMIUM_OVER_CHEAPEST = 0.75;

export const V3_PRODUCT_REQUIREMENT = Object.freeze({
  'dg-chicken-value-3lb': 'chicken',
  'dg-chicken-rightsize-1lb': 'chicken',
  'dg-penne-value-16oz': 'penne',
  'dg-penne-rightsize-12oz': 'penne',
  'dg-parmesan-value-6oz': 'parmesan',
  'dg-parmesan-rightsize-3oz': 'parmesan'
});

export const V3_PRODUCT_CATALOG = Object.freeze({
  'dg-chicken-value-3lb': Object.freeze({ title: 'Demo Value Chicken Breasts', packageQuantity: 3, packageUnit: 'pound', visiblePrice: 9.47 }),
  'dg-chicken-rightsize-1lb': Object.freeze({ title: 'Demo Rightsize Chicken Breasts', packageQuantity: 1, packageUnit: 'pound', visiblePrice: 5.00 }),
  'dg-penne-value-16oz': Object.freeze({ title: 'Demo Value Penne Pasta', packageQuantity: 16, packageUnit: 'ounce', visiblePrice: 1.24 }),
  'dg-penne-rightsize-12oz': Object.freeze({ title: 'Demo Rightsize Penne Pasta', packageQuantity: 12, packageUnit: 'ounce', visiblePrice: 1.65 }),
  'dg-parmesan-value-6oz': Object.freeze({ title: 'Demo Value Finely Shredded Parmesan', packageQuantity: 6, packageUnit: 'ounce', visiblePrice: 2.08 }),
  'dg-parmesan-rightsize-3oz': Object.freeze({ title: 'Demo Rightsize Finely Shredded Parmesan', packageQuantity: 3, packageUnit: 'ounce', visiblePrice: 2.42 })
});

export const V3_CANONICAL_REQUIREMENTS = Object.freeze([
  Object.freeze({ key: 'chicken', name: 'Chicken breast', requiredQuantity: 1.5, unit: 'lb', productIDs: Object.freeze(['dg-chicken-value-3lb', 'dg-chicken-rightsize-1lb']) }),
  Object.freeze({ key: 'penne', name: 'Penne pasta', requiredQuantity: 12, unit: 'oz', productIDs: Object.freeze(['dg-penne-value-16oz', 'dg-penne-rightsize-12oz']) }),
  Object.freeze({ key: 'parmesan', name: 'Finely shredded Parmesan', requiredQuantity: 3, unit: 'oz', productIDs: Object.freeze(['dg-parmesan-value-6oz', 'dg-parmesan-rightsize-3oz']) })
]);
