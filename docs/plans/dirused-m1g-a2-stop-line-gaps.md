# dirused M1g A2 — close the gaps in the "scan stopped" line (Argon review of #13)

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused; `m1g-timeout-folder-parallel-walk` (head a242be0, PR wilddog64/dirused#13)
**Tracked:** separately from k3d-manager releases (operator, 2026-11-15). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Follows:** `docs/plans/dirused-m1g-timeout-names-folder-and-parallel-walk.md` Part A; findings from `docs/plans/dirused-m1g-a-review.md` (Argon, 2026-11-17), each re-read by Claude against a242be0.
**Risk:** low (one check in `Scanner.Walk`, one stderr string, tests)
**Implementer:** Luna (Codex). **Verifier:** Claude (pre-fix red, mutations, dirused-dev VM).

## Problem (verified by Claude from the code at a242be0)

1. **Argon 1 (high).** `ReportStop(path)` is called only from the cancel check inside the two per-entry loops
   (`src/Dirused.Core/Scanner.cs:81`, `:117`). If the scan is cancelled while `reader(path)` is reading a folder whose listing
   is empty, or which is the last folder still open, no later loop iteration runs, and the result is INCOMPLETE with no
   `not finished: scan stopped` line. A slow SMB listing is the office case.
2. **Argon 2 (medium).** Same gap when the cancel lands during `Allocated(...)` or `Length` on a folder's last file (`/exact` on
   SMB is a network call per file), or between a parent's check and the child's entry check (`:54`).
3. **Argon 4 (low, pre-existing).** `/csv`: `src/Dirused.Cli/Program.cs:51` writes `item.Reason` without `item.Path`, so the
   new line prints as a bare `not finished: scan stopped` on stderr, without the folder.
4. **Argon 5 (low).** Neither new test asserts `result.Complete` is false.

Not covered here (recorded, no change): Argon 3 — when `DirectoryReader.Read` blocks past `ScanRunner`'s grace window the scan
thread is abandoned and only `TIMED OUT` is printed (design limit; belongs with Part B). `TextRenderer.cs:68` prints the first 10
errors only (pre-existing).

## Before You Start

1. `git -C <worktree> log --oneline -1` is a242be0.
2. Read `src/Dirused.Core/Scanner.cs` (`Scan`, `Walk`, `ReportStop`), `src/Dirused.Cli/Program.cs`, and
   `tests/Dirused.Tests/ScannerTests.cs` (`Test_StoppedScanNamesFolderInProgress`, `Test_CancelledBeforeStartNamesNothingExtra`)
   before editing.

## Change

1. **`Scanner.Walk`:** after the listing loop finishes (either branch, normal end or `break`), inside the existing `try`, add
   `if (ct.IsCancellationRequested) ReportStop(path);` before the return. Keep the two in-loop calls. `ReportStop` already
   reports only once per scan, and the innermost open folder's `Walk` ends first, so the deepest folder is the one named.
   The check at the top of `Walk` (`if (ct.IsCancellationRequested) return (0, 0);`) stays unchanged, so a scan cancelled
   before it starts still adds nothing.
2. **`Program.cs:51`:** `error.WriteLine($"{item.Path}: {item.Reason}");` (same format as `TextRenderer.cs:68`).
3. **Tests:** add `Assert.False(result.Complete);` to both existing tests.

## Files

| File | Change |
|---|---|
| `src/Dirused.Core/Scanner.cs` | Change 1 |
| `src/Dirused.Cli/Program.cs` | Change 2 |
| `tests/Dirused.Tests/ScannerTests.cs` | tests 1, 2; Change 3 |
| `tests/Dirused.Tests/` CLI test file that already covers `/csv` stderr (find it; if none exists, add test 3 to `ScannerTests.cs`'s sibling CLI test file and name it in the report) | test 3 |

## Contract readers

`grep -rn "\.Reason" src` (2026-11-17, a242be0): `Program.cs:43` (single-error volume-less target, unchanged), `Program.cs:51`
(this change), `SummaryRenderer.cs:16` (`/summary` uses `ProbeSummary`, never `Scanner`, unaffected), `ScanRunner.cs:109,131`
(match `CANCELLED`, unaffected), `TextRenderer.cs:68` (already prints `Path: Reason`). No test asserted the bare reason on
`/csv` stderr; if one does, update it to the `Path: Reason` form and say so in the report.

## Tests (these names exactly)

1. `Test_StoppedScanInEmptyFolderNamesIt` — root lists `a` and `b` (directories); the reader for `a` cancels the token and returns
   an empty listing → exactly one error, path `a`, reason `not finished: scan stopped`; `Complete` false; the reader for `b`
   is never called.
2. `Test_StoppedScanInLastFolderNamesIt` — root lists one directory `a`; the reader for `a` cancels and returns one file → exactly
   one error, path `a`; `Complete` false.
3. `Test_CsvStderrNamesStoppedFolder` — the `/csv` stderr writer prints `<path>: not finished: scan stopped` for an incomplete
   result carrying that error (drive the smallest seam that exists; do not add a public API for the test).

Pre-fix red: 1 and 3 fail on a242be0 (2 passes today: its loop check catches the file entry; it guards the single-folder
case). Mutations (apply by hand, run, revert; each must turn the named test red): remove the post-loop check (1); write
`item.Reason` alone again (3); make `ReportStop` report every call instead of once (1 or the existing
`Test_StoppedScanNamesFolderInProgress`).

## What NOT to Do

- Do NOT change `ScanRunner`, the timeout or grace logic, `TextRenderer`, `SummaryRenderer`, JSON/CSV stdout, or exit codes.
- Do NOT start Part B (parallel walk).
- Do NOT commit, push or comment on the PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Keep existing indentation, naming and brace style; LF endings; no unsolicited refactors; no unused fields (warnings are errors).
- Tests use the injected reader; no real network share.

## Gates

`dotnet test` if the SDK is available in your sandbox; otherwise say so and report the code only (Claude runs it on the
dirused-dev VM and CI).

## Definition of Done

- [ ] Changes 1–3 made; `git status` shows only files in the Files table.
- [ ] Tests 1–3 added; gate output or the reason it could not run.
- [ ] Report: changed files, test output, mutation table if run. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: a stopped scan always names the deepest folder still open, including an empty or last folder
  - id: M2
    text: /csv stderr names the folder in the stop line
must_not:
  - id: N1
    text: a scan stopped while reading an empty folder ends INCOMPLETE with no stop line — red today
  - id: N2
    text: /csv stderr prints "not finished: scan stopped" without the folder — red today
  - id: N3
    text: a scan cancelled before it starts gains a stop line
evidence:
  - id: E1
    proves: [M1, N1, N3]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~Stopped|FullyQualifiedName~CancelledBeforeStart"
    intent: When a timeout hits a slow share, dirused always says which folder it was stuck in.
  - id: E2
    proves: [M2, N2]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~CsvStderrNamesStoppedFolder"
    intent: The folder name also shows in /csv runs, so a scheduled CSV job tells you where it stopped.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "go ahead for that, and you can dispatch the tasks on you will" and "I can't test those until you cut a release to create v0.0.4" (fix the review's real findings before tagging v0.0.4).
