# dirused M8: `/purge` deletes the files `/largest` lists (dry run unless `/confirm`)

**Filed:** 2026-11-18
**Status:** DRAFT (dispatch after M7 `dirused-m7-check-highlight` lands: shares `HtmlRenderer.cs`, `ArgParser.cs` help, README, CHANGELOG)
**Repo / branch:** wilddog64/dirused / `m8-purge` (from main after M7 merges)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** high (first feature that deletes files, on production admin shares where deletes bypass the Recycle Bin)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.

## Problem

Operator, 2026-11-18, after `/largest` found a 116.7 GB `tomcat85-stderr` log on `\\us03p02ffm01\d$`: "can we add a /purge to
purge largest file when /largest specific. /purge without /confirm will only do dry run". Then: "make clear help message for
how /purge work".

## Operator decisions (2026-11-18, answers to Claude's questions)

1. **What is deleted:** only the files `/largest` lists (top `/largestcount` per target, default 20). `/purge` is refused when
   the pattern list contains `*` or `*.*`.
2. **Recent files:** never touch a file modified in the last 24 hours; `/purge N` sets N days instead.
3. **Method:** permanent delete. A locked or denied file is reported as failed and the run goes on.
4. **Record:** every output format shows a per-file status and the space freed per target; each `/confirm` run appends to
   `C:\temp\dirused-purge.log`.

## Change

### Switches (`src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`)

- `Options` gains, at the end with defaults: `bool Purge = false, int PurgeDays = 1, bool Confirm = false`.
- `case "purge"`: `Purge = true`; an optional following all-digit argument is the days value (same shape as `case "warn"`,
  `:112-117`), range 1-3650, else `Error: "/purge requires a number of days from 1 to 3650"`.
- `case "confirm"`: `Confirm = true`.
- After the loop (next to the `/largestcount requires /largest` check, `:189`), in this order:
  - `/purge` without `/largest` → `"/purge requires /largest"`.
  - `/confirm` without `/purge` → `"/confirm requires /purge"`.
  - `/purge` with a final pattern list containing `*` or `*.*` (so `+*` too) → `"/purge cannot be used with the '*' pattern; name the file types to delete, e.g. /largest *.log"`.
- **Help text (operator asked for it to be clear).** In `UsageText`, after the `/largestcount` line, add exactly:
  ```
    /purge [days]       Delete the files /largest lists that were last
                        modified more than [days] days ago (default: 1).
                        Without /confirm this is a dry run: nothing is
                        deleted, the report shows what would be.
    /confirm            With /purge: really delete. Deletes are permanent
                        (admin shares like \\host\d$ skip the Recycle Bin).
                        Each deletion is logged to C:\temp\dirused-purge.log
  ```
  and a new section before `Exit codes:`:
  ```
  Purge examples:
    dirused D:\ /largest /purge
        Dry run: list what would be deleted, delete nothing
    dirused D:\ /largest /purge /confirm
        Delete the listed files not modified in the last day
    dirused /file servers.txt /largest *.log /purge 7 /confirm
        On every server, delete listed .log files older than 7 days
  Purge never deletes with the '*' pattern, files newer than [days],
  links or files outside the target; a locked file is reported as failed.
  ```
  Exit code 3 line becomes `Any target incomplete, failed, timed out, or a /purge delete failed`.

### Purge engine (new `src/Dirused.Common/Purge.cs`)

- `public interface IPurgeFileSystem { PurgeFileInfo? Stat(string path); void Delete(string path); }` with
  `public sealed record PurgeFileInfo(long Length, DateTime LastWriteUtc, bool IsReparsePoint)` (`null` = no longer exists).
  `RealPurgeFileSystem` uses `FileInfo` (`Attributes.HasFlag(FileAttributes.ReparsePoint)`) and `File.Delete`.
- `public static PurgeRun Purge.Apply(IReadOnlyList<ScanResult> results, int days, bool confirm, IPurgeFileSystem fs, DateTime utcNow, TextWriter? log, CancellationToken ct)`
  returns the results with statuses set, plus totals (`WouldDelete`, `Deleted`, `Skipped`, `Failed` counts and bytes).
- Sequential, targets in result order, files in list order. Cutoff = `utcNow - days`. For each listed file, the first rule
  that applies sets its status:
  1. `Path.GetFullPath(file)` is not under `Path.GetFullPath(result.Target)` (ordinal ignore-case, prefix plus separator, or
     equal to a root that already ends in a separator) → `skipped: outside target`.
  2. scan-time `LastWriteUtc` is null → `skipped: modification time unknown`.
  3. scan-time `LastWriteUtc > cutoff` → `skipped: modified within {days} day(s)`.
  4. `fs.Stat` is null → `skipped: no longer exists`; `IsReparsePoint` → `skipped: not a regular file`; `LastWriteUtc > cutoff`
     → `skipped: modified since scan`.
  5. dry run → `would delete`.
  6. `fs.Delete`: success → `deleted` (bytes = the Stat length); `IOException`/`UnauthorizedAccessException` →
     `failed: {message}`; continue with the next file.
  On `ct` cancellation stop before the next file; the rest keep no status.
- Results that carry no `Largest` are untouched (in `/summary` mode only warn/crit volumes carry a list, `TopFolders.Attach`).
- **Log (confirm only):** for every `deleted` or `failed` file, one tab-separated line:
  `{utcNow:o}\t{Environment.UserName}\t{Environment.MachineName}\t{path}\t{bytes}\t{status}`, flushed per line.

### Model (`src/Dirused.Common/Largest.cs`)

- `LargestFile` gains `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public string? PurgeStatus { get; init; }`.
- `LargestFiles` gains `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public long? PurgeFreedBytes { get; init; }`
  (bytes deleted, or bytes that would be deleted in a dry run) and `public bool? PurgeDryRun { get; init; }` (same attribute).
  Positional constructors are unchanged, so existing `new LargestFile(...)` / `new LargestFiles(...)` calls compile. Without
  `/purge` the JSON is byte-identical to today.

### Wiring (`src/Dirused.Cli/Program.cs`)

- With `/purge /confirm`, open the log **before scanning**: append to `PurgeLog.DefaultPath = @"C:\temp\dirused-purge.log"`,
  creating the folder (as `ReportOutput.TryOpen` does). Failure → stderr `Cannot open purge log '{path}': {message}; nothing
  was scanned or deleted`, exit 1.
- After `results` (and `TopFolders.Attach`) and before rendering: `results = Purge.Apply(...)` with `RealPurgeFileSystem`,
  `DateTime.UtcNow`, the log, `cts.Token`.
- After the report, one stderr line:
  - dry run: `Purge dry run: {n} file(s), {size} would be deleted; {s} skipped. Add /confirm to delete them.`
  - confirm: `Purge: deleted {n} file(s), {size} freed; {s} skipped; {f} failed. Log: {path}`
- Exit code: crit (4) first, then 3 if any target is incomplete **or** any file `failed`, else 0. A dry run never changes the exit code.
- Test entry: `public static int RunWithPurgeLog(string[] args, TextWriter output, TextWriter error, string purgeLogPath)`
  (same as `Run`, with the log path overridden).

### Renderers

- **Text** (`TextRenderer.WriteLargest`, used by summary too): when `PurgeStatus` is set, append `  [{status}]` to the file line;
  the heading gets `, would free {size}` (dry run) or `, freed {size}` when `PurgeFreedBytes` is set.
- **HTML** (`HtmlRenderer`, largest table): when any group has a status, add a `Purge` column after `Path` (and `colspan`
  becomes 5 on group rows); the cell has `class="purge"`, text is the status. The group header gets `, would free X` / `, freed X`.
  Without `/purge` the table is byte-identical to M7's.
- **JSON:** the new properties appear only when set (attribute above).
- **CSV** (non-summary): with `/purge`, the header gains `,purge_status` and every row gets a trailing field (empty except
  `largest` rows, `Format.Quote`d). Without `/purge`, unchanged.

### Docs

- **`README.md`:** a `/purge` section after `/largest` with the help text above, the four rules (listed files only, no `*`,
  age, failed-not-fatal), the log path and format, and: "Always run without /confirm first and read the list."
- **`CHANGELOG.md` `[Unreleased]`:** "`/purge [days]` deletes the files `/largest` lists that are older than days (default 1);
  a dry run unless `/confirm`; each deletion is logged to `C:\temp\dirused-purge.log`."

## Tests

Portable (`tests/Dirused.Tests.Portable/`):
- **P1 `ArgParserTests.PurgeSwitches`:** `[@"C:\", "/largest", "/purge"]` → `Purge`, `PurgeDays == 1`, `!Confirm`;
  `[@"C:\", "/largest", "/purge", "7", "/confirm"]` → 7, `Confirm`. Errors (exact text): `/purge` without `/largest`;
  `/confirm` without `/purge`; `/largest * /purge`; `/largest +* /purge`; `/purge 0`; `/purge 3651`. `UsageText` contains
  the `/purge [days]`, `/confirm` and `Purge examples:` lines exactly as above.
- **New `PurgeTests.cs`** with a fake `IPurgeFileSystem` (records `Delete` calls, can throw, can return null/reparse/new time)
  and a fixed `utcNow`:
  - **P2 dry run:** old, new and null-date files → `would delete`, `skipped: modified within 1 day(s)`,
    `skipped: modification time unknown`; `Delete` never called; log writer gets nothing; `PurgeFreedBytes` = old file size.
  - **P3 confirm:** the old file is deleted (`Delete` called once with its path), the recent file is not (positive control in
    the same run); log has exactly one line, 6 tab-separated fields, field 4 the path, field 6 `deleted`.
  - **P4 failure continues:** first file's `Delete` throws `IOException("in use")` → `failed: in use`; the second file is still
    deleted; totals Failed 1, Deleted 1.
  - **P5 re-stat:** `Stat` null → `skipped: no longer exists`; reparse → `skipped: not a regular file`; Stat time newer than the
    cutoff → `skipped: modified since scan`; none deleted.
  - **P6 outside target:** a listed path not under the target → `skipped: outside target`, never passed to `Stat` or `Delete`.
  - **P7 boundary:** `days = 1`: a file modified `utcNow - 1 day - 1 s` is eligible; `utcNow - 1 day + 1 s` is skipped.
  - **P8 renderers:** text line ends with `[would delete]`; HTML has `<th>Purge</th>` and `class="purge"` only when a status is
    set, and the no-purge HTML equals the M7 output for the same input (positive control); JSON has `purgeStatus` only when
    set; CSV header gains `,purge_status` only with purge.

Windows (`tests/Dirused.Tests/ProgramPurgeTests.cs`, real files in a scratch temp dir; assert the dir is under
`Path.GetTempPath()` first; log path in the same dir):
- **WP1:** files `a.log` (2 KB, LastWriteTime 3 days ago), `b.log` (now), `c.txt` (3 days ago). `[dir, "/largest", "/purge"]`
  via `RunWithPurgeLog`: all three files still exist, stdout has `a.log` with `[would delete]`, no log file created, exit 0.
  Then with `/confirm`: `a.log` gone, `b.log` and `c.txt` exist, the log has one line for `a.log` ending `deleted`, stderr has
  `Purge: deleted 1 file(s)`, exit 0.
- **WP2:** a log path in a directory that cannot be created (a path under an existing *file*) with `/confirm` → exit 1, the
  message `nothing was scanned or deleted`, and `a.log` still exists.

Red on main (post-M7): P1 fails there (`Unknown switch: /purge`); the rest do not compile; paste both.

## Files

- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Options.cs`
- `src/Dirused.Common/Largest.cs`
- `src/Dirused.Common/Purge.cs`
- `src/Dirused.Cli/Program.cs`
- `src/Dirused.Common/Renderers/TextRenderer.cs`
- `src/Dirused.Common/Renderers/HtmlRenderer.cs`
- `src/Dirused.Common/Renderers/CsvRenderer.cs`
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `tests/Dirused.Tests.Portable/PurgeTests.cs`
- `tests/Dirused.Tests/ProgramPurgeTests.cs`
- `README.md`
- `CHANGELOG.md`

## Contract readers

- `Options` (positional record): constructed at `ArgParser.cs:173,192` only; new fields go at the end with defaults.
- `LargestFile` / `LargestFiles`: constructed in `Largest.cs` (`Snapshot`), `LargestTests.cs` (3), `TopFoldersTests.cs` (1);
  copied by `TopFolders.cs:29`. Init-only properties keep every constructor call and the `with` copy valid.
- Largest rendering: `TextRenderer.cs:78-84` (also via `SummaryRenderer.cs:18`), `HtmlRenderer.cs:76-86`, `CsvRenderer.cs:11`,
  `JsonRenderer` (serializes the records).
- Exit codes: README and `UsageText` exit-code block; `FleetRunnerTests`/`ProgramHtmlTests` assert 0/3/4 (unchanged without `/purge`).

## What NOT to Do

- Do not delete anything that is not in a `/largest` list, follow links, or delete directories.
- Do not delete in parallel, or before the log is open.
- Do not change output, JSON, CSV or exit codes for runs without `/purge`.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "`/largest /purge` without /confirm deletes nothing and marks each listed file would delete or skipped with a reason"
  - id: M2
    text: "`/purge /confirm` deletes only listed files last modified more than [days] days ago (default 1), logs each deletion, and goes on past a failed file"
  - id: M3
    text: "`/help` explains /purge, /confirm, the dry-run default, the log and three examples"
must_not:
  - id: N1
    text: "a dry run calls Delete (P2, WP1 first half) — red today: /purge is an unknown switch (P1)"
  - id: N2
    text: "a file modified within [days], a link, a vanished file or a path outside the target is deleted (P3, P5, P6, P7, WP1)"
  - id: N3
    text: "/purge is accepted with the '*' pattern or without /largest; /confirm without /purge (P1)"
  - id: N4
    text: "/confirm deletes when the log cannot be opened (WP2)"
  - id: N5
    text: "output without /purge changes (P8 positive control)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3, N4, N5]
    kind: offline
    command: portable suite (P1-P8) locally and on PR CI; Windows CI for WP1, WP2; P1 red on main
    intent: Purge only ever deletes old files from the /largest list, shows you first, and writes down what it deleted.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    command: "operator, work laptop: `dirused /help` shows the purge text; on a scratch folder (e.g. C:\\temp\\purgetest with an old and a new .log), `dirused C:\\temp\\purgetest /largest /purge` then the same with /confirm; then a dry run only against \\\\us03p02ffm01\\d$ with /purge 7 and read the list before any /confirm"
    intent: On your laptop, try purge on a throwaway folder first, then see what it would remove on ffm01 before deleting anything there.
interface:
  - "/purge requires /largest"
  - "/confirm requires /purge"
  - "/purge cannot be used with the '*' pattern; name the file types to delete, e.g. /largest *.log"
  - "/purge requires a number of days from 1 to 3650"
  - "Purge dry run: N file(s), SIZE would be deleted; S skipped. Add /confirm to delete them."
  - "Purge: deleted N file(s), SIZE freed; S skipped; F failed. Log: PATH"
  - "log line: ISO-UTC<TAB>user<TAB>machine<TAB>path<TAB>bytes<TAB>status"
```

**Intent approved:** operator, 2026-11-18
**Intent approval note:** answers to Claude's questions: listed files only (refuse '*'), skip modified < 24 h with /purge N days, permanent delete with failures reported, report + C:\temp\dirused-purge.log; plus "make clear help message for how /purge work"
