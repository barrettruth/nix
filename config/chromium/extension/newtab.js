const port = chrome.runtime.connect({ name: "tab" });
const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
let isDark = darkQuery.matches;
let overlay = null;
let overlayResults = [];
let overlaySelectedIndex = 0;
let overlayRequestId = 0;
let overlayDisposition = "currentTab";
const darkPalette = {
  accent: "#7aa2f7",
  bg: "#121212",
  bgAlt: "#2d2d2d",
  border: "#3d3d3d",
  fg: "#e0e0e0",
  fgAlt: "#666666",
};
const lightPalette = {
  accent: "#3b5bdb",
  bg: "#f5f5f5",
  bgAlt: "#ebebeb",
  border: "#e8e8e8",
  fg: "#1a1a1a",
  fgAlt: "#999999",
};

function overlayPalette() {
  return isDark ? darkPalette : lightPalette;
}

function overlayBackdrop() {
  return isDark ? "rgba(0, 0, 0, 0.34)" : "rgba(15, 23, 42, 0.12)";
}

function applyOverlayTheme() {
  if (!overlay) return;
  const palette = overlayPalette();
  const host = overlay.host;
  host.style.setProperty("--midnight-bg", palette.bg);
  host.style.setProperty("--midnight-fg", palette.fg);
  host.style.setProperty("--midnight-bg-alt", palette.bgAlt);
  host.style.setProperty("--midnight-fg-alt", palette.fgAlt);
  host.style.setProperty("--midnight-border", palette.border);
  host.style.setProperty("--midnight-accent", palette.accent);
  host.style.setProperty("--midnight-backdrop", overlayBackdrop());
  host.style.setProperty(
    "--midnight-shadow",
    isDark ? "rgba(0, 0, 0, 0.4)" : "rgba(15, 23, 42, 0.16)",
  );
}

function ensureOverlay() {
  if (overlay) return overlay;
  const host = document.createElement("div");
  const shadow = host.attachShadow({ mode: "open" });
  const style = document.createElement("style");
  const backdrop = document.createElement("div");
  const panel = document.createElement("div");
  const search = document.createElement("label");
  const prompt = document.createElement("span");
  const input = document.createElement("input");
  const results = document.createElement("ul");

  style.textContent = `
    :host {
      all: initial;
    }

    .backdrop {
      position: fixed;
      inset: 0;
      z-index: 2147483647;
      display: none;
      align-items: flex-start;
      justify-content: center;
      padding: clamp(72px, 18vh, 180px) 16px 32px;
      box-sizing: border-box;
      background: var(--midnight-backdrop);
    }

    .backdrop.is-open {
      display: flex;
    }

    .panel {
      width: min(760px, 100%);
      background: var(--midnight-bg);
      color: var(--midnight-fg);
      border: 1px solid var(--midnight-border);
      box-shadow: 0 28px 96px var(--midnight-shadow);
      overflow: hidden;
      font:
        400 20px/1.2 Berkeley Mono,
        Symbols Nerd Font,
        monospace;
    }

    .search {
      display: flex;
      align-items: center;
      gap: 14px;
      padding: 18px 22px;
    }

    .prompt {
      color: var(--midnight-fg-alt);
      font-size: 20px;
      line-height: 1;
      user-select: none;
    }

    .input {
      flex: 1;
      min-width: 0;
      border: 0;
      padding: 0;
      background: transparent;
      color: var(--midnight-fg);
      outline: none;
      font:
        400 20px/1.2 Berkeley Mono,
        Symbols Nerd Font,
        monospace;
    }

    .input::placeholder {
      color: var(--midnight-fg-alt);
    }

    .results {
      list-style: none;
      margin: 0;
      padding: 0 10px 10px;
      display: flex;
      flex-direction: column;
      gap: 4px;
    }

    .result {
      width: 100%;
      display: block;
      border: 0;
      padding: 12px 14px;
      background: transparent;
      color: var(--midnight-fg);
      text-align: left;
      cursor: pointer;
      font:
        400 20px/1.2 Berkeley Mono,
        Symbols Nerd Font,
        monospace;
    }

    .result:hover,
    .result.is-selected {
      background: var(--midnight-bg-alt);
    }

    .result-url {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .result-match {
      color: var(--midnight-accent);
    }
  `;

  backdrop.className = "backdrop";
  panel.className = "panel";
  search.className = "search";
  prompt.className = "prompt";
  prompt.textContent = ">";
  input.className = "input";
  input.type = "text";
  input.autocomplete = "off";
  input.spellcheck = false;
  results.className = "results";

  search.append(prompt, input);
  panel.append(search, results);
  backdrop.append(panel);
  shadow.append(style, backdrop);
  (document.documentElement || document.body).append(host);

  overlay = { host, backdrop, input, results };
  applyOverlayTheme();

  input.addEventListener("input", () => {
    overlaySelectedIndex = 0;
    requestOverlayResults();
  });
  backdrop.addEventListener("mousedown", (e) => {
    if (e.target === backdrop) closeOverlay();
  });

  return overlay;
}

function overlayIsOpen() {
  return !!overlay && overlay.backdrop.classList.contains("is-open");
}

function overlayOwnsEvent(e) {
  return overlayIsOpen() && e.composedPath().includes(overlay.host);
}

function fillHighlightedUrl(container, text) {
  container.textContent = "";
  const query = ensureOverlay().input.value.toLowerCase().replace(/\s+/g, "");
  if (!query) {
    container.textContent = text;
    return;
  }

  const lower = text.toLowerCase();
  const matched = new Set();
  let cursor = 0;
  for (const char of query) {
    const index = lower.indexOf(char, cursor);
    if (index === -1) break;
    matched.add(index);
    cursor = index + 1;
  }

  for (let i = 0; i < text.length; i++) {
    const span = document.createElement("span");
    if (matched.has(i)) span.className = "result-match";
    span.textContent = text[i];
    container.append(span);
  }
}

function renderOverlayResults() {
  const state = ensureOverlay();
  state.results.textContent = "";
  if (!overlayResults.length) {
    state.results.style.display = "none";
    return;
  }
  state.results.style.display = "flex";

  overlayResults.forEach((result, index) => {
    const item = document.createElement("li");
    const button = document.createElement("button");
    const url = document.createElement("span");

    button.type = "button";
    button.className =
      index === overlaySelectedIndex ? "result is-selected" : "result";
    url.className = "result-url";
    fillHighlightedUrl(url, result.displayUrl || result.url);

    button.append(url);
    button.addEventListener("mouseenter", () => {
      if (overlaySelectedIndex === index) return;
      overlaySelectedIndex = index;
      renderOverlayResults();
    });
    button.addEventListener("click", () => openOverlayResult(index));

    item.append(button);
    state.results.append(item);
  });
}

function updateOverlayResults(nextResults) {
  overlayResults = nextResults;
  if (!overlayResults.length) overlaySelectedIndex = 0;
  else
    overlaySelectedIndex = Math.max(
      0,
      Math.min(overlaySelectedIndex, overlayResults.length - 1),
    );
  renderOverlayResults();
}

async function requestOverlayResults() {
  const state = ensureOverlay();
  const requestId = ++overlayRequestId;
  try {
    const response = await chrome.runtime.sendMessage({
      type: "searchHistory",
      text: state.input.value,
      limit: 11,
    });
    if (requestId !== overlayRequestId) return;
    updateOverlayResults(response?.results || []);
  } catch (_) {
    if (requestId !== overlayRequestId) return;
    updateOverlayResults([]);
  }
}

function moveOverlaySelection(delta) {
  if (!overlayResults.length) return;
  overlaySelectedIndex =
    (overlaySelectedIndex + delta + overlayResults.length) %
    overlayResults.length;
  renderOverlayResults();
}

function closeOverlay() {
  if (!overlayIsOpen()) return;
  overlay.backdrop.classList.remove("is-open");
  overlay.input.value = "";
  overlayResults = [];
  overlaySelectedIndex = 0;
  renderOverlayResults();
}

function openOverlayResult(index) {
  const result = overlayResults[index];
  if (!result?.url) return;
  closeOverlay();
  chrome.runtime.sendMessage({
    type: "openHistoryResult",
    url: result.url,
    disposition: overlayDisposition,
  });
}

function openOverlay(disposition = "currentTab") {
  const state = ensureOverlay();
  overlayRequestId++;
  overlaySelectedIndex = 0;
  overlayDisposition = disposition;
  state.input.value = "";
  applyOverlayTheme();
  state.backdrop.classList.add("is-open");
  renderOverlayResults();
  requestOverlayResults();
  queueMicrotask(() => state.input.focus());
}

function toggleOverlay(disposition = "currentTab") {
  if (overlayIsOpen() && overlayDisposition !== disposition) {
    closeOverlay();
    openOverlay(disposition);
    return;
  }
  if (overlayIsOpen()) closeOverlay();
  else openOverlay(disposition);
}

function handleOverlayKeydown(e) {
  if (!overlayOwnsEvent(e)) return false;
  if (e.key === "ArrowDown") {
    e.preventDefault();
    moveOverlaySelection(1);
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    moveOverlaySelection(-1);
  } else if (e.ctrlKey && !e.shiftKey && !e.altKey && !e.metaKey) {
    if (e.key === "n") {
      e.preventDefault();
      moveOverlaySelection(1);
    } else if (e.key === "p") {
      e.preventDefault();
      moveOverlaySelection(-1);
    } else {
      return false;
    }
  } else if (e.key === "Enter") {
    e.preventDefault();
    openOverlayResult(overlaySelectedIndex);
  } else if (e.key === "Escape") {
    e.preventDefault();
    closeOverlay();
  } else {
    return false;
  }
  return true;
}

port.onMessage.addListener((msg) => {
  if (msg.type === "setNumber")
    document.title = `${msg.number}. ${document.title.replace(/^\d+\. /, "")}`;
  else if (msg.type === "clearNumber")
    document.title = document.title.replace(/^\d+\. /, "");
  else if (msg.type === "toggleOverlay")
    toggleOverlay(msg.disposition || "currentTab");
});

darkQuery.addEventListener("change", (e) => {
  isDark = e.matches;
  applyOverlayTheme();
});

document.addEventListener(
  "keydown",
  (e) => {
    if (overlayOwnsEvent(e)) {
      handleOverlayKeydown(e);
      e.stopImmediatePropagation();
      return;
    }
    if (overlayIsOpen()) return;
    if (!e.ctrlKey || e.shiftKey || e.altKey || e.metaKey) return;
    const n = parseInt(e.key);
    if (n >= 1 && n <= 9) {
      e.preventDefault();
      e.stopImmediatePropagation();
      chrome.runtime.sendMessage({ type: "switchTab", number: n });
    }
  },
  true,
);
