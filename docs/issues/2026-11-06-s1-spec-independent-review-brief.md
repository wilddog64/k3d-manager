# Task: independent review of the P0 S1 dispatch-gates spec

**Status:** OPEN
**Approval:** operator, 2026-11-06: "P0 S1 can have agy review (gemini 4 is running weekly token, maybe Codex Sol/Terra. this can be up to your call)". Reviewer: Codex Terra.
**Branch:** `k3d-manager-v1.43.14`

## Goal

Review `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md`, slice S1 only, before it is dispatched. Do not implement anything. Claude has already reviewed this spec, so look for what a second reader would catch.

Read also: `bin/k3dm-codex-dispatch`, `bin/k3dm-dispatch-metrics`, `scripts/tests/fixtures/dispatch-gates/synthetic.jsonl`, `scripts/tests/fixtures/dispatch-gates/expected.json`.

Answer, with `file:line` evidence for each finding:

1. Do the replay fixture and `expected.json` agree with the S1 rules? Work through at least three cases by hand.
2. Does the event schema match what the dispatcher writes to the ledger today? Name any field the spec assumes but the code does not emit.
3. Can the Luna half (dispatcher) and the agy half (metrics and dashboard) be built separately from this text without the two disagreeing?
4. Is every `must_not` testable, and can each test go red on pre-fix code?
5. Is anything in S1 a hidden dependency on S2 to S5?

## Files

- `docs/issues/2026-11-06-s1-spec-review-findings.md` (new; the only file you write)

Format: findings ranked by severity (`blocker`, `should-fix`, `nit`), each with evidence and a proposed spec change. End with a verdict: `ready`, `ready after should-fix`, or `not ready`. If you find nothing in a category, say so. Do not edit the spec.

## Acceptance

```yaml
must:
  - id: M1
    text: "The findings file answers all five questions with file:line evidence and ends with a verdict."
must_not:
  - id: N1
    text: "No file other than the findings file changes."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, text: "Claude reads the findings and checks the diff scope."}
interface:
  - "docs/issues/2026-11-06-s1-spec-review-findings.md"
```
