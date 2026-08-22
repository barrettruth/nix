---
name: jj-stack
description: Use where work ships as stacked pull requests or merge requests on github.com or gitlab.com — the `jj pr` tool, pull request bases, bookmarks that look odd, or a stack that is not behaving. Establish real state with read-only commands, then report concisely.
---

# jj-stack

Where work ships through stacked pull requests, on github.com or gitlab.com,
he uses plain jj plus one tool. Read the `jj` skill for the underlying model;
this covers the workflow built on top.

## Where this applies

Confirm the repository ships that way before reaching for any of it. Open pull
requests, `push-*` bookmarks on the remote, and a pull request template each say
yes; a history of direct commits on trunk says the repository ships another way,
and his nix config is one of those. There, shipping means advancing the bookmark
the remote already tracks:

```
jj bookmark set main -r @
jj git push -b main
```

Read "push my changes" in such a repository as exactly that pair, and stack only
where he says so or the repository already does.

## How to answer

Establish what is actually true — the stack, the bookmarks, the pull request
bases — with read-only commands. Then answer in two parts: what is going on, and
what fixes it.

- One command fixes it, give the command and one sentence saying what it does.
- Several steps or a real tradeoff, say so in a line first, then lay it out.
- A question is a request to understand. Investigate, report, hand over the
  command. When he asks for the change to be made, make it.

## When the workflow is at fault

Some bad states are reachable through ordinary use — the tooling allowed
something it could have caught, or this file was missing the fact that would
have prevented it. Say so in one line next to the fix, and name the change that
stops a repeat: a guard in `jj-pr`, a setting in `jjConf`, a row in the recipes
below. Worth raising even mid-incident, briefly, because repairing the state and
leaving the hole open pays for the same problem twice.

An ordinary slip just needs the command.

## The loop

```
jj sy                  fetch, rebase the stack onto trunk, show it
jj s                   the stack containing @
jj edit <id>           work anywhere in it; descendants follow
jj pr                  make GitHub match
```

`jj sd` is the cumulative diff of the stack, `jj sp` the per-change patches that
map one-to-one onto the open pull requests, `jj h` the project history. Long
forms are `stack`, `sync`, `restack`, `up`, `sdiff`, `spatch`, `hist`. All of
them are defined in the `jjConf` block of
`~/.config/nix/modules/barrett/workstation.nix`, which is the source of
truth if one looks unfamiliar.

Within a stack the bookmarks are generated: `jj git push -c` creates
`push-<change-id>`, and because change IDs survive rewrites, a pull request
stays attached to its change through any amount of restructuring.

## The invariant

**Bookmark `push-<id>` belongs on change `<id>`.**

Everything else follows. Pull request bases are read from position in the chain,
computed fresh each run, so there is no stored state and nothing to reconcile.
`jj pr` (`~/.config/nix/scripts/jj-pr`) enforces the invariant, pushes, then
creates missing pull requests, corrects stale bases and titles, and lets deleted
branches close their own. It echoes every command it runs, and `--dry-run` shows
the plan without touching anything. It resolves the forge before it writes, so
an unusable remote cannot leave repaired bookmarks pushed behind a failure.

Titles track the change description, since a split leaves them describing the
wrong diff. Bodies are the user's — written once at creation from the repo
template if there is one, and left alone afterwards.

`jj pr` reports rather than guesses when the stack forks, when a change has no
bookmark, or when it cannot tell what the origin host is running. The first two
mean the correct base is genuinely unknown, and a wrong base shows reviewers the
wrong diff without any visible sign.

## GitHub and GitLab

The forge comes from the origin host: `gh` for github.com, `glab` for
gitlab.com. Everything above the forge call is plain jj and behaves identically
on both, so only the last step differs. A self-hosted host is never guessed —
pass `--forge github` or `--forge gitlab`, which addresses the host in the
origin URL rather than the public one.

On GitLab the vocabulary shifts but the workflow does not: merge requests, `iid`
rather than number, and `--target-branch` where GitHub says base. Bodies come
from `.gitlab/merge_request_templates/Default.md`, which `jj pr` reads itself
because the API, unlike the web UI, does not apply that template. Deleting a
source branch closes its merge request, so squash and abandon settle exactly as
they do on GitHub.

## Waiting on CI

| forge | command |
|---|---|
| github | `gh pr checks <n> --watch --fail-fast` |
| gitlab | `glab ci status --wait` |

Both block until the run settles and exit non-zero when it fails, so start one
with a long timeout and read it once. Add `--required` on GitHub to ignore
advisory checks. Never loop on status: each call costs a turn, and the
non-watching form of `gh pr checks` exits 8 while checks are merely pending,
which reads as failure.

## What each operation costs

| intent | command | bookmark repair | base drift |
|---|---|---|---|
| add on top | `jj new -m …` | — | — |
| amend in place | `jj edit <id>` | — | — |
| insert | `jj new -A <id> -m …` | — | yes |
| reorder | `jj rebase -r <id> -B <id>` | — | yes |
| drop | `jj abandon <id>` | jj deletes it | yes |
| split one PR into two | `jj split -r <id> <files>` | move it back | yes |
| merge two PRs into one | `jj squash -u --from <id> --into <id>` | delete the orphan | yes |

Append and amend never drift, which is why ordinary days need no reconciliation.
Restructuring always drifts, and `jj pr` is how it settles.

Split hands the bottom half the change ID and the top half the bookmark, so the
two come apart. Squash lands the source's bookmark on the destination, leaving
one change wearing two. Both are repaired by restoring the invariant.

## Recipes

| situation | check | fix |
|---|---|---|
| "Bookmark already exists" on push | `jj s` — a split split the name from the ID | `jj pr` |
| a change shows two bookmarks | `jj bookmark list` | `jj pr` |
| a pull request shows more diff than its change | `gh pr view <n> --json baseRefName`, or `glab mr view <n> --output json` | `jj pr` |
| a pull request stayed open after squash or abandon | `jj bookmark list` for the deletion | `jj git push --deleted`, or `jj pr` |
| changes above `@` did not reach the remote | bare `jj git push` covers `remote_bookmarks()..@` only | `jj up` |
| a new bookmark was declined on push | creating one needs `-b`, `-c`, `--named` or `--all` | `jj up` |
| the stack sits on an old trunk | `jj log -r 'trunk()'` | `jj sy` |
| `jj pr` reports a fork | `jj s` shows two children sharing a parent | `jj pr --revset 'trunk()..<id>'` for one line at a time |
| what a reviewer will see as new | | `jj interdiff --from <bookmark>@origin --to <bookmark>` |

`jj pr` is idempotent, so it is the right answer to most of these — it repairs
whatever it finds and reports what it changed.
