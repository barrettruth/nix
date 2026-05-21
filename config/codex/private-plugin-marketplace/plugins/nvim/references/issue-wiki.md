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
    repro.md
    code-map.md
  logs/
```

Treat `sources/` and `logs/` as immutable raw material. Treat `index.md`,
`report.md`, `sources.md`, `log.md`, and `evidence/*.md` as derived markdown
that agents may update.

Create this pointer inside the worktree:

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

## File Roles

- `index.md`: small future-session entrypoint; target under 120 lines.
- `report.md`: teaching synthesis for Barrett; target 800-1500 words.
- `sources.md`: source manifest with issue URL, `gh` commands, related
  issues/PRs, and raw artifact links.
- `log.md`: append-only activity log.
- `evidence/history.md`: GitHub history role output.
- `evidence/repro.md`: reproducer role output and exact commands.
- `evidence/code-map.md`: optional relevant files/functions map.
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
- [Repro](evidence/repro.md)
- [Code map](evidence/code-map.md)

## Logs
- [name](logs/name.txt): command, exit status, short purpose

## Open Questions
- Evidence-resolvable unknowns only.

## Optional
- Long logs, dead ends, and low-confidence adjacent material.
```

`report.md` is for Barrett. Target 800-1500 words, with small code snippets and
links. It teaches the issue objectively without suggesting fixes.

`sources.md` is the source manifest: every raw GitHub response, command transcript,
and log file gets a relative link plus the command or URL that produced it.

`log.md` is append-only and chronological. Start each entry with
`## [YYYY-MM-DD HH:MM] <event>` so agents can inspect recent activity with grep.

Keep source-vs-synthesis boundaries clear. Raw material belongs in `sources/`
and `logs/`; claims in `report.md` should trace to `index.md`, `sources.md`, or
an evidence file.
