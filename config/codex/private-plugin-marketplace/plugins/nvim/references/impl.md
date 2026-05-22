# Implementation Outcomes

Use for `$nvim-impl`. Barrett must explicitly choose an implementation-capable
outcome in the current prompt; the plan recommendation is context, not
permission.

## `fix`

Implement the selected source-level change and only the tests/docs necessary to
support it.

Allowed:

- Edit Neovim source files.
- Add or update focused tests.
- Make minimal docs updates when behavior, API, or user-facing semantics change.
- Inspect nearby precedent and current architecture.
- Run cheap local checks.

Stop instead of switching outcomes if source inspection shows the selected fix
is wrong, materially incomplete, or actually belongs to another outcome.

Forbidden:

- Broad adjacent cleanup.
- Implementing multiple fix outcomes.
- Expensive local builds/tests; hand those to `$nvim-verify`.
- Commits, pushes, PRs, GitHub comments, or AI attribution.

## `test-or-docs`

Edit only tests, documentation, examples, or fixtures needed for the selected
outcome. Do not change runtime/source behavior.

Allowed:

- Add or update focused tests.
- Update docs/help text/examples.
- Adjust fixtures that exist only to support the selected test/doc outcome.
- Run cheap local checks.

Stop and ask Barrett to reclassify as `fix` if a runtime/source change is
needed.

Forbidden:

- Source/runtime behavior changes.
- Tiny source tweaks to make a test pass.
- Broad test/doc rewrites.
- Expensive local builds/tests; hand those to `$nvim-verify`.
- Commits, pushes, PRs, GitHub comments, or AI attribution.
