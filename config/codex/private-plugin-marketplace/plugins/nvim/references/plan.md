# Planning Outcomes

Use for `$nvim-plan`. Write `evidence/plan.md`, compare the realistic
outcomes, recommend one, and stop.

Outcome types:

- `fix`: implement one concrete source change.
- `alternate-fix`: implement a different source-level tradeoff.
- `no-change`: close, mark invalid, duplicate, already fixed, or expected.
- `clarify`: do not implement; ask Barrett to seek missing GitHub facts.
- `more-repro`: stop because current evidence is not good enough to choose.
- `test-or-docs`: add coverage or docs without changing behavior.

Produce 2-4 outcomes by default. Use one outcome only when alternatives would
be artificial; use more than four only when the issue genuinely has separate
viable paths.

Each outcome should state evidence, tradeoff, and next verification step in
2-4 bullets. Do not edit source, commit, push, open PRs, or post comments.

Coordinator updates after `evidence/plan.md` exists:

- `index.md`: planning status and link to `evidence/plan.md`.
- `log.md`: one short append-only entry.
