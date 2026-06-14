# Implementation Outcomes

Use for `$nvim-impl`. Barrett must explicitly choose an implementation-capable
outcome in the current prompt; the plan recommendation is context, not
permission.

Global forbids for every outcome: commits, pushes, PR work, GitHub comments,
reviews, replies, reactions, labels, assignment, closing/reopening issues or
PRs, workflow dispatch/reruns, GraphQL mutations, and AI attribution.

Cheap local checks mean status/diff inspection, targeted text searches, and
fast formatting or static checks for touched files when already configured. Do
not run builds, test suites, rbuild verification, or broad CI-equivalent checks;
stop with a `$nvim-verify` handoff instead.

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
- Builds, test suites, rbuild verification, or broad CI-equivalent checks.

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
- Builds, test suites, rbuild verification, or broad CI-equivalent checks.

## `no-change`

Do not implement.

Use when the plan says the issue is already fixed, duplicate, invalid,
expected, stale, outside Neovim, or otherwise should not receive a patch here.

If Barrett explicitly selects `no-change`, stop with the local rationale from
`evidence/plan.md`. Do not edit source, tests, docs, or GitHub state.

## `clarify`

Do not implement. Write a local GitHub-comment draft for Barrett to review and
edit manually.

Draft path:

```text
<wiki>/drafts/clarify.md
```

This is durable issue-wiki state, not `/tmp` and not the Neovim worktree.
Create parent directories as needed. The draft file shape is:

```markdown
# Rationale

Why clarification is needed, with relevant local context links.

# Comment

The proposed GitHub comment text.
```

`# Rationale` may link local wiki files such as `report.md`,
`evidence/repro.md`, `evidence/history.md`, and relevant GitHub URLs.

`# Comment` is prospective GitHub UI text. Use GitHub-flavored Markdown
naturally: `@user` mentions when useful, Markdown links, exact issue/PR/comment
or code permalinks, and short quotes from prior replies when they clarify the
question.

Use read-only `gh`/`gh api --method GET` if needed to refresh current thread
context before drafting. Keep the comment concise, human, and grounded in the
issue wiki/current thread. Ask the smallest question that unblocks the next
decision. Write one comment draft, not multiple variants.

Overwrite the draft path by default; it represents the current draft. After
writing it, update `index.md` with the draft link and append one `log.md` entry.
Then open it for Barrett using the `$nvim-edit` editor handoff. Treat the
handoff as expected to work; if it does not, print the absolute draft path and
stop.

Forbidden:

- Source, test, or doc edits.
- Posting, reacting, labeling, assigning, closing, or otherwise mutating
  GitHub.
- Preparing a posting command.
- Broad issue summaries in the comment section.

## `more-repro`

Do not implement.

Use when the plan says the current evidence is not enough to choose or execute
a fix: blocked repro, too-synthetic repro, missing control, platform/version
uncertainty, or an untested strategy such as TUI/RPC/timing behavior.

If Barrett explicitly selects `more-repro`, stop with the missing reproduction
fact and the recommended next reproduction step from `evidence/plan.md`. Do not
create repro files, run rbuild, edit source/tests/docs, or improvise a new repro
strategy from `$nvim-impl`; route back to `$nvim-repro` or future repro-strategy
work.

## Plan Statuses

These are hard guards, not implementation outcomes.

- `Status: blocked`: stop. Quote the exact `Status:` line from
  `evidence/plan.md`. Report the blocker and next concrete step from
  `evidence/plan.md`, with relevant local paths or GitHub links. Give a short
  explanation of why implementation cannot proceed. Do not edit
  source/tests/docs, run repro, run verification, or draft GitHub text unless
  Barrett gives a new explicit instruction.
- `Status: resolved upstream`: terminal stop for this issue workflow. Quote the
  exact `Status:` line from `evidence/plan.md`. Report the upstream resolution
  with the issue URL, merged PR permalink, relevant merge/commit links when
  available, and a one-paragraph explanation of why the issue workflow is done.
  Do not port, cherry-pick, edit, verify, or suggest follow-up implementation.
