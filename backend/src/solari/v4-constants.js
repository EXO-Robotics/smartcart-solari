export const V4_DEMO_ID = 'owned-demo-grocer-basket-v4';
export const V4_STORE_REFERENCE = 'smartcart-demo-grocer-owned-catalog-v4';
export const V4_MAX_PREMIUM_OVER_CHEAPEST = 0.75;
export const V4_MAX_REQUIREMENTS = 12;
export const V4_MAX_CANDIDATES_PER_REQUIREMENT = 3;
export const V4_MAX_OBSERVATIONS = 24;

const product = (group, dimension, title, packageQuantity, packageUnit, visiblePrice) =>
  Object.freeze({ group, dimension, title, packageQuantity, packageUnit, visiblePrice });

// This is an owned synthetic catalog. The identifiers deliberately do not reuse
// or expose identifiers from any external retailer.
export const V4_PRODUCT_CATALOG = Object.freeze({
  'dg4-chicken-value-3lb': product('chicken', 'mass', 'Demo Chicken Breasts — Value', 3, 'lb', 8.13),
  'dg4-chicken-organic-1-5lb': product('chicken', 'mass', 'Demo Chicken Breasts — Organic', 1.5, 'lb', 8.76),
  'dg4-chicken-free-range-3lb': product('chicken', 'mass', 'Demo Chicken Breasts — Free Range', 3, 'lb', 13.92),
  'dg4-penne-value-16oz': product('pasta', 'mass', 'Demo Penne Pasta — Value', 16, 'oz', 1.24),
  'dg4-penne-glutenfree-24oz': product('pasta', 'mass', 'Demo Penne Pasta — Gluten Free', 24, 'oz', 11.98),
  'dg4-olive-oil-value-17floz': product('olive-oil', 'volume', 'Demo Extra Virgin Olive Oil — Value', 17, 'fl oz', 6.12),
  'dg4-olive-oil-organic-17floz': product('olive-oil', 'volume', 'Demo Extra Virgin Olive Oil — Organic', 17, 'fl oz', 7.36),
  'dg4-olive-oil-smooth-16floz': product('olive-oil', 'volume', 'Demo Extra Virgin Olive Oil — Smooth', 16, 'fl oz', 6.75),
  'dg4-heavy-cream-value-16floz': product('heavy-cream', 'volume', 'Demo Heavy Whipping Cream — Value', 16, 'fl oz', 2.96),
  'dg4-heavy-cream-organic-16floz': product('heavy-cream', 'volume', 'Demo Heavy Whipping Cream — Organic', 16, 'fl oz', 5.87),
  'dg4-parmesan-value-6oz': product('parmesan', 'mass', 'Demo Finely Shredded Parmesan — Value', 6, 'oz', 2.08),
  'dg4-parmesan-frigo-5oz': product('parmesan', 'mass', 'Demo Shredded Parmesan — Cup', 5, 'oz', 3.28),
  'dg4-parmesan-kraft-6oz': product('parmesan', 'mass', 'Demo Finely Shredded Parmesan — Premium', 6, 'oz', 4.98),
  'dg4-garlic-bulb-8ct': product('garlic', 'count', 'Demo Fresh Whole Garlic Bulb', 8, 'count', 0.78),
  'dg4-garlic-peeled-6oz': product('garlic', 'mass', 'Demo Fresh Peeled Garlic', 6, 'oz', 3.07),
  'dg4-garlic-minced-8oz': product('garlic', 'mass', 'Demo Minced Garlic in Olive Oil', 8, 'oz', 3.12),
  'dg4-lemon-each-1ct': product('lemon', 'count', 'Demo Fresh Lemon', 1, 'count', 0.64),
  'dg4-lemon-organic-2lb': product('lemon', 'mass', 'Demo Organic Lemons', 2, 'lb', 3.92),
  'dg4-parsley-bunch-1ct': product('parsley', 'count', 'Demo Fresh Cut Parsley', 1, 'count', 0.98)
});

export const V4_GROUP_ALIASES = Object.freeze({
  chicken: ['chicken'],
  pasta: ['pasta', 'penne', 'rigatoni', 'spaghetti', 'fettuccine', 'noodle'],
  'olive-oil': ['olive oil'],
  'heavy-cream': ['heavy cream', 'whipping cream', 'cream'],
  parmesan: ['parmesan'],
  garlic: ['garlic'],
  lemon: ['lemon'],
  parsley: ['parsley']
});

export function controlledV4ProductURL(baseURL, productID) {
  const url = new URL(baseURL);
  const basePath = url.pathname.replace(/\/+$/, '');
  url.pathname = `${basePath}/retailer-v4/product/${productID}.html`;
  url.search = '';
  url.hash = '';
  return url.href;
}
