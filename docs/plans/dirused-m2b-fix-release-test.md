# dirused M2b-fix — order-independent top-folders walk test; quick-start /summary line

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused / `m2b-fix-release-test` (from main 13bd6c4)
**Tracked:** separately from k3d-manager releases. This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (one test and one README line)
**Implementer:** Luna (Codex). **Verifier:** Claude.

## Problem

1. The v0.0.6 Release run 44152555895 (2026-11-17, win-x64) failed in
   `TopFoldersTests.Test_AttachWalksOnlyWarnAndCritTargets` (`tests/Dirused.Tests.Portable/TopFoldersTests.cs:24`):
   `Expected ["warn", "crit"]`, `Actual ["crit", "warn"]`. `ScanRunner.Run` scans targets on parallel workers
   (`src/Dirused.Common/ScanRunner.cs:13-22`, default 4), so the order of the `walked.Add` calls is arbitrary. The test also
   appends to a plain `List<string>` from several threads. The product code is correct: `TopFolders.Attach` pairs results
   by index, not by finish order. PR CI and macOS happened to pass.
2. The blind Argon review of PR #15 found that `tools/PACKAGE-README.txt:17` still describes `/summary` as
   `volume used/free only, no folder walk`. Since M2b, a warn/crit volume also lists its top 3 folders.

## Change

1. `tests/Dirused.Tests.Portable/TopFoldersTests.cs`, `Test_AttachWalksOnlyWarnAndCritTargets`:
   - Record walks thread-safely (`lock` around the add, or a `ConcurrentBag<string>`).
   - Assert the walked set without depending on order: exactly two walks, and the sorted list equals `["crit", "warn"]`.
   - Make the fake scan delay the `warn` target by 100 ms before returning (`Thread.Sleep(100)` when
     `t.Display == "warn"`). This makes crit finish first every time, so the old ordered assertion fails deterministically.
   - Keep the existing assertions on `attached[0]` and `attached[3]`. Add the same check for the index pairing:
     `attached[1]` and `attached[2]` carry the directories their own fake scan returned. Give the fake scan one entry
     named after the target, e.g. `new Entry(t.Display, 1, 0)`, and assert `attached[1].Directories[0].Path == "warn"` and
     `attached[2].Directories[0].Path == "crit"`.
2. `tools/PACKAGE-README.txt:17`: replace `volume used/free only, no folder walk` with
   `volume usage; a warn/crit volume also lists its top 3 folders`. If the column alignment of the neighbouring lines
   needs it, wrap onto a second line indented to the description column.

## Files

| File | Change |
|---|---|
| `tests/Dirused.Tests.Portable/TopFoldersTests.cs` | Change 1 |
| `tools/PACKAGE-README.txt` | Change 2 |

## Contract readers

None. The test is self-contained. `PACKAGE-README.txt` is copied into the release zip as `README.txt` by
`.github/workflows/release.yml`, unchanged.

## What NOT to Do

- Do NOT change product code (`src/`), any other test, or `live-check.ps1`.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Keep the existing test style. LF line endings. No refactors.

## Gates

- `dotnet test tests/Dirused.Tests.Portable -c Release -m:1 -p:NuGetAudit=false` passes, run 5 times in a row (paste each summary line).
- With the new 100 ms delay in place, temporarily restore the old `Assert.Equal(new[] { "warn", "crit" }, walked)`: the test must fail.
  Paste the failure, then revert to the new assertion.

## Definition of Done

- [ ] Changes 1-2; `git status` shows only the two files.
- [ ] Gate output pasted. Report: diff summary. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: the walk test passes whatever order the parallel workers finish in
  - id: M2
    text: the test still proves only warn/crit targets are walked and each result keeps its own scan's folders
  - id: M3
    text: the packaged README.txt describes /summary as listing a warn/crit volume's top 3 folders
must_not:
  - id: N1
    text: the walk test fails because crit finished before warn — red today with the 100 ms warn delay
  - id: N2
    text: the quick-start says /summary does no folder walk — red today at PACKAGE-README.txt:17
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    command: Release-config portable tests 5x green; the old ordered assert with the delay is red
    intent: The release build stops failing at random on a test that depended on timing.
  - id: E2
    proves: [M3, N2]
    kind: offline
    command: grep of tools/PACKAGE-README.txt for the new /summary line, no "no folder walk"
    intent: The README inside the zip you take to the office matches what /summary now does.
  - id: E3
    proves: [M1, M3]
    kind: live
    command: the v0.0.7 tag's Release run publishes both zips (Claude, gh release view)
    intent: The package you were waiting for actually gets built.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "#15 merged" / "please run a release to build package" (v0.0.5 precedent). Fixes the test that blocked the v0.0.6 package build, plus Argon finding 1 from PR #15.
