# Native Neovim 0.12 Completion Migration Plan

## Status

This document maps out the full migration from the removed `blink.cmp`-based completion stack in `config/nvim` to a largely native Neovim `0.12` completion stack.

This plan is intentionally extensive. It is not just a task list. It is a design document, migration checklist, risk register, and sequencing guide.

The goals that drove this plan are:

1. remove `blink.cmp`
2. remove the Rust fuzzy build and its maintenance cost
3. keep or restore similar parity over time

Current repo state at the time of this revision:

- `config/nvim/lua/plugins/cmp.lua` has been removed
- `config/nvim/lua/config/cmp.lua` has been removed
- no native day-one baseline has been implemented yet
- the config is now in an intentional transition state between the old blink broker and the future native baseline

The plan assumes the following user-approved compromises for phase 1:

- ghost text can disappear
- snippet-specific parity is not important
- path completion can move to native `CTRL-X CTRL-F`
- day one `<C-n>` only needs to cover `LSP + buffer`
- `CTRL-X CTRL-O` should remain the explicit “force LSP completion now” key
- `git`, `lazydev` source integration, and `conventional_commits` are eventual parity items, not day-one blockers

The main long-term constraint that still matters is this:

- parity eventually matters
- `git` is bundled and must eventually come back as one feature family

---

## 1. Why this migration is worth doing

The removed completion setup was not just “a completion menu”. It was a fairly broad source broker with custom UI, custom mappings, multiple extra providers, and a build step for the blink fuzzy binary.

The immediate value of replacing it is:

- less moving machinery
- fewer plugin-specific abstractions
- no Rust binary build or rebuild workflow
- clearer separation between:
  - native completion behavior
  - LSP completion
  - future file-backed adapters

The risk is not “native Neovim cannot complete”. It can. The risk is that source breadth temporarily narrows during the transition.

That is why this plan is phased rather than all-or-nothing.

---

## 2. Current state snapshot

### 2.1 Historical blink entrypoint and present state

The removed blink completion stack was centered on:

- `config/nvim/lua/plugins/cmp.lua`
- `config/nvim/lua/config/cmp.lua`

Those files used to do several jobs at once:

- installing and loading `blink.cmp`
- loading extra blink providers
- compiling the Rust fuzzy shared object
- rebuilding that binary when the package changes
- defining the menu UI
- defining key behavior
- registering source providers

Those files are now gone from the repo config.

The current live state after their removal is:

- blink is no longer configured
- the Rust fuzzy build path is no longer configured
- none of the blink source registrations remain in the config
- the native replacement layer still needs to be added

### 2.2 Historical source set

The removed blink configuration used the following default source order:

- `lazydev`
- `git`
- `conventional_commits`
- `lsp`
- `path`
- `buffer`
- `env`
- `snippets`
- `ssh`
- `tmux`
- `ghostty`

There is also a filetype-specific override:

- `pending` uses `omni + buffer`

### 2.3 Current UI and interaction

The current interaction model is:

- manual menu trigger through insert-mode completion flow
- custom blink mappings for `<C-n>`, `<C-p>`, `<C-y>`
- no blink cmdline completion
- ghost text enabled
- docs popup enabled
- custom kind rendering and column layout

### 2.4 Current maintenance cost

The maintenance cost that motivated this migration is real:

- `blink.cmp` depends on a compiled fuzzy implementation
- the config currently builds it from within the package directory
- package updates trigger rebuild logic

This is exactly the type of ongoing “tooling tax” the migration is meant to eliminate.

---

## 3. Native Neovim 0.12 capability summary

This section is the core technical justification for the migration.

### 3.1 Generic insert completion

Native insert completion is driven by:

- `CTRL-N`
- `CTRL-P`
- `'complete'`
- `'completeopt'`
- `'autocomplete'`

The important part is that generic insert completion is not limited to buffer words. Native Neovim can merge multiple source classes into the same `CTRL-N` pipeline.

Key source flags in `'complete'` that matter for this migration:

- `.` current buffer
- `w` other windows
- `b` loaded buffers
- `F{func}` custom completion functions
- `F` use `'completefunc'`
- `o` use `'omnifunc'`

This means native `<C-n>` can be made to merge:

- buffer text
- LSP
- later custom adapters

### 3.2 LSP completion

Neovim `0.12` can do native LSP completion through:

- `vim.lsp.omnifunc()`
- `vim.lsp.completion.enable(...)`
- popup docs and completion item resolve
- application of completion side effects

The important design fact is:

- LSP completion is not the problem
- source integration beyond LSP is the problem

### 3.3 Path completion

Native path completion already exists and is good enough for phase 1:

- `CTRL-X CTRL-F`

The migration does not need to solve “path in the main menu” on day one because the user explicitly allowed native path completion to remain separate.

### 3.4 Snippets

Neovim now has native snippets:

- `vim.snippet.expand`
- `vim.snippet.active`
- `vim.snippet.jump`

For this migration, snippet parity is not a blocker because:

- the user does not consider snippet behavior central
- special `<C-y>` snippet-forward behavior can disappear

### 3.5 Custom completion adapters

The most important native mechanism for eventual parity is:

- `completefunc`
- `omnifunc`
- `F{func}` inside `'complete'`

These functions can return rich completion items with:

- `word`
- `abbr`
- `menu`
- `info`
- `kind`
- `user_data`
- popup-menu highlight fields

This is what makes a “simple adapter over file-backed or generated data” realistic.

### 3.6 Syntax fallback

Native Neovim also ships:

- `syntaxcomplete#Complete`

This is useful as a low-cost fallback for filetypes that do not yet have a dedicated adapter.

---

## 4. Migration philosophy

The migration should not try to prove full parity before the first blink-free iteration.

The correct philosophy is:

1. remove blink as the core broker
2. keep the day-one user workflow intact enough to be livable
3. restore lost source families in a sequence that matches cost and value

The first version only needs to answer this question:

> Is a native `<C-n>` flow built from `LSP + buffer`, with explicit `CTRL-X CTRL-O` and `CTRL-X CTRL-F`, good enough to justify deleting blink?

If the answer is yes, the migration continues.

If the answer is no, the migration either pauses or narrows.

This is a deliberate “prove the floor first” strategy.

---

## 5. Phase map at a glance

| Phase | Outcome | Main user-visible result | Relative difficulty | Blockers |
| --- | --- | --- | --- | --- |
| Phase 0 | Pre-migration inventory and decision capture | Baseline behavior captured | Low | None |
| Phase 1 | Native baseline implementation | `<C-n>` becomes `LSP + buffer` and replaces the now-removed blink layer | Medium | None |
| Phase 2 | Easy parity adapters | `lazydev` source and `conventional_commits` return | Medium | Native baseline must feel acceptable |
| Phase 3 | Git bundle | `#`, `@`, `:`, `!` git completion returns | High | Cache and trigger design |
| Phase 4 | Config-file extras | `env`, `ssh`, `tmux`, `ghostty` return | Medium | Phase 1 must be stable |
| Phase 5 | Polish | sorting, menu feel, optional fuzzy tuning | Low to Medium | Earlier phases complete |

---

## 6. Phase 0: inventory and baseline capture

Phase 0 is mostly already complete conceptually, but it is still useful to record it as part of the plan.

### 6.1 Goals

- make all migration assumptions explicit
- avoid accidental “implicit parity” expectations
- define day-one success

### 6.2 Decisions already made

The investigation produced these explicit decisions:

#### Core priority ordering

- remove blink
- remove the build and maintenance tax
- maintain parity later

#### Day-one compromises already accepted

- no ghost text
- no blink-specific snippet behavior
- path can move to `CTRL-X CTRL-F`
- native popup can be simpler
- native ranking can be simpler
- no native fuzzy requirement for day one
- `<C-n>` only needs `LSP + buffer`

#### Eventual parity targets that matter

- `git` bundle
- `lazydev` source
- `conventional_commits`
- later `env`, `ssh`, `tmux`, `ghostty`

### 6.3 Day-one acceptance criteria

Phase 1 is acceptable if:

- the Rust build machinery is gone
- a deliberate native baseline exists in place of blink
- `<C-n>` works in normal coding buffers and feels usable
- LSP completion is accessible both through `<C-n>` and `CTRL-X CTRL-O`
- path completion is available through `CTRL-X CTRL-F`
- the native baseline is good enough to live with while phase 2 and phase 3 are built

### 6.4 Explicit non-goals for day one

The following are not required on day one:

- git trigger completions
- module-name completion in `require("...")`
- conventional commit helper completion
- env completion
- ssh/tmux/ghostty completion
- parity in menu drawing
- parity in source ranking

---

## 7. Phase 1: native day-one replacement

This is now the phase that turns the hard blink removal into a usable native baseline.

### 7.1 Phase 1 goals

- replace the removed blink layer with a deliberate native baseline
- keep the Rust fuzzy build path absent
- keep completion usable immediately
- ensure the transition is testing the intended native setup, not raw defaults

### 7.2 Phase 1 user-facing behavior target

The target interaction model for phase 1 is:

- `<C-n>`: generic insert completion using `buffer + LSP`
- `<C-p>`: previous item
- `<C-y>`: accept
- `CTRL-X CTRL-O`: explicit LSP
- `CTRL-X CTRL-F`: explicit path
- `autocomplete` remains off
- popup docs remain available when native LSP supports them

### 7.3 Recommended file layout for the native baseline

The cleanest file layout is:

- add `config/nvim/plugin/completion.lua`
- update `config/nvim/lua/config/lsp.lua`

This division keeps responsibilities clean:

- `plugin/completion.lua` handles editor-native completion options
- `config/lsp.lua` handles LSP behavior during attach

### 7.4 Why not stop at the hard removal and rely on defaults

That would be a bad place to stop.

Stopping after the hard removal would test:

- Neovim defaults

What phase 1 needs to test is:

- a deliberately chosen native baseline

Those are not the same thing.

### 7.5 Phase 1 exact work items

#### Step 1: removed the blink plugin broker

Completed:

- `config/nvim/lua/plugins/cmp.lua`
- `config/nvim/lua/config/cmp.lua`

That removal already eliminates:

- blink installation
- source registration
- custom menu setup
- custom key behavior
- Rust fuzzy build and rebuild logic

#### Step 2: add a dedicated native completion config file

Add:

- `config/nvim/plugin/completion.lua`

Its job should be:

- configure `'complete'`
- configure `'completeopt'`
- configure popup border and height
- keep `autocomplete` off
- avoid custom remapping unless absolutely necessary

Recommended starting shape:

```lua
vim.opt.complete = { '.', 'w', 'b', 'o' }
vim.opt.completeopt = { 'menuone', 'popup' }
vim.o.autocomplete = false
vim.o.pumheight = 15
vim.o.pumborder = 'single'
```

This choice deliberately does not include:

- `u` unloaded buffers
- `t` tags
- fuzzy
- preinsert
- noselect

Those can be revisited later if phase 1 feels too narrow or too noisy.

#### Step 3: enable native LSP completion per attached client

Update:

- `config/nvim/lua/config/lsp.lua`

The native LSP completion hook should be enabled inside `on_attach` when the client supports completion.

Recommended starting shape:

```lua
if client:supports_method(vim.lsp.protocol.Methods.textDocument_completion) then
    vim.lsp.completion.enable(true, client.id, bufnr, {
        autotrigger = false,
    })
end
```

That choice is intentional:

- manual completion remains the default
- `<C-n>` and `CTRL-X CTRL-O` are the core workflows
- phase 1 does not attempt auto-popup behavior

#### Step 4: keep `lazydev.nvim`, drop only the blink source integration

Keep:

- `config/nvim/lua/plugins/lsp.lua`

Do not remove:

- `require('lazydev').setup(...)`

Rationale:

- core `lazydev.nvim` still helps LuaLS workspace behavior
- only the extra completion source is postponed

#### Step 5: do not add replacement mappings unless testing proves they are needed

The default recommendation is:

- keep native `<C-n>`, `<C-p>`, `<C-y>`
- do not add custom popup-aware remaps immediately

Reason:

- phase 1 should be a real test of native completion ergonomics
- extra mapping glue too early can hide whether the baseline is actually acceptable

### 7.6 Phase 1 behavior expectations

What should feel better:

- less invisible machinery
- cleaner mental model
- no build step

What will feel worse:

- fewer total sources under `<C-n>`
- less sophisticated ordering
- less polished popup rendering

### 7.7 Phase 1 verification plan

#### Manual behavior checks

Open a Lua buffer in the config and verify:

1. `<C-n>` shows completion candidates
2. `<C-p>` moves backward
3. `<C-y>` accepts
4. `CTRL-X CTRL-O` produces LSP completions explicitly
5. `CTRL-X CTRL-F` completes paths

Good smoke-test buffers:

- `config/nvim/lua/plugins/fzf.lua`
- `config/nvim/lua/plugins/guard.lua`
- `config/nvim/lua/plugins/dev.lua`

#### Suggested manual exercises

In a Lua file:

- complete after `vim.`
- complete after a local variable backed by an LSP-known module
- complete a word that already exists elsewhere in the current buffer
- use `CTRL-X CTRL-O` explicitly in a place where LSP should answer
- use `CTRL-X CTRL-F` in a string or path-like context

#### Headless sanity check

Use a headless session to confirm:

- the buffer gets `omnifunc = v:lua.vim.lsp.omnifunc`
- the language server is attached
- native completion is enabled in practice

#### Project checks

After code changes, run:

```sh
direnv exec /home/barrett/.config/nix just lint
```

If formatting or linting requires it, also run:

```sh
direnv exec /home/barrett/.config/nix just format
```

### 7.8 Phase 1 acceptance criteria

Phase 1 is successful if:

- blink remains absent from the repo config
- no Rust fuzzy build remains
- the native baseline is usable enough for normal editing
- the user can live with the gap until phase 2 begins

### 7.9 Phase 1 rollback criteria

Rollback to blink if:

- `<C-n>` feels too narrow even for everyday coding
- LSP and buffer interaction under `<C-n>` feels unexpectedly bad
- explicit `CTRL-X CTRL-O` is too awkward in practice
- the user loses too much speed immediately

If rollback is needed, the rollback should be honest:

- restore blink
- record the exact reasons the native floor failed
- use those notes to redefine the baseline before retrying

---

## 8. Phase 2: restore the easiest high-value parity targets

Phase 2 should restore the items that are both:

- important
- simpler than the git bundle

That means:

- `lazydev` source
- `conventional_commits`

There is also room to pull `env` into phase 2 if energy is good, but it is not required.

### 8.1 Phase 2 philosophy

Use simple adapters and keep them small.

The rule for this phase is:

> no large completion framework recreation

Each adapter should:

- have narrow scope
- detect its own relevant context
- return nothing outside that context
- expose only the minimum required data

---

### 8.2 Phase 2A: `lazydev` module-name completion source

#### What matters here

The must-have part of `lazydev` is:

- module-name completion while typing:
  - `require("...")`
  - `---@module "..."`

The core `lazydev.nvim` plugin already stays in place after phase 1. Phase 2 is only about restoring the extra module-name completion source.

#### Recommended mechanism

Add a custom adapter via:

- `F{func}` in `'complete'`

Potential file:

- `config/nvim/lua/config/completion/lazydev.lua`

Potential function name:

- `v:lua.require('config.completion.lazydev').complete`

#### Why `F{func}` is the right fit

This source should participate in generic `<C-n>` completion.

It is:

- global
- context-sensitive
- lightweight

That fits `F{func}` better than filetype-local `omnifunc`.

#### Recommended behavior

Only activate when the cursor is inside:

- `require("...")`
- `require('...')`
- `---@module "..."` or `---@module '...'`

Outside those contexts:

- return an empty result immediately

#### Data source options

There are three realistic implementation choices.

##### Option A: wrap existing `lazydev` internals

Pros:

- likely closest to current behavior
- avoids re-implementing module discovery logic

Cons:

- couples the config to plugin internals
- may break on upstream changes

##### Option B: adapt the existing cmp integration

Pros:

- conceptually closer to what the plugin already supports

Cons:

- may still require translating logic rather than reusing it directly

##### Option C: reimplement the minimum necessary query layer

Pros:

- full ownership
- minimal dependency on internal APIs

Cons:

- more work than wrapping existing logic

#### Recommendation

Start with:

- thin wrapper around the plugin’s current module-discovery logic if feasible

If that proves brittle:

- replace it with a small owned adapter that only handles `require(...)` and `---@module`

#### Output shape

The adapter should return completion items with:

- `word` as the completion text
- `abbr` if helpful
- `menu` indicating the source
- `info` optionally showing plugin/library origin

#### Verification

Test in Lua buffers:

1. `require("fz` should show `fzf-lua`
2. `require("guard` should show `guard.filetype` and similar modules
3. `---@module "fz` should show module-name candidates
4. outside those contexts, the source should stay silent

---

### 8.3 Phase 2B: `conventional_commits`

#### What matters here

User-approved scope:

- target at least `gitcommit`
- maybe `markdown`
- `BREAKING CHANGE` helper is nice, not required

#### Recommended mechanism

Use another small `F{func}` adapter.

Potential file:

- `config/nvim/lua/config/completion/conventional_commits.lua`

#### Why this is a good phase-2 candidate

This source is mostly:

- static
- low-risk
- local to the repo

It does not need:

- network
- repo scanning
- async cache

#### Recommended first implementation

Phase 2 version should only do:

- static commit type suggestions
- filetype gating

Suggested activation:

- `gitcommit`
- optionally `markdown`

Suggested result items:

- `feat`
- `fix`
- `docs`
- `style`
- `refactor`
- `perf`
- `test`
- `build`
- `ci`
- `chore`
- `revert`

Use:

- `menu` or `info` for the explanation text

#### Defer initially

Do not build the `BREAKING CHANGE` header-modification helper in the first pass unless phase 2 feels trivial.

#### Verification

Test in `gitcommit`:

- typing at the start of the header should surface the types
- the source should stay quiet in unrelated buffers

---

### 8.4 Optional Phase 2C: `env`

This source was marked “eventual”, not phase-2 required, but it is worth documenting because it is straightforward.

Recommended shape:

- `F{func}` adapter
- only trigger when the token begins with `$`

Data source:

- `vim.fn.environ()`

Result shape:

- variable name as `word`
- optional `info` showing the value

Because it is so simple, it can be added whenever phase 2 momentum is good.

---

## 9. Phase 3: git bundle

This is the hardest parity phase and should be treated like a self-contained project.

### 9.1 Why git is the hard part

The git source family is hard because it combines:

- trigger-aware context
- repo awareness
- remote awareness
- GitHub vs GitLab behavior
- network or CLI-backed data
- caching
- user-facing docs

This is the only phase where “simple adapter” still means meaningful design work.

### 9.2 User-approved scope

The git bundle is all-or-nothing in eventual importance.

The eventual scope is:

- only in `gitcommit + markdown`
- trigger-gated

Trigger set:

- `#` issue or PR
- `@` mention
- `:` commit
- `!` GitLab MR

There should be:

- no git candidates when those trigger chars are not present

### 9.3 Recommended architecture

Use one shared git adapter, not four unrelated ones.

Potential file:

- `config/nvim/lua/config/completion/git.lua`

Reasons to keep it bundled:

- shared repo detection
- shared remote detection
- shared cache
- shared background refresh

The adapter should:

1. reject immediately outside `gitcommit + markdown`
2. inspect the token before the cursor
3. determine whether the token begins with one of the trigger chars
4. route to the correct candidate family
5. read from cache if possible
6. refresh cache when stale

### 9.4 Context model

A good internal context model should include:

- current buffer filetype
- current working directory or buffer-local repo root
- trigger character
- current query text after the trigger
- remote host type

Example normalized context:

- `filetype = gitcommit`
- `repo = /path/to/repo`
- `trigger = #`
- `query = 12`
- `provider = github`

### 9.5 Provider families

#### `:` commit completion

Likely easiest of the git bundle.

Possible data source:

- `git log`
- `gh api` when needed for `octo`-like cases later

Minimal candidate data:

- short hash
- first line of commit subject

#### `#` issue and PR completion

This needs:

- repo remote detection
- GitHub or GitLab API/CLI support

The design question is whether issues and PRs should be merged into one list under `#` or separated internally but combined for display.

Recommendation:

- internally separate
- externally merged under the same trigger

#### `!` GitLab MR completion

This is GitLab-specific.

It should only activate when:

- provider is GitLab

Otherwise:

- return nothing

#### `@` mention completion

Data source candidate:

- repository contributors
- or repo members if available and acceptable

This is likely the most cache-sensitive family because it may be larger and less obviously bounded.

### 9.6 Cache design

This phase should not query the network on every completion request.

Recommended cache tiers:

#### In-memory session cache

For:

- current Neovim session reuse

Key dimensions:

- repo root
- provider type
- trigger family

#### Optional disk cache

If needed later, store under:

- `$XDG_CACHE_HOME/nvim/completion/`

Reasons not to store in the repo:

- avoid churn
- avoid stale generated data in git
- avoid machine-specific state in version control

### 9.7 Refresh model

Recommended starting refresh strategy:

- lazy fetch on first relevant trigger use
- re-use cache for the rest of the session
- manual refresh command later if necessary

Potential future addition:

- refresh on repo change
- refresh on InsertEnter in `gitcommit`

### 9.8 Candidate fields

The adapter should return rich native completion items, likely using:

- `word`
- `abbr`
- `menu`
- `info`
- `kind`

Examples:

#### Commit candidate

- `word`: short hash or inserted token form
- `abbr`: short hash plus subject
- `menu`: `git`
- `info`: full commit details if desired

#### Issue or PR candidate

- `word`: `#123`
- `abbr`: `#123 Title`
- `menu`: `github` or `gitlab`
- `info`: state, author, timestamps, summary

#### Mention candidate

- `word`: `@username`
- `abbr`: `@username`
- `menu`: provider
- `info`: optional user detail

### 9.9 Verification plan

Phase 3 needs real interactive verification in:

- `gitcommit`
- `markdown`

Trigger-specific checks:

- type `#` and confirm issue/PR candidates
- type `@` and confirm mention candidates
- type `:` and confirm commit candidates
- type `!` in a GitLab repo and confirm MR candidates

Also verify:

- no git noise when none of those triggers are present
- no git noise outside `gitcommit + markdown`
- no major lag on first use after cache warm-up

### 9.10 Phase 3 acceptance criteria

The git bundle is successful if:

- all four trigger families exist
- it only activates in approved filetypes
- it only activates when the trigger char is actually present
- performance is acceptable after warm-up

### 9.11 Biggest risks in phase 3

- provider detection edge cases
- stale cache
- query latency
- too much code growth in one adapter
- accidental recreation of a mini completion framework

The discipline here is:

- keep scope narrow
- avoid broad abstraction until the concrete behaviors work

---

## 10. Phase 4: config-file extras

These are valuable, but they are not what should decide whether blink is removed.

The approved eventual targets here are:

- `env`
- `ssh`
- `tmux`
- `ghostty`

### 10.1 `env`

Recommended mechanism:

- `F{func}` adapter

Trigger:

- `$`

Data:

- environment variables from `vim.fn.environ()`

Complexity:

- low

### 10.2 `ssh`

Recommended mechanism:

- filetype-local `omnifunc`

Reason:

- it is naturally tied to `sshconfig`
- key/value structure matters
- it is not a general global source

Possible implementation strategy:

- parse cached output from `man ssh_config`
- parse enum-like values from `ssh -Q`

This closely matches the spirit of the current blink provider but in native form.

### 10.3 `tmux`

Recommended mechanism:

- filetype-local `omnifunc`

Possible implementation strategy:

- parse `tmux list-commands`
- optionally enrich docs from `man tmux`

This is another good fit for an owned native filetype-specific provider.

### 10.4 `ghostty`

Recommended mechanism:

- filetype-local `omnifunc`

Possible implementation strategy:

- parse `ghostty +show-config --docs`
- enrich enum values from generated or installed completion data

### 10.5 Why these are later, not earlier

Because none of them are necessary to prove the baseline.

They matter as quality-of-life adapters, not as the initial justification for removing blink.

---

## 11. Phase 5: polish and parity tuning

Polish should happen only after the source architecture is settled.

### 11.1 Potential polish items

- revisit `'completeopt'`
- try native `fuzzy`
- experiment with `menuone`, `noselect`, `noinsert`
- add better `menu` and `info` strings to custom adapters
- tune popup height and border feel
- refine source ordering in `'complete'`

### 11.2 Possible future settings to revisit

Candidates for later experimentation:

```lua
vim.opt.completeopt = { 'menuone', 'popup', 'fuzzy' }
```

or:

```lua
vim.opt.completeopt = { 'menuone', 'popup', 'noselect' }
```

These should not be phase-1 defaults because they change completion feel in ways that are hard to separate from the baseline migration itself.

### 11.3 What polish should not become

Phase 5 should not turn into:

- a new mini completion engine
- a large generalized abstraction layer
- parity obsession before the practical editing workflow is stable

---

## 12. Proposed file and module layout across phases

This section is the recommended long-term shape of the config if the migration continues.

### 12.1 Existing files to remove or modify

#### Already removed

- `config/nvim/lua/plugins/cmp.lua`
- `config/nvim/lua/config/cmp.lua`

#### Modify

- `config/nvim/lua/config/lsp.lua`
- `config/nvim/plugin/options.lua` only if necessary
- `config/nvim/lua/plugins/lsp.lua` only if lazydev core setup needs adjustment

### 12.2 New files recommended for the migration

#### Phase 1

- `config/nvim/plugin/completion.lua`

#### Phase 2

- `config/nvim/lua/config/completion/init.lua`
- `config/nvim/lua/config/completion/lazydev.lua`
- `config/nvim/lua/config/completion/conventional_commits.lua`

#### Phase 3

- `config/nvim/lua/config/completion/git.lua`

#### Phase 4

- `config/nvim/lua/config/completion/env.lua`
- `config/nvim/lua/config/completion/ssh.lua`
- `config/nvim/lua/config/completion/tmux.lua`
- `config/nvim/lua/config/completion/ghostty.lua`

#### Optional filetype hooks later

- `config/nvim/after/ftplugin/sshconfig.lua`
- `config/nvim/after/ftplugin/tmux.lua`
- `config/nvim/after/ftplugin/ghostty.lua`

### 12.3 Data location recommendations

For declarative or generated data, prefer this split:

#### Checked-in static data

Use:

- `config/nvim/lua/config/completion/data/`

For:

- small static tables
- conventional commit type metadata
- hand-maintained declarative mappings if needed

#### Generated cache data

Use:

- `$XDG_CACHE_HOME/nvim/completion/`

For:

- repo-specific git cache
- generated CLI/manpage extraction cache
- host-specific machine data

This avoids polluting the repo with generated artifacts.

---

## 13. Verification matrix by phase

### Phase 1

- `<C-n>` in Lua buffers
- `<C-p>` navigation
- `<C-y>` accept
- `CTRL-X CTRL-O` LSP completion
- `CTRL-X CTRL-F` path completion

### Phase 2

#### Lazydev source

- `require("...")` module-name completion
- `---@module "..."` completion
- silence outside those contexts

#### Conventional commits

- suggestions at the start of `gitcommit`
- optional `markdown` support
- no noise in general editing

### Phase 3

- `#` issue/PR completion
- `@` mention completion
- `:` commit completion
- `!` MR completion
- only in `gitcommit + markdown`

### Phase 4

- `$` env completion
- ssh keyword/value completion
- tmux command completion
- ghostty key/value completion

### Phase 5

- quality tuning only after all prior phases are stable

---

## 14. Risks, tradeoffs, and failure modes

### 14.1 Risks that are acceptable

- simpler menu visuals
- simpler ranking initially
- losing some completion breadth temporarily

These are acceptable because they directly support the higher-priority goals:

- remove blink
- remove maintenance burden

### 14.2 Risks that should trigger re-evaluation

- phase 1 is too annoying to live with
- LSP completion under `<C-n>` feels materially worse than expected
- adapter code grows too quickly
- git phase becomes a maintenance sink larger than blink ever was

### 14.3 Main architectural tradeoff

The migration trades:

- one sophisticated plugin broker

for:

- native completion core
- a small number of owned adapters

That is good only if the adapters stay small and purposeful.

If the adapter layer turns into a plugin-sized framework, the migration loses its point.

---

## 15. Recommended execution order

If this plan is executed, the recommended order is:

### Step A

Implement phase 1 fully.

Do not start with git.

Do not start with lazydev source parity.

Do not start with conventional commits.

First prove:

- blink-free native editing is acceptable

### Step B

Live with phase 1 long enough to collect real pain points.

Questions to answer during that period:

- does `<C-n>` feel acceptable without git and lazydev source?
- is `CTRL-X CTRL-F` acceptable for path?
- is the popup shape acceptable?
- is the ranking too weak?

### Step C

Restore:

- `lazydev` source
- `conventional_commits`

These are the highest-value “easy” parity wins.

### Step D

Start the git bundle as a contained project with:

- explicit trigger design
- cache design
- provider design
- filetype restrictions

### Step E

Only after git is good:

- add env
- add ssh
- add tmux
- add ghostty

### Step F

Tune feel and polish only after the source plan is stable.

---

## 16. Decision summary

Given the current state of the repo, the most rational next move is:

- do not linger in the current post-blink transition state
- add the deliberate native baseline next
- keep the baseline small
- postpone parity items in the order already established

In plain terms:

### Day one

- native `<C-n>` for `LSP + buffer`
- native `CTRL-X CTRL-O`
- native `CTRL-X CTRL-F`
- no blink
- no ghost text
- no Rust build

### Soon after

- `lazydev` source
- `conventional_commits`

### Hard project later

- `git`

### After that

- `env`
- `ssh`
- `tmux`
- `ghostty`

That is the plan that best matches the current priorities while still leaving room for eventual parity.
