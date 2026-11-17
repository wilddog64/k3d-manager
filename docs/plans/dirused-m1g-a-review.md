# Review: dirused PR #13 (M1g Part A) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `dirused` / `m1g-timeout-folder-parallel-walk` (head a242be0, base `main` 6c66022)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff 6c66022..a242be0` blind: you get the diff and the code, not the author's conclusions. Intended behaviour:
when a scan is stopped by `/timeout` or Ctrl-C, the scan's errors name the folder that was being read as
`<path>: not finished: scan stopped`, once; a scan cancelled before it starts adds nothing; no other output changes.

Look for: wrong or missing folder named, duplicate or missing lines, behaviour change when nothing is cancelled, races
with `ScanRunner`'s timeout or abandoned-thread path (`src/Dirused.Core/ScanRunner.cs`), exit-code or renderer effects,
tests that cannot fail.

## Before You Start

1. Read `README.md`, `src/Dirused.Core/Scanner.cs`, `src/Dirused.Core/ScanRunner.cs` and `tests/Dirused.Tests/ScannerTests.cs`.
2. `git log --oneline -3` and confirm HEAD is a242be0.

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
    intent: An independent model checks the timeout change before you rely on it at the office.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "I can't test those until you cut a release to create v0.0.4" (release v0.0.4 needs the review rules' blind Argon review of #13).
