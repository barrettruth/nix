import { loadPierre } from "./client.js";
import { pierreTheme } from "./themes.js";

const diffTextCache = new Map();
const diffParseCache = new Map();
const diffSelectors = {
  boxes: '#diff-file-boxes .diff-file-box[id^="diff-"]',
  placeholder:
    '.barrett-pierre-diff-target[data-barrett-pierre-placeholder="1"]',
};
const diffState = {
  pending: "pending",
  rendering: "rendering",
  rendered: "rendered",
};
let diffBoxObserver;
let diffBoxObserverContainer;
let diffRenderQueued = false;

function pathParts() {
  return window.location.pathname
    .split("/")
    .filter(Boolean)
    .map(decodeURIComponent);
}

function repoPrefix(parts = pathParts()) {
  if (parts.length < 2) return null;
  return `/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`;
}
function diffUrlFromLocation() {
  const parts = pathParts();
  const prefix = repoPrefix(parts);
  if (!prefix) return null;
  const commitIndex = parts.indexOf("commit");
  if (commitIndex >= 0 && parts[commitIndex + 1]) {
    return `${prefix}/commit/${encodeURIComponent(parts[commitIndex + 1])}.diff`;
  }
  return null;
}

function preloadedDiffPromise(url) {
  const preload = window.__barrettForgejoDiffPreload;
  if (!preload || preload.url !== url) return null;
  return preload.textPromise || null;
}

function getDiffText(url) {
  const cached = diffTextCache.get(url);
  if (cached) return cached;

  const promise =
    preloadedDiffPromise(url) ||
    fetch(url, { credentials: "same-origin" }).then((response) => {
      if (!response.ok) throw new Error(response.statusText);
      return response.text();
    });

  const tracked = promise.catch((error) => {
    diffTextCache.delete(url);
    throw error;
  });
  diffTextCache.set(url, tracked);
  return tracked;
}

function getParsedDiff(url, parsePatchFiles, patchPromise = getDiffText(url)) {
  const cached = diffParseCache.get(url);
  if (cached) return cached;

  const parsed = patchPromise
    .then((patch) => parsePatchFiles(patch, `barrett:${url}`))
    .catch((error) => {
      diffParseCache.delete(url);
      throw error;
    });
  diffParseCache.set(url, parsed);
  return parsed;
}

function diffPathCandidates(box) {
  const placeholder = pierreDiffPlaceholder(box);
  const values = [
    placeholder?.dataset.newFilename,
    placeholder?.dataset.oldFilename,
    box.dataset.newFilename,
    box.dataset.oldFilename,
  ];
  return values
    .filter(Boolean)
    .map((value) => value.trim())
    .filter((value, index, all) => value && all.indexOf(value) === index);
}

function indexPatchFiles(parsed) {
  const files = parsed.flatMap((patch) => patch.files || []);
  const byName = new Map();
  for (const file of files) {
    if (file.name) byName.set(file.name, file);
    if (file.prevName) byName.set(file.prevName, file);
  }
  return byName;
}

function diffFileForBox(box, byName) {
  for (const path of diffPathCandidates(box)) {
    const file = byName.get(path);
    if (file) return file;
  }
  return null;
}

function diffStyleFromLocation() {
  return new URLSearchParams(window.location.search).get("style") === "split"
    ? "split"
    : "unified";
}

function diffRenderOptions() {
  return {
    diffStyle: diffStyleFromLocation(),
    disableFileHeader: true,
    enableLineSelection: true,
    lineDiffType: "char",
    maxLineDiffLength: 500,
    theme: pierreTheme,
  };
}

function isNearViewport(element, margin = 1200) {
  const rect = element.getBoundingClientRect();
  return rect.bottom >= -margin && rect.top <= window.innerHeight + margin;
}

function sortedDiffBoxes(boxes) {
  return boxes
    .map((box, index) => ({
      box,
      index,
      top: box.getBoundingClientRect().top,
      visible: isNearViewport(box),
    }))
    .sort((a, b) => {
      if (a.visible !== b.visible) return a.visible ? -1 : 1;
      return a.top - b.top || a.index - b.index;
    })
    .map(({ box }) => box);
}

function pierreDiffPlaceholder(box) {
  return box.querySelector(diffSelectors.placeholder);
}

function shouldRenderDiffBox(box) {
  return box.dataset.barrettPierreMode !== "native";
}

function diffBoxes() {
  return Array.from(document.querySelectorAll(diffSelectors.boxes));
}

function renderableDiffBoxes() {
  return diffBoxes().filter(shouldRenderDiffBox);
}

function showDiffRenderFallback(box, url) {
  const target = pierreDiffPlaceholder(box);
  if (!target) return;
  target.classList.add("barrett-pierre-diff-fallback");
  target.replaceChildren();

  const message = document.createElement("span");
  message.textContent = "Diff rendering failed.";
  target.append(message);

  if (url) {
    target.append(" ");
    const link = document.createElement("a");
    link.href = url;
    link.textContent = "Open raw diff";
    target.append(link);
  }
}

function mountDiffContainer(placeholder) {
  placeholder.classList.add("barrett-pierre-diff");
  placeholder.replaceChildren();
  const fileContainer = document.createElement("diffs-container");
  placeholder.append(fileContainer);
  return fileContainer;
}

function markDiffRendered(box) {
  let marked = false;
  return () => {
    if (marked) return;
    marked = true;
    requestAnimationFrame(() => {
      box.dataset.barrettPierreState = diffState.rendered;
      delete box.dataset.barrettPierreQueued;
    });
  };
}

function renderDiffBox(box, fileDiff, cacheKey, pierre) {
  if (box.dataset.barrettPierreState === diffState.rendered) return false;
  if (box.dataset.barrettPierreState === diffState.rendering) return false;

  const body = box.querySelector(".diff-file-body");
  const placeholder = pierreDiffPlaceholder(box);
  if (!body || !placeholder) {
    showDiffFallback(box, cacheKey);
    return false;
  }
  box.dataset.barrettPierreState = diffState.rendering;

  const fileContainer = mountDiffContainer(placeholder);
  const options = diffRenderOptions();
  const markRendered = markDiffRendered(box);
  options.onLineSelectionEnd = (range) => {
    if (!range) return;
    const prefix = range.side === "additions" ? "R" : "L";
    window.history.replaceState(
      null,
      "",
      `#${box.id || "diff"}${prefix}${range.start}`,
    );
  };
  options.onPostRender = markRendered;

  try {
    const instance = new pierre.FileDiff(options);
    const rendered = instance.render({
      fileDiff: {
        ...fileDiff,
        cacheKey: `${cacheKey}:${fileDiff.name || fileDiff.prevName || "file"}`,
      },
      fileContainer,
    });
    if (rendered) markRendered();
    return true;
  } catch (error) {
    console.warn("Pierre diff rendering failed", error);
    showDiffRenderFallback(box, cacheKey);
    delete box.dataset.barrettPierreState;
    delete box.dataset.barrettPierreQueued;
    return false;
  }
}

function showDiffFallback(box, url) {
  showDiffRenderFallback(box, url);
  delete box.dataset.barrettPierreState;
  delete box.dataset.barrettPierreQueued;
}

function showDiffFallbacks(boxes, url) {
  for (const box of boxes) showDiffFallback(box, url);
}

function markDiffPending(box) {
  if (!shouldRenderDiffBox(box)) return;
  if (box.dataset.barrettPierreState || box.dataset.barrettPierreQueued) return;
  const placeholder = pierreDiffPlaceholder(box);
  if (!placeholder) return;
  box.dataset.barrettPierreState = diffState.pending;
}

function markDiffsPending(boxes) {
  for (const box of boxes) markDiffPending(box);
}

function scheduleDiffRendering(boxes, byName, url, pierre) {
  const ordered = sortedDiffBoxes(boxes);
  const renderOne = (box) => {
    if (!shouldRenderDiffBox(box)) return false;
    const fileDiff = diffFileForBox(box, byName);
    if (!fileDiff) {
      showDiffFallback(box, url);
      return false;
    }
    return renderDiffBox(box, fileDiff, url, pierre);
  };

  const pending = [];
  let renderedInitial = 0;
  for (const box of ordered) {
    const state = box.dataset.barrettPierreState;
    if (
      state === diffState.rendered ||
      state === diffState.rendering ||
      box.dataset.barrettPierreQueued
    ) {
      continue;
    }
    if (isNearViewport(box) || renderedInitial === 0) {
      if (renderOne(box)) renderedInitial += 1;
    } else {
      pending.push(box);
      box.dataset.barrettPierreQueued = "1";
    }
  }

  if (pending.length === 0) return;

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const box = entry.target;
          observer.unobserve(box);
          renderOne(box);
        }
      },
      { rootMargin: "1600px 0px" },
    );
    for (const box of pending) observer.observe(box);
    return;
  }

  const runIdle =
    window.requestIdleCallback ||
    ((callback) =>
      window.setTimeout(() => callback({ timeRemaining: () => 0 }), 1));
  for (const box of pending) {
    runIdle(() => renderOne(box));
  }
}

function queueDiffRendering() {
  if (diffRenderQueued) return;
  diffRenderQueued = true;
  window.setTimeout(() => {
    diffRenderQueued = false;
    renderDiffView();
  }, 0);
}

function observeDiffBoxes() {
  const container = document.querySelector("#diff-file-boxes");
  if (!container) return;
  if (diffBoxObserver && diffBoxObserverContainer === container) return;
  diffBoxObserver?.disconnect();
  diffBoxObserverContainer = container;
  diffBoxObserver = new MutationObserver((records) => {
    let shouldRender = false;
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType !== 1) continue;
        const boxes = [];
        if (node.matches?.('.diff-file-box[id^="diff-"]')) boxes.push(node);
        boxes.push(
          ...(node.querySelectorAll?.('.diff-file-box[id^="diff-"]') ?? []),
        );
        for (const box of boxes) {
          if (!shouldRenderDiffBox(box)) continue;
          markDiffPending(box);
          shouldRender = true;
        }
      }
    }
    if (shouldRender) queueDiffRendering();
  });
  diffBoxObserver.observe(container, { childList: true, subtree: true });
}

export async function renderDiffView() {
  const boxes = renderableDiffBoxes();
  if (boxes.length === 0) return;
  const url = diffUrlFromLocation();
  if (!url) return;
  markDiffsPending(boxes);
  observeDiffBoxes();

  try {
    const pierrePromise = loadPierre();
    const patchPromise = getDiffText(url);
    const pierre = await pierrePromise;
    const parsed = await getParsedDiff(
      url,
      pierre.parsePatchFiles,
      patchPromise,
    );
    const indexed = indexPatchFiles(parsed);
    scheduleDiffRendering(boxes, indexed, url, pierre);
  } catch (error) {
    console.warn("Pierre diff rendering failed", error);
    showDiffFallbacks(boxes, url);
  }
}
