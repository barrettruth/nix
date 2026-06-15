import { FileTree } from "@pierre/trees";

const OCTICON_EXPAND =
  '<svg viewBox="0 0 16 16" width="16" height="16" class="svg octicon-sidebar-expand" aria-hidden="true"><path d="m4.177 7.823 2.396-2.396A.25.25 0 0 1 7 5.604v4.792a.25.25 0 0 1-.427.177L4.177 8.177a.25.25 0 0 1 0-.354Z"></path><path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25H9.5v-13Zm12.5 13a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H11v13Z"></path></svg>';

const OCTICON_COLLAPSE =
  '<svg viewBox="0 0 16 16" width="16" height="16" class="svg octicon-sidebar-collapse" aria-hidden="true"><path d="M6.823 7.823a.25.25 0 0 1 0 .354l-2.396 2.396A.25.25 0 0 1 4 10.396V5.604a.25.25 0 0 1 .427-.177Z"></path><path d="M1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25V1.75C0 .784.784 0 1.75 0ZM1.5 1.75v12.5c0 .138.112.25.25.25H9.5v-13H1.75a.25.25 0 0 0-.25.25ZM11 14.5h3.25a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H11Z"></path></svg>';

const STATE_KEY = "pierre-ft-open";

let activeTree = null;
let pendingUrl = null;

function meta(name) {
  const el = document.querySelector(`meta[name="${name}"]`);
  return el ? el.getAttribute("content") || "" : "";
}

function readContext() {
  const treeListUrl = meta("pierre-ft-tree-list");
  if (!treeListUrl) return null;
  return {
    treeListUrl,
    srcPrefix: meta("pierre-ft-src-prefix"),
    currentPath: meta("pierre-ft-current-path"),
    isFile: meta("pierre-ft-is-file") === "1",
    repoName: meta("pierre-ft-repo"),
  };
}

function isOpen() {
  return localStorage.getItem(STATE_KEY) !== "0";
}

function applyOpenClass() {
  document.documentElement.classList.toggle("pierre-ft-open", isOpen());
}

function syncToggle() {
  const btn = document.querySelector(".pierre-ft-toggle");
  if (btn) btn.innerHTML = isOpen() ? OCTICON_EXPAND : OCTICON_COLLAPSE;
}

function setOpen(value) {
  localStorage.setItem(STATE_KEY, value ? "1" : "0");
  applyOpenClass();
  syncToggle();
}

function ensureToggle() {
  const row = document.querySelector(".repo-button-row .button-sequence");
  if (!row || row.querySelector(".pierre-ft-toggle")) return;
  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = "ui compact basic button pierre-ft-toggle";
  btn.setAttribute("data-tooltip-content", "Toggle file browser");
  btn.setAttribute("aria-label", "Toggle file browser");
  btn.innerHTML = isOpen() ? OCTICON_EXPAND : OCTICON_COLLAPSE;
  btn.addEventListener("click", () => setOpen(!isOpen()));
  row.insertBefore(btn, row.firstElementChild);
}

function ensureDrawer(ctx) {
  let drawer = document.getElementById("pierre-ft-drawer");
  if (!drawer) {
    drawer = document.createElement("aside");
    drawer.id = "pierre-ft-drawer";
    const head = document.createElement("div");
    head.className = "pierre-ft-head";
    const mountPoint = document.createElement("div");
    mountPoint.className = "pierre-ft-mount";
    mountPoint.id = "pierre-ft-mount";
    drawer.append(head, mountPoint);
    document.body.appendChild(drawer);
  }
  const nav =
    document.querySelector("#navbar") ||
    document.querySelector(".secondary-nav");
  if (nav) {
    const bottom = Math.max(0, Math.round(nav.getBoundingClientRect().bottom));
    drawer.style.top = `${bottom}px`;
  }
  drawer.querySelector(".pierre-ft-head").textContent = ctx.repoName || "Files";
  return drawer;
}

function ancestorsOf(path) {
  const parts = path.split("/").filter(Boolean);
  const out = [];
  for (let i = 1; i < parts.length; i += 1)
    out.push(parts.slice(0, i).join("/"));
  return out;
}

function navigateTo(ctx, path) {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  window.location.assign(`${ctx.srcPrefix}/${encoded}`);
}

function focusCurrent(tree, ctx) {
  if (!ctx.currentPath) return;
  try {
    tree.scrollToPath(ctx.currentPath, { focus: false });
  } catch {}
}

async function renderTree(ctx) {
  const drawer = ensureDrawer(ctx);
  const mountPoint = drawer.querySelector("#pierre-ft-mount");
  if (mountPoint.dataset.treeUrl === ctx.treeListUrl) {
    if (activeTree) focusCurrent(activeTree, ctx);
    return;
  }
  if (pendingUrl === ctx.treeListUrl) return;
  pendingUrl = ctx.treeListUrl;
  try {
    let paths;
    try {
      const response = await fetch(ctx.treeListUrl, {
        credentials: "same-origin",
        headers: { "X-Requested-With": "XMLHttpRequest" },
      });
      if (!response.ok) throw new Error(response.statusText);
      paths = await response.json();
    } catch (error) {
      console.warn("[pierre-file-tree] tree list load failed", error);
      return;
    }
    if (!Array.isArray(paths) || paths.length === 0) return;
    const fileSet = new Set(paths);
    if (activeTree) {
      try {
        activeTree.cleanUp();
      } catch {}
      activeTree = null;
    }
    mountPoint.replaceChildren();
    const selected =
      ctx.isFile && fileSet.has(ctx.currentPath) ? [ctx.currentPath] : [];
    const tree = new FileTree({
      paths,
      search: true,
      initialExpansion: "closed",
      initialExpandedPaths: ctx.currentPath ? ancestorsOf(ctx.currentPath) : [],
      initialSelectedPaths: selected,
      onSelectionChange: (selectedPaths) => {
        const path = selectedPaths[0];
        if (!path || !fileSet.has(path) || path === ctx.currentPath) return;
        navigateTo(ctx, path);
      },
    });
    tree.render({ containerWrapper: mountPoint });
    activeTree = tree;
    mountPoint.dataset.treeUrl = ctx.treeListUrl;
    focusCurrent(tree, ctx);
  } finally {
    pendingUrl = null;
  }
}

export function initFileTree() {
  const ctx = readContext();
  document.documentElement.classList.toggle("pierre-ft-has-tree", Boolean(ctx));
  if (!ctx) return;
  applyOpenClass();
  ensureToggle();
  renderTree(ctx);
  requestAnimationFrame(() => {
    document.documentElement.classList.add("pierre-ft-anim");
  });
}
