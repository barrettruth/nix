---
name: nvim-edit
description: Use when Barrett asks to open, show, or pull up file(s) in his editor — e.g. "open in my editor", "open in nvim/neovim", "pull this up", or "populate the mux edit window" — resolving a natural-language file target. Editor navigation only; do not edit file contents.
---

# nvim-edit

Resolve a natural-language file target and open it in the project's `edit` view.
This is editor navigation, not implementation. The helper does the nvim work
(opening the files in the project's Neovim server via `$NVIM`); your job is to
resolve the target to concrete path(s) and pass them.

## Resolve

- Resolve the target mux project first. By default the helper targets the cwd's
  git/jj root and opens files in that project's `edit` view.
- If Barrett names or clearly implies a different checkout, repo, PR, branch, or
  worktree, pass that repo root with `--root <repo-root>` instead of relying on
  the shell cwd.
- If opening a generated or temporary file related to another repo, keep the temp
  file path as the file argument and pass `--root <repo-root>` for the related
  repo's mux session.
- Interpret the request, then call the helper with concrete path(s). Prefer
  explicit paths the user gives; for natural-language targets find them with
  `git ls-files`, `rg` (names/content), and git status — for a random file use
  `git ls-files` directly.
- Filter before sampling: "a random file containing X" means find files
  containing X, then pick one.
- Singular phrasing ("a random file") populates one file unless Barrett asks for
  more.
- For one resolved file, extract an explicit position from natural language or
  pasted locations and pass it as 1-based `--line <n>` plus optional
  `--column <n>` after the path. Examples: `foo.lua:42`, `foo.lua:42:7`,
  "line 42 column 7". Omit position flags for multiple files.
- Compose the resolver and helper in one shell invocation when the request is
  simple.

## Communication

- Minimal: before opening, name the file(s) and why in a sentence or two; say
  nothing about resolver steps or the helper.
- A zero exit is success — stop. Re-open or inspect the editor only if Barrett
  says the editor state is wrong.
- On failure, report the helper's stderr exactly enough to identify the mux root
  or server problem; do not guess or retry with direct `nvim --server` commands.

## Rules

- Navigation only: do not edit, run tests, commit, push, open PRs, mutate
  remotes, or kill/restart a running Neovim.
- Always use the helper for opening; do not bypass it with direct
  `nvim --server ... --remote` calls.
- If no file matches, say so — don't open an unrelated fallback.
- `--dry-run` only to preview resolution or report ambiguity instead of opening.

## Helper

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py --dry-run <path> [<path> ...]
python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py <path> [<path> ...]
python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py --root <repo-root> <path> [<path> ...]
python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py <path> --line <n> [--column <n>]
file=$(git ls-files | shuf -n 1) && python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py "$file"
```
