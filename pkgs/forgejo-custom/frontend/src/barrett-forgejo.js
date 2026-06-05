import { replaceRepositoryFileIcons } from "./nonicons.js";
import { renderGithubStats } from "./github-stats.js";

function init() {
  renderGithubStats();
  replaceRepositoryFileIcons();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init, { once: true });
} else {
  init();
}

document.addEventListener("turbo:load", init);
