import { replaceRepositoryFileIcons } from "./nonicons.js";
import { renderDiffView } from "./pierre/diff-view.js";
import { renderFileView } from "./pierre/file-view.js";
import { renderPullRequestDiffView } from "./pierre/pr-diff-bridge.js";

function init() {
  renderFileView();
  renderDiffView();
  renderPullRequestDiffView();
  replaceRepositoryFileIcons();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init, { once: true });
} else {
  init();
}

document.addEventListener("turbo:load", init);
