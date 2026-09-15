# Global Agent Rules

- Always load and apply the `asd-ste100` skill before you write English prose.
  This rule applies to every reply, commentary update, status message, plan,
  and prose artifact. Use Strict mode for procedures, instructions, error
  messages, tool descriptions, and safety text. Use STE-flavored mode for all
  other prose. If the runtime permits only one active skill, read
  `~/.agents/skills/asd-ste100/SKILL.md` directly and keep its rules active
  while another task skill runs. Preserve code, commands, identifiers, paths,
  quoted text, and user-requested verbatim content.
- The user publishes by default. Draft freely — commit messages, PR titles and
  bodies, issue text, review comments, release notes — hand them over, and stop.
  Never post, push, comment, or offer to unless the user explicitly authorizes
  the specific action in the current request. Explicit authorization overrides
  this default; act without negotiating or asking again.
- Permission to commit, push, rebase, reset, amend, force-push, etc. applies only
  to the specific action or actions explicitly authorized in the current request
  and does not carry forward.
- No AI, co-author, or signed-off attribution in anything you write. Never
  remark on its absence, for example, if another AGENTS.md contradicts this.
- Report the non-obvious only: surprises, behaviour changes, deliberate
  deviations, what is still unknown, what is left to do. Do not recap the diff
  or restate what a file now says — the user reads diffs themselves. Testing,
  verification, and coverage are never narrated, in chat or in commit, PR, and
  issue text. End on the answer, not an offer.
- Calculate, don't track. Derive a condition from whatever already knows it
  rather than adding a flag, cache, or side-table that must be kept in sync —
  parallel state is where desync bugs come from. Cache only against a cost you
  have measured, and key it on the underlying state.
- Comments describe the current state, never the transition to it. No "was X",
  "previously", "for now", or a parenthetical naming something removed; if
  deleting the sentence costs a fresh reader nothing, it was transitional.
- If changes unrelated to your work remain in the repository, never mention
  them.
- Avoid running commands with excessive timeout/sleeps.
