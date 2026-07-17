(() => {
  "use strict";

  const toggle = document.querySelector("[data-nav-toggle]");
  const nav = document.querySelector("[data-site-nav]");

  if (toggle && nav) {
    const closeNav = () => {
      toggle.setAttribute("aria-expanded", "false");
      nav.dataset.open = "false";
    };

    toggle.addEventListener("click", () => {
      const isOpen = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!isOpen));
      nav.dataset.open = String(!isOpen);
    });

    nav.addEventListener("click", (event) => {
      if (event.target.closest("a")) closeNav();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closeNav();
        toggle.focus();
      }
    });

    window.addEventListener("resize", () => {
      if (window.innerWidth > 820) closeNav();
    });
  }

  document.querySelectorAll("[data-demo-form]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const status = form.querySelector("[data-form-status]");
      if (status) {
        status.textContent = "Demo only: nothing was sent or stored. Add and verify a real support channel before publishing.";
        status.focus();
      }
    });
  });
})();
