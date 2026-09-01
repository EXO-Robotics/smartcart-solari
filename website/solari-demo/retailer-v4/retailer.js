(() => {
  "use strict";
  const match = location.pathname.match(/\/product\/([^/]+)\.html$/);
  const productID = match ? decodeURIComponent(match[1]) : null;
  const host = document.querySelector("[data-product-host]");
  const catalogHost = document.querySelector("[data-catalog-host]");
  const node = (tag, className, text) => { const item = document.createElement(tag); if (className) item.className = className; if (text !== undefined) item.textContent = text; return item; };
  function renderProduct(product) {
    const article = node("article", "product");
    Object.assign(article.dataset, { solariProduct: "true", catalogEra: "current-v4", productId: product.id, productName: product.name, packageValue: String(product.packageValue), packageUnit: product.packageUnit, priceCents: String(product.priceCents), currency: product.currency, syntheticPrice: "true" });
    const copy = node("div"); copy.append(node("p", "eyebrow", `${product.brand} · current V4 synthetic product`), node("h2", "", product.name));
    const meta = node("div", "product-meta"); meta.append(node("span", "", product.packageDisplay), node("span", "", `Synthetic ID ${product.id}`), node("span", "", "Current synthetic test data only")); copy.append(meta);
    const price = node("div", "price"); price.append(node("strong", "", `$${(product.priceCents / 100).toFixed(2)}`), node("small", "", "current synthetic price")); article.append(copy, price); host.replaceChildren(article);
  }
  function renderCatalog(products) { const list = node("div", "catalog-list"); for (const product of products) { const link = node("a", "", `${product.brand} ${product.name} · ${product.packageDisplay}`); link.href = `product/${product.id}.html`; list.append(link); } catalogHost.replaceChildren(list); }
  window.setTimeout(async () => {
    try { const response = await fetch(productID ? "../catalog.json" : "catalog.json", { cache: "no-store" }); if (!response.ok) throw new Error(`catalog ${response.status}`); const catalog = await response.json(); if (catalog.synthetic !== true || catalog.current !== true || catalog.catalogVersion !== "smartcart.demo-grocer.v4") throw new Error("catalog identity mismatch"); if (productID) { const product = catalog.products.find(({ id }) => id === productID); if (!product) throw new Error("product not found"); renderProduct(product); } else renderCatalog(catalog.products); }
    catch (error) { const target = host || catalogHost; if (target) target.textContent = `Synthetic catalog unavailable: ${error.message}`; }
  }, 100);
})();
