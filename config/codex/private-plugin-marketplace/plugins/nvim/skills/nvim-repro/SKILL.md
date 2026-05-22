---
name: nvim-repro
description: Reproduce a Neovim issue after `$nvim-issue` has created the worktree and issue wiki, or mark reproduction not applicable for non-bug issues. Use when Barrett explicitly asks for bounded reproduction evidence; do not read Codex memory.
---

# nvim-repro

Use `$nvim-repro <issue>` after `$nvim-issue <issue>`.

Input: one explicit Neovim issue number, with or without `#`.

Output: tiny status summary plus absolute paths to `evidence/repro.md`,
`index.md`, and the worktree. No fixes or commit advice.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Normalize the issue number.
   Do not read Codex memory for this skill.
2. Run `../../scripts/repro-preflight.py <issue>`. If it fails, stop. Use its
   printed paths; do not rediscover them manually.
3. If the issue is not a bug claim, write `Status: not applicable` in
   `evidence/repro.md` and skip Spark. Otherwise select one allowed strategy.
   Current allowlist: `script`.
4. Spawn one isolated reproducer subagent for that strategy. Do not fork full
   conversation context. Keep the prompt short: issue number, paths, references
   to read, owned write paths, and hard prohibitions only. Do not paste the
   full contract into the prompt.
5. After the subagent writes `evidence/repro.md`, update only `index.md` and
   append one short `log.md` entry.
6. Print status plus absolute `Repro`, `Index`, and `Worktree` paths.

Follow `../../references/repro.md` for role isolation, owned paths, stopping
rules, and coordinator updates. Read `../../references/spark.md` and
`../../references/guardrails.md` only as needed.
