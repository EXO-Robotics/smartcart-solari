(() => {
  "use strict";

  const fixtureURL = "../../contracts/fixtures/v1/solari/chicken-parmesan-walmart-result.json";
  const state = {
    fixture: null,
    selectedByRequirement: new Map(),
    timers: [],
  };

  const requirements = {
    "20000000-0000-0000-0000-000000000001": { name: "Chicken breast", quantity: 1.5, unit: "pound" },
    "20000000-0000-0000-0000-000000000002": { name: "Penne pasta", quantity: 12, unit: "ounce" },
    "20000000-0000-0000-0000-000000000003": { name: "Parmesan", quantity: 3, unit: "ounce" },
  };

  const unitLabels = { pound: "lb", ounce: "oz", count: "count" };
  const weightScale = { pound: 16, ounce: 1 };

  const money = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  });

  const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function showStage(stageName, { focus = true } = {}) {
    if (state.fixture && (stageName === "decision" || stageName === "handoff")) {
      renderCandidates();
      renderDecision();
      renderHandoff();
    }

    document.querySelectorAll("[data-stage]").forEach((panel) => {
      const active = panel.dataset.stage === stageName;
      panel.hidden = !active;
      panel.classList.toggle("is-active", active);
    });

    document.querySelectorAll("[data-stage-target]").forEach((tab) => {
      const active = tab.dataset.stageTarget === stageName;
      tab.classList.toggle("is-active", active);
      if (active) tab.setAttribute("aria-current", "step");
      else tab.removeAttribute("aria-current");
    });

    if (focus) {
      const heading = document.querySelector(`[data-stage="${stageName}"] h2`);
      if (heading) {
        heading.setAttribute("tabindex", "-1");
        heading.focus({ preventScroll: true });
      }
      document.querySelector(".stage-nav")?.scrollIntoView({
        behavior: prefersReducedMotion.matches ? "auto" : "smooth",
        block: "start",
      });
    }

    if (stageName === "research") replayEvents();
  }

  function observationFor(id) {
    return state.fixture.observations.find((observation) => observation.observationID === id);
  }

  function requirementFor(id) {
    return requirements[id];
  }

  function packageMath(observation) {
    const required = requirementFor(observation.requirementID);
    if (!required || observation.packageQuantity === null || observation.packageUnit === null) return null;
    if ((required.unit === "count") !== (observation.packageUnit === "count")) return null;
    const requiredScale = required.unit === "count" ? 1 : weightScale[required.unit];
    const packageScale = observation.packageUnit === "count" ? 1 : weightScale[observation.packageUnit];
    if (!requiredScale || !packageScale) return null;
    const requiredBase = required.quantity * requiredScale;
    const packageBase = observation.packageQuantity * packageScale;
    const count = Math.ceil(requiredBase / packageBase);
    return {
      count,
      surplus: Number(((count * packageBase - requiredBase) / requiredScale).toFixed(3)),
      surplusUnit: required.unit,
    };
  }

  function selectedObservations() {
    return [...state.selectedByRequirement.values()].map(observationFor).filter(Boolean);
  }

  function evidenceDetails(observation) {
    const details = element("details", "evidence-toggle");
    const summary = element("summary", "", "Evidence & provenance");
    const meta = element("div", "evidence-meta");

    const fields = [
      ["Product ID", observation.retailerProductID],
      ["Recorded at", "Jul 16, 2026 · 12:00 UTC"],
      ["Match confidence", observation.confidence],
    ];

    fields.forEach(([label, value]) => {
      const item = element("p");
      item.append(element("strong", "", label), element("span", "", value));
      meta.append(item);
    });

    const source = element("p");
    source.append(element("strong", "", "Recorded source"));
    const sourceLink = element("a", "", observation.sourceURL);
    sourceLink.href = observation.sourceURL;
    sourceLink.target = "_blank";
    sourceLink.rel = "noreferrer noopener";
    const sourceValue = element("span");
    sourceValue.append(sourceLink);
    source.append(sourceValue);
    meta.append(source);

    const freshness = element("p");
    freshness.append(
      element("strong", "", "Freshness"),
      element("span", "", "Historical seeded record · current price unknown")
    );
    meta.append(freshness);

    const nutrition = element("p");
    nutrition.append(
      element("strong", "", "Nutrition evidence"),
      element("span", "", observation.proteinGramsPerPackage ?? "Not observed")
    );
    meta.append(nutrition);

    const ambiguity = element("p", "ambiguity-copy");
    ambiguity.append(
      element("strong", "", "Ambiguity"),
      element("span", "", observation.ambiguityReasons.length ? observation.ambiguityReasons.join(" · ") : "No recorded match ambiguity")
    );
    meta.append(ambiguity);

    details.append(summary, meta);
    return details;
  }

  function renderCandidates() {
    const host = document.querySelector("[data-candidate-groups]");
    if (!host || !state.fixture) return;
    clear(host);

    const recordedSelections = new Set(state.fixture.decisions.map((decision) => decision.observationID));
    const grouped = new Map();
    state.fixture.observations.forEach((observation) => {
      if (!grouped.has(observation.requirementID)) grouped.set(observation.requirementID, []);
      grouped.get(observation.requirementID).push(observation);
    });

    grouped.forEach((observations, requirementID) => {
      const required = requirementFor(requirementID);
      const group = element("section", "candidate-group");
      group.setAttribute("aria-labelledby", `candidate-${requirementID}`);

      const label = element("div", "candidate-label");
      const title = element("strong", "", required.name);
      title.id = `candidate-${requirementID}`;
      label.append(title, element("span", "", `${required.quantity} ${unitLabels[required.unit]} required`));

      const options = element("div", "candidate-options");
      observations.forEach((observation) => {
        const selected = state.selectedByRequirement.get(requirementID) === observation.observationID;
        const option = element("label", `candidate-option${selected ? " is-selected" : ""}`);

        const radio = document.createElement("input");
        radio.type = "radio";
        radio.name = `candidate-${requirementID}`;
        radio.value = observation.observationID;
        radio.checked = selected;
        radio.setAttribute("aria-label", `Select ${observation.title}`);

        const name = element("span", "candidate-name");
        name.append(
          element("strong", "", observation.title ?? "Product title unavailable"),
          element("small", "", recordedSelections.has(observation.observationID) ? "Recorded recommendation" : observation.ambiguityReasons.join(" · ") || "Alternative")
        );

        const packageText = element("span", "candidate-package", observation.packageDescription ?? "Package unavailable");
        const price = element("span", "candidate-price", observation.visiblePrice === null ? "Unavailable" : money.format(observation.visiblePrice));
        const unitPrice = observation.visiblePrice === null || observation.packageQuantity === null
          ? "unit price unavailable"
          : `${money.format(observation.visiblePrice / observation.packageQuantity)}/${unitLabels[observation.packageUnit]}`;
        price.append(element("small", "", unitPrice));

        radio.addEventListener("change", () => {
          state.selectedByRequirement.set(requirementID, observation.observationID);
          renderCandidates();
          renderDecision();
          renderHandoff();
        });

        option.append(radio, name, packageText, price, evidenceDetails(observation));
        options.append(option);
      });

      group.append(label, options);
      host.append(group);
    });
  }

  function derivedDecision() {
    const selected = selectedObservations();
    const lines = selected.flatMap((observation) => {
      const math = packageMath(observation);
      if (!math) return [];
      return {
        observationID: observation.observationID,
        retailerProductID: observation.retailerProductID,
        requirementID: observation.requirementID,
        packageCount: math.count,
        package: observation.packageDescription,
        lineEstimate: observation.visiblePrice === null ? null : Number((observation.visiblePrice * math.count).toFixed(2)),
        surplus: math.surplus,
        surplusUnit: math.surplusUnit,
        confidence: observation.confidence,
        ambiguityReasons: observation.ambiguityReasons,
      };
    });
    const hasMissingPrice = lines.some((line) => line.lineEstimate === null);
    const complete = lines.length === Object.keys(requirements).length && !hasMissingPrice;
    const confidenceCounts = selected.reduce((counts, observation) => {
      counts[observation.confidence] = (counts[observation.confidence] ?? 0) + 1;
      return counts;
    }, {});
    const confidenceSummary = confidenceCounts.high === selected.length
      ? "High on all selected lines"
      : ["high", "medium", "low"]
          .filter((level) => confidenceCounts[level])
          .map((level) => `${confidenceCounts[level]} ${level}`)
          .join(" · ");

    return {
      displayMode: "non-evidence what-if preview",
      sourceSchemaVersion: state.fixture.schemaVersion,
      completedAt: state.fixture.completedAt,
      currentPriceVerified: state.fixture.trust.priceClaim !== "recorded-fixture-not-live",
      browserProvenance: state.fixture.provenance.browser,
      sandboxProvenance: state.fixture.provenance.sandbox,
      lines,
      completeness: complete ? "complete" : "partial",
      checkoutEstimate: complete
        ? Number(lines.reduce((sum, line) => sum + line.lineEstimate, 0).toFixed(2))
        : null,
      confidenceSummary,
      proteinPerDollar: null,
      proteinPerDollarReason: state.fixture.trust.limitations.find((item) => item.includes("protein")) ?? "No reviewed nutrition evidence.",
    };
  }

  function renderDecision() {
    if (!state.fixture) return;
    const decision = derivedDecision();
    const linesHost = document.querySelector("[data-receipt-lines]");
    const total = document.querySelector("[data-basket-total]");
    const json = document.querySelector("[data-decision-json]");
    const confidence = document.querySelector("[data-decision-confidence]");
    const packageTotal = document.querySelector("[data-package-count]");
    const finePrint = document.querySelector("[data-receipt-fine]");
    if (!linesHost || !total || !json || !confidence || !packageTotal || !finePrint) return;
    clear(linesHost);

    decision.lines.forEach((line) => {
      const observation = observationFor(line.observationID);
      const row = element("div", "receipt-row");
      const copy = element("span");
      copy.append(
        element("strong", "", `${line.packageCount} × ${observation.title}`),
        element("small", "", `${line.package} · surplus ${line.surplus} ${unitLabels[line.surplusUnit]}`)
      );
      row.append(copy, element("span", "", line.lineEstimate === null ? "Unavailable" : money.format(line.lineEstimate)));
      linesHost.append(row);
    });

    total.textContent = decision.checkoutEstimate === null ? "Incomplete" : money.format(decision.checkoutEstimate);
    confidence.textContent = decision.confidenceSummary || "Unavailable";
    packageTotal.textContent = String(decision.lines.reduce((sum, line) => sum + line.packageCount, 0));
    finePrint.textContent = decision.checkoutEstimate === null
      ? "No complete estimate: at least one selected line lacks compatible package or visible-price evidence."
      : "Fixture-based preview before tax, fees, fulfillment, or substitutions. Current price and availability unknown.";
    json.textContent = JSON.stringify({
      ...decision,
      notice: "Locally recalculated preview from immutable fixture observations; not a new evidence receipt or live Solari result.",
    }, null, 2);
  }

  function renderHandoff() {
    const host = document.querySelector("[data-handoff-list]");
    if (!host || !state.fixture) return;
    clear(host);

    selectedObservations().forEach((observation, index) => {
      const item = element("div", "handoff-item");
      const copy = element("span");
      const count = packageMath(observation)?.count;
      copy.append(
        element("strong", "", observation.title ?? "Product title unavailable"),
        element("small", "", `${count ?? "No compatible"} package${count === 1 ? "" : "s"} suggested · recorded ${observation.visiblePrice === null ? "price unavailable" : money.format(observation.visiblePrice)} each · current price unknown`)
      );

      const link = element("a", "retailer-link", "Open source page ↗");
      link.href = observation.sourceURL;
      link.target = "_blank";
      link.rel = "noreferrer noopener";
      link.setAttribute("aria-label", `Open Walmart source page for ${observation.title}; current details must be verified`);

      item.append(element("span", "handoff-number", String(index + 1).padStart(2, "0")), copy, link);
      host.append(item);
    });
  }

  function replayEvents() {
    state.timers.forEach(window.clearTimeout);
    state.timers = [];
    const events = [...document.querySelectorAll("[data-event]")];
    const meter = document.querySelector("[data-research-meter]");
    const status = document.querySelector("[data-research-status]");
    events.forEach((event) => event.classList.remove("is-complete"));
    if (meter) meter.style.width = "0%";
    if (status) status.textContent = "Replaying the receipt-backed sequence—no new Solari or retailer request is being made.";

    const interval = prefersReducedMotion.matches ? 0 : 360;
    events.forEach((event, index) => {
      const timer = window.setTimeout(() => {
        event.classList.add("is-complete");
        if (meter) meter.style.width = `${((index + 1) / events.length) * 100}%`;
        if (status && index === events.length - 1) {
          status.textContent = "Sequence replay complete · receipt records six Browser observations and three Sandbox decisions.";
        }
      }, interval * (index + 1));
      state.timers.push(timer);
    });
  }

  async function loadFixture() {
    const response = await fetch(fixtureURL, { cache: "no-store" });
    if (!response.ok) throw new Error(`Fixture request failed: ${response.status}`);
    const fixture = await response.json();
    if (fixture.schemaVersion !== "solari-shopping-research-result-v1") {
      throw new Error("Unsupported replay fixture schema");
    }
    state.fixture = fixture;
    fixture.decisions.forEach((decision) => {
      state.selectedByRequirement.set(decision.requirementID, decision.observationID);
    });
    renderCandidates();
    renderDecision();
    renderHandoff();
  }

  document.querySelectorAll("[data-stage-target]").forEach((button) => {
    button.addEventListener("click", () => showStage(button.dataset.stageTarget));
  });

  document.querySelectorAll("[data-next-stage]").forEach((button) => {
    button.addEventListener("click", () => showStage(button.dataset.nextStage));
  });

  document.querySelector("[data-replay-events]")?.addEventListener("click", replayEvents);

  const walmartTerms = document.querySelector("[data-walmart-terms]");
  if (walmartTerms) {
    walmartTerms.href = "https://www.walmart.com/help/article/walmart-com-terms-of-use/3b75080af40340d6bbd596f116fae5a0/";
  }

  const fixtureLink = document.querySelector("[data-fixture-link]");
  if (fixtureLink) fixtureLink.href = fixtureURL;

  const liveRunLink = document.querySelector("[data-live-run-link]");
  if (liveRunLink) {
    liveRunLink.href = "https://github.com/EXO-Robotics/smartcart-solari/actions/runs/33519606791";
  }

  const liveReceiptLink = document.querySelector("[data-live-receipt-link]");
  if (liveReceiptLink) {
    liveReceiptLink.href = "https://exo-robotics.github.io/smartcart-solari/evidence/live/smartcart-solari-live-proof-33519606791.json";
  }

  loadFixture().catch((error) => {
    const host = document.querySelector("[data-candidate-groups]");
    if (host) {
      host.textContent = "Replay fixture could not load. Serve this directory over HTTP and try again; no live retailer fallback will run.";
    }
    const status = document.querySelector("[data-research-status]");
    if (status) status.textContent = error.message;
  });
})();
