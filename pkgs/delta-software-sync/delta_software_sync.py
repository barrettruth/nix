#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class SyncError(RuntimeError):
    pass


class RateLimitError(SyncError):
    pass


JsonObject = dict[str, Any]


@dataclass(frozen=True)
class RepoRef:
    provider: str
    base_url: str
    owner: str
    name: str
    html_url: str
    priority: int

    @property
    def key(self) -> str:
        return f"{self.owner}/{self.name}".lower()

    @property
    def label(self) -> str:
        return f"{self.owner}/{self.name}"

    @property
    def source_id(self) -> str:
        return f"{urllib.parse.urlparse(self.base_url).netloc}/{self.owner}/{self.name}"


@dataclass(frozen=True)
class ExternalItem:
    source: RepoRef
    external_id: str
    thread_type: str
    title: str | None
    body: str | None
    url: str
    remote_state: str
    remote_updated_at: str | None = None
    external_human_activity_at: str | None = None

    def as_delta_item(self) -> JsonObject:
        item: JsonObject = {
            "externalId": self.external_id,
            "threadType": self.thread_type,
            "url": self.url,
            "remoteState": self.remote_state,
        }
        if self.title is not None:
            item["title"] = self.title
        if self.body is not None:
            item["body"] = self.body
        if self.remote_updated_at is not None:
            item["remoteUpdatedAt"] = self.remote_updated_at
        if self.external_human_activity_at is not None:
            item["externalHumanActivityAt"] = self.external_human_activity_at
        return item


@dataclass(frozen=True)
class Batch:
    source: RepoRef
    items: tuple[ExternalItem, ...]
    category: str

    def as_delta_batch(self) -> JsonObject:
        return {
            "source": {
                "provider": self.source.provider,
                "kind": "forge_repository",
                "id": self.source.source_id,
                "label": self.source.label,
                "url": self.source.html_url,
                "defaultCategory": self.category,
            },
            "items": [item.as_delta_item() for item in self.items],
        }


class JsonHttpClient:
    def __init__(self, *, min_remaining: int = 2, sleep: Any = time.sleep):
        self.min_remaining = min_remaining
        self.sleep = sleep

    def request_json(
        self,
        method: str,
        url: str,
        *,
        token: str | None = None,
        params: dict[str, str | int] | None = None,
        body: JsonObject | None = None,
        extra_headers: dict[str, str] | None = None,
    ) -> Any:
        if params:
            query = urllib.parse.urlencode(params)
            sep = "&" if urllib.parse.urlparse(url).query else "?"
            url = f"{url}{sep}{query}"

        headers = {
            "Accept": "application/json",
            "User-Agent": "delta-software-sync",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if extra_headers:
            headers.update(extra_headers)

        payload = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            payload = json.dumps(body).encode()

        request = urllib.request.Request(
            url, data=payload, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                self._check_rate_limit(response.status, dict(response.headers))
                raw = response.read()
        except urllib.error.HTTPError as error:
            self._check_rate_limit(error.code, dict(error.headers))
            detail = error.read().decode(errors="replace")
            raise SyncError(f"{method} {url} failed: {error.code} {detail}") from error

        if not raw:
            return None
        return json.loads(raw.decode())

    def _check_rate_limit(self, status: int, headers: dict[str, str]) -> None:
        retry_after = headers.get("Retry-After")
        if status in {403, 429} and retry_after:
            delay = int(retry_after)
            if delay > 0:
                self.sleep(min(delay, 60))
            raise RateLimitError(f"provider requested retry after {retry_after}s")

        remaining = headers.get("X-RateLimit-Remaining") or headers.get(
            "X-RateLimit-Remaining".lower()
        )
        if remaining is None:
            return

        try:
            remaining_count = int(remaining)
        except ValueError:
            return

        if remaining_count <= self.min_remaining:
            reset = headers.get("X-RateLimit-Reset")
            suffix = f" until {reset}" if reset else ""
            raise RateLimitError(
                f"provider rate limit remaining={remaining_count}{suffix}"
            )


def read_text_file(path: str) -> str:
    return Path(path).read_text(encoding="utf-8").strip()


def iso(value: str | None) -> str | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return value
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def latest_iso(values: list[str | None]) -> str | None:
    valid: list[datetime] = []
    for value in values:
        normalized = iso(value)
        if not normalized:
            continue
        try:
            valid.append(datetime.fromisoformat(normalized.replace("Z", "+00:00")))
        except ValueError:
            continue
    if not valid:
        return None
    return max(valid).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def user_login(user: JsonObject | None) -> str:
    if not isinstance(user, dict):
        return ""
    value = user.get("login") or user.get("username") or user.get("name") or ""
    return str(value)


def is_bot_user(user: JsonObject | None) -> bool:
    login = user_login(user).lower()
    if login.endswith("[bot]") or login.endswith("-bot") or login == "bot":
        return True
    if not isinstance(user, dict):
        return False
    return bool(user.get("is_bot")) or str(user.get("type", "")).lower() == "bot"


def is_external_human(user: JsonObject | None, maintainer: str) -> bool:
    login = user_login(user).lower()
    return bool(login) and login != maintainer.lower() and not is_bot_user(user)


def external_human_activity_at(
    thread: JsonObject,
    comments: list[JsonObject],
    maintainer: str,
) -> str | None:
    candidates: list[str | None] = []
    if is_external_human(thread.get("user") or thread.get("poster"), maintainer):
        candidates.append(thread.get("updated_at") or thread.get("created_at"))
    for comment in comments:
        if is_external_human(comment.get("user") or comment.get("poster"), maintainer):
            candidates.append(comment.get("updated_at") or comment.get("created_at"))
    return latest_iso(candidates)


def issue_remote_state(issue: JsonObject) -> str:
    if issue.get("state") == "open":
        return "open"
    reason = str(issue.get("state_reason") or issue.get("stateReason") or "").lower()
    if reason in {"not_planned", "duplicate", "rejected"}:
        return "cancelled"
    return "completed"


def pull_remote_state(pull: JsonObject) -> str:
    if pull.get("state") == "open":
        return "open"
    return "completed" if pull.get("merged") or pull.get("merged_at") else "cancelled"


class ForgeAdapter:
    def __init__(
        self,
        *,
        provider: str,
        base_url: str,
        token_file: str,
        priority: int,
        maintainer: str,
        http: JsonHttpClient,
    ):
        self.provider = provider
        self.base_url = base_url.rstrip("/")
        self.token = read_text_file(token_file)
        self.priority = priority
        self.maintainer = maintainer
        self.http = http

    def list_owned_repos(self) -> list[RepoRef]:
        raise NotImplementedError

    def list_open_issues(self, repo: RepoRef) -> list[ExternalItem]:
        raise NotImplementedError

    def list_open_pulls(self, repo: RepoRef) -> list[ExternalItem]:
        raise NotImplementedError

    def list_authored_open_pulls(self) -> list[ExternalItem]:
        raise NotImplementedError

    def fetch_item(
        self,
        repo: RepoRef,
        external_id: str,
        thread_type: str,
    ) -> ExternalItem | None:
        raise NotImplementedError


class GitHubAdapter(ForgeAdapter):
    @property
    def api_url(self) -> str:
        parsed = urllib.parse.urlparse(self.base_url)
        if parsed.netloc == "github.com":
            return "https://api.github.com"
        return f"{self.base_url}/api/v3"

    def _get(self, path: str, params: dict[str, str | int] | None = None) -> Any:
        return self.http.request_json(
            "GET", f"{self.api_url}{path}", token=self.token, params=params
        )

    def list_owned_repos(self) -> list[RepoRef]:
        repos: list[RepoRef] = []
        page = 1
        while True:
            rows = self._get(
                f"/users/{self.maintainer}/repos",
                {"type": "owner", "sort": "full_name", "per_page": 100, "page": page},
            )
            if not rows:
                break
            for row in rows:
                if row.get("private") is not False:
                    continue
                repos.append(
                    RepoRef(
                        provider=self.provider,
                        base_url=self.base_url,
                        owner=row["owner"]["login"],
                        name=row["name"],
                        html_url=row["html_url"],
                        priority=self.priority,
                    )
                )
            page += 1
        return repos

    def _comments(self, owner: str, repo: str, number: str) -> list[JsonObject]:
        return (
            self._get(
                f"/repos/{owner}/{repo}/issues/{number}/comments", {"per_page": 100}
            )
            or []
        )

    def _issue_item(
        self, repo: RepoRef, row: JsonObject, include_comments: bool
    ) -> ExternalItem:
        comments = (
            self._comments(repo.owner, repo.name, str(row["number"]))
            if include_comments
            else []
        )
        return ExternalItem(
            source=repo,
            external_id=str(row["number"]),
            thread_type="issue",
            title=row.get("title"),
            body=row.get("body"),
            url=row["html_url"],
            remote_state=issue_remote_state(row),
            remote_updated_at=iso(row.get("updated_at")),
            external_human_activity_at=external_human_activity_at(
                row, comments, self.maintainer
            ),
        )

    def _pull_item(
        self, repo: RepoRef, row: JsonObject, include_comments: bool
    ) -> ExternalItem:
        comments = (
            self._comments(repo.owner, repo.name, str(row["number"]))
            if include_comments
            else []
        )
        return ExternalItem(
            source=repo,
            external_id=str(row["number"]),
            thread_type="pull_request",
            title=row.get("title"),
            body=row.get("body"),
            url=row["html_url"],
            remote_state=pull_remote_state(row),
            remote_updated_at=iso(row.get("updated_at")),
            external_human_activity_at=external_human_activity_at(
                row, comments, self.maintainer
            ),
        )

    def list_open_issues(self, repo: RepoRef) -> list[ExternalItem]:
        rows = (
            self._get(
                f"/repos/{repo.owner}/{repo.name}/issues",
                {"state": "open", "per_page": 100},
            )
            or []
        )
        return [
            self._issue_item(repo, row, False)
            for row in rows
            if "pull_request" not in row
        ]

    def list_open_pulls(self, repo: RepoRef) -> list[ExternalItem]:
        rows = (
            self._get(
                f"/repos/{repo.owner}/{repo.name}/pulls",
                {"state": "open", "per_page": 100},
            )
            or []
        )
        return [self._pull_item(repo, row, False) for row in rows]

    def list_authored_open_pulls(self) -> list[ExternalItem]:
        query = f"is:pr is:open author:{self.maintainer} -user:{self.maintainer}"
        rows = self._get("/search/issues", {"q": query, "per_page": 100}) or {}
        items: list[ExternalItem] = []
        for row in rows.get("items", []):
            repo_url = row.get("repository_url", "")
            parts = urllib.parse.urlparse(repo_url).path.strip("/").split("/")
            if len(parts) < 2:
                continue
            repo = RepoRef(
                provider=self.provider,
                base_url=self.base_url,
                owner=parts[-2],
                name=parts[-1],
                html_url=f"{self.base_url}/{parts[-2]}/{parts[-1]}",
                priority=self.priority,
            )
            items.append(self._pull_item(repo, row, False))
        return items

    def fetch_item(
        self, repo: RepoRef, external_id: str, thread_type: str
    ) -> ExternalItem | None:
        if thread_type == "pull_request":
            row = self._get(f"/repos/{repo.owner}/{repo.name}/pulls/{external_id}")
            return self._pull_item(repo, row, True)
        row = self._get(f"/repos/{repo.owner}/{repo.name}/issues/{external_id}")
        return self._issue_item(repo, row, True)


class ForgejoAdapter(ForgeAdapter):
    @property
    def api_url(self) -> str:
        return f"{self.base_url}/api/v1"

    def _get(self, path: str, params: dict[str, str | int | bool] | None = None) -> Any:
        normalized = {
            key: ("true" if value is True else "false" if value is False else value)
            for key, value in (params or {}).items()
        }
        return self.http.request_json(
            "GET", f"{self.api_url}{path}", token=self.token, params=normalized
        )

    def list_owned_repos(self) -> list[RepoRef]:
        repos: list[RepoRef] = []
        page = 1
        while True:
            rows = self._get(
                f"/users/{self.maintainer}/repos", {"limit": 50, "page": page}
            )
            if not rows:
                break
            for row in rows:
                if row.get("private") is not False:
                    continue
                owner = (
                    row.get("owner", {}).get("login")
                    or row.get("owner", {}).get("username")
                    or self.maintainer
                )
                repos.append(
                    RepoRef(
                        provider=self.provider,
                        base_url=self.base_url,
                        owner=owner,
                        name=row["name"],
                        html_url=row.get("html_url")
                        or row.get("html_url".upper())
                        or f"{self.base_url}/{owner}/{row['name']}",
                        priority=self.priority,
                    )
                )
            page += 1
        return repos

    def _comments(self, owner: str, repo: str, number: str) -> list[JsonObject]:
        return (
            self._get(f"/repos/{owner}/{repo}/issues/{number}/comments", {"limit": 100})
            or []
        )

    def _issue_item(
        self, repo: RepoRef, row: JsonObject, include_comments: bool
    ) -> ExternalItem:
        number = str(row.get("number") or row.get("index"))
        comments = (
            self._comments(repo.owner, repo.name, number) if include_comments else []
        )
        return ExternalItem(
            source=repo,
            external_id=number,
            thread_type="issue",
            title=row.get("title"),
            body=row.get("body"),
            url=row.get("html_url") or f"{repo.html_url}/issues/{number}",
            remote_state=issue_remote_state(row),
            remote_updated_at=iso(row.get("updated_at")),
            external_human_activity_at=external_human_activity_at(
                row, comments, self.maintainer
            ),
        )

    def _pull_item(
        self, repo: RepoRef, row: JsonObject, include_comments: bool
    ) -> ExternalItem:
        number = str(row.get("number") or row.get("index"))
        comments = (
            self._comments(repo.owner, repo.name, number) if include_comments else []
        )
        return ExternalItem(
            source=repo,
            external_id=number,
            thread_type="pull_request",
            title=row.get("title"),
            body=row.get("body"),
            url=row.get("html_url") or f"{repo.html_url}/pulls/{number}",
            remote_state=pull_remote_state(row),
            remote_updated_at=iso(row.get("updated_at")),
            external_human_activity_at=external_human_activity_at(
                row, comments, self.maintainer
            ),
        )

    def list_open_issues(self, repo: RepoRef) -> list[ExternalItem]:
        rows = (
            self._get(
                f"/repos/{repo.owner}/{repo.name}/issues",
                {"state": "open", "type": "issues", "limit": 50},
            )
            or []
        )
        return [
            self._issue_item(repo, row, False)
            for row in rows
            if not row.get("pull_request")
        ]

    def list_open_pulls(self, repo: RepoRef) -> list[ExternalItem]:
        rows = (
            self._get(
                f"/repos/{repo.owner}/{repo.name}/pulls", {"state": "open", "limit": 50}
            )
            or []
        )
        return [self._pull_item(repo, row, False) for row in rows]

    def list_authored_open_pulls(self) -> list[ExternalItem]:
        rows = (
            self._get(
                "/repos/issues/search",
                {"state": "open", "type": "pulls", "created": True, "limit": 50},
            )
            or []
        )
        items: list[ExternalItem] = []
        for row in rows:
            if (
                user_login(row.get("poster") or row.get("user")).lower()
                != self.maintainer.lower()
            ):
                continue
            repo_row = row.get("repository") or {}
            repo_owner = repo_row.get("owner") if isinstance(repo_row, dict) else None
            if isinstance(repo_owner, dict):
                owner = repo_owner.get("login") or repo_owner.get("username")
            elif isinstance(repo_owner, str):
                owner = repo_owner
            else:
                owner = None
            name = repo_row.get("name") if isinstance(repo_row, dict) else None
            if not owner or not name:
                path = (
                    urllib.parse.urlparse(row.get("html_url", ""))
                    .path.strip("/")
                    .split("/")
                )
                if len(path) < 4:
                    continue
                owner, name = path[0], path[1]
            repo = RepoRef(
                provider=self.provider,
                base_url=self.base_url,
                owner=owner,
                name=name,
                html_url=(
                    repo_row.get("html_url") if isinstance(repo_row, dict) else None
                )
                or f"{self.base_url}/{owner}/{name}",
                priority=self.priority,
            )
            items.append(self._pull_item(repo, row, False))
        return items

    def fetch_item(
        self, repo: RepoRef, external_id: str, thread_type: str
    ) -> ExternalItem | None:
        if thread_type == "pull_request":
            row = self._get(f"/repos/{repo.owner}/{repo.name}/pulls/{external_id}")
            return self._pull_item(repo, row, True)
        row = self._get(f"/repos/{repo.owner}/{repo.name}/issues/{external_id}")
        return self._issue_item(repo, row, True)


class DeltaClient:
    def __init__(self, url: str, api_key_file: str, http: JsonHttpClient):
        self.url = url.rstrip("/")
        self.api_key = read_text_file(api_key_file)
        self.http = http

    def post_batch(self, batch: Batch) -> JsonObject:
        return self.http.request_json(
            "POST",
            f"{self.url}/api/external-tasks/batch",
            token=self.api_key,
            body=batch.as_delta_batch(),
        )

    def list_software_tasks(self, category: str) -> list[JsonObject]:
        rows = self.http.request_json(
            "GET",
            f"{self.url}/api/tasks",
            token=self.api_key,
            params={"category": category},
        )
        return rows or []


def select_canonical_repos(
    adapters: list[ForgeAdapter],
    canonical_providers: dict[str, str] | None = None,
) -> dict[str, tuple[ForgeAdapter, RepoRef]]:
    # A repo owned on several forges normally resolves to the lowest-priority
    # forge. canonical_providers pins specific "owner/name" keys to one provider
    # regardless of priority -- e.g. popular plugins whose issues live on GitHub
    # even though the code is mirrored to Forgejo.
    overrides = {
        key.lower(): provider
        for key, provider in (canonical_providers or {}).items()
    }
    canonical: dict[str, tuple[ForgeAdapter, RepoRef]] = {}
    for adapter in sorted(adapters, key=lambda item: item.priority):
        for repo in adapter.list_owned_repos():
            override = overrides.get(repo.key)
            if override and override != adapter.provider:
                continue
            canonical.setdefault(repo.key, (adapter, repo))
    return canonical


def group_batches(items: list[ExternalItem], category: str) -> list[Batch]:
    grouped: dict[tuple[str, str], list[ExternalItem]] = {}
    sources: dict[tuple[str, str], RepoRef] = {}
    for item in items:
        key = (item.source.provider, item.source.source_id)
        grouped.setdefault(key, []).append(item)
        sources[key] = item.source
    return [
        Batch(
            sources[key],
            tuple(
                sorted(
                    batch_items, key=lambda item: (item.thread_type, item.external_id)
                )
            ),
            category,
        )
        for key, batch_items in sorted(grouped.items())
    ]


def build_discovery_batches(
    adapters: list[ForgeAdapter],
    maintainer: str,
    category: str,
    canonical_providers: dict[str, str] | None = None,
) -> list[Batch]:
    canonical = select_canonical_repos(adapters, canonical_providers)
    items: list[ExternalItem] = []

    for adapter, repo in canonical.values():
        items.extend(adapter.list_open_issues(repo))
        items.extend(adapter.list_open_pulls(repo))

    owned_keys = set(canonical)
    for adapter in adapters:
        for item in adapter.list_authored_open_pulls():
            if item.source.owner.lower() == maintainer.lower():
                continue
            if item.source.key in owned_keys:
                continue
            items.append(item)

    return group_batches(items, category)


def repo_from_source_info(source_info: JsonObject) -> RepoRef | None:
    source_id = source_info.get("sourceId")
    source_provider = source_info.get("sourceProvider")
    source_url = source_info.get("sourceUrl")
    source_title = source_info.get("sourceTitle")
    if not source_id or not source_provider or not source_title:
        return None
    host, owner, name = str(source_id).split("/", 2)
    # Derive base_url from the stored sourceId host (not sourceUrl) so the
    # RepoRef's computed source_id round-trips to the same value Delta stored.
    # Otherwise a host change (e.g. git.* -> forge.* in html_url) would make the
    # reconcile pass re-post under a different source id and duplicate the task.
    parsed = urllib.parse.urlparse(str(source_url)) if source_url else None
    scheme = parsed.scheme if parsed and parsed.scheme else "https"
    base_url = f"{scheme}://{host}"
    return RepoRef(
        provider=str(source_provider),
        base_url=base_url,
        owner=owner,
        name=name,
        html_url=str(source_url or f"{base_url}/{owner}/{name}"),
        priority=0,
    )


def build_active_batches(
    adapters_by_provider: dict[str, ForgeAdapter],
    tasks: list[JsonObject],
    category: str,
) -> list[Batch]:
    items: list[ExternalItem] = []
    for task in tasks:
        if task.get("status") not in {"pending", "wip", "blocked"}:
            continue
        source_info = task.get("sourceInfo")
        if (
            not isinstance(source_info, dict)
            or source_info.get("sourceKind") != "forge_repository"
        ):
            continue
        repo = repo_from_source_info(source_info)
        if not repo:
            continue
        adapter = adapters_by_provider.get(repo.provider)
        if not adapter:
            continue
        try:
            fetched = adapter.fetch_item(
                repo,
                str(source_info.get("externalId")),
                str(source_info.get("threadType") or "issue"),
            )
        except RateLimitError:
            raise
        except SyncError as error:
            print(
                f"skipping {repo.label}#{source_info.get('externalId')}: {error}",
                file=sys.stderr,
            )
            continue
        if fetched:
            items.append(fetched)
    return group_batches(items, category)


def build_adapters(config: JsonObject, http: JsonHttpClient) -> list[ForgeAdapter]:
    maintainer = config["maintainerUsername"]
    adapters: list[ForgeAdapter] = []
    for forge in config.get("forges", []):
        cls: type[ForgeAdapter]
        provider = forge["provider"]
        if provider == "github":
            cls = GitHubAdapter
        elif provider == "forgejo":
            cls = ForgejoAdapter
        else:
            raise SyncError(f"unsupported forge provider: {provider}")
        adapters.append(
            cls(
                provider=provider,
                base_url=forge["baseUrl"],
                token_file=forge["tokenFile"],
                priority=int(forge.get("priority", 100)),
                maintainer=maintainer,
                http=http,
            )
        )
    return adapters


def run(config: JsonObject, mode: str, *, dry_run: bool = False) -> list[JsonObject]:
    http = JsonHttpClient(min_remaining=int(config.get("minRateLimitRemaining", 2)))
    adapters = build_adapters(config, http)
    category = config.get("category", "Software")
    batches: list[Batch] = []

    if mode in {"discovery", "all"}:
        batches.extend(
            build_discovery_batches(
                adapters,
                config["maintainerUsername"],
                category,
                config.get("canonicalProviders"),
            )
        )

    if mode in {"active", "all"}:
        delta_config = config["delta"]
        delta = DeltaClient(delta_config["url"], delta_config["apiKeyFile"], http)
        adapters_by_provider = {adapter.provider: adapter for adapter in adapters}
        batches.extend(
            build_active_batches(
                adapters_by_provider, delta.list_software_tasks(category), category
            )
        )

    if dry_run:
        payloads = [batch.as_delta_batch() for batch in batches]
        print(json.dumps(payloads, indent=2, sort_keys=True))
        return payloads

    delta_config = config["delta"]
    delta = DeltaClient(delta_config["url"], delta_config["apiKeyFile"], http)
    results = []
    for batch in batches:
        if batch.items:
            results.append(delta.post_batch(batch))
    print(json.dumps({"batches": len(results), "results": results}, sort_keys=True))
    return results


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--mode", choices=["active", "discovery", "all"], default="all")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    try:
        run(config, args.mode, dry_run=args.dry_run)
    except RateLimitError as error:
        print(f"rate limited: {error}", file=sys.stderr)
        return 75
    except SyncError as error:
        print(f"sync failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
