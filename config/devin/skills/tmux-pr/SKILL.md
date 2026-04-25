---
name: tmux-pr
description: tmux issue workflow for Barrett Ruth — reproduce first, minimal fixes, tmux-native commit and PR style
user-invocable: true
---

# /tmux-pr

Use this for work in `/home/barrett/dev/tmux` when the goal is to reproduce,
fix, commit, and submit one tmux PR at a time in Barrett's style.

## Verbatim critique from the previous session

The specific failure mode here was not technical; it was **state management**.
I kept treating your corrections as local edits to the current draft instead of
as **durable workflow constraints** that should have been applied to every
later step.

Specific critique:

- I drafted commit messages before anchoring on actual `tmux master` subjects,
  so I defaulted to generic Git prose instead of tmux’s one-line, sentence-case,
  usually-bodyless style.
- I drafted PR text in generic assistant voice instead of first matching your
  existing tmux PRs and your own narration style.
- I wrote repro scripts like report artifacts instead of like the scrappy local
  shell you actually write.
- I failed to infer stable preferences after repeated correction: lowercase
  `asan`, short vars, no fancy heredoc quoting, no polished harness tone,
  shorter tmux aliases, `sleep 2`, fewer redirects, etc.
- I let you spend cycles correcting presentation at the same time we were
  supposed to be spending cycles on bug triage and fix complexity.
- I should have created a reusable memory artifact after the **second**
  correction, not after the PR was already open.

The most efficient setup is **not** a git-ignored markdown file by itself. A
plain MD file is passive: it only helps if I remember to reread it before every
commit message, PR title, PR body, and repro block. The better setup is:

1. **A user-level Devin skill for stable rules**
2. **Per-issue scratch files under `/tmp/tmux/` for transient material**

That split matches the problem:

- the **skill** stores the stable workflow and style constraints across all
  8-ish PRs
- the `/tmp` files store issue-specific repros, raw asan output, and PR drafts,
  then disappear with the worktree

## Why this skill exists

Previous tmux sessions wasted time by repeatedly missing obvious style and
workflow requirements that the user had already corrected:

- commit messages were drafted in generic Git style instead of current tmux
  `master` style
- PR bodies sounded too polished and generic instead of like Barrett
- repro scripts were too cleaned up, too indirect, and not realistic enough
- user corrections were applied locally, but not turned into durable rules for
  the next step
- we kept iterating on avoidable presentation failures instead of saving time
  for the hard bugs

This skill exists to stop that loop.

## Non-negotiable workflow

1. Work one issue at a time.
2. Reproduce first.
3. Only attempt a fix after the bug is demonstrated locally.
4. If the fix is not clearly small and local, stop after root cause and repro.
5. Never commit, push, or open or update a PR without explicit user permission.
6. When opening a PR, create it as a draft first with an empty body unless the
   user says otherwise.

## Before drafting anything user-facing

Before drafting a commit message, PR title, or PR body:

1. Inspect recent `tmux master` commit subjects with `git log`.
2. Inspect Barrett's recent tmux PRs with `gh pr view`.
3. Re-read the user's latest style corrections from the current chat.
4. Ask: "Does this sound like tmux and Barrett, or like generic assistant
   prose?"
5. If it sounds generic, rewrite it before showing it.

## Commit message rules for tmux

Default to tmux-native commit subjects:

- one sentence
- sentence case
- trailing period
- usually no body unless the user explicitly asks for one
- prefer tmux-like forms such as:
  - `Do not ...`
  - `If ..., ...`
  - direct imperative summaries

Do not default to conventional commit style here.

## PR body rules for Barrett

The PR body should sound like Barrett, not like a polished project template.

Preferred traits:

- direct
- plainspoken
- concrete
- slightly rough is fine
- realistic self-narration about how the bug was found
- specific local repro and testing notes

Avoid unless the user explicitly wants them:

- canned "Summary/Test Plan" sections
- corporate tone
- over-explaining obvious code
- invented structure that does not match Barrett's voice

## Repro requirements for each issue

Every issue should have all of the following before a fix is proposed:

1. a concise summary of the bug
2. a copy-pasteable tmux script or command sequence that triggers it
3. an actual local run of that repro
4. raw output proving the bug, including asan or lsan text when relevant
5. a judgment call on fix complexity:
   - trivial or local: patch it
   - nontrivial or risky: stop and discuss first

## Repro script style preferences

When writing repro shell for Barrett, prefer the rough local style he asked for:

- lowercase `asan`
- short var names like `t`, `d`, `p`
- `mktemp -d`, not fancy temp path schemes
- inline temp paths instead of many named variables
- no fancy quoted heredoc marker unless needed
- 2-space indentation in shell blocks
- no unnecessary `>/dev/null`
- no line-continuation backslashes unless unavoidable
- use the shortest tmux aliases that actually exist
- `sleep 2` when a small delay is needed
- overall: make it look like a quick local repro, not a polished harness

## Repo-local Nix and autotools rules

For this repo, prefer the repo-local flake and `.envrc`:

- use `direnv exec /home/barrett/dev/tmux bash -lc '<cmd>'` for one-shot
  commands that should run in the tmux dev shell
- do not rely on ad-hoc `nix shell` when the command needs setup hooks,
  `pkg-config`, or aclocal macro wiring

### Worktree bootstrap

When working in a tmux issue worktree, bootstrap it first:

```bash
/home/barrett/dev/tmux/.devin/bin/bootstrap-worktree.sh <worktree-path>
```

This copies the local `flake.nix`, `.envrc`, `flake.lock`, and tmux skill into
the worktree, adds worktree-local ignore rules, and runs `direnv allow`.

After that, prefer:

```bash
direnv exec <worktree-path> bash -lc '<cmd>'
```

### Tooling caveat

- Do not assume a newly created project-local skill will be discoverable by the
  current session immediately.
- If `skill list` does not show `tmux-pr`, keep using the file as durable local
  guidance for the current session and expect it to help on a later session.

### Do not repeat these build failures

- Do not assume `configure` exists in a fresh scratch worktree.
- If `configure` is missing, run `sh autogen.sh` inside the `direnv exec`
  environment.
- After running `autogen.sh`, verify that `configure` does not contain literal
  `PKG_PROG_PKG_CONFIG` or `PKG_CHECK_MODULES`.
- If those macros are still present literally, the autotools environment is
  wrong; stop and fix the environment instead of repeatedly retrying configure.
- In this repo, the shell must provide `ACLOCAL_PATH` entries for the
  `pkg-config` and `pkgconf` aclocal directories before `autogen.sh`.
- If the patch is isolated to one source file and the build system is the
  bottleneck, a scratch relink against an existing configured build is an
  acceptable validation shortcut.

## Build and verification expectations

- Use Nix when that is the real way to get the needed toolchain.
- For leak or uaf issues, prefer an asan build.
- Run the repro before and after the change.
- If the "after" state is absence of a leak log, say that plainly.
- Also verify any adjacent semantic fix caused by the patch.

## Persistent scratch workflow

Use transient task files under `/tmp/tmux/` for issue-specific material:

- draft PR bodies
- raw asan snippets
- repro scripts
- per-issue notes

Suggested layout:

- `/tmp/tmux/pr-<pr-number>/pr-body.md`
- `/tmp/tmux/<bug-id>/repro.sh`
- `/tmp/tmux/<bug-id>/notes.md`

Do not store issue-specific scratch notes in the repo unless the user asks.

## Worktree expectations

If a separate worktree is needed for an issue or PR, create it under `/tmp/tmux/`
and remove it after the PR is shipped if the user wants that cleanup.

## Self-check before sending a draft to the user

Before showing any commit message, PR text, or repro script, verify all of:

- tmux style fits recent `master`
- Barrett voice fits prior tmux PRs and current corrections
- repro is runnable as pasted
- raw proof is present
- unnecessary polish has been removed
- if the user already corrected this once, do not make them correct it again
