importScripts("theme.js");

const tabNumberCache = new Map();
const extPorts = new Map();
const groupLastActive = new Map();

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== "tab") return;
  const tabId = port.sender?.tab?.id;
  if (!tabId) return;
  extPorts.set(tabId, port);
  port.onDisconnect.addListener(() => extPorts.delete(tabId));
  const num = tabNumberCache.get(tabId);
  if (num) port.postMessage({ type: "setNumber", number: num });
});

async function getVisibleTabs(windowId) {
  const tabs = await chrome.tabs.query({ windowId });
  const collapsed = new Set();
  try {
    const groups = await chrome.tabGroups.query({ windowId });
    for (const g of groups) if (g.collapsed) collapsed.add(g.id);
  } catch (_) {}
  return tabs.filter((t) => t.groupId === -1 || !collapsed.has(t.groupId));
}

async function recalculate(windowId) {
  if (!windowId) {
    for (const w of await chrome.windows.getAll({ windowTypes: ["normal"] }))
      await recalculate(w.id);
    return;
  }

  const visible = await getVisibleTabs(windowId);
  for (let i = 0; i < visible.length; i++) {
    const tab = visible[i];
    const num = i + 1;
    if (tabNumberCache.get(tab.id) === num) continue;
    tabNumberCache.set(tab.id, num);
    try {
      if (extPorts.has(tab.id)) {
        extPorts.get(tab.id).postMessage({ type: "setNumber", number: num });
      } else {
        await chrome.tabs.sendMessage(tab.id, {
          type: "setNumber",
          number: num,
        });
      }
    } catch (_) {}
  }
}

for (const ev of [
  "onCreated",
  "onRemoved",
  "onMoved",
  "onDetached",
  "onAttached",
])
  chrome.tabs[ev].addListener(() => recalculate());

chrome.tabs.onUpdated.addListener((_id, info) => {
  if (info.status === "complete") recalculate();
});
chrome.tabs.onActivated.addListener(async ({ tabId, windowId }) => {
  try {
    const tab = await chrome.tabs.get(tabId);
    if (tab.groupId !== -1) groupLastActive.set(tab.groupId, tabId);
  } catch (_) {}
  recalculate(windowId);
});
try {
  chrome.tabGroups.onUpdated.addListener(() => recalculate());
} catch (_) {}

async function switchToVisibleTab(number, windowId) {
  if (!windowId) windowId = (await chrome.windows.getCurrent()).id;
  const visible = await getVisibleTabs(windowId);
  const target =
    number === 9 ? visible[visible.length - 1] : visible[number - 1];
  if (target) await chrome.tabs.update(target.id, { active: true });
}

async function getOrderedGroups(windowId) {
  const tabs = await chrome.tabs.query({ windowId });
  const seen = new Set();
  const ordered = [];
  for (const tab of tabs) {
    if (tab.groupId !== -1 && !seen.has(tab.groupId)) {
      seen.add(tab.groupId);
      ordered.push(tab.groupId);
    }
  }
  return ordered;
}

async function switchWorkspace(index, windowId) {
  if (!windowId) windowId = (await chrome.windows.getCurrent()).id;
  const groupIds = await getOrderedGroups(windowId);
  if (index >= groupIds.length) return;

  const targetId = groupIds[index];
  for (const gid of groupIds) {
    await chrome.tabGroups.update(gid, { collapsed: gid !== targetId });
  }

  const lastTab = groupLastActive.get(targetId);
  if (lastTab) {
    try {
      const tab = await chrome.tabs.get(lastTab);
      if (tab.groupId === targetId) {
        await chrome.tabs.update(lastTab, { active: true });
        return;
      }
    } catch (_) {}
  }

  const tabs = await chrome.tabs.query({ windowId, groupId: targetId });
  if (tabs.length > 0) await chrome.tabs.update(tabs[0].id, { active: true });
}

let systemIsDark = false;
const attached = new Set();

async function cdpAttach(tabId) {
  if (attached.has(tabId)) return true;
  try {
    await chrome.debugger.attach({ tabId }, "1.3");
    attached.add(tabId);
    return true;
  } catch (_) {
    return false;
  }
}

async function cdpSetDark(tabId, enabled) {
  try {
    const params = enabled ? { enabled: true } : {};
    await chrome.debugger.sendCommand(
      { tabId },
      "Emulation.setAutoDarkModeOverride",
      params,
    );
  } catch (_) {}
}

async function applyDarkToTab(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (
    !tab?.url ||
    tab.url.startsWith("chrome://") ||
    tab.url.startsWith(`chrome-extension://${chrome.runtime.id}`)
  )
    return;

  let hostname;
  try {
    hostname = new URL(tab.url).hostname;
  } catch (_) {
    return;
  }

  const { disabledSites = [] } =
    await chrome.storage.local.get("disabledSites");
  const shouldDarken = systemIsDark && !disabledSites.includes(hostname);

  if (shouldDarken) {
    if (await cdpAttach(tabId)) await cdpSetDark(tabId, true);
  } else if (attached.has(tabId)) {
    await cdpSetDark(tabId, false);
  }
}

async function applyDarkToAll() {
  for (const tab of await chrome.tabs.query({})) await applyDarkToTab(tab.id);
}

chrome.debugger.onDetach.addListener((source) => {
  attached.delete(source.tabId);
});

chrome.tabs.onRemoved.addListener((tabId) => {
  attached.delete(tabId);
});

chrome.tabs.onUpdated.addListener((tabId, info) => {
  if (info.status === "loading") applyDarkToTab(tabId);
});

chrome.tabs.onCreated.addListener(async (tab) => {
  try {
    const groups = await chrome.tabGroups.query({ windowId: tab.windowId });
    const expanded = groups.find((g) => !g.collapsed);
    if (expanded && tab.groupId === -1) {
      await chrome.tabs.group({ tabIds: [tab.id], groupId: expanded.id });
    }
  } catch (_) {}
  if (systemIsDark) applyDarkToTab(tab.id);
});

async function toggleDark(tab) {
  if (!tab?.url) return;
  let hostname;
  try {
    hostname = new URL(tab.url).hostname;
  } catch (_) {
    return;
  }
  const { disabledSites = [] } =
    await chrome.storage.local.get("disabledSites");
  const idx = disabledSites.indexOf(hostname);
  if (idx === -1) disabledSites.push(hostname);
  else disabledSites.splice(idx, 1);
  await chrome.storage.local.set({ disabledSites });

  for (const t of await chrome.tabs.query({})) {
    try {
      if (new URL(t.url).hostname === hostname) applyDarkToTab(t.id);
    } catch (_) {}
  }
}

const ACTIONS = {
  historyBack: (tab) => chrome.tabs.goBack(tab.id),
  historyForward: (tab) => chrome.tabs.goForward(tab.id),
  moveTabLeft: (tab) =>
    chrome.tabs.move(tab.id, { index: Math.max(0, tab.index - 1) }),
  moveTabRight: (tab) => chrome.tabs.move(tab.id, { index: tab.index + 1 }),
  switchWorkspace: (tab, index) => switchWorkspace(index, tab.windowId),
};

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "switchTab") {
    switchToVisibleTab(msg.number, sender.tab?.windowId);
  } else if (msg.type === "action") {
    const fn = ACTIONS[msg.action];
    if (fn && sender.tab) fn(sender.tab, msg.arg);
  } else if (msg.type === "getNumber") {
    const num = tabNumberCache.get(sender.tab?.id);
    sendResponse({ number: num || null });
  } else if (msg.type === "themeChanged") {
    const wasDark = systemIsDark;
    systemIsDark = !!msg.isDark;
    if (wasDark !== systemIsDark) applyDarkToAll();
  } else if (msg.type === "toggleDark") {
    toggleDark(sender.tab);
  }
});

chrome.commands.onCommand.addListener((command) => {
  if (command === "toggle-dark")
    chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
      if (tab) toggleDark(tab);
    });
});

chrome.runtime.onInstalled.addListener(async () => {
  for (const tab of await chrome.tabs.query({})) {
    try {
      await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        files: ["theme.js", "content.js"],
      });
    } catch (_) {}
  }
  recalculate();
});
