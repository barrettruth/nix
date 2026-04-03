(function () {
  if (window.__midnightLoaded) return;
  window.__midnightLoaded = true;

  const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
  let isDark = darkQuery.matches;
  let currentNumber = null;

  function theme() {
    return isDark ? MIDNIGHT : DAYLIGHT;
  }

  let faviconObserver;

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
      if (!document.head) return;
      document
        .querySelectorAll("link[rel*='icon']:not(#midnight-tab-num)")
        .forEach((el) => el.remove());
      let link = document.getElementById("midnight-tab-num");
      if (!link) {
        link = document.createElement("link");
        link.id = "midnight-tab-num";
        link.rel = "icon";
        link.type = "image/svg+xml";
        document.head.appendChild(link);
      }
      link.href = href;
    }

    function guard() {
      if (faviconObserver) faviconObserver.disconnect();
      if (!document.head) return;
      faviconObserver = new MutationObserver((muts) => {
        for (const m of muts)
          for (const n of m.addedNodes)
            if (
              n.nodeName === "LINK" &&
              n.rel?.includes("icon") &&
              n.id !== "midnight-tab-num"
            ) {
              n.remove();
              apply();
              return;
            }
      });
      faviconObserver.observe(document.head, { childList: true });
    }

    if (document.readyState === "loading") {
      document.addEventListener(
        "DOMContentLoaded",
        () => {
          apply();
          guard();
        },
        { once: true },
      );
    } else {
      apply();
      guard();
    }
  }

  function reportTheme() {
    chrome.runtime.sendMessage({ type: "themeChanged", isDark });
  }

  darkQuery.addEventListener("change", (e) => {
    isDark = e.matches;
    reportTheme();
    if (currentNumber) setFavicon(currentNumber);
  });

  reportTheme();

  chrome.runtime.sendMessage({ type: "getNumber" }, (res) => {
    if (chrome.runtime.lastError) return;
    if (res?.number) setFavicon(res.number);
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "setNumber") setFavicon(msg.number);
  });

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
        chrome.runtime.sendMessage({
          type: "action",
          action: b.action,
          arg: b.arg,
        });
      }
    },
    true,
  );
})();
