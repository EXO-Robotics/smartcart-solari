(() => {
  "use strict";

  const header = document.querySelector("[data-header]");
  const updateHeader = () => header?.classList.toggle("is-scrolled", window.scrollY > 18);
  updateHeader();
  window.addEventListener("scroll", updateHeader, { passive: true });

  const revealObserver = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        });
      }, { threshold: 0.12, rootMargin: "0px 0px -40px" })
    : null;

  document.querySelectorAll(".reveal").forEach((element) => {
    if (revealObserver) revealObserver.observe(element);
    else element.classList.add("is-visible");
  });

  const comparison = document.querySelector("[data-comparison-state]");
  const modeButtons = Array.from(document.querySelectorAll("[data-mode]"));
  const modePanels = Array.from(document.querySelectorAll("[data-process], [data-panel]"));

  const setComparisonMode = (mode, shouldFocus = false) => {
    if (!mode || !comparison) return;
    comparison.dataset.comparisonState = mode;
    modeButtons.forEach((candidate) => {
      const selected = candidate.dataset.mode === mode;
      candidate.setAttribute("aria-selected", String(selected));
      candidate.tabIndex = selected ? 0 : -1;
      if (selected && shouldFocus) candidate.focus();
    });
    modePanels.forEach((panel) => {
      const panelMode = panel.dataset.process || panel.dataset.panel;
      const hidden = panelMode !== mode;
      panel.setAttribute("aria-hidden", String(hidden));
      panel.inert = hidden;
    });
  };

  modeButtons.forEach((button) => {
    button.addEventListener("click", () => {
      setComparisonMode(button.dataset.mode);
    });
    button.addEventListener("keydown", (event) => {
      const currentIndex = modeButtons.indexOf(button);
      let nextIndex = currentIndex;
      if (event.key === "ArrowRight") nextIndex = (currentIndex + 1) % modeButtons.length;
      else if (event.key === "ArrowLeft") nextIndex = (currentIndex - 1 + modeButtons.length) % modeButtons.length;
      else if (event.key === "Home") nextIndex = 0;
      else if (event.key === "End") nextIndex = modeButtons.length - 1;
      else return;
      event.preventDefault();
      setComparisonMode(modeButtons[nextIndex]?.dataset.mode, true);
    });
  });
  setComparisonMode(modeButtons.find((button) => button.getAttribute("aria-selected") === "true")?.dataset.mode);

  const frontends = {
    smartcart: {
      name: "SmartCart",
      intent: "Recipe, pantry, servings, and normalized ingredient requirements.",
      outcome: "Grounded basket",
      result: "Selected products, package counts, overage, estimated total, confidence, and provenance."
    },
    procurement: {
      name: "Procurement",
      intent: "Approved bill of materials, quantities, supplier rules, and budget constraints.",
      outcome: "Supplier decision",
      result: "Comparable offers, landed quantities, policy checks, decision evidence, and source provenance."
    },
    travel: {
      name: "Travel planner",
      intent: "Dates, routes, accessibility needs, preferences, and budget constraints.",
      outcome: "Grounded itinerary",
      result: "Observed options, constraint-fit evaluation, ambiguity, freshness, and user-controlled handoff."
    },
    "field-service": {
      name: "Field service",
      intent: "Service diagnosis, compatible parts, required quantities, and approved sourcing rules.",
      outcome: "Sourced parts plan",
      result: "Candidate components, compatibility evidence, package counts, total cost, and supplier handoff."
    }
  };

  const frontendButtons = Array.from(document.querySelectorAll("[data-frontend]"));
  const frontendName = document.querySelector("[data-frontend-name]");
  const frontendIntent = document.querySelector("[data-frontend-intent]");
  const frontendOutcome = document.querySelector("[data-frontend-outcome]");
  const frontendResult = document.querySelector("[data-frontend-result]");

  frontendButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const key = button.dataset.frontend;
      const model = key ? frontends[key] : null;
      if (!model) return;
      if (frontendName) frontendName.textContent = model.name;
      if (frontendIntent) frontendIntent.textContent = model.intent;
      if (frontendOutcome) frontendOutcome.textContent = model.outcome;
      if (frontendResult) frontendResult.textContent = model.result;
      frontendButtons.forEach((candidate) => {
        candidate.setAttribute("aria-selected", String(candidate === button));
      });
    });
  });

  const heroSystem = document.querySelector(".hero-system");
  const allowsMotion = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (heroSystem && allowsMotion && window.matchMedia("(pointer: fine)").matches) {
    heroSystem.addEventListener("pointermove", (event) => {
      const bounds = heroSystem.getBoundingClientRect();
      const x = (event.clientX - bounds.left) / bounds.width - 0.5;
      const y = (event.clientY - bounds.top) / bounds.height - 0.5;
      heroSystem.style.transform = `translate3d(${x * 8}px, ${y * 6}px, 0)`;
    });
    heroSystem.addEventListener("pointerleave", () => {
      heroSystem.style.transform = "translate3d(0, 0, 0)";
    });
  }
})();
