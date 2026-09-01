(() => {
  "use strict";

  const page = document.body.dataset.productPage;
  const host = document.querySelector("[data-product-host]");
  const catalogHost = document.querySelector("[data-catalog-host]");
  const legacyPage = Boolean(page && !page.startsWith("dg-"));
  const catalogURL = page ? (legacyPage ? "../legacy-catalog.json" : "../catalog.json") : "catalog.json";

  const node = (tag, className, text) => {
    const item = document.createElement(tag);
    if (className) item.className = className;
    if (text !== undefined) item.textContent = text;
    return item;
  };

  function renderProduct(product, catalog) {
    const article = node("article", "product");
    article.dataset.solariProduct = "true";
    article.dataset.catalogEra = catalog.historical ? "historical-v1" : "current-v3";
    article.dataset.productId = product.id;
    article.dataset.productName = product.name;
    article.dataset.packageValue = String(product.packageValue);
    article.dataset.packageUnit = product.packageUnit;
    article.dataset.priceCents = String(product.priceCents);
    article.dataset.currency = product.currency;
    article.dataset.syntheticPrice = String(product.syntheticPrice === true);

    const copy = node("div");
    const eraLabel = catalog.historical ? "historical V1 synthetic product" : "current V3 synthetic product";
    copy.append(node("p", "eyebrow", `${product.brand} · ${eraLabel}`), node("h2", "", product.name));
    const meta = node("div", "product-meta");
    meta.append(node("span", "", product.packageDisplay), node("span", "", `Synthetic ID ${product.id}`), node("span", "", catalog.historical ? "Historical test data only" : "Current synthetic test data only"));
    copy.append(meta);

    const price = node("div", "price");
    price.append(node("strong", "", `$${(product.priceCents / 100).toFixed(2)}`), node("small", "", catalog.historical ? "historical synthetic price" : "current synthetic price"));
    article.append(copy, price);
    host.replaceChildren(article);

    const jsonLD = document.createElement("script");
    jsonLD.type = "application/ld+json";
    jsonLD.textContent = JSON.stringify({
      "@context": "https://schema.org",
      "@type": "Product",
      name: product.name,
      sku: product.id,
      brand: { "@type": "Brand", name: product.brand },
      offers: { "@type": "Offer", price: (product.priceCents / 100).toFixed(2), priceCurrency: product.currency },
      additionalProperty: [
        { "@type": "PropertyValue", name: "synthetic", value: true },
        { "@type": "PropertyValue", name: "catalogEra", value: catalog.historical ? "historical-v1" : "current-v3" },
        { "@type": "PropertyValue", name: "packageValue", value: product.packageValue },
        { "@type": "PropertyValue", name: "packageUnit", value: product.packageUnit }
      ]
    });
    document.head.append(jsonLD);
  }

  function renderCatalog(products) {
    const list = node("div", "catalog-list");
    products.forEach((product) => {
      const link = node("a", "", `${product.brand} ${product.name} · ${product.packageDisplay}`);
      link.href = `product/${product.id}.html`;
      list.append(link);
    });
    catalogHost.replaceChildren(list);
  }

  window.setTimeout(async () => {
    try {
      const response = await fetch(catalogURL, { cache: "no-store" });
      if (!response.ok) throw new Error(`catalog ${response.status}`);
      const catalog = await response.json();
      if (catalog.synthetic !== true) throw new Error("catalog is not marked synthetic");
      if (page) {
        if (legacyPage !== (catalog.historical === true)) throw new Error("catalog era mismatch");
        const product = catalog.products.find((item) => item.id === page);
        if (!product) throw new Error("product not found");
        const banner = document.querySelector(".synthetic-banner");
        if (banner) {
          banner.textContent = catalog.historical
            ? "Historical V1 synthetic test page · preserved for immutable evidence URLs · no retailer affiliation"
            : "Current V3 synthetic test catalog · owned integration surface · no retailer affiliation";
        }
        renderProduct(product, catalog);
      } else {
        if (catalog.current !== true || catalog.historical !== false) throw new Error("default catalog is not current V3");
        renderCatalog(catalog.products);
      }
    } catch (error) {
      const target = host || catalogHost;
      if (target) target.textContent = `Synthetic catalog unavailable: ${error.message}`;
    }
  }, 650);
})();
