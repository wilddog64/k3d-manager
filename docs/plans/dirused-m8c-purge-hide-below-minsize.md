# dirused M8c: `/purge` text and HTML output leave out files below `/minsize`

**Filed:** 2026-11-19
**Status:** READY — operator said "go ahead to write a bug and dispatch to flash", 2026-11-19
**Repo / branch:** wilddog64/dirused / `m8c-purge-hide-below-minsize` (from main b708b63, v0.0.19)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Bug:** `docs/dirused/bugs/2026-11-19-dirused-purge-dry-run-lists-files-below-minsize.md` (P3)
**Risk:** low (display only; `Purge.cs` decides nothing differently)
**Implementer:** Flash (agy). **Verifier:** Claude. Live check by the operator on the work laptop.
**Intent approved:** operator, 2026-11-19
Intent note: operator read the proposed change in Claude's reply and the bug doc and replied "go ahead to write a bug and dispatch to flash" (2026-11-19).

## Problem

With `/purge`, every `/largest` row is printed, including rows marked `[skipped: smaller than 1.0 GB]`. Operator's run on
us03p02ffm01 showed 3 deletable rows among 20; the other 17 were too small to ever be deleted.

## Change

Rendering only. `Purge.cs`, `Largest.cs`, JSON, CSV and `/largest` without `/purge` are unchanged.

1. **`src/Dirused.Common/Renderers/TextRenderer.cs` `WriteLargest` (:78-85):** a row is *hidden* when its `PurgeStatus` starts
   with `"skipped: smaller than "`. Let `hidden` be the number of hidden rows and `reason` the text after `"skipped: "` of the
   first hidden row (e.g. `smaller than 1.0 GB`).
   - Header: the first number becomes the count of shown rows, and when `hidden > 0` the text
     `, {hidden} {reason} not shown` is inserted right after the matched-bytes size and before `, would free` / `, freed`.
     Example: `Largest candidate files (3 of 32 matches, 134G, 17 smaller than 1.0 GB not shown, would free 134G):`
   - Only shown rows are printed. When `hidden > 0` and no row is shown, print one line `  no files of at least {size}`, where
     `{size}` is `reason` with the leading `smaller than ` removed (e.g. `  no files of at least 1.0 GB`).
   - When no row has a `PurgeStatus` (no `/purge`), output is byte-identical to today.
2. **`src/Dirused.Common/Renderers/HtmlRenderer.cs` (:84-94):** the same rule per group: hidden rows are not written, the group
   header carries the same count and `, {hidden} {reason} not shown` text in the same position, `maxBytes` (size bar) is computed
   from shown rows only, and a group with no shown rows writes one row
   `<tr><td colspan="5">no files of at least {size}</td></tr>` (HTML-encoded with `E`).
3. **Help (`ArgParser.cs` `/minsize` lines) and `README.md`:** one sentence: text and HTML output do not list files smaller than
   `/minsize`; lower `/minsize` to see them; JSON and CSV list every file. **`CHANGELOG.md` `[Unreleased]`:** one line.

Every other skip reason (`modified within`, `read-only`, `hard-linked`, `changed since scan`, `outside target`, and the rest),
`would delete`, `deleted` and `failed` rows are still printed.

## Tests

- `tests/Dirused.Tests.Portable/LargestTests.cs` or `RendererTests.cs` / `HtmlRendererTests.cs`: build a `LargestFiles` with rows
  `would delete` (2G), `skipped: modified within 1 day(s)` (3G), `skipped: smaller than 1.0 GB` (5M, 1K), `PurgeBytes` set,
  `PurgeDryRun = true`. Text: header is exactly `Largest candidate files (2 of 4 matches, <size>, 2 smaller than 1.0 GB not shown, would free <size>):`
  (use the real `size` formatting), the 2G and 3G rows are printed, the 5M and 1K rows are not. HTML: same group header text,
  the two small paths are absent, the two large paths present.
- All rows `skipped: smaller than 1.0 GB`: text prints `  no files of at least 1.0 GB`; HTML writes the colspan row.
- Positive control: the same files with `PurgeStatus = null` (no `/purge`) render exactly as before (all rows, header `4 of 4`).
- JSON and CSV for the mixed set still contain all four paths.

## Files

- `src/Dirused.Common/Renderers/TextRenderer.cs`
- `src/Dirused.Common/Renderers/HtmlRenderer.cs`
- `src/Dirused.Common/ArgParser.cs` (help text only)
- `tests/Dirused.Tests.Portable/*.cs` (renderer tests)
- `README.md`
- `CHANGELOG.md`

## Contract readers

- `TextRenderer.WriteLargest`: called by the text output path and the summary renderer (grep `WriteLargest`); both get the rule.
- Tests matching `"Largest candidate files ("` (`LargestTests.cs`, `tests/Dirused.Tests/ProgramPurgeTests.cs`): rows below
  `/minsize` in a purge test now disappear; update an assertion only where it checked a `smaller than` row, and say so in the
  commit message.

## What NOT to Do

- Do not change `Purge.cs`, statuses, counts, `PurgeBytes`, exit codes, the purge log, or what is deleted.
- Do not change JSON or CSV output, or any output when `/purge` is absent.
- Do not hide any row whose status is not `skipped: smaller than ...`.
- Do not add a switch.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "with /purge, text and HTML output omit rows whose status starts with 'skipped: smaller than ' and the header shows '<shown> of <matches> matches, <size>, <n> smaller than <min> not shown'"
  - id: M2
    text: "rows with any other status (would delete, deleted, failed, other skip reasons) are still printed"
  - id: M3
    text: "a target whose rows are all below /minsize prints 'no files of at least <min>' (text) or the colspan row (HTML)"
  - id: M4
    text: "without /purge, text and HTML output are byte-identical to v0.0.19; JSON and CSV list every row with or without /purge (positive control)"
must_not:
  - id: N1
    text: "with /purge, a 'skipped: smaller than' row is printed in text or HTML output (red on main b708b63: the new renderer assertions fail)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable; new renderer assertions red on main b708b63; mutant 'hide every skipped: row' makes M2 red; mutant 'filter rows also when PurgeStatus is null' or 'filter in JSON' makes M4 red; Windows CI green"
    intent: The purge list shows only files big enough to delete (and big files with a reason they won't be), with a count of the small ones left out.
  - id: E2
    kind: live
    proves: [M1, M3]
    command: "operator, work laptop: rerun `dirused /top 3 /warn 30 /crit 45 /html /file server-list.txt /largest /purge`; ffm01 shows the 3 would-delete rows and '17 smaller than 1.0 GB not shown'; app01 shows 'no files of at least 1.0 GB'"
    intent: Rerun your command and see just the three big tomcat logs on ffm01, and a one-line 'nothing to delete' on app01.
interface:
  - "smaller than 1.0 GB not shown"
  - "no files of at least"
```
