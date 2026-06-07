import contextlib
import io
import unittest
from tempfile import NamedTemporaryFile

from delta_software_sync import (
    Batch,
    ExternalItem,
    ForgejoAdapter,
    JsonHttpClient,
    RateLimitError,
    RepoRef,
    SyncError,
    build_active_batches,
    build_discovery_batches,
    external_human_activity_at,
    repo_from_source_info,
)


class FakeAdapter:
    def __init__(self, provider, priority, owned=(), issues=(), pulls=(), authored=()):
        self.provider = provider
        self.priority = priority
        self.owned = list(owned)
        self.issues = list(issues)
        self.pulls = list(pulls)
        self.authored = list(authored)

    def list_owned_repos(self):
        return self.owned

    def list_open_issues(self, repo):
        return [item for item in self.issues if item.source == repo]

    def list_open_pulls(self, repo):
        return [item for item in self.pulls if item.source == repo]

    def list_authored_open_pulls(self):
        return self.authored


class FakeHttp:
    def __init__(self, payload):
        self.payload = payload

    def request_json(self, *_args, **_kwargs):
        return self.payload


class FakeSequenceHttp:
    def __init__(self, payloads):
        self.payloads = list(payloads)

    def request_json(self, *_args, **_kwargs):
        return self.payloads.pop(0)


def repo(provider, owner, name, priority):
    return RepoRef(
        provider=provider,
        base_url=(
            "https://git.example.com" if provider == "forgejo" else "https://github.com"
        ),
        owner=owner,
        name=name,
        html_url=f"https://{provider}.example.com/{owner}/{name}",
        priority=priority,
    )


def item(source, external_id, thread_type="issue", title=None):
    return ExternalItem(
        source=source,
        external_id=external_id,
        thread_type=thread_type,
        title=title or f"{source.label} #{external_id}",
        body="body",
        url=f"{source.html_url}/issues/{external_id}",
        remote_state="open",
        remote_updated_at="2026-06-06T12:00:00Z",
    )


class DiscoveryBatchTests(unittest.TestCase):
    def test_prefers_forgejo_over_github_for_same_owned_repo(self):
        forgejo_repo = repo("forgejo", "barrettruth", "delta", 10)
        github_repo = repo("github", "barrettruth", "delta", 20)
        forgejo = FakeAdapter(
            "forgejo",
            10,
            owned=[forgejo_repo],
            issues=[item(forgejo_repo, "1")],
        )
        github = FakeAdapter(
            "github",
            20,
            owned=[github_repo],
            issues=[item(github_repo, "1")],
        )

        batches = build_discovery_batches([github, forgejo], "barrettruth", "Software")

        self.assertEqual(len(batches), 1)
        self.assertEqual(batches[0].source.provider, "forgejo")
        self.assertEqual(
            batches[0].as_delta_batch()["source"]["id"],
            "git.example.com/barrettruth/delta",
        )

    def test_includes_owned_issues_owned_pulls_and_non_owned_authored_pulls(self):
        owned = repo("forgejo", "barrettruth", "delta", 10)
        external = repo("github", "someone", "project", 20)
        own_issue = item(owned, "1", "issue")
        own_pull = item(owned, "2", "pull_request")
        external_pull = item(external, "3", "pull_request")
        adapter = FakeAdapter(
            "forgejo",
            10,
            owned=[owned],
            issues=[own_issue],
            pulls=[own_pull],
            authored=[external_pull],
        )

        batches = build_discovery_batches([adapter], "barrettruth", "Software")
        payloads = [batch.as_delta_batch() for batch in batches]
        flat = [item for payload in payloads for item in payload["items"]]

        self.assertEqual({entry["externalId"] for entry in flat}, {"1", "2", "3"})
        self.assertEqual(
            {entry["threadType"] for entry in flat},
            {"issue", "pull_request"},
        )

    def test_excludes_non_owned_issues_and_owned_authored_pr_duplicates(self):
        owned = repo("github", "barrettruth", "delta", 20)
        own_authored_pull = item(owned, "4", "pull_request")
        adapter = FakeAdapter(
            "github",
            20,
            owned=[owned],
            pulls=[],
            authored=[own_authored_pull],
        )

        batches = build_discovery_batches([adapter], "barrettruth", "Software")

        self.assertEqual(batches, [])

    def test_batches_are_one_source_per_request(self):
        first = repo("forgejo", "barrettruth", "delta", 10)
        second = repo("forgejo", "barrettruth", "nix", 10)
        adapter = FakeAdapter(
            "forgejo",
            10,
            owned=[first, second],
            issues=[item(first, "1"), item(second, "1")],
        )

        batches = build_discovery_batches([adapter], "barrettruth", "Software")

        self.assertEqual(len(batches), 2)
        self.assertEqual({len(batch.items) for batch in batches}, {1})
        self.assertEqual(
            {batch.as_delta_batch()["source"]["label"] for batch in batches},
            {"barrettruth/delta", "barrettruth/nix"},
        )

    def test_forgejo_owned_repos_are_public_only(self):
        with NamedTemporaryFile("w") as token_file:
            token_file.write("token")
            token_file.flush()
            adapter = ForgejoAdapter(
                provider="forgejo",
                base_url="https://git.example.com",
                token_file=token_file.name,
                priority=10,
                maintainer="barrettruth",
                http=FakeSequenceHttp(
                    [
                        [
                            {
                                "owner": {"login": "barrettruth"},
                                "name": "public-repo",
                                "html_url": "https://git.example.com/barrettruth/public-repo",
                                "private": False,
                            },
                            {
                                "owner": {"login": "barrettruth"},
                                "name": "private-repo",
                                "html_url": "https://git.example.com/barrettruth/private-repo",
                                "private": True,
                            },
                        ],
                        [],
                    ]
                ),
            )

            repos = adapter.list_owned_repos()

        self.assertEqual([repo.name for repo in repos], ["public-repo"])

    def test_forgejo_authored_pulls_accept_string_repository_owner(self):
        with NamedTemporaryFile("w") as token_file:
            token_file.write("token")
            token_file.flush()
            adapter = ForgejoAdapter(
                provider="forgejo",
                base_url="https://git.example.com",
                token_file=token_file.name,
                priority=10,
                maintainer="barrettruth",
                http=FakeHttp(
                    [
                        {
                            "poster": {"login": "barrettruth"},
                            "number": 7,
                            "title": "PR",
                            "body": "Body",
                            "state": "open",
                            "html_url": "https://git.example.com/someone/project/pulls/7",
                            "repository": {
                                "owner": "someone",
                                "name": "project",
                            },
                        }
                    ]
                ),
            )

            items = adapter.list_authored_open_pulls()

        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].source.owner, "someone")
        self.assertEqual(items[0].source.name, "project")


class ActivityTests(unittest.TestCase):
    def test_includes_bot_created_threads_but_excludes_bot_activity(self):
        thread = {
            "user": {"login": "renovate[bot]", "type": "Bot"},
            "updated_at": "2026-06-06T12:00:00Z",
        }
        comments = [
            {
                "user": {"login": "alex", "type": "User"},
                "updated_at": "2026-06-06T12:05:00Z",
            },
            {
                "user": {"login": "dependabot[bot]", "type": "Bot"},
                "updated_at": "2026-06-06T12:10:00Z",
            },
        ]

        self.assertEqual(
            external_human_activity_at(thread, comments, "barrettruth"),
            "2026-06-06T12:05:00Z",
        )

    def test_excludes_maintainer_activity(self):
        thread = {
            "user": {"login": "barrettruth", "type": "User"},
            "updated_at": "2026-06-06T12:00:00Z",
        }
        comments = [
            {
                "user": {"login": "barrettruth", "type": "User"},
                "updated_at": "2026-06-06T12:05:00Z",
            }
        ]

        self.assertIsNone(external_human_activity_at(thread, comments, "barrettruth"))


def software_task(owner, name, external_id, status="pending"):
    return {
        "status": status,
        "sourceInfo": {
            "sourceKind": "forge_repository",
            "sourceProvider": "github",
            "sourceId": f"github.com/{owner}/{name}",
            "sourceUrl": f"https://github.com/{owner}/{name}",
            "sourceTitle": f"{owner}/{name}",
            "externalId": external_id,
            "threadType": "pull_request",
        },
    }


class ActiveBatchTests(unittest.TestCase):
    def test_skips_items_whose_fetch_fails_and_keeps_the_rest(self):
        class FetchAdapter:
            provider = "github"

            def fetch_item(self, repo_ref, external_id, _thread_type):
                if repo_ref.owner == "nvimtools":
                    raise SyncError("403 forbidden")
                return ExternalItem(
                    source=repo_ref,
                    external_id=external_id,
                    thread_type="pull_request",
                    title="ok",
                    body=None,
                    url=f"{repo_ref.html_url}/pulls/{external_id}",
                    remote_state="cancelled",
                )

        tasks = [
            software_task("someone", "project", "3"),
            software_task("nvimtools", "none-ls-extras.nvim", "47"),
        ]

        with contextlib.redirect_stderr(io.StringIO()) as captured:
            batches = build_active_batches(
                {"github": FetchAdapter()}, tasks, "Software"
            )

        flat = [entry for batch in batches for entry in batch.as_delta_batch()["items"]]
        self.assertEqual({entry["externalId"] for entry in flat}, {"3"})
        self.assertIn("none-ls-extras.nvim#47", captured.getvalue())

    def test_propagates_rate_limit_errors(self):
        class RateLimitedAdapter:
            provider = "github"

            def fetch_item(self, _repo_ref, _external_id, _thread_type):
                raise RateLimitError("slow down")

        tasks = [software_task("someone", "project", "3")]

        with self.assertRaises(RateLimitError):
            build_active_batches({"github": RateLimitedAdapter()}, tasks, "Software")

    def test_only_reconciles_active_status_tasks(self):
        seen: list[str] = []

        class RecordingAdapter:
            provider = "github"

            def fetch_item(self, repo_ref, external_id, _thread_type):
                seen.append(external_id)
                return ExternalItem(
                    source=repo_ref,
                    external_id=external_id,
                    thread_type="pull_request",
                    title="ok",
                    body=None,
                    url=f"{repo_ref.html_url}/pulls/{external_id}",
                    remote_state="open",
                )

        tasks = [
            software_task("someone", "project", "1", status="pending"),
            software_task("someone", "project", "2", status="wip"),
            software_task("someone", "project", "3", status="blocked"),
            software_task("someone", "project", "4", status="done"),
            software_task("someone", "project", "5", status="cancelled"),
        ]

        build_active_batches({"github": RecordingAdapter()}, tasks, "Software")

        self.assertEqual(set(seen), {"1", "2", "3"})


class RepoFromSourceInfoTests(unittest.TestCase):
    def test_source_id_round_trips_when_url_host_differs(self):
        info = {
            "sourceKind": "forge_repository",
            "sourceProvider": "forgejo",
            "sourceId": "git.barrettruth.com/barrettruth/delta",
            "sourceUrl": "https://forge.barrettruth.com/barrettruth/delta",
            "sourceTitle": "barrettruth/delta",
            "externalId": "1",
            "threadType": "issue",
        }

        repo = repo_from_source_info(info)

        self.assertIsNotNone(repo)
        assert repo is not None
        self.assertEqual(repo.source_id, "git.barrettruth.com/barrettruth/delta")
        self.assertEqual(repo.provider, "forgejo")
        self.assertEqual(repo.owner, "barrettruth")
        self.assertEqual(repo.name, "delta")


class RateLimitTests(unittest.TestCase):
    def test_raises_when_remaining_quota_is_low(self):
        client = JsonHttpClient(min_remaining=2)

        with self.assertRaises(RateLimitError):
            client._check_rate_limit(200, {"X-RateLimit-Remaining": "1"})


class BatchShapeTests(unittest.TestCase):
    def test_request_shape_matches_delta_contract(self):
        source = repo("github", "barrettruth", "delta", 20)
        batch = Batch(source=source, items=(item(source, "123"),), category="Software")

        payload = batch.as_delta_batch()

        self.assertEqual(payload["source"]["kind"], "forge_repository")
        self.assertEqual(payload["source"]["id"], "github.com/barrettruth/delta")
        self.assertEqual(payload["source"]["label"], "barrettruth/delta")
        self.assertEqual(payload["items"][0]["externalId"], "123")
        self.assertNotIn("providerPayload", payload["items"][0])


if __name__ == "__main__":
    unittest.main()
