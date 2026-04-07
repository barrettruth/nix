const OMNIBOX_RESULT_LIMIT = 9;
const HISTORY_CACHE_TTL_MS = 5 * 60 * 1000;
const HISTORY_CACHE_MAX_RESULTS = 5000;
const NEGATIVE_SCORE = -1e9;

let historyIndex = [];
let historyIndexLoadedAt = 0;
let historyIndexPromise = null;
let omniboxRequestId = 0;
let lastOmniboxText = "";
let lastOmniboxResults = [];

function safeDecode(value) {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

function normalizeBase(value) {
  return safeDecode(
    String(value || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, ""),
  );
}

function normalizeHost(value) {
  return normalizeBase(value)
    .replace(/^www\./i, "")
    .toLowerCase();
}

function normalizeTitle(value) {
  return normalizeBase(value)
    .replace(/^(?:\d+\.\s+)+/, "")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizePath(value) {
  return normalizeBase(value).replace(/\/+/g, "/").trim();
}

function normalizeQueryValue(value) {
  return normalizeBase(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function extractTitleHead(value) {
  const title = normalizeTitle(value);
  const parts = title.split(/\s(?:\||·|–|—|-)\s/).filter(Boolean);
  return (parts[0] || title).trim();
}

function buildField(rawValue) {
  const raw = String(rawValue || "")
    .replace(/\s+/g, " ")
    .trim();
  const base = normalizeBase(raw);
  const text = base.toLowerCase();
  const tokens = text.split(/[^a-z0-9]+/).filter(Boolean);
  const tokenSet = new Set(tokens);
  let acronym = "";
  for (const token of tokens) acronym += token[0] || "";
  return {
    raw: base,
    text,
    tokens,
    tokenSet,
    acronym,
    boundaries: buildBoundaryBonuses(base, text),
  };
}

function isLowerAscii(char) {
  return char >= "a" && char <= "z";
}

function isUpperAscii(char) {
  return char >= "A" && char <= "Z";
}

function isWordAscii(char) {
  return (
    (char >= "a" && char <= "z") ||
    (char >= "A" && char <= "Z") ||
    (char >= "0" && char <= "9")
  );
}

function buildBoundaryBonuses(raw, text) {
  const bonuses = new Array(text.length).fill(0);
  for (let i = 0; i < text.length; i++) {
    const current = text[i];
    if (
      !(
        (current >= "a" && current <= "z") ||
        (current >= "0" && current <= "9")
      )
    )
      continue;
    if (i === 0) {
      bonuses[i] = 12;
      continue;
    }
    const prevRaw = raw[i - 1];
    const currRaw = raw[i];
    if (prevRaw === " " || prevRaw === "/") bonuses[i] = 12;
    else if (prevRaw === "." || prevRaw === "-" || prevRaw === "_")
      bonuses[i] = 11;
    else if (!isWordAscii(prevRaw)) bonuses[i] = 10;
    else if (isLowerAscii(prevRaw) && isUpperAscii(currRaw)) bonuses[i] = 9;
  }
  return bonuses;
}

function buildHistoryEntry(item) {
  let parsed;
  try {
    parsed = new URL(item.url);
  } catch (_) {
    return null;
  }
  if (
    !parsed.protocol ||
    parsed.protocol === "chrome:" ||
    parsed.protocol === "chrome-extension:"
  )
    return null;

  const host = normalizeHost(parsed.hostname);
  if (!host) return null;

  const title = normalizeTitle(item.title || "");
  const titleHead = extractTitleHead(title || host);
  const path = normalizePath(parsed.pathname || "");
  const search = normalizePath(parsed.search || "");
  const hostPath = `${host}${path || ""}`;
  const urlText = [host, path, search].filter(Boolean).join(" ");
  const pathDisplay = `${safeDecode(parsed.pathname || "")}${safeDecode(parsed.search || "")}`;
  const displayUrl = `${host}${pathDisplay || ""}`;

  return {
    url: item.url,
    title: title || item.url,
    displayUrl: displayUrl || host,
    hostField: buildField(host),
    titleHeadField: buildField(titleHead || title || host),
    titleFullField: buildField(title || host),
    pathField: buildField(path),
    urlField: buildField(urlText),
    hostPathField: buildField(hostPath),
    lastVisitTime: Number(item.lastVisitTime || 0),
    visitCount: Number(item.visitCount || 0),
    typedCount: Number(item.typedCount || 0),
  };
}

function parseQuery(text) {
  const normalized = normalizeQueryValue(text);
  const tokens = normalized.split(/\s+/).filter(Boolean);
  return {
    text: String(text || ""),
    normalized,
    tokens,
    joined: tokens.join(""),
  };
}

function historyPrior(entry, now) {
  const ageHours = Math.max(0, (now - entry.lastVisitTime) / 3600000);
  const recency =
    30 * Math.exp(-ageHours / 24) + 15 * Math.exp(-ageHours / (24 * 14));
  const typed = 10 * Math.log2(1 + entry.typedCount);
  const visits = 6 * Math.log2(1 + entry.visitCount);
  return recency + typed + visits;
}

function scorePrefixToken(token, field) {
  let best = NEGATIVE_SCORE;
  for (const current of field.tokens) {
    if (current === token) return 120;
    if (!current.startsWith(token)) continue;
    const score = 108 - Math.min(12, current.length - token.length);
    if (score > best) best = score;
  }
  return best;
}

function scoreAcronymToken(token, field) {
  if (!field.acronym || !field.acronym.startsWith(token)) return NEGATIVE_SCORE;
  return 96 - Math.max(0, field.acronym.length - token.length) * 0.5;
}

function scoreSubstringToken(token, field) {
  if (!token || !field.text) return NEGATIVE_SCORE;
  let best = NEGATIVE_SCORE;
  let index = field.text.indexOf(token);
  while (index !== -1) {
    const boundary = field.boundaries[index] || 0;
    let score = token.length >= 4 ? 58 : NEGATIVE_SCORE;
    if (boundary) score = Math.max(score, 78 + boundary);
    if (score > NEGATIVE_SCORE) {
      score -= Math.min(20, index) * 0.35;
      if (score > best) best = score;
    }
    index = field.text.indexOf(token, index + 1);
  }
  return best;
}

function quickScoreValue(query, field, matches) {
  const scorer = globalThis.quickScore?.quickScore;
  if (!scorer) return 0;
  return scorer(field.raw, query, matches, field.text, query);
}

function countBoundaryMatches(field, matches) {
  let count = 0;
  for (const [start] of matches) {
    if ((field.boundaries[start] || 0) >= 10) count++;
  }
  return count;
}

function fuzzySubsequenceScore(pattern, field) {
  if (!pattern || !field.text) return NEGATIVE_SCORE;
  const matches = [];
  const rawScore = quickScoreValue(pattern, field, matches);
  if (!(rawScore > 0) || !matches.length) return NEGATIVE_SCORE;

  const start = matches[0][0];
  const boundaryMatches = countBoundaryMatches(field, matches);
  if (start > 0 && boundaryMatches < 2 && rawScore < 0.75) {
    return NEGATIVE_SCORE;
  }
  if (pattern.length === 2) {
    if (rawScore < 0.45) return NEGATIVE_SCORE;
    if (start > 0 && boundaryMatches < 2) return NEGATIVE_SCORE;
  } else if (pattern.length === 3) {
    if (boundaryMatches < 2 && rawScore < 0.4) return NEGATIVE_SCORE;
  } else if (boundaryMatches < 2 && rawScore < 0.5) {
    return NEGATIVE_SCORE;
  }

  const end = matches[matches.length - 1][1];
  const span = Math.max(0, end - start);
  return (
    34 +
    rawScore * 56 +
    boundaryMatches * 4 -
    Math.max(0, span - pattern.length - 2) * 1.5
  );
}

function scoreFieldToken(token, field) {
  if (!field.text) return NEGATIVE_SCORE;
  const prefix = scorePrefixToken(token, field);
  if (prefix > NEGATIVE_SCORE) return prefix;

  const acronym = scoreAcronymToken(token, field);
  if (acronym > NEGATIVE_SCORE) return acronym;

  const substring = scoreSubstringToken(token, field);
  if (substring > NEGATIVE_SCORE) return substring;

  if (token.length < 2) return NEGATIVE_SCORE;
  return fuzzySubsequenceScore(token, field);
}

function weightScore(score, weight) {
  if (score <= NEGATIVE_SCORE / 2) return NEGATIVE_SCORE;
  return score * weight;
}

function bestTokenScore(token, entry) {
  return Math.max(
    weightScore(scoreFieldToken(token, entry.hostField), 1.35),
    weightScore(scoreFieldToken(token, entry.hostPathField), 1.15),
    weightScore(scoreFieldToken(token, entry.pathField), 1.0),
    weightScore(scoreFieldToken(token, entry.titleHeadField), 0.7),
    weightScore(scoreFieldToken(token, entry.titleFullField), 0.4),
    weightScore(scoreFieldToken(token, entry.urlField), 0.4),
  );
}

function scoreQueryPhrase(query, entry) {
  if (query.tokens.length < 2 || query.joined.length < 3) return 0;
  const score = fuzzySubsequenceScore(query.joined, entry.hostPathField);
  if (score <= NEGATIVE_SCORE / 2) return 0;
  return score * 0.35;
}

function scoreHistoryEntry(query, entry, now) {
  let score = historyPrior(entry, now);
  if (!query.tokens.length) return score;

  for (const token of query.tokens) {
    const tokenScore = bestTokenScore(token, entry);
    if (tokenScore <= NEGATIVE_SCORE / 2) return NEGATIVE_SCORE;
    score += tokenScore;
  }

  score += scoreQueryPhrase(query, entry);
  return score;
}

async function loadHistoryIndex() {
  const items = await chrome.history.search({
    text: "",
    startTime: 0,
    maxResults: HISTORY_CACHE_MAX_RESULTS,
  });
  historyIndex = items.map(buildHistoryEntry).filter(Boolean);
  historyIndexLoadedAt = Date.now();
  return historyIndex;
}

async function getHistoryIndex() {
  if (
    historyIndex.length &&
    Date.now() - historyIndexLoadedAt < HISTORY_CACHE_TTL_MS
  )
    return historyIndex;

  if (!historyIndexPromise) {
    historyIndexPromise = loadHistoryIndex().finally(() => {
      historyIndexPromise = null;
    });
  }
  return historyIndexPromise;
}

function invalidateHistoryIndex() {
  historyIndex = [];
  historyIndexLoadedAt = 0;
}

async function searchHistory(queryText, limit = OMNIBOX_RESULT_LIMIT) {
  const entries = await getHistoryIndex();
  const query = parseQuery(queryText);
  const now = Date.now();
  const scored = [];

  for (const entry of entries) {
    const score = scoreHistoryEntry(query, entry, now);
    if (score <= NEGATIVE_SCORE / 2) continue;
    scored.push({ entry, score });
  }

  scored.sort(
    (a, b) =>
      b.score - a.score ||
      b.entry.lastVisitTime - a.entry.lastVisitTime ||
      b.entry.typedCount - a.entry.typedCount,
  );

  return scored
    .slice(0, limit)
    .map(({ entry, score }) => ({ ...entry, score }));
}

function escapeDescription(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function truncate(value, maxLength) {
  const text = String(value || "");
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 1)}…`;
}

function buildSuggestionDescription(entry) {
  return `<url>${escapeDescription(truncate(entry.displayUrl, 120))}</url>`;
}

function toSuggestion(entry) {
  return {
    content: entry.url,
    description: buildSuggestionDescription(entry),
  };
}

async function openOmniboxResult(url, disposition) {
  if (disposition === "currentTab") {
    const [tab] = await chrome.tabs.query({
      active: true,
      currentWindow: true,
    });
    if (tab?.id) {
      await chrome.tabs.update(tab.id, { url });
      return;
    }
  }

  await chrome.tabs.create({
    url,
    active: disposition !== "newBackgroundTab",
  });
}

function resolveSelectedUrl(text, results) {
  if (!text) return results[0]?.url || null;
  const direct = results.find((result) => result.url === text);
  if (direct) return direct.url;
  try {
    return new URL(text).toString();
  } catch (_) {}
  return results[0]?.url || null;
}

chrome.history.onVisited.addListener(() => invalidateHistoryIndex());
chrome.history.onVisitRemoved.addListener(() => invalidateHistoryIndex());

chrome.omnibox.onInputStarted.addListener(() => {
  omniboxRequestId++;
  lastOmniboxText = "";
  lastOmniboxResults = [];
});

chrome.omnibox.onInputChanged.addListener((text, suggest) => {
  const requestId = ++omniboxRequestId;
  lastOmniboxText = text;

  void (async () => {
    const results = await searchHistory(text, OMNIBOX_RESULT_LIMIT);
    if (requestId !== omniboxRequestId) return;
    lastOmniboxResults = results;
    suggest(results.map(toSuggestion));
  })().catch(() => {
    if (requestId !== omniboxRequestId) return;
    lastOmniboxResults = [];
    suggest([]);
  });
});

chrome.omnibox.onInputEntered.addListener((text, disposition) => {
  void (async () => {
    const results =
      text === lastOmniboxText && lastOmniboxResults.length
        ? lastOmniboxResults
        : await searchHistory(text, 1);
    const url = resolveSelectedUrl(text, results);
    if (!url) return;
    await openOmniboxResult(url, disposition);
  })();
});

chrome.omnibox.onInputCancelled.addListener(() => {
  omniboxRequestId++;
  lastOmniboxText = "";
  lastOmniboxResults = [];
});
