(() => {
  "use strict";

  const video = document.querySelector("[data-demo-video]");
  const source = document.querySelector("[data-video-source]");
  const stage = document.querySelector(".video-stage");
  const tabs = Array.from(document.querySelectorAll(".video-tabs [data-video-mode]"));
  const play = document.querySelector("[data-video-play]");
  const playLabel = document.querySelector("[data-play-label]");
  const summary = document.querySelector("[data-video-summary]");
  const note = document.querySelector("[data-video-note]");
  const error = document.querySelector("[data-video-error]");
  const download = document.querySelector("[data-download]");
  if (!video || !source || !stage || !play || !playLabel || !summary || !note || !error || !download) return;

  const recordings = {
    before: {
      src: "assets/smartcart-before-solari.mp4",
      poster: "assets/smartcart-before-solari-poster.jpg",
      title: "Before Solari native SmartCart recording",
      duration: "0:40",
      summary: "Shopping list. Manual retailer search.",
      note: "Recorded flow · Retailer footage, not current prices or availability."
    },
    after: {
      src: "assets/smartcart-after-solari.mp4",
      poster: "assets/smartcart-after-solari-poster.jpg",
      title: "After Solari native SmartCart recording",
      duration: "0:25",
      summary: "Research packages. Compare the basket.",
      note: "DEBUG recorded replay · Demo Grocer test data · Not a live run."
    }
  };
  let mode = "after";
  let revision = 0;

  function showPlay(label = "Watch demo") {
    playLabel.replaceChildren(document.createTextNode(label));
    const duration = document.createElement("span");
    duration.className = "play-duration";
    duration.textContent = recordings[mode].duration;
    playLabel.append(duration);
    play.setAttribute("aria-label", `${label}: ${recordings[mode].title}, ${recordings[mode].duration}`);
    play.hidden = false;
  }

  function selectMode(nextMode) {
    if (!recordings[nextMode] || nextMode === mode) return;
    revision += 1;
    video.pause();
    mode = nextMode;
    const recording = recordings[mode];
    tabs.forEach((tab) => {
      const selected = tab.dataset.videoMode === mode;
      tab.setAttribute("aria-selected", String(selected));
      tab.tabIndex = selected ? 0 : -1;
      if (selected) stage.setAttribute("aria-labelledby", tab.id);
    });
    stage.dataset.videoState = mode;
    source.src = recording.src;
    video.poster = recording.poster;
    video.setAttribute("aria-label", recording.title);
    video.controls = false;
    summary.textContent = recording.summary;
    note.textContent = recording.note;
    download.href = recording.src;
    error.hidden = true;
    video.load();
    showPlay();
  }

  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => selectMode(tab.dataset.videoMode));
    tab.addEventListener("keydown", (event) => {
      let next;
      if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
      else if (event.key === "ArrowLeft") next = (index - 1 + tabs.length) % tabs.length;
      else if (event.key === "Home") next = 0;
      else if (event.key === "End") next = tabs.length - 1;
      else return;
      event.preventDefault();
      selectMode(tabs[next].dataset.videoMode);
      tabs[next].focus();
    });
  });

  play.addEventListener("click", async () => {
    const attemptedRevision = revision;
    video.controls = true;
    play.hidden = true;
    try {
      await video.play();
    } catch {
      if (attemptedRevision !== revision) return;
      error.hidden = false;
      showPlay("Try playback");
    }
  });
  video.addEventListener("play", () => {
    play.hidden = true;
    error.hidden = true;
    video.controls = true;
  });
  video.addEventListener("ended", () => showPlay("Watch again"));
  video.addEventListener("error", () => {
    error.hidden = false;
    video.controls = true;
    showPlay("Try playback");
  });
  video.controls = false;
  showPlay();
})();
