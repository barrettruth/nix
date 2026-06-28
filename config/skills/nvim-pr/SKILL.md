---
name: nvim-pr
description: Placeholder for Barrett's Neovim pull request workflow. Reports that PR compose is unavailable. Not for committing, pushing, merging, or reviewing.
---

# nvim-pr

The Neovim PR compose workflow is currently unavailable.

## Run

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-pr/scripts/pr-window.py --title "<pr title>" <<'BODY'
<filled template body>
BODY
```

The helper exits non-zero until a new PR workflow replaces the removed compose integration.
