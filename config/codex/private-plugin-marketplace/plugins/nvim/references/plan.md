# Planning Outcomes

Use for `$nvim-plan`. Produce exactly three outcomes, recommend one, and stop.

Outcome types:

- `fix`: implement one concrete source change.
- `alternate-fix`: implement a different source-level tradeoff.
- `no-change`: close, mark invalid, duplicate, already fixed, or expected.
- `clarify`: do not implement; ask Barrett to seek missing GitHub facts.
- `more-repro`: stop because current evidence is not good enough to choose.
- `test-or-docs`: add coverage or docs without changing behavior.

Each outcome should state evidence, tradeoff, and next verification step in
2-4 bullets. Do not edit source, commit, push, open PRs, or post comments.
