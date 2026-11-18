# dirused M1h — "System Volume Information" denied is "system only (not counted)", not INCOMPLETE

**Filed:** 2026-11-17
**Status:** ready for dispatch (queued behind `dirused-m1g-a2-stop-line-gaps`: both change `src/Dirused.Core/Scanner.cs`, one dispatch per file)
**Repo / branch:** wilddog64/dirused; `m1g-timeout-folder-parallel-walk` after A2 lands (ships in v0.0.4 with PR #13)
**Tracked:** separately from k3d-manager releases (operator, 2026-11-15). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (one catch branch in `Scanner.Walk`, one additive result field, one text line)
**Implementer:** Luna (Codex). **Verifier:** Claude (pre-fix red, mutations, dirused-dev VM).

## Why

Office run, operator, 2026-11-17 (screenshot): `dirused /top 3 /file servers.list` finished on all four agent hosts, but two
printed `INCOMPLETE` with `...\System Volume Information: Access is denied` and exit 3. That folder at a volume root is
readable only by SYSTEM by design; the volume's used figure already includes it. Operator: "probably should not go check
System Volume Information".

## Change

1. **`Scanner`:** keep the volume root that `Scan` computes (`root`, `Path.GetPathRoot(full)`) in a field. In `Walk`'s outer
   `catch (Exception ex) when (IsScanError(ex))` (`Scanner.cs:164` at a242be0), if the error is access denied
   (`UnauthorizedAccessException`, or `Win32Exception` with `NativeErrorCode == 5`) **and** `path` is
   `<volume root>\System Volume Information` (file name compared `OrdinalIgnoreCase`; parent equal to the volume root,
   trailing `\` ignored; works for `C:\` and `\\host\d$` roots), add `path` to a new `systemOnly` list instead of `errors`.
   Clear it in `Scan` with the others. Any other error, any other folder, and the same name below the root are unchanged.
   If the folder is readable, walk and count it as today.
2. **`ScanResult`:** add `List<string> SystemOnly` as the last positional parameter with a default of an empty list (or an
   init property defaulting to empty, whichever keeps every existing constructor call compiling unchanged). `Complete`
   does not depend on it.
3. **`TextRenderer`:** for each `SystemOnly` path print `<path>: system only (not counted)` once, after the rows and
   before any `INCOMPLETE` block.
4. **README:** one line under the output notes saying this.

JSON gains a `systemOnly` array per target (additive). CSV stdout, `/summary`, exit codes for other errors: unchanged.

## Files

| File | Change |
|---|---|
| `src/Dirused.Core/Scanner.cs` | Change 1 |
| `src/Dirused.Common/ScanResult.cs` | Change 2 |
| `src/Dirused.Common/Renderers/TextRenderer.cs` | Change 3 |
| `README.md` | Change 4 |
| `tests/Dirused.Tests/ScannerTests.cs` | tests 1–4 |
| `tests/Dirused.Tests/` renderer test file that already covers `TextRenderer` (name it in the report) | test 5 |

## Contract readers

`ScanResult` constructor callers: `grep -rn "new ScanResult\|with {" src tests` — every caller must compile unchanged
(default value). JSON: `JsonRenderer.cs:11,18` serialize `ScanResult` directly, so `systemOnly` appears; if a test compares
a whole JSON document, update it and say so. `ScanRunner` builds results with `with { Errors = ..., Complete = false }`,
which keeps `SystemOnly`.

## Tests (these names exactly)

1. `Test_SystemVolumeInformationDeniedIsNotCounted` — root lists `System Volume Information` (directory) and `data`
   (directory); the reader throws `UnauthorizedAccessException` for `<root>\System Volume Information` → `Complete` true,
   `Errors` empty, `SystemOnly` equals that one path, `data` still walked.
2. `Test_SystemVolumeInformationWin32DeniedIsNotCounted` — same with `new Win32Exception(5)`.
3. `Test_OtherDeniedFolderIsStillIncomplete` (positive control) — the reader throws `UnauthorizedAccessException` for
   `<root>\secret` → `Complete` false, one error at `secret`, `SystemOnly` empty.
4. `Test_NestedSystemVolumeInformationIsStillIncomplete` — denied at `<root>\a\System Volume Information` → INCOMPLETE as
   today (only the volume-root folder is special).
5. `Test_TextShowsSystemOnlyLine` — a complete result with one `SystemOnly` path renders
   `<path>: system only (not counted)` and no `INCOMPLETE` line.

Pre-fix red: 1, 2, 5 fail (or do not compile) on the base; 3 and 4 pass (guards). Mutations (apply by hand, run, revert;
each must turn the named test red): match the folder name at any depth (4); treat any exception type as system-only (3 if
it throws a non-denied error — or add that case to 3); drop the `NativeErrorCode == 5` branch (2); skip the renderer line (5).

## What NOT to Do

- Do NOT skip or avoid reading the folder (try it; only a denied read is labelled). Do NOT special-case `$Recycle.Bin` or
  any other name.
- Do NOT change `ScanRunner`, timeout logic, A2's stop-line code, CSV stdout, `/summary`, or the exit code for other errors.
- Do NOT commit, push or comment on the PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Keep existing indentation, naming and brace style; LF endings; no unused fields (warnings are errors); no refactors.
- Tests use the injected reader; no real share, no real ACLs.

## Gates

`dotnet test` if the SDK is available in your sandbox; otherwise say so (Claude runs it on the dirused-dev VM and CI).

## Definition of Done

- [ ] Changes 1–4; `git status` shows only files in the Files table.
- [ ] Tests 1–5 added; gate output or the reason it could not run.
- [ ] Report: changed files, test output, mutation table if run. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: a denied read of System Volume Information at the volume root is listed as system only and the scan stays complete (exit 0)
  - id: M2
    text: text output shows "<path>: system only (not counted)"
must_not:
  - id: N1
    text: a denied System Volume Information at the volume root makes the scan INCOMPLETE — red today
  - id: N2
    text: any other denied folder, or the same name below the root, stops counting as INCOMPLETE
evidence:
  - id: E1
    proves: [M1, N1, N2]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~SystemVolumeInformation|FullyQualifiedName~OtherDeniedFolder"
    intent: The Windows system folder no longer turns a finished scan into INCOMPLETE, while real permission problems still do.
  - id: E2
    proves: [M2]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~TextShowsSystemOnlyLine"
    intent: You still see that the folder was not counted, on a plain line instead of an error.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "go dispatch M1h" (after Claude proposed labelling System Volume Information "system only (not counted)" instead of INCOMPLETE).
