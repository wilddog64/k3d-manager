# dirused M8d: `/purge` labels a file below `/minsize` as `smaller than` before any age reason

**Filed:** 2026-11-19
**Status:** READY
**Repo / branch:** wilddog64/dirused / `m8d-purge-size-before-age` (from main 31edffe, v0.0.20)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Bug:** `docs/dirused/bugs/2026-11-19-dirused-purge-dry-run-lists-files-below-minsize.md` (P3, Recurrence section)
**Risk:** low (changes which skip label a file gets; no file that was skipped becomes deletable, none that was deletable becomes skipped)
**Implementer:** Flash (agy). **Verifier:** Claude. Live check by the operator on the work laptop.
**Intent approved:** operator, 2026-11-19
Intent note: same intent as M8c ("if we give /largest and /purge, the list should give only largest files", operator 2026-11-19, and "go ahead to write a bug and dispatch to flash"); M8d makes the v0.0.20 output meet it on us03p02app01.

## Problem

v0.0.20 on us03p02app01: `15 of 96 matches, 627M, 5 smaller than 1.0 GB not shown, would free 0B`. All rows are below 1 GB,
but files also modified within the age window (or with an unknown time) are labelled by age, because `Purge.cs:82-83` run
before the size check at `:84`. M8c hides only `skipped: smaller than` rows.

## Change

1. **`src/Dirused.Common/Purge.cs:82-84`:** move the `file.LogicalBytes < minBytes` branch (status
   `skipped: smaller than {size}`) so it comes directly after the `IsPurgeLog` branch (`:81`) and before the
   `LastWriteUtc == null` and `LastWriteUtc >= cutoff` branches. Nothing else in the chain moves; the status text is unchanged.
2. **`CHANGELOG.md` `[Unreleased]`:** one line.

## Tests

- `tests/Dirused.Tests.Portable/PurgeTests.cs`: a file below `/minsize` that is also modified within the age window is
  `skipped: smaller than 1.0 GB`; a file below `/minsize` with `LastWriteUtc == null` is `skipped: smaller than 1.0 GB`.
  Positive control: a file at or above `/minsize` modified within the window is still `skipped: modified within 1 day(s)`,
  and an old large file is still `would delete`. Existing assertions at `:37`, `:53`, `:54` keep passing or are updated only
  where a small recent file changes label; say which in the commit message.
- Text rendering of a `/purge` result with a small recent file: the row is not printed and is counted in `not shown`.

## Files

- `src/Dirused.Common/Purge.cs`
- `tests/Dirused.Tests.Portable/PurgeTests.cs`
- `tests/Dirused.Tests.Portable/RendererTests.cs`
- `tests/Dirused.Tests/ProgramPurgeTests.cs` (only if an assertion on a small recent file's label must change)
- `CHANGELOG.md`

## Contract readers

- Status strings: `Purge.cs` writes; `TextRenderer.WriteLargest` and `HtmlRenderer` read the `skipped: smaller than ` prefix
  (M8c); CSV/JSON print the status as is; `ProgramPurgeTests.cs:56` asserts `modified within` on a fixture row (check its size).
- Counts: `skipped` is incremented for every `skipped:` status (`Purge.cs:100`), so totals are unchanged.

## What NOT to Do

- Do not change the order of `outside target`, `purge log`, or any check after the size check, or any status wording.
- Do not change what is deleted, `would`/`wouldBytes`/`PurgeBytes`, the purge log, exit codes, or the renderers.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "with /purge, a file below /minsize is labelled 'skipped: smaller than <min>' even when it is also modified within the age window or has an unknown modification time"
  - id: M2
    text: "a file at or above /minsize modified within the window is still 'skipped: modified within N day(s)', and an old file at or above /minsize is still 'would delete' (positive control)"
  - id: M3
    text: "text output of a /purge run hides such a small recent file and counts it in 'N smaller than <min> not shown'"
must_not:
  - id: N1
    text: "a file below /minsize is labelled 'skipped: modified within' (red on main 31edffe)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable; new assertions red on 31edffe; mutant 'size check after the age checks again' red; mutant 'size check before outside target' does not change any test outcome is acceptable, but 'drop the age check' makes M2 red; Windows CI green"
    intent: Small files never show up in the purge list, even if they were written recently.
  - id: E2
    kind: live
    proves: [M1, M3]
    command: "operator, work laptop: rerun `dirused /top 3 /warn 30 /crit 45 /html /file server-list.txt /largest /purge`; us03p02app01 shows 'no files of at least 1.0 GB'; us03p02ffm01 still shows its three tomcat logs"
    intent: Rerun your command; app01 shows one 'nothing to delete' line instead of 15 small files.
interface:
  - "skipped: smaller than"
```
