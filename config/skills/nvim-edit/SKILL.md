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

- Work inside the current mux project — the helper targets the project's Neovim
  server (`$NVIM`), resolving the root from the cwd's git toplevel.
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

## Rules

- Navigation only: do not edit, run tests, commit, push, open PRs, mutate
  remotes, or kill/restart a running Neovim.
- If no file matches, say so — don't open an unrelated fallback.
- `--dry-run` only to preview resolution or report ambiguity instead of opening.

## Helper

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py --dry-run <path> [<path> ...]
python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py <path> [<path> ...]
python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py <path> --line <n> [--column <n>]
file=$(git ls-files | shuf -n 1) && python3 /home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit.py "$file"
```
