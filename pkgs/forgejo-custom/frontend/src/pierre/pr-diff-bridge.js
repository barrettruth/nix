const prDiffSelectors = {
  container: "#diff-file-boxes",
  boxes: '#diff-file-boxes .diff-file-box[id^="diff-"]',
  nativeDiff: ".file-body.code-diff",
  table: "table.chroma",
  rows: "tr[data-line-type]",
};

const prDiffState = {
  queued: "queued",
  painted: "painted",
};

let prDiffObserver;
let prDiffObserverContainer;
let prDiffRenderQueued = false;

function isPullRequestDiffPage() {
  return Boolean(document.querySelector(".repository.pull.diff"));
}

function isNearViewport(element, margin = 1600) {
  const rect = element.getBoundingClientRect();
  return rect.bottom >= -margin && rect.top <= window.innerHeight + margin;
}

function pullDiffBoxes() {
  if (!isPullRequestDiffPage()) return [];
  return Array.from(document.querySelectorAll(prDiffSelectors.boxes)).filter(
    (box) => box.querySelector(prDiffSelectors.table),
  );
}

function markCodeCell(cell) {
  const code = cell.querySelector("code.code-inner");
  if (!code) return;
  cell.dataset.barrettPrDiffCell = "1";
  code.dataset.barrettPrDiffCode = "1";
}

function paintRow(row) {
  if (row.dataset.barrettPrDiffRow === "1") return;
  row.dataset.barrettPrDiffRow = "1";
  for (const cell of row.querySelectorAll("td.lines-code")) {
    markCodeCell(cell);
  }
}

function paintBox(box) {
  const nativeDiff = box.querySelector(prDiffSelectors.nativeDiff);
  const table = nativeDiff?.querySelector(prDiffSelectors.table);
  if (!nativeDiff || !table) return false;

  box.dataset.barrettPrDiffState = prDiffState.painted;
  nativeDiff.classList.add("barrett-pr-diff");
  table.classList.add("barrett-pr-diff-table");

  for (const row of table.querySelectorAll(prDiffSelectors.rows)) {
    paintRow(row);
  }

  return true;
}

function sortBoxesForPaint(boxes) {
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

function schedulePullDiffPainting(boxes = pullDiffBoxes()) {
  const ordered = sortBoxesForPaint(boxes);
  const deferred = [];
  let paintedInitial = 0;

  for (const box of ordered) {
    if (isNearViewport(box) || paintedInitial === 0) {
      if (paintBox(box)) paintedInitial += 1;
    } else {
      box.dataset.barrettPrDiffState = prDiffState.queued;
      deferred.push(box);
    }
  }

  if (deferred.length === 0) return;

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          observer.unobserve(entry.target);
          paintBox(entry.target);
        }
      },
      { rootMargin: "1800px 0px" },
    );
    for (const box of deferred) observer.observe(box);
    return;
  }

  const runIdle =
    window.requestIdleCallback ||
    ((callback) =>
      window.setTimeout(() => callback({ timeRemaining: () => 0 }), 1));
  for (const box of deferred) runIdle(() => paintBox(box));
}

function queuePullDiffPainting() {
  if (prDiffRenderQueued) return;
  prDiffRenderQueued = true;
  window.setTimeout(() => {
    prDiffRenderQueued = false;
    schedulePullDiffPainting();
  }, 0);
}

function observePullDiffMutations() {
  const container = document.querySelector(prDiffSelectors.container);
  if (!container) return;
  if (prDiffObserver && prDiffObserverContainer === container) return;

  prDiffObserver?.disconnect();
  prDiffObserverContainer = container;
  prDiffObserver = new MutationObserver((records) => {
    let shouldPaint = false;

    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType !== 1) continue;

        const box = node.matches?.(".diff-file-box")
          ? node
          : node.closest?.(".diff-file-box");
        if (box?.querySelector(prDiffSelectors.table)) {
          shouldPaint = true;
          continue;
        }

        if (
          node.matches?.(prDiffSelectors.rows) ||
          node.querySelector?.(prDiffSelectors.rows)
        ) {
          shouldPaint = true;
        }
      }
    }

    if (shouldPaint) queuePullDiffPainting();
  });

  prDiffObserver.observe(container, { childList: true, subtree: true });
}

export function renderPullRequestDiffView() {
  const boxes = pullDiffBoxes();
  if (boxes.length === 0) return;
  observePullDiffMutations();
  schedulePullDiffPainting(boxes);
}

window.__barrettForgejoRepaintPullDiffs = renderPullRequestDiffView;
