(() => {
  const CACHE_KEY = "codeforcesRoundIndexV1";
  const CACHE_VERSION = 1;
  const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
  const MISSING_REFRESH_AGE_MS = 15 * 60 * 1000;
  const REQUEST_INTERVAL_MS = 2100;
  const MAX_RESULTS = 8;
  const CONTEST_LIST_URL =
    "https://codeforces.com/api/contest.list?gym=false&lang=en";
  const PROBLEM_LIST_URL =
    "https://codeforces.com/api/problemset.problems?lang=en";
  const ROUND_PATTERN = /(?:^|\band\s+)Codeforces (?:Beta )?Round #?(\d+)\b/i;
  const problemIndexCollator = new Intl.Collator(undefined, {
    numeric: true,
    sensitivity: "base",
  });

  let memoryIndex = null;
  let cacheReadPromise = null;
  let refreshPromise = null;
  let inputRequestId = 0;
  let currentInput = "";
  let currentDefaultUrl = null;

  function wait(milliseconds) {
    return new Promise((resolve) => setTimeout(resolve, milliseconds));
  }

  function escapeDescription(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function setDefaultSuggestion(description) {
    chrome.omnibox.setDefaultSuggestion({ description });
  }

  function roundNumber(contestName) {
    const match = String(contestName || "").match(ROUND_PATTERN);
    return match?.[1] || null;
  }

  function validIndex(index) {
    return (
      index?.version === CACHE_VERSION &&
      Number.isFinite(index.fetchedAt) &&
      index.rounds &&
      typeof index.rounds === "object"
    );
  }

  async function readCachedIndex() {
    if (memoryIndex) return memoryIndex;
    if (!cacheReadPromise) {
      cacheReadPromise = chrome.storage.local.get(CACHE_KEY).then((stored) => {
        const index = stored[CACHE_KEY];
        if (!validIndex(index)) return null;
        memoryIndex = index;
        return index;
      });
    }
    return cacheReadPromise;
  }

  async function fetchResult(url) {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Codeforces returned HTTP ${response.status}`);
    }
    const payload = await response.json();
    if (payload?.status !== "OK") {
      throw new Error(payload?.comment || "Codeforces returned invalid data");
    }
    return payload.result;
  }

  function buildIndex(contests, problems) {
    const rounds = {};
    const contestsById = new Map();

    for (const source of contests) {
      const number = roundNumber(source.name);
      if (!number || !Number.isInteger(source.id)) continue;

      const contest = {
        id: source.id,
        name: String(source.name || `Codeforces Round ${number}`),
        problems: [],
      };
      if (!rounds[number]) rounds[number] = [];
      rounds[number].push(contest);
      contestsById.set(contest.id, contest);
    }

    for (const source of problems) {
      const contest = contestsById.get(source.contestId);
      if (!contest || !source.index || !source.name) continue;
      contest.problems.push({
        index: String(source.index),
        name: String(source.name),
      });
    }

    for (const contestsForRound of Object.values(rounds)) {
      contestsForRound.sort((a, b) => a.name.localeCompare(b.name));
      for (const contest of contestsForRound) {
        contest.problems.sort((a, b) =>
          problemIndexCollator.compare(a.index, b.index),
        );
      }
    }

    return {
      version: CACHE_VERSION,
      fetchedAt: Date.now(),
      rounds,
    };
  }

  function refreshIndex() {
    if (refreshPromise) return refreshPromise;

    refreshPromise = (async () => {
      const firstRequestAt = Date.now();
      const contests = await fetchResult(CONTEST_LIST_URL);
      const remainingDelay =
        REQUEST_INTERVAL_MS - (Date.now() - firstRequestAt);
      if (remainingDelay > 0) await wait(remainingDelay);
      const problemSet = await fetchResult(PROBLEM_LIST_URL);
      const index = buildIndex(contests, problemSet.problems || []);
      await chrome.storage.local.set({ [CACHE_KEY]: index });
      memoryIndex = index;
      cacheReadPromise = Promise.resolve(index);
      return index;
    })().finally(() => {
      refreshPromise = null;
    });

    return refreshPromise;
  }

  async function warmIndex() {
    const index = await readCachedIndex();
    if (!index) return refreshIndex();
    if (Date.now() - index.fetchedAt > CACHE_TTL_MS) {
      refreshIndex().catch(() => {});
    }
    return index;
  }

  async function indexForRound(number) {
    let index = await readCachedIndex();
    if (!index) return refreshIndex();

    const age = Date.now() - index.fetchedAt;
    if (age > CACHE_TTL_MS) refreshIndex().catch(() => {});
    if (!index.rounds[number] && age > MISSING_REFRESH_AGE_MS) {
      try {
        index = await refreshIndex();
      } catch (_) {}
    }
    return index;
  }

  function contestResult(contest) {
    return {
      url: `https://codeforces.com/contest/${contest.id}`,
      description: `<match>${escapeDescription(contest.name)}</match> <dim>- contest</dim>`,
      searchText: `${contest.name} contest`,
    };
  }

  function problemResult(contest, problem) {
    return {
      url: `https://codeforces.com/contest/${contest.id}/problem/${encodeURIComponent(problem.index)}`,
      description: `<match>${escapeDescription(problem.index)}</match> - ${escapeDescription(problem.name)} <dim>- ${escapeDescription(contest.name)}</dim>`,
      searchText: `${problem.index} ${problem.name} ${contest.name}`,
    };
  }

  function normalizeSearchText(value) {
    return String(value || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  function fallbackFuzzyScore(text, query) {
    let cursor = 0;
    for (const character of query) {
      const index = text.indexOf(character, cursor);
      if (index === -1) return -1;
      cursor = index + 1;
    }
    return query.length / Math.max(query.length, text.length);
  }

  function fuzzyScore(result, query) {
    const text = normalizeSearchText(result.searchText);
    const normalizedQuery = normalizeSearchText(query);
    if (!normalizedQuery) return 0;

    const quickScore = globalThis.quickScore?.quickScore;
    let score = quickScore
      ? quickScore(text, normalizedQuery, [], text, normalizedQuery)
      : fallbackFuzzyScore(text, normalizedQuery);
    if (!(score > 0)) return -1;

    const tokens = text.split(" ");
    if (text === normalizedQuery) score += 4;
    if (tokens.includes(normalizedQuery)) score += 2;
    if (tokens.some((token) => token.startsWith(normalizedQuery))) score += 1;
    return score;
  }

  function resultsForRound(index, number, query) {
    const contests = index?.rounds?.[number] || [];
    const results = contests.map(contestResult);
    const problems = [];
    for (const contest of contests) {
      for (const problem of contest.problems) {
        problems.push({ contest, problem });
      }
    }
    problems.sort(
      (a, b) =>
        problemIndexCollator.compare(a.problem.index, b.problem.index) ||
        a.contest.name.localeCompare(b.contest.name),
    );
    for (const { contest, problem } of problems) {
      results.push(problemResult(contest, problem));
    }

    if (!query) return results.slice(0, MAX_RESULTS);
    return results
      .map((result, position) => ({
        result,
        position,
        score: fuzzyScore(result, query),
      }))
      .filter((match) => match.score >= 0)
      .sort((a, b) => b.score - a.score || a.position - b.position)
      .slice(0, MAX_RESULTS)
      .map((match) => match.result);
  }

  function parseInput(input) {
    const match = String(input || "")
      .trimStart()
      .match(/^(\d+)(?:\s+(.*))?$/);
    if (!match) return null;
    return {
      number: match[1].replace(/^0+(?=\d)/, ""),
      query: String(match[2] || "").trim(),
    };
  }

  async function navigate(url, disposition) {
    if (disposition === "currentTab") {
      const [tab] = await chrome.tabs.query({
        active: true,
        currentWindow: true,
      });
      if (tab?.id) await chrome.tabs.update(tab.id, { url });
      return;
    }

    await chrome.tabs.create({
      url,
      active: disposition !== "newBackgroundTab",
    });
  }

  setDefaultSuggestion("Enter a Codeforces round number");

  chrome.omnibox.onInputStarted.addListener(() => {
    warmIndex().catch(() => {});
  });

  chrome.omnibox.onInputChanged.addListener((input, suggest) => {
    const requestId = ++inputRequestId;
    const parsed = parseInput(input);
    currentInput = String(input || "").trim();
    currentDefaultUrl = null;

    if (!currentInput) {
      setDefaultSuggestion("Enter a Codeforces round number");
      suggest([]);
      return;
    }
    if (!parsed) {
      setDefaultSuggestion("Enter a round number before the search text");
      suggest([]);
      return;
    }

    const { number, query } = parsed;
    setDefaultSuggestion(`Loading Codeforces Round ${number}`);
    indexForRound(number)
      .then((index) => {
        if (requestId !== inputRequestId) return;
        const contests = index?.rounds?.[number] || [];
        if (!contests.length) {
          setDefaultSuggestion(`No Codeforces Round ${number}`);
          suggest([]);
          return;
        }

        const results = resultsForRound(index, number, query);
        if (!results.length) {
          setDefaultSuggestion(
            `No result in Codeforces Round ${number} matches ${escapeDescription(query)}`,
          );
          suggest([]);
          return;
        }

        const [first, ...rest] = results;
        currentDefaultUrl = first.url;
        setDefaultSuggestion(first.description);
        suggest(
          rest.map((result) => ({
            content: result.url,
            description: result.description,
          })),
        );
      })
      .catch(() => {
        if (requestId !== inputRequestId) return;
        setDefaultSuggestion("Codeforces data is unavailable");
        suggest([]);
      });
  });

  chrome.omnibox.onInputEntered.addListener((input, disposition) => {
    const value = String(input || "").trim();
    const url = value.startsWith("https://codeforces.com/contest/")
      ? value
      : value === currentInput
        ? currentDefaultUrl
        : null;
    if (url) navigate(url, disposition).catch(() => {});
  });

  chrome.omnibox.onInputCancelled.addListener(() => {
    inputRequestId++;
    currentInput = "";
    currentDefaultUrl = null;
    setDefaultSuggestion("Enter a Codeforces round number");
  });

  chrome.runtime.onInstalled.addListener(() => {
    refreshIndex().catch(() => {});
  });

  chrome.runtime.onStartup.addListener(() => {
    warmIndex().catch(() => {});
  });
})();
