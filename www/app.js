(function () {
  "use strict";

  const jsActionBtn = document.querySelector("[data-js-action]");
  if (jsActionBtn) {
    jsActionBtn.addEventListener("click", () => {
      const target = document.querySelector(jsActionBtn.getAttribute("data-js-action"));
      if (!target) return;
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      target.style.outline = "2px solid rgba(125, 211, 252, 0.75)";
      setTimeout(() => (target.style.outline = ""), 1200);
    });
  }

  const year = document.querySelector("[data-year]");
  if (year) year.textContent = String(new Date().getFullYear());
})();

