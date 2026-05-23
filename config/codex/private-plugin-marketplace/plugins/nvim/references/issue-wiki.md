# Issue Wiki Contract

Create one cross-session wiki per issue:

```text
/home/barrett/.local/state/codex-nvim/issues/12345/
  index.md
  report.md
  sources.md
  log.md
  sources/
    github/
    commands/
  evidence/
    history.md
    repro.md         # created by $nvim-repro only
    verify.md        # created by $nvim-verify only
    code-map.md      # optional, only when populated
  logs/
```

Treat `sources/` and `logs/` as immutable raw material. Treat `index.md`,
`report.md`, `sources.md`, `log.md`, and `evidence/*.md` as derived markdown
that agents may update.

Create this plain text pointer file inside the worktree:

```text
.codex/issue-wiki
```

with:

```text
issue=12345
wiki=/home/barrett/.local/state/codex-nvim/issues/12345
report=/home/barrett/.local/state/codex-nvim/issues/12345/report.md
index=/home/barrett/.local/state/codex-nvim/issues/12345/index.md
```

Before writing the pointer, ensure `.codex/` is ignored. If it is not ignored,
append `.codex/` to the local exclude file from:

```sh
git rev-parse --git-path info/exclude
```

Agents should read `.codex/issue-wiki` as a key/value pointer file and follow
its `wiki=` path. It is not a directory. If the direct
`/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` path exists for
an issue number, use it directly instead of scanning every worktree.

## File Roles

- `index.md`: small future-session entrypoint; target under 80 lines.
- `report.md`: teaching synthesis for Barrett; target 500-1000 words.
- `sources.md`: source manifest for raw artifacts that support report claims.
- `log.md`: append-only activity log.
- `evidence/history.md`: GitHub history role output.
- `evidence/repro.md`: created by `$nvim-repro`; see `repro.md`.
- `evidence/verify.md`: created by `$nvim-verify`; focused check evidence
  after implementation.
- `evidence/code-map.md`: optional relevant files/functions map; create and
  link only when populated.
- `logs/`: bulky output only; link from evidence files.
- `sources/github/`: raw `gh`/`gh api` responses.
- `sources/commands/`: raw command transcripts worth preserving.

`index.md` is for future AI sessions. Keep it neutral and small: issue link,
worktree path, reproduction status, key files, linked evidence, logs worth
reading, open questions, and the next file to open. Future agents should read
`index.md` first, then only the linked files needed for the task.

Suggested `index.md` shape:

```markdown
# Neovim issue 12345

> Neutral one-sentence symptom and current repro status.

Issue: https://github.com/neovim/neovim/issues/12345
Worktree: /home/barrett/dev/neovim/.worktrees/12345
Phase: investigation/report only
Last updated: YYYY-MM-DD

## Start Here
- [Report](report.md)
- [Sources](sources.md)

## Evidence
- [History](evidence/history.md)

Reproduction: not attempted.

## Logs
- [name](logs/name.txt): command, exit status, short purpose

## Open Questions
- Evidence-resolvable unknowns only.

## Optional
- [Code map](evidence/code-map.md), only if populated.
- Long logs, dead ends, and low-confidence adjacent material.
```

`report.md` is for Barrett. Target 500-1000 words, with links over large
excerpts. It teaches the issue objectively without suggesting fixes.

`sources.md` is the source manifest: raw GitHub responses, command transcripts,
and log files that support claims get a relative link plus the command or URL
that produced them.

`log.md` is append-only and chronological. Start each entry with
`## [YYYY-MM-DD HH:MM] <event>` so agents can inspect recent activity with grep.

Keep source-vs-synthesis boundaries clear. Raw material belongs in `sources/`
and `logs/`; claims in `report.md` should trace to `index.md`, `sources.md`, or
an evidence file.
