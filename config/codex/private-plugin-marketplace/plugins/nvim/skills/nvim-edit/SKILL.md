---
name: nvim-edit
description: Use when Barrett asks Codex to populate the current mux edit Neovim window from a natural-language file target. Navigation only; do not edit files.
---

# nvim-edit

This skill is for editor navigation, not implementation.

Expected behavior:

- Resolve targets inside the current tmux/mux project. The helper reads the
  current session's `@mux-project-path` and falls back to the current working
  directory when outside tmux.
- Prefer explicit paths when the user gives them.
- For natural-language targets, choose likely repo files from file names, path
  tokens, content hits, and working-tree state.
- Populate the mux `edit` window.
- If `edit` already runs Neovim, remote into that instance and replace its
  arglist/quickfix list with the resolved files.
- If `edit` is an idle shell, start Neovim there.
- If no `edit` window exists, create or adopt one using the current mux session.

Rules:

- Do not edit files, run tests, commit, push, open PRs, or mutate remotes.
- Do not kill or restart an existing Neovim instance implicitly.
- Do not send raw keys into a busy non-Neovim `edit` window. Report the blocker.
- Call the helper directly with Barrett's target text. Do not pre-resolve
  targets with `find`, `shuf`, `rg`, or ad hoc shell unless the helper reports a
  blocker.
- For `/tmp`, absolute paths, directories, or random-file requests, let the
  helper resolve the target; do not reinterpret the request manually.
- Use `--dry-run` only when Barrett explicitly asks to preview resolution or
  when you are intentionally reporting ambiguity instead of opening the editor.

Helper:

```sh
python3 /home/barrett/.config/nix/config/codex/private-plugin-marketplace/plugins/nvim/scripts/edit-window.py --dry-run <query>
python3 /home/barrett/.config/nix/config/codex/private-plugin-marketplace/plugins/nvim/scripts/edit-window.py <query>
```
