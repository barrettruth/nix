(function () {
  if (window.__midnightLoaded) return;
  window.__midnightLoaded = true;

  const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
  let isDark = darkQuery.matches;
  let currentNumber = null;

  function theme() {
    return isDark ? MIDNIGHT : DAYLIGHT;
  }

  // --- Favicon tab numbers ---

  function setFavicon(number) {
    currentNumber = number;
    const t = theme();
    const sz = number > 9 ? 14 : 20;
    const y = number > 9 ? 21 : 22;
    const svg =
      `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">` +
      `<rect width="32" height="32" rx="6" fill="${t.bgAlt}"/>` +
      `<text x="16" y="${y}" text-anchor="middle" font-family="system-ui,sans-serif" ` +
      `font-size="${sz}" font-weight="700" fill="${t.accent}">${number}</text></svg>`;

    const href = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);

    function apply() {
      document.querySelectorAll("link[rel*='icon']").forEach((el) => el.remove());
      const link = document.createElement("link");
      link.rel = "icon";
      link.type = "image/svg+xml";
      link.href = href;
      document.head.appendChild(link);
    }

    if (document.head) apply();
    else document.addEventListener("DOMContentLoaded", apply, { once: true });
  }

  // --- Dark mode: report system preference to background (CDP handles the rest) ---

  function reportTheme() {
    chrome.runtime.sendMessage({ type: "themeChanged", isDark });
  }

  darkQuery.addEventListener("change", (e) => {
    isDark = e.matches;
    reportTheme();
    if (currentNumber) setFavicon(currentNumber);
  });

  reportTheme();

  // --- Init ---

  chrome.runtime.sendMessage({ type: "getNumber" }, (res) => {
    if (chrome.runtime.lastError) return;
    if (res?.number) setFavicon(res.number);
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "setNumber") setFavicon(msg.number);
  });

  // --- Keybindings ---
  // { ctrl, shift, alt, key, action, arg? }
  // Add rows here to bind more shortcuts.

  const BINDINGS = [
    { ctrl: true, key: "[", action: "historyBack" },
    { ctrl: true, key: "]", action: "historyForward" },
  ];

  function matchBinding(e) {
    return BINDINGS.find(
      (b) =>
        !!b.ctrl === e.ctrlKey &&
        !!b.shift === e.shiftKey &&
        !!b.alt === e.altKey &&
        e.key === b.key,
    );
  }

  document.addEventListener(
    "keydown",
    (e) => {
      // Ctrl+1-9: visible-tab switching
      if (e.ctrlKey && !e.shiftKey && !e.altKey && !e.metaKey) {
        const n = parseInt(e.key);
        if (n >= 1 && n <= 9) {
          e.preventDefault();
          e.stopImmediatePropagation();
          chrome.runtime.sendMessage({ type: "switchTab", number: n });
          return;
        }
      }

      // General bindings table
      const b = matchBinding(e);
      if (b) {
        e.preventDefault();
        e.stopImmediatePropagation();
        chrome.runtime.sendMessage({ type: "action", action: b.action, arg: b.arg });
      }
    },
    true,
  );
})();
