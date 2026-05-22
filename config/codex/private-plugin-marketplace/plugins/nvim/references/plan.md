# Planning Outcomes

Use for `$nvim-plan`. Write `evidence/plan.md`, compare the realistic
outcomes, recommend one, and stop.

Read `index.md` first. If older report prose conflicts with later stage
evidence, prefer `index.md`, `evidence/repro.md`, `evidence/history.md`, and
`log.md` timestamps for current status.

If an issue number is provided, resolve the worktree directly at
`/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki`; do not scan all
worktrees unless that path is missing.

Outcome types:

- `fix`: implement one concrete source change.
- `no-change`: close, mark invalid, duplicate, already fixed, or expected.
- `clarify`: do not implement; ask Barrett to seek missing GitHub facts.
- `more-repro`: stop because current evidence is not good enough to choose.
- `test-or-docs`: add coverage or docs without changing behavior.

If there are multiple source-change directions, list them as separate `fix`
outcomes with descriptive titles. Do not create a separate alternate source
type; from `$nvim-impl`'s point of view, each selected source-code direction is
a `fix`.

Produce 2-4 outcomes by default. Use one outcome only when alternatives would
be artificial; use more than four only when the issue genuinely has separate
viable paths.

If planning is premature, write `Status: blocked` in `evidence/plan.md` and
stop without outcomes. Name the blocker and the next concrete step, such as
rerunning `$nvim-repro`, gathering missing GitHub context, or asking Barrett for
a user decision.

If a read-only freshness check finds the issue is already closed by a merged PR,
write a short `Status: resolved upstream` plan and stop. Include the merged PR,
the local repro status, and at most one optional local-carry outcome. Do not
promote superseded historical alternatives into full outcomes.

Each outcome should state evidence, tradeoff, and next verification step in
2-4 bullets. Do not edit source, commit, push, open PRs, or post comments.

Include a `Recommendation` section. It may recommend one outcome or say
`no clear winner`, but it must give a short rationale. If there is no clear
winner, name the missing evidence or user decision that blocks selection.

If real user-choice knobs exist, add a short `User decisions` section. Include
only decisions that affect behavior, API, compatibility, UX, maintainer
acceptability, or verification scope. There is no quota: many issues have none;
some feature work may have several.

For complex plans, the coordinator may spawn narrow subagents for competing
directions, precedent, or risk checks. Use none for obvious cases. The
coordinator owns `evidence/plan.md`; subagents return concise evidence and do
not write wiki files.

Allowed during planning: targeted source reads, `rg`, `git show/log/blame`,
small read-only scripts, and cheap probes that do not modify the worktree.
Do not run builds, test suites, Spark verification, or implementation-phase
checks; defer those to `$nvim-impl`/`$nvim-verify`.

Describe implementation directions at a high level. Link or name relevant
files/functions/line anchors when useful, but do not include code snippets,
pseudo-patches, or patch-shaped instructions.

Coordinator updates after `evidence/plan.md` exists:

- `index.md`: planning status and link to `evidence/plan.md`.
- `log.md`: one short append-only entry.

Do not update `report.md`, `sources.md`, `evidence/history.md`, or
`evidence/repro.md` during `$nvim-plan`.
