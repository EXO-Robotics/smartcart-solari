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
