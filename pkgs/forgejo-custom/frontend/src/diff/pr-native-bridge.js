import { scheduleViewportWork } from "../shared/viewport.js";
import { applyLineDiffs, lineDiffOptionKey } from "./line-dom.js";
import { diffRenderOptions } from "./options.js";
import {
  changedCodeCellGroups,
  diffTableForBox,
  prDiffSelectors,
  pullDiffBoxes,
} from "./pr-dom.js";

const prDiffState = {
  queued: "queued",
  painted: "painted",
};

let prDiffObserver;
let prDiffObserverContainer;
let prDiffRenderQueued = false;

function currentLineNumberMode() {
  const params = new URLSearchParams(window.location.search);
  if (params.get("line-numbers") === "one" && params.get("style") !== "split") {
    return "one";
  }
  return "two";
}

function samePageSearchHref(params) {
  const search = params.toString();
  return search ? `?${search}` : window.location.pathname;
}

function diffQueryParams(params = new URLSearchParams(window.location.search)) {
  const next = new URLSearchParams();
  next.set("style", params.get("style") === "split" ? "split" : "unified");
  next.set("whitespace", params.get("whitespace") || "show-all");
  next.set("show-outdated", params.get("show-outdated") || "false");
  if (currentLineNumberMode() === "one") next.set("line-numbers", "one");
  return next;
}

function optionHrefForMode(mode) {
  const params = diffQueryParams();
  if (mode === "one") {
    params.set("style", "unified");
    params.set("line-numbers", "one");
  } else {
    params.delete("line-numbers");
  }
  return samePageSearchHref(params);
}

function hrefWithLineNumberMode(href, mode) {
  const url = new URL(href, window.location.href);
  if (url.origin !== window.location.origin) return null;
  if (!url.searchParams.has("style")) return null;

  if (mode === "one" && url.searchParams.get("style") !== "split") {
    url.searchParams.set("line-numbers", "one");
  } else {
    url.searchParams.delete("line-numbers");
  }

  const path = url.pathname === window.location.pathname ? "" : url.pathname;
  return `${path}${url.search}${url.hash}`;
}

function updateLineNumberOptionControls() {
  const mode = currentLineNumberMode();
  for (const item of document.querySelectorAll(
    "[data-barrett-pr-line-numbers-option]",
  )) {
    const itemMode = item.dataset.barrettPrLineNumbersOption;
    item.setAttribute("href", optionHrefForMode(itemMode));
    const input = item.querySelector('input[type="radio"]');
    if (input) input.checked = itemMode === mode;
  }
}

function preserveLineNumberModeInDiffLinks() {
  const mode = currentLineNumberMode();
  for (const link of document.querySelectorAll(
    ".diff-detail-actions a, .repository.pull.diff .ui.info.message a",
  )) {
    if (link.dataset.barrettPrLineNumbersOption) continue;
    const href = link.getAttribute("href");
    if (!href) continue;
    const nextHref = hrefWithLineNumberMode(href, mode);
    if (nextHref) link.setAttribute("href", nextHref);
  }

  const commitSelect = document.querySelector("#diff-commit-select");
  if (commitSelect?.dataset.queryparams) {
    const params = new URLSearchParams(commitSelect.dataset.queryparams);
    if (mode === "one") params.set("line-numbers", "one");
    else params.delete("line-numbers");
    commitSelect.dataset.queryparams = samePageSearchHref(params);
  }
}

function updateLineNumberModeUi() {
  updateLineNumberOptionControls();
  preserveLineNumberModeInDiffLinks();
}

function applyNativeLineDiffs(table, options) {
  const optionKey = lineDiffOptionKey(options);
  for (const group of changedCodeCellGroups(table)) {
    if (
      group.rows.every(
        (row) => row.dataset.barrettPrDiffAlgorithm === optionKey,
      )
    ) {
      continue;
    }

    applyLineDiffs({
      additions: group.additions,
      deletions: group.deletions,
      options,
    });

    for (const row of group.rows) {
      row.dataset.barrettPrDiffAlgorithm = optionKey;
    }
  }
}

function paintBox(box) {
  const diffTable = diffTableForBox(box);
  if (!diffTable) return false;
  const { nativeDiff, table } = diffTable;
  const options = diffRenderOptions();

  box.dataset.barrettPrDiffState = prDiffState.painted;
  nativeDiff.classList.add("barrett-pr-diff");
  nativeDiff.dataset.barrettPrDiffIndicators = options.diffIndicators;
  nativeDiff.dataset.barrettPrLineNumbers = currentLineNumberMode();

  applyNativeLineDiffs(table, options);
  return true;
}

function schedulePullDiffPainting(boxes = pullDiffBoxes()) {
  scheduleViewportWork(
    boxes.filter(
      (box) => box.dataset.barrettPrDiffState !== prDiffState.queued,
    ),
    paintBox,
    {
      margin: 1600,
      rootMargin: "1800px 0px",
      markDeferred: (box) => {
        box.dataset.barrettPrDiffState = prDiffState.queued;
      },
    },
  );
}

function queuePullDiffPainting() {
  if (prDiffRenderQueued) return;
  prDiffRenderQueued = true;
  window.setTimeout(() => {
    prDiffRenderQueued = false;
    schedulePullDiffPainting();
  }, 0);
}

function addedNodeMayContainDiffRows(node) {
  if (node.nodeType !== 1) return false;
  if (node.matches?.(".diff-file-box")) {
    return Boolean(node.querySelector(prDiffSelectors.table));
  }
  if (
    node.querySelector?.(`${prDiffSelectors.boxes} ${prDiffSelectors.table}`)
  ) {
    return true;
  }
  return (
    node.matches?.(prDiffSelectors.rows) ||
    Boolean(node.querySelector?.(prDiffSelectors.rows))
  );
}

function observePullDiffMutations() {
  const container = document.querySelector(prDiffSelectors.container);
  if (!container) return;
  if (prDiffObserver && prDiffObserverContainer === container) return;

  prDiffObserver?.disconnect();
  prDiffObserverContainer = container;
  prDiffObserver = new MutationObserver((records) => {
    if (
      records.some((record) =>
        Array.from(record.addedNodes).some(addedNodeMayContainDiffRows),
      )
    ) {
      queuePullDiffPainting();
    }
  });

  prDiffObserver.observe(container, { childList: true, subtree: true });
}

export function renderPullRequestDiffView() {
  const boxes = pullDiffBoxes();
  if (boxes.length === 0) return;
  updateLineNumberModeUi();
  observePullDiffMutations();
  schedulePullDiffPainting(boxes);
}

window.__barrettForgejoRepaintPullDiffs = renderPullRequestDiffView;
