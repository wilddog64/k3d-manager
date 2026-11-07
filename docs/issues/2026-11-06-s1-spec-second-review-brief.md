# Task: second independent review of the P0 S1 dispatch-gates spec

**Status:** OPEN
**Approval:** operator, 2026-11-06: "go ahead to work on S1 spec then dispatch to Luna" (Claude's stated plan: revise, then a second independent review before dispatch). Reviewer: Codex Terra.
**Branch:** `k3d-manager-v1.43.14`

## Goal

Review `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md`, slice S1 only (`## Slice S1` to the end of the file), before it is dispatched. Do not implement anything. `docs/issues/2026-11-06-s1-spec-review-findings.md` holds the first review's verdict of not ready. Check its findings against the revised text; do not assume they are fixed.

Read also: `bin/k3dm-codex-dispatch`, `bin/k3dm-dispatch-metrics`, and everything in `scripts/tests/fixtures/dispatch-gates/`.

Answer, with `file:line` evidence for each finding:

1. Is each blocker and should-fix from the first review actually closed by the revised text?
2. Do `synthetic.jsonl` and `expected.json` agree with the rules? Work through at least three cases by hand, including one tie on the same second and one late assessment.
3. New since the first review, so read it hardest: the prompts-by-model rule, the `--sent-by` and `--cause` flags, the three `k3dm_dispatch_model_*` series and the two panels. Do `prompts.jsonl` and `prompts-expected.json` agree with the rule? Work through the model switch, the fallback and the start before the marker by hand. Does the attribution match what the dispatcher writes today, in particular the order of `intervention` and `resume` at `bin/k3dm-codex-dispatch:1049`? Do these additions belong in S1, or should they be a follow-up spec? Say which and why.
4. Can the Luna half and the agy half be built separately from this text without disagreeing?
5. Is every `must_not` testable as the Acceptance section describes?
6. Is anything in S1 a hidden dependency on S2 to S5?

## Files

- `docs/issues/2026-11-06-s1-spec-second-review-findings.md` (new; the only file you write)

Format: findings ranked by severity (`blocker`, `should-fix`, `nit`), each with evidence and a proposed spec change. End with a verdict: `ready`, `ready after should-fix`, or `not ready`. If you find nothing in a category, say so. Do not edit the spec or the fixtures.

## Acceptance

```yaml
must:
  - id: M1
    text: "The findings file answers all six questions with file:line evidence and ends with a verdict."
must_not:
  - id: N1
    text: "No file other than the findings file changes."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, text: "Claude reads the findings and checks the diff scope."}
interface:
  - "docs/issues/2026-11-06-s1-spec-second-review-findings.md"
```
