(() => {
  // CodeMirror 6 (used in /repos/.../_edit/...) hardcodes VSCode-ish hex
  // colors in HighlightStyle.define() and picks dark vs light at editor
  // mount time via isDarkTheme() (web_src/js/utils.js). Both branches'
  // hex values get mapped to the SAME midnight CSS variable here, so
  // the resolved color always matches the current Forgejo theme
  // regardless of which VSCode palette CM6 picked. The variables are
  // declared on :root in theme-midnight-{light,dark}.css and resolve
  // through the cascade at use time.
  const COLOR_MAP = {
    "#569cd6": "var(--midnight-syntax-keyword)",
    "#0064ff": "var(--midnight-syntax-keyword)",
    "#c586c0": "var(--midnight-syntax-keyword)",
    "#af00db": "var(--midnight-syntax-keyword)",
    "#006ab1": "var(--midnight-syntax-keyword)",
    "#9cdcfe": "var(--color-text)",
    "#383a42": "var(--color-text)",
    "#4ec9b0": "var(--color-text)",
    "#267f99": "var(--color-text)",
    "#dcdcaa": "var(--color-text)",
    "#795e26": "var(--color-text)",
    "#d4d4d4": "var(--color-text)",
    "#ce9178": "var(--midnight-syntax-string)",
    "#a31515": "var(--midnight-syntax-string)",
    "#b5cea8": "var(--midnight-syntax-constant)",
    "#098658": "var(--midnight-syntax-constant)",
    "#6a9955": "var(--midnight-syntax-comment)",
    "#6b6b6b": "var(--midnight-syntax-comment)",
    "#ff0000": "var(--midnight-syntax-error)",
    "#e51400": "var(--midnight-syntax-error)",
    "#d16969": "var(--midnight-syntax-error)",
  };
  const rewrite = (el) => {
    if (!el || el.tagName !== "STYLE") return;
    let txt = el.textContent;
    if (!txt) return;
    let modified = false;
    for (const [from, to] of Object.entries(COLOR_MAP)) {
      if (txt.toLowerCase().includes(from)) {
        txt = txt.split(from).join(to);
        txt = txt.split(from.toUpperCase()).join(to);
        modified = true;
      }
    }
    if (modified) el.textContent = txt;
  };
  document.querySelectorAll("style").forEach(rewrite);
  new MutationObserver((muts) => {
    for (const m of muts) {
      for (const node of m.addedNodes) {
        if (node.nodeType === 1 && node.tagName === "STYLE") rewrite(node);
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
