# Neovim Workflow Framework

Scope: only `neovim/neovim` in `/home/barrett/dev/neovim`.

Primary skills:

- `$nvim-issue 12345`: create worktree/wiki, gather history, and stop at a
  no-reproduction report.
- `$nvim-repro 12345`: run one bounded reproduction strategy with Spark.
- `$nvim-plan 12345`: choose among realistic evidence-backed outcomes; no edits.
- `$nvim-impl 12345`: implement only a chosen outcome.
- `$nvim-verify 12345`: verify focused implementation checks.
- `$nvim-review 12345`: inspect local implementation patch state and prepare
  mux review UI.

Target stages:

1. `issue`: create the worktree/wiki, explore history, report.
2. `repro`: run one bounded Spark reproduction strategy.
3. `explain`: explain current artifacts at any stage; no mutation.
4. `plan`: compare realistic outcomes and choose a direction; no edits.
5. `impl`: implement only after Barrett chooses an outcome.
6. `verify`: run focused local/Spark checks and record evidence.
7. `review`: summarize diff, evidence, risks, and unresolved questions before
   commit.
8. `commit`: prepare or make a commit only after explicit permission; prefer a
   visible Fugitive buffer in the mux `git` window.
9. `pr`: later workflow through `forge.nvim`; remote-visible actions remain
   separately gated.

Lower-level skills:

- `$nvim-wt`: worktree and current-checkout state
- `$nvim-repro`: bounded reproduction after `$nvim-issue`
- `$nvim-plan`: decision stage after evidence
- `$nvim-impl`: implementation after Barrett explicitly chooses an outcome
- `$nvim-verify`: implementation-phase build/test verification
- `$nvim-review`: human inspection checkpoint before commit workflow
- `$nvim-pr`: placeholder until commit and PR policy is researched
- `$nvim-clean 12345`: manual full cleanup for one issue-number checkout

Plugin command files may also expose `/nvim:*` slash commands when the command
surface is available, but the skill invocation contract is the reliable one.

Stage boundaries matter. Issue, repro, explain, plan, impl, verify, and review
do not commit or mutate remotes. Review prepares human inspection UI only.
Commit requires Barrett to literally say `commit`, and commits are main-thread
only. PR response work is separate from commit.

`.worktrees/.codex/current` is the global active-worktree pointer.
`.codex/issue-wiki` is a per-worktree plain text pointer file; follow its
`wiki=` path to the issue wiki.

Issue flow is owned by `skills/nvim-issue/SKILL.md`; this file only records
stage boundaries. For resumes, read only `index.md` first and follow its links
selectively.

Cleanup is manual only. `$nvim-clean <issue-number>` prompts `y/N` and removes
the local worktree, local branch, issue wiki, local Spark logs, Spark mirror,
and current pointer for that issue. It never uses GitHub status,
auto-detection, batches, or pruning.
