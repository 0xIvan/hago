# Implementation Plans

Read each plan fully before execution. Milestone checks are verification and
progress checkpoints, not approval gates. Continue authorized work when its
acceptance criteria pass; ask only for missing material decisions, access, or
new authority. Current conversation instructions take precedence over older
checkpoint language in individual plans.

## Execution order and status

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 001 | Add local AI harness selection and safe Review automation | P1 | L | - | DONE |
| [002](002-reliable-tracking-and-personal-classification.md) | Reliable tracking and personal classification blueprint | P0 | L, staged | Reuses 001 | IN PROGRESS |

Status values: TODO, IN PROGRESS, DONE, BLOCKED, or REJECTED.

## Dependency notes

- Plan 001 is staged internally. Discovery and recommendation-only execution
  must land before auto-apply. Audit and Undo must land before auto-apply is
  enabled.

## Findings considered and rejected

- Full disk scanning for arbitrary AI tools: unnecessary, slower, and less
  predictable than a known catalog plus a custom binary path.
- Reusing T3 Code as a runtime dependency: its session-control architecture is
  much larger than Hago's one-shot classification need.
- Ollama or a local heuristic as a provider fallback: the selected CLI must be
  explicit, current, and visible to the user.
- Scheduled Review analysis was deferred in the original plan; the current app
  now implements scheduling. Plan 002 preserves that behavior.
