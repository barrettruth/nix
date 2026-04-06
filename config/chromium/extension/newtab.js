const port = chrome.runtime.connect({ name: "tab" });
port.onMessage.addListener((msg) => {
  if (msg.type === "setNumber")
    document.title = `${msg.number}. ${document.title.replace(/^\d+\. /, "")}`;
  else if (msg.type === "clearNumber")
    document.title = document.title.replace(/^\d+\. /, "");
});

document.addEventListener(
  "keydown",
  (e) => {
    if (!e.ctrlKey || e.shiftKey || e.altKey || e.metaKey) return;
    const n = parseInt(e.key);
    if (n >= 1 && n <= 9) {
      e.preventDefault();
      chrome.runtime.sendMessage({ type: "switchTab", number: n });
    }
  },
  true,
);
