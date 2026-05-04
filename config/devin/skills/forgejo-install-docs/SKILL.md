---
name: forgejo-install-docs
description: Update install/source documentation for Forgejo-canonical repos without mixing in GitHub mirror UX, runtime deprecations, or unrelated package-manager changes.
user-invocable: true
version: 1.1.0
---

# /forgejo-install-docs

Use this skill when updating README, vimdoc, rockspec, package metadata, or
other install/source references so a repo points at
`https://git.barrettruth.com/barrettruth/<repo>`.

This is a docs/metadata skill, not a GitHub mirror setup skill.

## Hard Rules

- **Do not add `.github/*` files** in an install-doc PR. GitHub mirror README
  banners, issue redirects, and PR auto-close workflows are separate work.
- **Do not add runtime warnings or deprecation code** in a Forgejo install-doc
  PR. If a GitHub-only warning is wanted, do it as a separate GitHub/mirror
  change after the exact delivery path is agreed.
- **Do not add migration help tags** to the Forgejo-facing vimdoc unless the
  user explicitly asks for migration docs in that PR.
- **Do not write self-referential copy** like "the canonical source is
  Forgejo" in a Forgejo README. People reading the Forgejo README are already
  there.
- **Do not replace the documented package manager unless the user asked for
  that.** If the current docs show lazy.nvim and the task is only "use my
  Forgejo source", keep lazy.nvim and change the source field.
- **If the user asks for `vim.pack`, include the Neovim version requirement in
  the heading/text**, e.g. `With vim.pack (Neovim 0.12+)`.
- **Do not annotate incidental local variables** when adding Lua. LuaCats
  annotations belong on public APIs, meaningful tables/classes, and non-obvious
  function contracts, not every temporary.
- **Keep the PR diff narrow.** A normal install-doc PR should touch only files
  that actually carry install/source metadata: README, vimdoc, rockspec,
  package metadata, or equivalent.
- **Do not trust a local clone until its remote is verified.** A stale local
  clone can still have `origin = github`. If auditing current Forgejo docs, first
  confirm `origin` is `git.barrettruth.com` and fetch `origin/main`, or query
  Forgejo directly with `tea api`.

## Scope And Source Of Truth

This skill is for repos that are already approved for Forgejo-canonical install
docs. Do not use it as a mechanical sweep over the deferred/popular plugin set
unless the user explicitly names those repos. When a repo is deferred, GitHub
short forms in its public install docs may be intentional until the policy
decision is made.

Before editing:

1. Verify the repo being inspected is the Forgejo repo:
   `git remote get-url origin` should point at
   `git.barrettruth.com/barrettruth/<repo>.git`.
2. Fetch before scanning: `git fetch origin main`.
3. Scan `origin/main`, not an unpulled local branch, when deciding what remains:
   `git grep -n -E 'github\\.com/barrettruth|barrettruth/[A-Za-z0-9._-]+' origin/main -- README.md 'doc/*' '*.rockspec' package.json Cargo.toml flake.nix 2>/dev/null`.
4. Review matches manually. Issue-template examples, upstream tracker docs, and
   deferred repos are not automatically install-doc bugs.

## Package Manager Patterns

Use the package manager the user requested. If none was requested, preserve the
existing documented manager and only rewrite the source URL.

### vim.pack

Use this wording in Markdown:

````md
With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({
  'https://git.barrettruth.com/barrettruth/<repo>',
})
```
````

Use this wording in vimdoc:

```txt
With vim.pack (Neovim 0.12+): >lua
    vim.pack.add({
      'https://git.barrettruth.com/barrettruth/<repo>',
    })
<
```

### lazy.nvim

If the existing docs use lazy.nvim and the user did not ask to switch package
managers, keep lazy.nvim and use `url`, not the GitHub shorthand:

```lua
{
  url = 'https://git.barrettruth.com/barrettruth/<repo>',
}
```

### luarocks

Keep Luarocks install commands as package-registry commands:

```sh
luarocks install <rock-name>
```

Update rockspec metadata separately:

```lua
source = {
  url = 'git+https://git.barrettruth.com/barrettruth/<repo>.git',
}

description = {
  homepage = 'https://git.barrettruth.com/barrettruth/<repo>',
}
```

## Vimdoc And Static Site Links

For vimdoc install sections:

- Keep the documented package manager unless the user asked for a replacement.
- Use full Forgejo URLs in install snippets.
- Do not add "migration" help tags or self-referential "canonical Forgejo"
  language to Forgejo-facing vimdoc.
- Run the repo's vimdoc checker when `doc/*.txt` changes.

For generated static sites, do not assume extensionless paths work. The
vimdoc-language-server site is deployed as static files and needed direct
`.html` links for internal docs pages:

```html
<a href="/installation.html">Installation</a>
<a href="/diagnostics.html">Diagnostics</a>
```

Use direct generated filenames when the deployed server does not rewrite
extensionless routes.

## Pre-PR Checklist

Run these checks before pushing:

1. Show the exact install snippets from README and vimdoc.
2. Verify remotes and fetched refs if using a local clone:
   `git remote -v && git fetch origin main`.
3. `rg -n 'cp.nvim-migration|Migration|migration|GitHub shorthand|canonical source|Forgejo source|\\.github' README.md doc/ <metadata files> 2>/dev/null || true`
4. `git diff --name-status origin/main...HEAD`
5. `git ls-tree -r --name-only HEAD | rg '^\\.github/' || true`
6. Repo format/lint/test commands as appropriate.
7. vimdoc checker if `doc/*.txt` changed.
8. rockspec lint if a rockspec changed.

The grep checks are not universal truth; review matches manually. The point is
to catch self-referential migration language, accidental GitHub mirror files,
and package-manager churn before the PR is created.

## PR Body

The PR body should describe only what the PR actually does. For a narrow
install-doc PR, a good summary is:

```md
## Summary
- update README and vimdoc install snippets to use <package manager> with the Forgejo URL
- update rockspec source/homepage metadata to Forgejo

## Verification
- <format/lint/test commands actually run>
- `git diff --name-status origin/main...HEAD` shows only <expected files>
```

Do not mention `.github`, PR redirects, migration warnings, or runtime
deprecation behavior unless those are actually in the diff and were explicitly
requested for the same PR.
