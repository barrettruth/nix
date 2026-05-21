# GitHub Data Policy

Use `gh` and `gh api` for GitHub issue, PR, review, and timeline context.
General network tools are allowed for non-GitHub docs, builds, and repros.

GitHub access is read-only unless a future PR workflow explicitly allows one
exact remote action.

Forbidden in active issue/code/verify phases: comments, reviews, replies,
reactions, issue/PR edits, labels, assignments, subscriptions, workflow
dispatch/reruns/cancels, auth token exposure, aliases/extensions that hide
writes, and GraphQL mutations.

Required issue intake:

```sh
gh issue view 12345 -R neovim/neovim --comments --json \
  number,title,state,author,body,comments,labels,createdAt,updatedAt,url,closedByPullRequestsReferences
```

Save raw `gh`/`gh api` JSON under `sources/github/` and link it from
`sources.md`; do not paste large raw responses into `index.md` or `report.md`.

Broad search is allowed only inside `neovim/neovim`:

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
