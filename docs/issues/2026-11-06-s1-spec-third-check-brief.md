# Task: narrow check that the S1 review blockers are closed

**Status:** OPEN
**Approval:** operator, 2026-11-06: "go ahead to work on S1 spec then dispatch to Luna"; Claude's call to confirm the fixes after a second not-ready verdict. Reviewer: Codex Terra.
**Branch:** `k3d-manager-v1.43.14`

## Goal

`docs/issues/2026-11-06-s1-spec-second-review-findings.md` listed four blockers and four should-fix items against slice S1 of `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md`. Claude has revised the slice and `scripts/tests/fixtures/dispatch-gates/expected.json`, and moved prompts by model to `docs/plans/prompts-by-model.md`. Do not implement anything.

This is a narrow check, not a new open-ended review. Answer, with `file:line` evidence:

1. For each of those eight findings: closed, partly closed or open?
2. Does every field of `gate-status --json` in the slice's output contract have a stored form in `expected.json` that an implementation can actually produce? Check all fields of three tasks, including `gates-open`.
3. Did the removal of prompts by model leave a dangling reference in S1, or the revision add a contradiction?

Report a new problem only if it would make a correct implementation fail its tests, or let a wrong one pass.

## Files

- `docs/issues/2026-11-06-s1-spec-third-check-findings.md` (new; the only file you write)

End with a verdict: `ready`, `ready after should-fix`, or `not ready`. Do not edit the spec or the fixtures.

## Acceptance

```yaml
must:
  - id: M1
    text: "The findings file answers all three questions with file:line evidence and ends with a verdict."
must_not:
  - id: N1
    text: "No file other than the findings file changes."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, text: "Claude reads the findings and checks the diff scope."}
interface:
  - "docs/issues/2026-11-06-s1-spec-third-check-findings.md"
```
