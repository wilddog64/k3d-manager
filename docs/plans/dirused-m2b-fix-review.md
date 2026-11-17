# Review: dirused PR #16 (M2b-fix release test) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `dirused` / `m2b-fix-release-test` (head 622fab5; diff `13bd6c4..622fab5`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff 13bd6c4..622fab5` blind. Intended behaviour:

- `Test_AttachWalksOnlyWarnAndCritTargets` passes whatever order the parallel `ScanRunner` workers finish in, and records
  walks thread-safely.
- It still proves only warn/crit targets are walked, and that each warn/crit result keeps the folders of its own scan.
- A 100 ms delay on the warn scan makes the old ordered assertion fail every time.
- `tools/PACKAGE-README.txt` quick-start describes `/summary` as listing a warn/crit volume's top 3 folders, aligned to
  the description column.

Look for:
- assertions that cannot fail;
- a remaining order or thread-safety dependency;
- a pairing check that would pass even with swapped results;
- README text that disagrees with the code.

## Before You Start

1. Read `README.md`, `tools/PACKAGE-README.txt`, `tools/live-check.ps1`, `src/Dirused.Common/TopFolders.cs`,
   `src/Dirused.Common/ScanRunner.cs`, `src/Dirused.Common/ScanResult.cs`, `src/Dirused.Common/Renderers/*.cs`,
   `src/Dirused.Cli/Program.cs` and the changed tests.
2. `git log --oneline -3` and confirm HEAD is 622fab5.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/TopFolders.cs` | read only |
| `src/Dirused.Cli/Program.cs` | read only |
| `src/Dirused.Common/Renderers/SummaryRenderer.cs` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT run tests that need Windows; reason from the code. `dotnet test tests/Dirused.Tests.Portable -m:1 -p:NuGetAudit=false` may be run.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`.
      If there are none, report `no findings`. Mark each finding as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: An independent model checks the release-build test fix before v0.0.7 is tagged.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "#15 merged" / release build fix (M2b-fix); dirused PRs get a blind Argon review per the PR review budget.
