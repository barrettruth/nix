# GitHub Data Policy

Use `gh` and `gh api` for GitHub issue, PR, review, and timeline context.
This reference is for GitHub/history context only.

GitHub access is read-only unless a future PR workflow explicitly allows one
exact remote action.

Forbidden in active issue/repro/plan/impl/verify/review phases: comments,
reviews, replies,
reactions, issue/PR edits, labels, assignments, subscriptions, workflow
dispatch/reruns/cancels, auth token exposure, aliases/extensions that hide
writes, and GraphQL mutations.

Required issue intake:

```sh
gh issue view 12345 -R neovim/neovim --comments --json \
  number,title,state,author,body,comments,labels,createdAt,updatedAt,url,closedByPullRequestsReferences
```

Save raw `gh`/`gh api` JSON under `sources/github/` only when it supports a
claim in `evidence/history.md`; link saved files from `sources.md`.

History evidence policy:

- Prefer the setup `issue.json` and `issue.md` before fetching more.
- Fetch direct references from the issue first: named commits, PRs, issues, and
  stack source files.
- Use controlled fanout by default. The parent history role must spawn up to
  three narrow child agents immediately unless the issue lacks that lane:
  direct commit/PR context, local source-path context, and related/excluded
  GitHub searches. The parent owns `evidence/history.md`, `sources.md`, and any
  saved raw source decisions.
- Child agents return concise evidence summaries and exact commands/URLs; they
  do not write final wiki files unless the parent assigns a specific raw-source
  path.
- Read broadly when the issue needs it, but save raw output only when it is
  cited in `evidence/history.md` as key evidence, relevant secondary context, a
  checked-and-excluded plausible lead, or an unresolved lead.
- Do not fetch PR files/reviews/timeline unless the issue or a direct PR makes
  them relevant.
- Broad search is for exact duplicates, named error text, named APIs, or direct
  subsystem terms. If a search does not change the report, summarize it without
  saving its raw JSON.
- `sources.md` is curated. Do not list every inspected GitHub response.

Broad search, when needed, stays inside `neovim/neovim`:

```sh
gh search issues <terms> --repo neovim/neovim --match title,body,comments --state all --json number,title,state,url,labels,commentsCount,updatedAt
gh search prs <terms> --repo neovim/neovim --match title,body,comments --state all --json number,title,state,url,labels,commentsCount,updatedAt
```

Use `gh api --method GET` for context the high-level commands do not expose:

```sh
gh api --method GET --paginate repos/neovim/neovim/issues/12345/timeline
gh api --method GET --paginate repos/neovim/neovim/pulls/<pr>/comments
gh api --method GET --paginate repos/neovim/neovim/pulls/<pr>/reviews
gh api --method GET --paginate repos/neovim/neovim/pulls/<pr>/files
```

For PR review threads and resolved conversations, use GraphQL
`pullRequest.reviewThreads` with a read-only `query`. Suggested changes are
review-comment bodies with fenced `suggestion` blocks.
