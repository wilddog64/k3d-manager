# Review: dirused PR #13 delta (M1g A2 + M1h) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `dirused` / `m1g-timeout-folder-parallel-walk` (head ae4b253; delta `a242be0..ae4b253`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff a242be0..ae4b253` blind. Intended behaviour:

- A scan stopped by `/timeout` or Ctrl-C names, once, the deepest folder still open as `<path>: not finished: scan stopped`,
  including an empty folder, the last folder, or a folder's last file. A scan cancelled before it starts adds nothing.
- `/csv` stderr prints `<path>: <reason>`.
- A denied read (`UnauthorizedAccessException` or Win32 error 5) of `System Volume Information` directly under the volume
  root (`C:\` or `\\host\d$`) goes to `SystemOnly`, not `Errors`; the scan stays complete; text prints
  `<path>: system only (not counted)`; JSON gains `systemOnly`. Any other error, folder or depth is unchanged.

Look for: wrong folder named or labelled, a real error hidden as system-only, results whose `SystemOnly` is lost
(`with` copies, `ScanRunner`, renderers), exit-code effects, JSON/CSV compatibility breaks, tests that cannot fail.

## Before You Start

1. Read `README.md`, `src/Dirused.Core/Scanner.cs`, `src/Dirused.Common/ScanResult.cs`, `src/Dirused.Common/ScanRunner.cs`,
   `src/Dirused.Common/Renderers/*.cs`, `src/Dirused.Cli/Program.cs` and the changed tests.
2. `git log --oneline -3` and confirm HEAD is ae4b253.

## Files

| File | Change |
|---|---|
| `src/Dirused.Core/Scanner.cs` | read only |
| `src/Dirused.Common/ScanResult.cs` | read only |
| `src/Dirused.Cli/Program.cs` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT run tests that need Windows; reason from the code.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back: one line per finding as `file:line — defect — concrete failure scenario — severity (high/medium/low)`,
      or `no findings`. Mark each as verified-from-code or speculative.

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
    intent: An independent model checks the two late changes before you rely on v0.0.4 at the office.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "I can't test those until you cut a release to create v0.0.4" and "go dispatch M1h" (v0.0.4 needs a blind Argon review of the A2 + M1h delta on #13).
