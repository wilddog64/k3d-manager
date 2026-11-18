# dirused M1h-b — fixes from the Argon review of the A2 + M1h delta on #13

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused; `m1g-timeout-folder-parallel-walk` (head ae4b253, PR wilddog64/dirused#13)
**Tracked:** separately from k3d-manager releases. This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Follows:** `docs/plans/dirused-m1h-system-folder-not-counted.md`; findings from `docs/plans/dirused-m1g-a2-m1h-review.md` (Argon), each re-read by Claude at ae4b253.
**Risk:** low. **Implementer:** Luna (Codex). **Verifier:** Claude (dirused-dev VM).

## Problem (verified by Claude at ae4b253)

1. The parent loop still adds a system-only child to `directories` as `(0, 0)`, so `System Volume Information` shows as a 0 B
   row in text/JSON/CSV next to its "system only" line.
2. `IsSystemOnlyDenied` has no depth check: `dirused "C:\System Volume Information"` (the target itself, depth 0) is labelled
   system-only and exits 0 though nothing was read.
3. `volumeRoot` keeps a `\\?\` / `\\?\UNC\` prefix while child paths are `Unextended`, so a `\\?\C:\` target never matches.
4. No test that a non-denied error on that folder stays INCOMPLETE (the "any exception" mutant survives).
5. `Test_CsvStderrNamesStoppedFolder` calls the private helper by reflection, so removing the call in `Program.Run` cannot fail it.

## Change

1. In both per-entry loops, do not add a directory entry for a child whose path was just added to `systemOnly`
   (e.g. compare `systemOnly.Count` before and after the child `Walk`, or check the last item).
2. Pass `depth` to `IsSystemOnlyDenied` and require `depth > 0`.
3. `volumeRoot = Unextended(root);`.
4. Tests (below). For 5, drive `Program` with `/csv` through the existing CLI seam if one exists; if there is none,
   keep the reflection test and say so — do not add a public API.

## Files

| File | Change |
|---|---|
| `src/Dirused.Core/Scanner.cs` | Changes 1–3 |
| `tests/Dirused.Tests/ScannerTests.cs` | tests 1–4 |
| `tests/Dirused.Tests/OutputCompatTests.cs` | test 5 (only if a CLI seam exists) |

## Tests (these names exactly)

1. Extend `AssertSystemVolumeInformationDenied`: `Assert.DoesNotContain(result.Directories, e => e.Path == systemPath)`.
2. `Test_SystemVolumeInformationAsTargetIsStillIncomplete` — target `<volume root>\System Volume Information`, reader throws
   `UnauthorizedAccessException` for it → `Complete` false, one error at that path, `SystemOnly` empty. (If depth 0 hits the
   real-filesystem reparse check first, use whatever path the existing depth-0 tests use and say so.)
3. `Test_SystemVolumeInformationExtendedRootIsNotCounted` — same as the denied test with target `@"\\?\" + volume root`
   → `Complete` true, `SystemOnly` equals the plain (unextended) path.
4. `Test_SystemVolumeInformationIoErrorIsStillIncomplete` — reader throws `new IOException("disk")` for
   `<volume root>\System Volume Information` → `Complete` false, one error at that path, `SystemOnly` empty.
5. `Test_CsvRunWritesStoppedFolderToStderr` — only if a CLI seam exists (see Change 4).

Pre-fix red: 1, 2, 3 fail at ae4b253; 4 passes (guard). Mutations: re-add the directory entry (1); drop `depth > 0` (2);
drop `Unextended` (3); `bool denied = ex is not null;` (4).

## What NOT to Do

- Do NOT change `ScanRunner`, renderers, JSON/CSV formats, exit codes, A2's stop-line code, or the "system only" text.
- Do NOT commit, push or comment on the PR. Do NOT skip hooks. Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Existing style; LF; no unused fields (warnings are errors); injected reader only.

## Gates

`dotnet test` if available (Scanner tests need Windows; say so). Claude runs them on the VM.

## Definition of Done

- [ ] Changes 1–3 (and 4 if a seam exists); only Files-table files changed.
- [ ] Tests added; gate output or why it could not run. Report back; no commit.

## Acceptance

```yaml
must:
  - id: M1
    text: a denied System Volume Information under the root appears only as "system only", never as a 0 B directory row
must_not:
  - id: N1
    text: scanning System Volume Information itself exits 0 when it cannot be read — red today
  - id: N2
    text: a \\?\ volume-root target reports a denied System Volume Information as INCOMPLETE — red today
  - id: N3
    text: a non-denied error on System Volume Information is hidden as system only
evidence:
  - id: E1
    proves: [M1, N1, N2, N3]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~SystemVolumeInformation"
    intent: The system folder is labelled once and only when it is really just a permission block, never hiding a failed scan.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "go dispatch M1h" (fix the M1h review findings before tagging v0.0.4).
