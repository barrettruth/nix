import { pathParts } from "./shared/repo-path.js";

const STATS_URL = "/assets/github-repo-stats.json";

let statsPromise;

function loadStats() {
  if (!statsPromise) {
    statsPromise = fetch(STATS_URL, { credentials: "same-origin" }).then(
      (response) => {
        if (!response.ok) throw new Error(response.statusText);
        return response.json();
      },
    );
  }
  return statsPromise;
}

function repoStats(data, owner, repo) {
  if (!data?.repos || !owner || !repo) return null;
  if (data.owner && data.owner.toLowerCase() !== owner.toLowerCase()) {
    return null;
  }
  const stats = data.repos[repo.toLowerCase()];
  return stats ? { ...stats, generated_at: data.generated_at } : null;
}

function formatCount(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "0";
  return new Intl.NumberFormat(undefined, {
    maximumFractionDigits: 1,
    notation: number >= 1000 ? "compact" : "standard",
  }).format(number);
}

function exactCount(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "0";
  return new Intl.NumberFormat().format(number);
}

function tooltipFor(stats) {
  const pieces = [
    `${exactCount(stats.stars)} GitHub stars`,
    `${exactCount(stats.forks)} GitHub forks`,
  ];
  if (Number(stats.open_issues) > 0) {
    pieces.push(`${exactCount(stats.open_issues)} open GitHub issues`);
  }
  if (stats.generated_at) {
    pieces.push(`cached ${stats.generated_at}`);
  }
  return pieces.join(", ");
}

function statItem(label, value) {
  const item = document.createElement("span");
  item.className = "barrett-github-stat";

  const count = document.createElement("span");
  count.className = "barrett-github-stat-count";
  count.textContent = formatCount(value);

  const text = document.createElement("span");
  text.className = "barrett-github-stat-label";
  text.textContent = label;

  item.append(count, text);
  return item;
}

function repoPathFromLink(anchor) {
  if (!anchor) return null;
  const url = new URL(anchor.getAttribute("href"), window.location.origin);
  if (url.origin !== window.location.origin) return null;
  const parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
  if (parts.length < 2) return null;
  return { owner: parts[0], repo: parts[1] };
}

function buildHeaderStats(stats) {
  const wrapper = document.createElement("div");
  wrapper.className = "ui labeled button barrett-github-stats";
  wrapper.dataset.barrettGithubStats = "true";

  const link = document.createElement("a");
  link.className = "ui compact small basic button";
  link.href = stats.html_url;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  link.textContent = "GitHub";

  const label = document.createElement("a");
  label.className = "ui basic label barrett-github-stats-label";
  label.href = stats.html_url;
  label.target = "_blank";
  label.rel = "noopener noreferrer";
  label.title = tooltipFor(stats);
  label.setAttribute("data-tooltip-content", tooltipFor(stats));
  label.append(statItem("stars", stats.stars), statItem("forks", stats.forks));

  wrapper.append(link, label);
  return wrapper;
}

function renderHeaderStats(data) {
  const parts = pathParts();
  if (parts.length < 2) return;

  const stats = repoStats(data, parts[0], parts[1]);
  const buttons = document.querySelector(".repo-header .repo-buttons");
  if (!stats || !buttons || buttons.querySelector("[data-barrett-github-stats]")) {
    return;
  }

  buttons.append(buildHeaderStats(stats));
}

function buildListStats(stats) {
  const link = document.createElement("a");
  link.className = "flex-text-inline barrett-github-list-stats";
  link.href = stats.html_url;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  link.title = tooltipFor(stats);
  link.setAttribute("data-tooltip-content", tooltipFor(stats));

  const source = document.createElement("span");
  source.className = "barrett-github-source";
  source.textContent = "GitHub";

  link.append(source, statItem("stars", stats.stars), statItem("forks", stats.forks));
  return link;
}

function renderRepoListStats(data) {
  for (const item of document.querySelectorAll(".flex-list .flex-item")) {
    if (item.querySelector("[data-barrett-github-stats]")) continue;

    const titleLinks = item.querySelectorAll(".flex-item-title a.text.primary.name");
    const repoLink = titleLinks[titleLinks.length - 1];
    const path = repoPathFromLink(repoLink);
    const stats = path && repoStats(data, path.owner, path.repo);
    const trailing = item.querySelector(".flex-item-trailing.muted-links");
    if (!stats || !trailing) continue;

    const node = buildListStats(stats);
    node.dataset.barrettGithubStats = "true";
    trailing.append(node);
  }
}

export function renderGithubStats() {
  loadStats()
    .then((data) => {
      renderHeaderStats(data);
      renderRepoListStats(data);
    })
    .catch(() => {});
}
