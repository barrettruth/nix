# Neovim Workflow Framework

Scope: only `neovim/neovim` in `/home/barrett/dev/neovim`.

Primary skill:

- `$nvim-issue 12345`: investigate the GitHub issue and stop at a report.

Target stages:

1. `issue`: create the worktree/wiki, explore history, reproduce, report.
2. `explain`: explain current artifacts at any stage; no mutation.
3. `design`: debate implementation options and choose a direction; no edits.
4. `code`: implement only after Barrett asks or chooses a direction.
5. `verify`: run focused local/Spark checks and record evidence.
6. `review`: summarize diff, evidence, risks, and unresolved questions before
   commit.
7. `commit`: prepare or make a commit only after explicit permission; prefer a
   visible Fugitive buffer in the mux `git` window.
8. `pr`: later workflow through `forge.nvim`; remote-visible actions remain
   separately gated.

Lower-level skills:

- `$nvim-wt`: worktree and current-checkout state
- `$nvim-code`: implementation after Barrett explicitly asks
- `$nvim-verify`: implementation-phase build/test verification
- `$nvim-pr`: placeholder until commit and PR policy is researched
- `$nvim-clean 12345`: manual full cleanup for one issue-number checkout

Plugin command files may also expose `/nvim:*` slash commands when the command
surface is available, but the skill invocation contract is the reliable one.

Stage boundaries matter. Issue, explain, design, code, verify, and review do
not commit or mutate remotes. Commit requires Barrett to literally say
`commit`, and commits are main-thread only. PR/review-response work is separate
from commit.

`.worktrees/.codex/current` is the global active-worktree pointer.
`.codex/issue-wiki` is the per-worktree issue-wiki pointer.

Issue flow:

1. Run `scripts/issue-setup.py 12345`.
2. Read the printed `index`, `report`, and worktree paths.
3. Run isolated `history` and `reproducer` roles in parallel. Do not fork full
   conversation context. `history` gets GitHub/history context; `reproducer`
   gets raw issue sources, the worktree, `spark.md`, and `repro.md` only.
   History is direct-first and curated; no exhaustive search archive.
4. Run `integrator` as a third isolated role after both role outputs exist.
5. Print absolute report/index/worktree paths.

No solutions are allowed in this phase. Next investigation experiments are ok.
For resumes, read only `index.md` first and follow its links selectively.

Cleanup is manual only. `$nvim-clean <issue-number>` prompts `y/N` and removes
the local worktree, local branch, issue wiki, local Spark logs, Spark mirror,
and current pointer for that issue. It never uses GitHub status,
auto-detection, batches, or pruning.
