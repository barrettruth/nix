(function () {
  if (window.__midnightLoaded) return;
  window.__midnightLoaded = true;

  const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
  let isDark = darkQuery.matches;
  let currentNumber = null;

  function stripPrefix(title) {
    return title.replace(/^\d+\. /, "");
  }

  function applyPrefix() {
    if (!currentNumber) return;
    const base = stripPrefix(document.title);
    const want = base ? `${currentNumber}. ${base}` : `${currentNumber}`;
    if (document.title !== want) document.title = want;
  }

  function setNumber(number) {
    currentNumber = number;
    applyPrefix();
  }

  function observeTitle() {
    if (!document.head) return;
    new MutationObserver(() => applyPrefix()).observe(document.head, {
      childList: true,
      subtree: true,
      characterData: true,
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", observeTitle, { once: true });
  } else {
    observeTitle();
  }

  function reportTheme() {
    chrome.runtime.sendMessage({ type: "themeChanged", isDark });
  }

  darkQuery.addEventListener("change", (e) => {
    isDark = e.matches;
    reportTheme();
  });

  reportTheme();

  chrome.runtime.sendMessage({ type: "getNumber" }, (res) => {
    if (chrome.runtime.lastError) return;
    if (res?.number) setNumber(res.number);
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "setNumber") setNumber(msg.number);
  });

  const BINDINGS = [
    { ctrl: true, key: "[", action: "historyBack" },
    { ctrl: true, key: "]", action: "historyForward" },
    { ctrl: true, shift: true, key: "{", action: "moveTabLeft" },
    { ctrl: true, shift: true, key: "}", action: "moveTabRight" },
    { ctrl: true, shift: true, key: "H", action: "switchWorkspace", arg: 0 },
    { ctrl: true, shift: true, key: "J", action: "switchWorkspace", arg: 1 },
    { ctrl: true, shift: true, key: "K", action: "switchWorkspace", arg: 2 },
    { ctrl: true, shift: true, key: "L", action: "switchWorkspace", arg: 3 },
    {
      ctrl: true,
      key: "y",
      local: () => navigator.clipboard.writeText(location.href),
    },
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
      if (e.ctrlKey && !e.shiftKey && !e.altKey && !e.metaKey) {
        const n = parseInt(e.key);
        if (n >= 1 && n <= 9) {
          e.preventDefault();
          e.stopImmediatePropagation();
          chrome.runtime.sendMessage({ type: "switchTab", number: n });
          return;
        }
      }

      const b = matchBinding(e);
      if (b) {
        e.preventDefault();
        e.stopImmediatePropagation();
        if (b.local) {
          b.local();
        } else {
          chrome.runtime.sendMessage({
            type: "action",
            action: b.action,
            arg: b.arg,
          });
        }
      }
    },
    true,
  );
})();
