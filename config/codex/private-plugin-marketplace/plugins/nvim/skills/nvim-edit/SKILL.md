---
name: nvim-edit
description: Use when Barrett asks Codex to populate the current mux edit Neovim window from a natural-language file target. Navigation only; do not edit files.
---

# nvim-edit

This skill is for editor navigation, not implementation.

Communication:

- Keep user-facing updates minimal. Do not explain that this skill was selected,
  narrate resolver steps, or announce that the helper script is being run.
- Before opening, say only which file(s) are being opened and why, in one or two
  sentences.
- After the helper exits successfully, stop. Do not announce verification,
  inspect tmux state, capture the pane, retry, or reopen the window unless
  Barrett explicitly reports that it failed or asks for verification.
- Do not report intermediate failed candidate searches. If a first resolver is
  too broad or wrong, discard it silently and report only the final path(s).

Expected behavior:

- Resolve targets inside the current tmux/mux project. The helper reads the
  current session's `@mux-project-path` and falls back to the current working
  directory when outside tmux.
- Prefer explicit paths when the user gives them.
- Treat everything after `$nvim-edit` as a natural-language command for Codex to
  interpret before invoking the helper.
- For natural-language targets, use normal repo investigation to decide the
  concrete file path(s): `rg --files`, `rg` content searches, Git status, path
  tokens, file names, and surrounding project context.
- Apply filters before sampling. For example, "a random file containing
  \"hari\"" means search for files containing the literal string first, then
  choose one matching file at random.
- Singular requests such as "a random file" should populate one file unless
  Barrett explicitly asks for multiple files.
- Prefer one shell invocation that both resolves and opens the file when the
  request is simple. For a random file in a Git checkout, use `git ls-files`
  directly; do not run `rg --files` first and then correct it after seeing
  `.git` internals.
- Populate the mux `edit` window.
- If `edit` already runs Neovim, remote into that instance and replace its
  arglist/quickfix list with the resolved files.
- If `edit` is an idle shell, start Neovim there.
- If no `edit` window exists, create or adopt one using the current mux session.

Rules:

- Do not edit files, run tests, commit, push, open PRs, or mutate remotes.
- Do not kill or restart an existing Neovim instance implicitly.
- Do not send raw keys into a busy non-Neovim `edit` window. Report the blocker.
- Treat a zero exit from `edit-window.py` as success. Do not perform post-open
  tmux/window/process checks in normal navigation requests; those checks are
  only for nonzero helper exits, explicit dry-run/verification requests, or
  when Barrett says the visible editor state is wrong.
- Do not pass unresolved natural-language text to the helper. Resolve the
  target first, then call the helper with concrete path(s).
- Do not split trivial resolution into multiple visible tool calls. Compose the
  resolver and helper in one command when doing so is clear and safe.
- If no file matches the interpreted request, report that directly instead of
  opening an unrelated fallback file.
- Do not add explanatory quickfix item text to Neovim. The helper may use the
  quickfix list to navigate multiple files, but item messages should remain
  blank.
- Use `--dry-run` only when Barrett explicitly asks to preview resolution or
  when you are intentionally reporting ambiguity instead of opening the editor.

Helper:

```sh
python3 /home/barrett/.config/nix/config/codex/private-plugin-marketplace/plugins/nvim/scripts/edit-window.py --dry-run <path> [<path> ...]
python3 /home/barrett/.config/nix/config/codex/private-plugin-marketplace/plugins/nvim/scripts/edit-window.py <path> [<path> ...]
file=$(git ls-files | shuf -n 1) && python3 /home/barrett/.config/nix/config/codex/private-plugin-marketplace/plugins/nvim/scripts/edit-window.py "$file"
```
