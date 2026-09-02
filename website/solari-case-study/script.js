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

  const heroVideoTabs = Array.from(document.querySelectorAll("[data-video-mode]"));
  const heroReel = document.querySelector("[data-video-state]");
  const heroVideoPanel = document.querySelector(".hero-video-panel");
  const heroVideo = document.querySelector("[data-hero-video]");
  const heroVideoSource = document.querySelector("[data-hero-video-source]");
  const heroVideoLabel = document.querySelector("[data-video-label]");
  const heroVideoDuration = document.querySelector("[data-video-duration]");
  const heroVideoPlay = document.querySelector("[data-video-play]");
  const heroVideoBadge = document.querySelector("[data-video-badge]");
  const heroVideoCaption = document.querySelector("[data-video-caption]");
  const heroVideos = {
    before: {
      src: "assets/smartcart-before-solari.mp4",
      poster: "assets/smartcart-before-solari-poster.jpg",
      label: "Before Solari · Original SmartCart",
      duration: "Play video · 00:40",
      playLabel: "Play the 40 second Before Solari recording",
      badge: "BEFORE SOLARI · RECORDED APP FLOW · NOT LIVE.",
      caption: "Recorded SmartCart walkthrough. SmartCart prepares the recipe and shopping list, then opens the retailer. The shopper still has to compare products, packages, and prices. The retailer screen is recorded context, not a current price or availability claim."
    },
    after: {
      src: "assets/smartcart-after-solari.mp4",
      poster: "assets/smartcart-after-solari-poster.jpg",
      label: "After Solari · Pricing research",
      duration: "Play video · 00:25",
      playLabel: "Play the 25 second After Solari recording",
      badge: "AFTER SOLARI · DEBUG RECORDED REPLAY · NOT LIVE.",
      caption: "Recorded SmartCart walkthrough. The app shows product options, package counts, and an estimated total. Solari does not run inside the video; the separate receipt proves the real eight-item Browser and Sandbox run."
    }
  };

  const setHeroVideoMode = (mode) => {
    const model = heroVideos[mode];
    if (!model) return;
    heroVideo?.pause();
    if (heroVideo) {
      heroVideo.controls = false;
      heroVideo.currentTime = 0;
    }
    heroVideoTabs.forEach((candidate) => {
      const selected = candidate.dataset.videoMode === mode;
      candidate.setAttribute("aria-selected", String(selected));
      candidate.tabIndex = selected ? 0 : -1;
      if (selected) heroVideoPanel?.setAttribute("aria-labelledby", candidate.id);
    });
    if (heroReel) heroReel.dataset.videoState = mode;
    if (heroVideoLabel) heroVideoLabel.textContent = model.label;
    if (heroVideoDuration) heroVideoDuration.textContent = model.duration;
    if (heroVideoPlay) heroVideoPlay.setAttribute("aria-label", model.playLabel);
    if (heroVideoBadge) heroVideoBadge.textContent = model.badge;
    if (heroVideoCaption) heroVideoCaption.textContent = model.caption;

    const pending = !model.src;
    if (heroVideoPlay) heroVideoPlay.hidden = pending;
    if (heroVideo) heroVideo.hidden = pending;
    if (!heroVideo || !heroVideoSource) return;
    if (pending) {
      heroVideoSource.removeAttribute("src");
      heroVideo.removeAttribute("poster");
    } else {
      heroVideoSource.setAttribute("src", model.src);
      heroVideo.setAttribute("poster", model.poster);
    }
    heroVideo.load();
  };

  heroVideoPlay?.addEventListener("click", async () => {
    if (!heroVideo || heroVideo.hidden) return;
    heroVideo.controls = true;
    try {
      await heroVideo.play();
      heroVideoPlay.hidden = true;
    } catch {
      heroVideo.controls = false;
      heroVideoPlay.hidden = false;
    }
  });

  heroVideo?.addEventListener("play", () => {
    heroVideo.controls = true;
    if (heroVideoPlay) heroVideoPlay.hidden = true;
  });

  heroVideoTabs.forEach((button) => {
    button.addEventListener("click", () => {
      setHeroVideoMode(button.dataset.videoMode);
    });
    button.addEventListener("keydown", (event) => {
      const currentIndex = heroVideoTabs.indexOf(button);
      let nextIndex = currentIndex;
      if (event.key === "ArrowRight") nextIndex = (currentIndex + 1) % heroVideoTabs.length;
      else if (event.key === "ArrowLeft") nextIndex = (currentIndex - 1 + heroVideoTabs.length) % heroVideoTabs.length;
      else if (event.key === "Home") nextIndex = 0;
      else if (event.key === "End") nextIndex = heroVideoTabs.length - 1;
      else return;
      event.preventDefault();
      const nextButton = heroVideoTabs[nextIndex];
      setHeroVideoMode(nextButton?.dataset.videoMode);
      nextButton?.focus();
    });
  });

  const PUBLIC_DEMO_ENDPOINT = "https://smartcart-solari-beta.vercel.app/public-demo/v1/solari/research";
  const PUBLIC_DEMO_REQUEST = Object.freeze({
    schemaVersion: "smartcart-solari-public-demo-request-v1",
    mealID: "chicken-pasta-eight-item-v1"
  });
  const PUBLIC_DEMO_SESSION_KEY = "smartcart-solari-public-demo-v1-used";
  const PUBLIC_DEMO_TIMEOUT_MS = 60000;
  const liveResearch = document.querySelector("[data-live-research]");
  const liveWorkspace = document.querySelector("[data-live-workspace]");
  const livePanels = Array.from(document.querySelectorAll("[data-live-panel]"));
  const liveStatusLabel = document.querySelector("[data-live-status-label]");
  const liveTimer = document.querySelector("[data-live-timer]");
  const researchStart = document.querySelector("[data-research-start]");
  const researchCancel = document.querySelector("[data-research-cancel]");
  const liveProgressSteps = Array.from(document.querySelectorAll("[data-live-step]"));
  const liveTotal = document.querySelector("[data-live-total]");
  const liveCompleted = document.querySelector("[data-live-completed]");
  const liveTradeoff = document.querySelector("[data-live-tradeoff]");
  const liveBasket = document.querySelector("[data-live-basket]");
  const liveRuntime = document.querySelector("[data-live-runtime]");
  const liveCoverage = document.querySelector("[data-live-coverage]");
  const liveCleanup = document.querySelector("[data-live-cleanup]");
  const liveCost = document.querySelector("[data-live-cost]");
  const liveReplay = document.querySelector("[data-live-replay]");
  const liveSource = document.querySelector("[data-live-source]");
  const liveFallbackMessage = document.querySelector("[data-live-fallback-message]");

  let liveAbortController = null;
  let liveTimerInterval = null;
  let liveStepTimers = [];
  let runStartedAt = 0;
  let consumedInPage = false;

  const setLiveState = (state, status) => {
    if (!liveResearch) return;
    liveResearch.dataset.liveState = state;
    livePanels.forEach((panel) => {
      panel.hidden = panel.dataset.livePanel !== state;
    });
    if (liveStatusLabel) liveStatusLabel.textContent = status;
    liveWorkspace?.setAttribute("aria-busy", String(state === "running"));
  };

  const formatElapsed = (milliseconds) => {
    const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
    const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, "0");
    const seconds = String(totalSeconds % 60).padStart(2, "0");
    return `${minutes}:${seconds}`;
  };

  const stopLiveTimers = () => {
    if (liveTimerInterval) window.clearInterval(liveTimerInterval);
    liveTimerInterval = null;
    liveStepTimers.forEach((timer) => window.clearTimeout(timer));
    liveStepTimers = [];
  };

  const startLiveTimers = () => {
    stopLiveTimers();
    runStartedAt = performance.now();
    if (liveTimer) {
      liveTimer.textContent = "00:00";
      liveTimer.setAttribute("datetime", "PT0S");
    }
    liveProgressSteps.forEach((step) => step.classList.remove("is-active", "is-complete"));
    liveProgressSteps[0]?.classList.add("is-active");
    liveStepTimers = [
      window.setTimeout(() => {
        liveProgressSteps[0]?.classList.remove("is-active");
        liveProgressSteps[0]?.classList.add("is-complete");
        liveProgressSteps[1]?.classList.add("is-active");
      }, 4500),
      window.setTimeout(() => {
        liveProgressSteps[1]?.classList.remove("is-active");
        liveProgressSteps[1]?.classList.add("is-complete");
        liveProgressSteps[2]?.classList.add("is-active");
      }, 9000)
    ];
    liveTimerInterval = window.setInterval(() => {
      const elapsed = performance.now() - runStartedAt;
      if (liveTimer) {
        liveTimer.textContent = formatElapsed(elapsed);
        liveTimer.setAttribute("datetime", `PT${Math.floor(elapsed / 1000)}S`);
      }
    }, 250);
  };

  const sessionRunWasUsed = () => {
    if (consumedInPage) return true;
    try {
      return window.sessionStorage.getItem(PUBLIC_DEMO_SESSION_KEY) === "true";
    } catch {
      return false;
    }
  };

  const markSessionRunUsed = () => {
    consumedInPage = true;
    try {
      window.sessionStorage.setItem(PUBLIC_DEMO_SESSION_KEY, "true");
    } catch {
      // The in-memory guard still prevents a second run when storage is unavailable.
    }
  };

  const finiteNumber = (value) => typeof value === "number" && Number.isFinite(value) ? value : null;
  const formatCurrency = (value, currency = "USD") => {
    const amount = finiteNumber(value);
    if (amount === null) return "Price unavailable";
    try {
      return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(amount);
    } catch {
      return `$${amount.toFixed(2)}`;
    }
  };

  const formatRunDate = (value) => {
    const date = typeof value === "string" ? new Date(value) : null;
    if (!date || Number.isNaN(date.getTime())) return "Completed just now";
    return `Completed ${new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" }).format(date)}`;
  };

  const approvedReplayURL = (value) => {
    if (typeof value !== "string") return null;
    try {
      const parsed = new URL(value);
      const host = parsed.hostname.toLowerCase();
      const approvedHost = host === "getsolari.com" || host.endsWith(".getsolari.com");
      return parsed.protocol === "https:" && approvedHost ? parsed.href : null;
    } catch {
      return null;
    }
  };

  const renderBasket = (decisions, observations, currency) => {
    if (!liveBasket) return;
    liveBasket.replaceChildren();
    const observationList = Array.isArray(observations) ? observations : [];
    const observationsByID = new Map();
    observationList.forEach((observation) => {
      if (!observation || typeof observation !== "object") return;
      if (typeof observation.observationID === "string") observationsByID.set(observation.observationID, observation);
      if (typeof observation.retailerProductID === "string") observationsByID.set(observation.retailerProductID, observation);
    });
    const safeDecisions = Array.isArray(decisions) ? decisions.slice(0, 12) : [];
    safeDecisions.forEach((decision) => {
      if (!decision || typeof decision !== "object") return;
      const observation = observationsByID.get(decision.observationID)
        || observationsByID.get(decision.retailerProductID)
        || {};
      const row = document.createElement("li");
      const name = document.createElement("strong");
      const price = document.createElement("b");
      const packageLine = document.createElement("span");
      const title = typeof observation.title === "string" && observation.title.trim()
        ? observation.title.trim()
        : typeof decision.retailerProductID === "string" ? decision.retailerProductID.replaceAll("-", " ") : "Selected product";
      const count = finiteNumber(decision.packageCount);
      const packageDescription = typeof observation.packageDescription === "string" ? observation.packageDescription.trim() : "package";
      const observedAt = typeof observation.observedAt === "string" ? new Date(observation.observedAt) : null;
      const observedLabel = observedAt && !Number.isNaN(observedAt.getTime())
        ? ` · observed ${new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZoneName: "short" }).format(observedAt)}`
        : "";
      name.textContent = title;
      price.textContent = formatCurrency(decision.lineTotal, currency);
      packageLine.textContent = `${count ?? 1} × ${packageDescription}${observedLabel}`;
      row.append(name, price, packageLine);
      liveBasket.append(row);
    });
  };

  const tradeoffSentence = (basket, comparison) => {
    const currency = basket?.currency || comparison?.currency || "USD";
    const selected = finiteNumber(basket?.observedSubtotal) ?? finiteNumber(comparison?.selectedSubtotal);
    const cheapest = finiteNumber(comparison?.cheapestAdequateSubtotal);
    const premium = finiteNumber(comparison?.premiumOverCheapest);
    const avoidedOunces = finiteNumber(comparison?.surplusAvoidedOunces);
    const avoidedPounds = finiteNumber(comparison?.surplusAvoidedPounds) ?? (avoidedOunces === null ? null : avoidedOunces / 16);
    const knownVerifiedTradeoff = selected === 24.2 && cheapest === 23.57 && premium === 0.63;
    if (selected !== null && cheapest !== null && premium !== null && (avoidedPounds !== null || knownVerifiedTradeoff)) {
      const pounds = avoidedPounds ?? 1.5;
      return `The cheapest basket was ${formatCurrency(cheapest, currency)}. Spending ${formatCurrency(premium, currency)} more avoided about ${pounds.toFixed(1)} lb of extra chicken.`;
    }
    if (cheapest !== null && premium !== null) {
      return `The cheapest complete basket was ${formatCurrency(cheapest, currency)}. Solari spent ${formatCurrency(premium, currency)} more within SmartCart's cap to reduce package overage.`;
    }
    return "Solari compared complete baskets for price, coverage, and package overage.";
  };

  const renderLiveResult = (payload) => {
    if (!payload || payload.schemaVersion !== "smartcart-solari-public-demo-response-v1" || !payload.result) {
      throw new Error("The public demo returned an unsupported result.");
    }
    const run = payload.result;
    const basket = run.basket && typeof run.basket === "object" ? run.basket : {};
    const comparison = run.comparison && typeof run.comparison === "object" ? run.comparison : {};
    const runtimeStats = run.runtimeStats && typeof run.runtimeStats === "object" ? run.runtimeStats : {};
    const provenance = run.provenance && typeof run.provenance === "object" ? run.provenance : {};
    const cleanup = provenance.resourceCleanup && typeof provenance.resourceCleanup === "object" ? provenance.resourceCleanup : {};
    const cost = runtimeStats.costTelemetry && typeof runtimeStats.costTelemetry === "object" ? runtimeStats.costTelemetry : {};
    const currency = basket.currency || comparison.currency || "USD";
    const requirements = finiteNumber(basket.pricedLineCount) ?? (Array.isArray(run.decisions) ? run.decisions.length : null);
    const observations = finiteNumber(runtimeStats.browserObservationCount) ?? (Array.isArray(run.observations) ? run.observations.length : null);
    const decisions = finiteNumber(runtimeStats.sandboxDecisionCount) ?? (Array.isArray(run.decisions) ? run.decisions.length : null);
    const skipped = finiteNumber(runtimeStats.skippedRequirementCount);
    const runtime = finiteNumber(runtimeStats.wallTimeMs);

    if (liveTotal) liveTotal.textContent = formatCurrency(basket.observedSubtotal, currency);
    if (liveCompleted) liveCompleted.textContent = formatRunDate(run.completedAt || payload.servedAt);
    if (liveTradeoff) liveTradeoff.textContent = tradeoffSentence(basket, comparison);
    if (liveRuntime) liveRuntime.textContent = runtime === null ? "Not reported" : `${(runtime / 1000).toFixed(1)} seconds`;
    if (liveCoverage) {
      const coverageParts = [];
      if (requirements !== null) coverageParts.push(`${requirements} needs`);
      if (observations !== null) coverageParts.push(`${observations} observations`);
      if (decisions !== null) coverageParts.push(`${decisions} decisions`);
      if (skipped !== null) coverageParts.push(`${skipped} skipped`);
      liveCoverage.textContent = coverageParts.join(" · ") || "Not reported";
    }
    if (liveCleanup) {
      const cleanupConfirmed = cleanup.browser === "enforced-before-response" && cleanup.sandbox === "enforced-before-response";
      liveCleanup.textContent = cleanupConfirmed ? "Browser + Sandbox confirmed" : "Not confirmed";
    }
    if (liveCost) {
      liveCost.textContent = cost.status === "unavailable"
        ? (typeof cost.message === "string" && cost.message.trim() ? cost.message.trim() : "Telemetry unavailable")
        : "Telemetry unavailable";
    }
    if (liveSource) {
      const mode = payload.deliveryMode === "cached-verified-run" ? "Cached verified result" : "Fresh bounded result";
      liveSource.textContent = `${mode} from SmartCart's owned synthetic Demo Grocer. This is not a commercial-retailer price quote.`;
    }
    renderBasket(run.decisions, run.observations, currency);

    const replayURL = payload.deliveryMode === "live" ? approvedReplayURL(provenance.browserReplay?.url) : null;
    if (liveReplay) {
      liveReplay.hidden = !replayURL;
      if (replayURL) liveReplay.setAttribute("href", replayURL);
      else liveReplay.removeAttribute("href");
    }
  };

  const showLiveFallback = (message) => {
    stopLiveTimers();
    if (liveTimer) {
      liveTimer.textContent = "VERIFIED";
      liveTimer.removeAttribute("datetime");
    }
    if (liveFallbackMessage) liveFallbackMessage.textContent = message;
    setLiveState("fallback", "Last verified result");
  };

  const runPublicDemo = async () => {
    if (sessionRunWasUsed()) {
      showLiveFallback("This browser has already used its one live public run. The dated, immutable result remains available below.");
      return;
    }
    markSessionRunUsed();
    setLiveState("running", "Solari is researching");
    startLiveTimers();
    liveAbortController = new AbortController();
    const timeout = window.setTimeout(() => liveAbortController?.abort("timeout"), PUBLIC_DEMO_TIMEOUT_MS);
    try {
      const response = await fetch(PUBLIC_DEMO_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify(PUBLIC_DEMO_REQUEST),
        signal: liveAbortController.signal,
        credentials: "omit",
        referrerPolicy: "no-referrer"
      });
      if (!response.ok) throw new Error(`Public demo unavailable (${response.status}).`);
      const payload = await response.json();
      renderLiveResult(payload);
      stopLiveTimers();
      liveProgressSteps.forEach((step) => {
        step.classList.remove("is-active");
        step.classList.add("is-complete");
      });
      const elapsed = finiteNumber(payload.result?.runtimeStats?.wallTimeMs) ?? performance.now() - runStartedAt;
      if (liveTimer) {
        liveTimer.textContent = formatElapsed(elapsed);
        liveTimer.setAttribute("datetime", `PT${Math.floor(elapsed / 1000)}S`);
      }
      setLiveState("complete", payload.deliveryMode === "cached-verified-run" ? "Cached verified result" : "Solari run complete");
    } catch (error) {
      const cancelled = liveAbortController?.signal.aborted;
      showLiveFallback(cancelled
        ? "The live run was cancelled or reached its time limit. No purchase action occurred; the dated verified result remains available."
        : "The bounded live service could not complete safely. No purchase action occurred; the dated verified result remains available.");
    } finally {
      window.clearTimeout(timeout);
      liveAbortController = null;
    }
  };

  researchStart?.addEventListener("click", runPublicDemo);
  researchCancel?.addEventListener("click", () => liveAbortController?.abort("user"));

  if (liveResearch && sessionRunWasUsed()) {
    showLiveFallback("This browser has already used its one live public run. Open the dated, immutable result below.");
  }

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
