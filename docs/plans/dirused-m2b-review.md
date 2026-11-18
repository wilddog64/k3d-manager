# Review: dirused PR #15 (M2b top folders) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `dirused` / `m2b-top-folders` (head 46d22df; diff `3eff57b..46d22df`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff 3eff57b..46d22df` blind. Intended behaviour:

- In `/summary` text and JSON, every target whose `Level` is `warn` or `crit` gets a second scan, one level deep and not
  exact, run through `ScanRunner`. It obeys `/parallel` and uses `/timeout`, or 60s per target when `/timeout` is not given.
  `ok` targets, targets with no level, and CSV runs get no second scan.
- The target keeps its first result's `Volume`, `Level`, `Complete` and `Errors`. It gains `Directories` = the top 3
  folders by `LogicalBytes`, largest first, ties broken by path. `Files` stays empty.
- If the second scan is incomplete (error or timeout), the text output adds `    top folders incomplete: <path>: <reason>`
  under that volume. The note never appears in JSON. The exit code and the footer counts never change because of the
  second scan.
- Folder line: 4 spaces, the size right-aligned to the widest size in that block, 2 spaces, the path.
- live-check `L13`: `C:\Windows\Web /summary /warn 1 /crit 2` passes on exit 4 plus at least one folder line.

Look for:
- a target and its second scan paired with the wrong index;
- the timeout or cancellation leaking into the first result or the exit code;
- folders shown for an `ok` volume;
- a sort or tie order that differs from the spec;
- padding that breaks when sizes have different widths;
- JSON compatibility breaks (non-summary JSON, `level`);
- the usage text, README or PACKAGE-README disagreeing with the code;
- tests that cannot fail;
- L13's regex matching something other than a folder line.

## Before You Start

1. Read `README.md`, `tools/PACKAGE-README.txt`, `tools/live-check.ps1`, `src/Dirused.Common/TopFolders.cs`,
   `src/Dirused.Common/ScanRunner.cs`, `src/Dirused.Common/ScanResult.cs`, `src/Dirused.Common/Renderers/*.cs`,
   `src/Dirused.Cli/Program.cs` and the changed tests.
2. `git log --oneline -3` and confirm HEAD is 46d22df.

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
    intent: An independent model checks the top-folders change before you try it at the office.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "go head to write M2b spec and dispatch when there's a slot" (M2b); dirused PRs get a blind Argon review per the PR review budget.
