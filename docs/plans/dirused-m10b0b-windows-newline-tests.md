# dirused M10b0b: ScheduleTests use one newline convention (Windows CI)

**Status:** OPEN — SPEC rev 1, 2026-11-24
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b0a](dirused-m10b0a-pr40-fixes.md) (landed `c6283a2` on `m10b0-schedule-preview`, PR #40). Test-only.
**Repo / branch:** wilddog64/dirused / `m10b0-schedule-preview` (tip `c6283a2`)
**Risk:** low — one test file; no product change
**Implementer:** Luna (Codex)
**Verifier:** Claude (static check) and the PR's windows CI job
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries M10b0's approved E-B0 intent unchanged; test-only fix for windows CI.
**Approval:** operator, 2026-11-24 — M10b0 PR flow ("preview first then move to actual scheduling")

## Why

Windows CI on `c6283a2` fails 5 `ScheduleTests` (`TimeRulesCoverZonesDstAndBoundaries`, `DayBeforeSpringForwardRejectsNextDaysGap`,
`PreviewPrintsPacificAndUtcAndUsesFilePathHost`, `DayBeforeFallBackRejectsNextDaysOverlap`,
`ListPathWrapsAt68AndBadLinesAreReportedAfterPreview`). Every test writer is `new StringWriter { NewLine = "\n" }`
(`ScheduleTests.cs:11`), but expectations and splits use `Environment.NewLine` (for example `:33`, `:148`, `:159`, `:209`), which is
`"\r\n"` on Windows and `"\n"` on macOS and Linux, so the mismatch only shows on the windows job.

## Scope

In `tests/Dirused.Tests.Portable/ScheduleTests.cs` only: every expected string, concatenation and `Split` that refers to the writers'
output uses `"\n"` (or `'\n'`), matching `Writer()`. No `Environment.NewLine` remains in that file. Every `StringWriter` the file
passes to `Schedule.Run` comes from `Writer()`. No assertion is removed or weakened; no product file changes.

## Files

- `tests/Dirused.Tests.Portable/ScheduleTests.cs`

## What NOT to Do

- Do not touch `src/`, other test files, or docs. Do not change what any test asserts beyond the newline form.
- Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: W-M1
    text: "grep -c 'Environment.NewLine' tests/Dirused.Tests.Portable/ScheduleTests.cs prints 0, and every 'new StringWriter' in that file is inside Writer() (grep -c 'new StringWriter' prints 0 outside the Writer() definition line)"
  - id: W-M2
    text: "dotnet test tests/Dirused.Tests.Portable passes on m4 with the same test count as c6283a2 (228), and the PR's windows CI job is green on the new head"
must_not:
  - id: W-N1
    text: "any ScheduleTests expectation depends on the host newline. Baseline red: on c6283a2 grep -c 'Environment.NewLine' ScheduleTests.cs is non-zero and the windows job fails 5 tests"
evidence:
  - id: E-W
    proves: [W-M1, W-M2, W-N1]
    kind: offline
    command: "the two greps above on the new tree (0, 0) and on c6283a2 (non-zero); dotnet test totals; gh pr checks 40 shows windows pass on the new head; git diff touches only ScheduleTests.cs"
    intent: "You type /schedule with a time and see exactly when the purge would run (Pacific and UTC, and how long from now), which server, how many files and how much space — and nothing is scheduled, written or touched on the server. Adding /confirm tells you scheduling is not in this version yet."
interface:
  - "test-only; no interface change"
```
