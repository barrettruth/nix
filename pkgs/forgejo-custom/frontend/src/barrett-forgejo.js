import { renderGithubStats } from "./github-stats.js";

function removeNavbarLogo() {
  document.getElementById("navbar-logo")?.remove();
}

function init() {
  removeNavbarLogo();
  renderGithubStats();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init, { once: true });
} else {
  init();
}

document.addEventListener("turbo:load", init);
