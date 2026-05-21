# Neovim Workflow Framework

Scope: only `neovim/neovim` in `/home/barrett/dev/neovim`.

Primary skill:

- `$nvim-issue 12345`: investigate the GitHub issue and stop at a report.

Lower-level skills:

- `$nvim-wt`: worktree and current-checkout state
- `$nvim-code`: implementation after Barrett explicitly asks
- `$nvim-verify`: implementation-phase build/test verification
- `$nvim-pr`: placeholder until commit and PR policy is researched
- `$nvim-clean 12345`: manual cleanup for one issue-number worktree

Plugin command files may also expose `/nvim:*` slash commands when the command
surface is available, but the skill invocation contract is the reliable one.

Commit, push, and PR are separate phases. The active issue/code/verify phases do
not commit or mutate remotes. Commit requires Barrett to literally say
`commit`, and commits are main-thread only.

`.worktrees/.codex/current` is the global active-worktree pointer.
`.codex/issue-wiki` is the per-worktree issue-wiki pointer.

Issue flow:

1. Fetch issue with `gh`.
2. Fetch `upstream master`.
3. Create branch/worktree `12345` from `upstream/master`.
4. Create issue wiki in `/home/barrett/.local/state/codex-nvim/issues/12345`.
5. Add ignored pointer `.codex/issue-wiki` in the worktree.
6. Run `history` and `reproducer` in parallel. `history` stays on GitHub/code
   history context; `reproducer` may inspect internals and must use Spark for
   expensive builds/tests.
7. Run `integrator` after both role outputs exist.
8. Print absolute report/index/worktree paths.

No solutions are allowed in this phase. Next investigation experiments are ok.
For resumes, read only `index.md` first and follow its links selectively.

Cleanup is manual only. `$nvim-clean <issue-number>` must inspect local state,
prompt `y/N`, and never use GitHub status or auto-detection.

Spark cleanup is separate: use `spark nvim clean <issue-number>` only when
Barrett asks to remove the Spark mirror.
