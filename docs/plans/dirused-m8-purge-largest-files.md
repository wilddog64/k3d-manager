# dirused M8: `/purge` deletes the files `/largest` lists (dry run unless `/confirm`)

**Filed:** 2026-11-18
**Status:** LANDED — merged PR wilddog64/dirused#31 (fa3a07c), released v0.0.18 (pre-release) 2026-11-18; CI green Windows + portable; Windows mutation proofs (e) WP3, (h) WP7, (j) WP5 red on CI; blind Argon diff review NONE. Live E2 (operator: scratch folder, then dry run on ffm01) pending.
**Repo / branch:** wilddog64/dirused / `m8-purge` (from main 19e66d0, M7 merge)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** high (first feature that deletes files, on production admin shares where deletes bypass the Recycle Bin)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.

## Problem

Operator, 2026-11-18, after `/largest` found a 116.7 GB `tomcat85-stderr` log on `\\us03p02ffm01\d$`: "can we add a /purge to
purge largest file when /largest specific. /purge without /confirm will only do dry run". Then: "make clear help message for
how /purge work".

## Operator decisions (2026-11-18, answers to Claude's questions)

1. **What is deleted:** only the files `/largest` lists (top `/largestcount` per target, default 20). Match-all patterns refused.
2. **Recent files:** never touch a file modified in the last 24 hours; `/purge N` sets N days instead.
3. **Method:** permanent delete. A locked or denied file is reported as failed and the run goes on.
4. **Record:** text, JSON, CSV and HTML show a per-file status and the size freed per target; each `/confirm` run appends to
   `C:\temp\dirused-purge.log`.

Claude, from review (rev 2), within those decisions: `/purge` requires an **explicit** `/largest` pattern list (the operator's
"when /largest specific"), because `/largest catalina.out` makes `catalina.out` a target and silently uses the default list
(`ArgParser.cs:151-157`), which includes `*.bak` and `*.dmp`.

## Change

### Switches (`src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`)

- `Options` gains, at the end with defaults: `bool Purge = false, int PurgeDays = 1, bool Confirm = false`.
- Remove `"purge"` from the stub at `ArgParser.cs:102` (`case "plan"` keeps `not available yet (M2)`), and delete the
  `[InlineData("/purge", "not available yet (M2)")]` row at `ArgParserTests.cs:49`.
- `case "purge"`: `Purge = true`; an optional following all-digit argument is the days value (same shape as `case "warn"`,
  `:112-117`), range 1-3650, else `Error: "/purge requires a number of days from 1 to 3650"`.
- `case "confirm"`: `Confirm = true`.
- `case "largest"` records whether a pattern argument was given (`largestExplicit`).
- After the loop (next to `:189`), in this order:
  1. `/purge` without `/largest` → `"/purge requires /largest"`.
  2. `/confirm` without `/purge` → `"/confirm requires /purge"`.
  3. `/purge` with `/largest` but no pattern argument → `"/purge requires /largest with file patterns, e.g. /largest *.log"`.
  4. `/purge` when any final pattern has no character other than `*`, `?` and `.` (so `*`, `*.*`, `**`, `*?`, `?*`, `*.?*`,
     `+*` all refused) → `"/purge cannot be used with a match-all pattern; name the file types to delete, e.g. /largest *.log"`.
  5. `/purge` and any target made only of digits → `"put the number of days right after /purge (e.g. /purge 7)"`.
  6. `/purge` with `/summary /csv` and no `/html` → `"/purge with /summary /csv needs /html, which lists the files"` (that
     mode attaches no list, `Program.cs:82`).
  7. `/purge /confirm` with `/output` whose `Path.GetFullPath` equals the purge log path (ordinal ignore-case) →
     `"/output cannot be the purge log"`.
- **Help text (operator asked for it to be clear).** In `UsageText`, after the `/largestcount` line, add exactly:
  ```
    /purge [days]       Delete the files /largest lists that were last
                        modified more than [days] days ago (default: 1).
                        Needs /largest with file patterns. Without /confirm
                        this is a dry run: nothing is deleted, the report
                        shows what would be.
    /confirm            With /purge: really delete. Deletes are permanent
                        (admin shares like \\host\d$ skip the Recycle Bin).
                        Each deletion is logged to C:\temp\dirused-purge.log
  ```
  and a new section before `Exit codes:`:
  ```
  Purge examples:
    dirused D:\ /largest *.log /purge
        Dry run: list what would be deleted, delete nothing
    dirused D:\ /largest *.log /purge /confirm
        Delete the listed .log files not modified in the last day
    dirused /file servers.txt /largest *.log;*.hprof /purge 7 /confirm
        On every server, delete listed .log and .hprof files older than 7 days
  Purge only deletes files in the /largest list. It skips files modified
  within [days], files changed since the scan, links, hard-linked files and
  anything outside the target. A file in use is reported as failed.
  ```
  `ShortUsageText` (`:15-19`) third line becomes `"               [/warn [1-100]] [/crit [1-100]] [/largest <patterns> [/purge [days] [/confirm]]]\n"`.
  Exit code 3 line becomes `Any target incomplete, failed, timed out, or a /purge did not finish`.

### Purge engine (new `src/Dirused.Common/Purge.cs`)

- **Containment, pure string function** `internal static bool Purge.IsStrictlyUnder(string path, string root)`: Windows
  semantics on every OS, no `Path.GetFullPath`; `\` and `/` are both separators; compares segments ordinal ignore-case; a root
  with or without a trailing separator; `C:\` and `\\host\d$` roots; false for the root itself, for a sibling sharing a
  prefix (`C:\logs2` vs `C:\logs`), and for any path with a `.` or `..` segment.
- **Name check:** a path with any segment ending in `.` or a space is skipped (Win32 would trim it and hit a different file).
- `public interface IPurgeFileSystem { PurgeOpen Open(string path); }`. `PurgeOpen` is either an error
  (`NotFound`, or `Failed` with a message) or an open, exclusively locked handle exposing `PurgeFileInfo Info`
  (`string FinalPath, long Length, DateTime LastWriteUtc, bool IsDirectory, bool IsReparsePoint, int LinkCount`), `void
  MarkDelete()` and `Dispose()`. A file that is never marked is left untouched when the handle closes.
- `RealPurgeFileSystem` (`[SupportedOSPlatform("windows")]`, P/Invoke `CreateFileW` with `DELETE | FILE_READ_ATTRIBUTES`,
  share mode 0, `OPEN_EXISTING`, `FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS`, on the `\\?\` extended form of
  the path as `Scanner.cs:196` builds it; `GetFileInformationByHandle` for attributes, size, last write, link count;
  `GetFinalPathNameByHandleW` for `FinalPath`; `MarkDelete` = `SetFileInformationByHandle(FileDispositionInfo, true)`).
  `ERROR_FILE_NOT_FOUND`/`ERROR_PATH_NOT_FOUND` → `NotFound`; any other error → `Failed` with the Win32 message (a file
  Tomcat holds open fails with "used by another process").
- The target root is opened the same way (directory, no delete) to get its final path once per target.
- `public static PurgeRun Purge.Apply(IReadOnlyList<ScanResult> results, int days, bool confirm, IPurgeFileSystem fs,
  Func<DateTime> utcNow, Action<string>? log, CancellationToken ct)`; `PurgeRun` has `IReadOnlyList<ScanResult> Results`
  (the input with statuses set) and totals `WouldDelete, Deleted, Skipped, Failed, NotAttempted` (counts) and
  `WouldDeleteBytes, DeletedBytes`. Program renders `run.Results`.
- Sequential, targets in result order, files in list order. `cutoff = utcNow() - days` taken once at start. A file is
  eligible only if `LastWriteUtc < cutoff` (equal is skipped). For each listed file, the first rule that applies sets its status:
  1. not `IsStrictlyUnder(file.Path, result.Target)`, or a bad segment (name check) → `skipped: outside target`.
  2. scan-time `LastWriteUtc` null → `skipped: modification time unknown`.
  3. scan-time `LastWriteUtc >= cutoff` → `skipped: modified within {days} day(s)`.
  4. dry run → `would delete` (no `Open`).
  5. `Open`: `NotFound` → `skipped: no longer exists`; `Failed` → `failed: {message}`; any exception → `failed: {message}`.
  6. on the open handle: `IsDirectory` or `IsReparsePoint` → `skipped: not a regular file`; `LinkCount != 1` →
     `skipped: hard-linked`; `FinalPath` not strictly under the target's final path → `skipped: outside target`;
     `Length != file.LogicalBytes` or `LastWriteUtc != scan LastWriteUtc` → `skipped: changed since scan`.
  7. `MarkDelete` then dispose: success → `deleted` (bytes = `Info.Length`); exception → `failed: {message}`.
  Then, confirm only, `log(...)` for every `deleted` or `failed` file; if `log` throws, purging stops: that file keeps its
  status, every later file gets `not attempted: log write failed`.
  On `ct` cancellation, every file not yet processed gets `not attempted: cancelled`.
- Results that carry no `Largest` are untouched (in `/summary` mode only warn/crit volumes carry a list, `TopFolders.Attach`).
- **Log line** (tab-separated, one per file, `utcNow()` at write time):
  `{time:o}\t{Environment.UserName}\t{Environment.MachineName}\t{path}\t{bytes}\t{status}`, flushed per line.

### Model (`src/Dirused.Common/Largest.cs`)

- `LargestFile` gains `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public string? PurgeStatus { get; init; }`.
- `LargestFiles` gains, same attribute, `long? PurgeBytes` (logical bytes deleted, or would be in a dry run) and `bool? PurgeDryRun`.
  Positional constructors unchanged. Without `/purge` the JSON is byte-identical to today.

### Wiring (`src/Dirused.Cli/Program.cs`)

- `/purge` on a non-Windows OS → `"/purge is available on Windows only"`, exit 1 (before scanning).
- With `/purge /confirm`, open the log **before scanning and before `/output` is opened (`:55`)**: append to
  `PurgeLog.DefaultPath = @"C:\temp\dirused-purge.log"`, creating the folder; never truncate. Failure → stderr
  `Cannot open purge log '{path}': {message}; nothing was scanned or deleted`, exit 1.
- After `results` (and `TopFolders.Attach`) and before rendering: `var run = Purge.Apply(...)`; render `run.Results`.
- After the report, one stderr line:
  - dry run: `Purge dry run: {n} file(s), {size} would be deleted; {s} skipped; {f} could not be checked. Add /confirm to delete them.`
    (`{f}` counts rule-1/2/3 failures only; dry runs never open files, so it is normally 0 and the clause is omitted when 0).
  - confirm: `Purge: deleted {n} file(s), {size} freed; {s} skipped; {f} failed; {a} not attempted. Log: {path}`
- Exit code: crit (4) first; then 3 if any target is incomplete or any file is `failed` or `not attempted`; else 0. A dry run
  never changes the exit code.
- Test entry: `public static int RunWithPurge(string[] args, TextWriter output, TextWriter error, string purgeLogPath, IPurgeFileSystem? fs = null)`.

### Renderers

- **Text** (`TextRenderer.WriteLargest`, also used by summary): when `PurgeStatus` is set, append `  [{status}]`; the heading
  gets `, would free {size}` or `, freed {size}` when `PurgeBytes` is set.
- **HTML** (largest table): when any group has a status, add a `Purge` column after `Path` (group rows `colspan="5"`); cell
  `class="purge"`. Group header gets `, would free X` / `, freed X`. Without `/purge` byte-identical to M7.
- **JSON:** the new properties appear only when set.
- **CSV** (non-summary): with `/purge`, the header gains `,purge_status` and **every** row (including `Format.Row` directory
  and file rows) gains a trailing field, empty except `largest` rows (`Format.Quote`d). Without `/purge`, unchanged.

### Docs

- **`README.md`:** a `/purge` section after `/largest`: the help text, every skip rule, the log path and format, and "Always run
  without /confirm first and read the list. A log still being written (modified today) is skipped; rotate it or stop the
  service first."
- **`CHANGELOG.md` `[Unreleased]`:** "`/purge [days]` deletes the files `/largest <patterns>` lists that are older than days
  (default 1); a dry run unless `/confirm`; each deletion is logged to `C:\temp\dirused-purge.log`."

## Tests

Portable (`tests/Dirused.Tests.Portable/`):
- **P1 `ArgParserTests.PurgeSwitches`:** `[@"C:\", "/largest", "*.log", "/purge"]` → `Purge`, `PurgeDays == 1`, `!Confirm`;
  `[..., "/purge", "7", "/confirm"]` → 7, `Confirm`. Exact error text for: no `/largest`; `/confirm` alone; `/largest /purge`
  (no patterns); `/largest catalina.out /purge` (no patterns, `catalina.out` a target); each of `*`, `*.*`, `**`, `*?`, `+*`,
  `+*.*`, `*.log;*` with `/purge`; `/purge 0`; `/purge 3651`; `/purge /confirm 7`; `/summary /csv /largest *.log /purge`;
  `/output <log path>` with `/purge /confirm`. Positive control: `*.log;*.hprof` accepted. `UsageText` contains the help
  lines above exactly; `/plan` still returns `not available yet (M2)`.
- **P2 `PurgeTests.IsStrictlyUnder`** table: true for `C:\logs\a.log` under `C:\logs` and `C:\logs\`; `C:\a.log` under `C:\`;
  `\\h\d$\x\a.log` under `\\h\d$` and `\\H\D$\`; false for `C:\logs2\a.log` under `C:\logs`, `C:\logs` under `C:\logs`,
  `C:\logs\..\x.log`, `D:\a.log` under `C:\`.
- **`PurgeTests.cs`** with a fake `IPurgeFileSystem` (records `Open`/`MarkDelete`, scripted infos/errors/exceptions) and a
  fake clock:
  - **P3 dry run:** old, new, null-date, equal-to-cutoff files → `would delete`, `skipped: modified within 1 day(s)` (new and
    equal), `skipped: modification time unknown`; `Open` never called; `log` never called; `PurgeBytes` = old file size.
  - **P4 confirm:** old file `MarkDelete`d once, recent file not (control in same run); exactly one log line, 6 tab fields,
    field 4 the path, field 6 `deleted`.
  - **P5 handle checks, each with an eligible sibling deleted in the same run (positive control):** NotFound → `skipped: no
    longer exists`; directory, reparse → `skipped: not a regular file`; `LinkCount 2` → `skipped: hard-linked`; `FinalPath`
    outside → `skipped: outside target`; length differs, time differs → `skipped: changed since scan`; none of them `MarkDelete`d.
  - **P6 failures continue:** `Open` returns `Failed("used by another process")` → `failed: used by another process`; `Open`
    throws `UnauthorizedAccessException` → `failed: ...`; `MarkDelete` throws `IOException` → `failed: ...`; next file deleted;
    totals Failed 3, Deleted 1.
  - **P7 outside / bad name:** a path not under the target and `C:\t\app.log.` (trailing dot) → `skipped: outside target`,
    never passed to `Open`.
  - **P8 log failure and cancel:** `log` throws on the first line → later files `not attempted: log write failed`, no further
    `Open`; cancel after the first file → rest `not attempted: cancelled`.
  - **P9 renderers:** text `[would delete]`; HTML `<th>Purge</th>`/`class="purge"` only with statuses, and no-purge HTML,
    text, JSON and CSV equal fixed expected strings captured on M7 for the same input (positive control); JSON `purgeStatus`
    only when set; CSV every row has the same field count with purge.

Windows (`tests/Dirused.Tests/ProgramPurgeTests.cs`, real files in a scratch temp dir; assert the dir is under
`Path.GetTempPath()` first; log path in the same dir; compare exit codes to a baseline run without `/purge` on the same dir,
since the temp volume's fullness may give 4):
- **WP1:** `a.log` (3 KB, 3 days old), `big.log` (5 KB, 3 days old), `b.log` (8 KB, now), `c.txt` (4 KB, 3 days old).
  Dry run `[dir, "/largest", "*.log", "/purge"]`: all four exist, stdout lists `b.log` `[skipped: modified within 1 day(s)]`,
  `big.log` and `a.log` `[would delete]`; no log file. Then `[dir, "/largest", "*.log", "/largestcount", "2", "/purge",
  "/confirm"]`: `big.log` gone; `b.log` (listed, skipped), `a.log` (not listed: count 2) and `c.txt` exist; log has exactly
  one line, for `big.log`, ending `deleted`; stderr `Purge: deleted 1 file(s)`. A second confirm run appends (log now 2+ lines,
  first line unchanged).
- **WP2:** a file held open with `FileShare.None` by the test → `failed: ...`, file still exists, exit 3 (or baseline 4).
- **WP3:** a log path under an existing *file* with `/confirm` → exit 1, `nothing was scanned or deleted`, all files exist.
- **WP4:** a hard link (`CreateHardLinkW`) to an old `.log` → `skipped: hard-linked`, both names exist.
- **WP5:** a directory junction inside the target pointing outside (`mklink /J` via `cmd /c`, skip the test with a reason if
  creation fails) to a folder holding an old `.log`: the outside file still exists after `/confirm`.

**Red proof (paste each):** P1 fails on main (`not available yet (M2)`). For N1-N5, one mutation each, with the failing test
pasted, then reverted: (a) dry-run branch removed → P3/WP1; (b) cutoff check removed → P3/P4; (c) handle checks removed →
P5/WP4; (d) `IsStrictlyUnder` returns true → P2/P7; (e) log open made lazy (after scan) → WP3; (f) match-all check removed → P1.

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

- `Options` (positional record): constructed at `ArgParser.cs:173,192` only; new fields at the end with defaults.
- `/purge` stub: `ArgParser.cs:102` and `ArgParserTests.cs:49` (both change).
- `LargestFile` / `LargestFiles`: constructed in `Largest.cs` (`Snapshot`), `LargestTests.cs` (3), `TopFoldersTests.cs` (1);
  copied by `TopFolders.cs:29`. Init-only properties keep every call valid.
- `ScanResult.Target` (containment root): written by `Scanner.cs:46-47`, `Program.cs` error results, `RemoteScan`, `ScanRunner`;
  the handle check compares final paths, so a display-spelling difference fails safe (skipped), never deletes.
- Largest rendering: `TextRenderer.cs:78-84` (also via `SummaryRenderer.cs:18`), `HtmlRenderer.cs:76-86`, `CsvRenderer.cs:11`
  and `Format.Row`, `JsonRenderer`.
- Usage: `UsageText`, `ShortUsageText`; exit codes in README; `FleetRunnerTests`/`ProgramHtmlTests` assert 0/3/4 (unchanged without `/purge`).

## What NOT to Do

- Do not delete anything not in a `/largest` list, follow links, delete directories, or delete by path without the locked handle.
- Do not delete in parallel, or before the log is open.
- Do not change output, JSON, CSV or exit codes for runs without `/purge`.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "`/largest <patterns> /purge` without /confirm deletes nothing and marks each listed file would delete or skipped with a reason"
  - id: M2
    text: "`/purge /confirm` deletes only listed, unlinked, unchanged regular files inside the target last modified more than [days] days ago (default 1), logs each, and goes on past a failed file"
  - id: M3
    text: "`/help` explains /purge, /confirm, the dry-run default, the log and three examples"
must_not:
  - id: N1
    text: "a dry run opens or deletes a file (P3, WP1) — mutation (a)"
  - id: N2
    text: "a file modified within [days], changed since scan, linked, hard-linked, vanished, or outside the target is deleted (P3-P7, WP1, WP4, WP5) — mutations (b)-(d)"
  - id: N3
    text: "/purge accepted with a match-all pattern, default patterns, or without /largest; /confirm without /purge (P1) — red on main, mutation (f)"
  - id: N4
    text: "/confirm deletes when the log cannot be opened, or keeps deleting after a log write fails (WP3, P8) — mutation (e)"
  - id: N5
    text: "output without /purge changes (P9 positive control)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3, N4, N5]
    kind: offline
    command: portable suite (P1-P9) locally and on PR CI; Windows CI for WP1-WP5; P1 red on main; mutations (a)-(f) red
    intent: Purge only ever deletes old, unchanged files from the /largest list, shows you first, and writes down what it deleted.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    command: "operator, work laptop: `dirused /help` shows the purge text; scratch folder C:\\temp\\purgetest with an old and a new .log: `dirused C:\\temp\\purgetest /largest *.log /purge`, then with /confirm; then only a dry run on \\\\us03p02ffm01\\d$ with `/largest *.log /purge 7`, read the list before any /confirm"
    intent: On your laptop, try purge on a throwaway folder first, then see what it would remove on ffm01 before deleting anything there.
interface:
  - "/purge requires /largest"
  - "/confirm requires /purge"
  - "/purge requires /largest with file patterns, e.g. /largest *.log"
  - "/purge cannot be used with a match-all pattern; name the file types to delete, e.g. /largest *.log"
  - "/purge requires a number of days from 1 to 3650"
  - "put the number of days right after /purge (e.g. /purge 7)"
  - "Purge: deleted N file(s), SIZE freed; S skipped; F failed; A not attempted. Log: PATH"
  - "log line: ISO-UTC<TAB>user<TAB>machine<TAB>path<TAB>bytes<TAB>status"
```

## Amendment 1 (Claude, 2026-11-18, blind Fable + Astra review; folded into rev 2 above)

- Fable 1-4, Astra 1-4: delete through an exclusive handle on the `\\?\` path after re-checking type, link count, final path,
  size and time; trailing-dot/space names skipped; explicit patterns required; any match-all refused; stray digits rejected.
- Astra 6, Fable 6: log opened before `/output`, never truncated, collision refused; Stat/Open errors per file; log-write
  failure stops purging and still renders.
- Astra 5, 7, 11, Fable 7-10: `/largestcount` test, mutation red proofs, pure-string containment for Linux CI, baseline exit
  codes, non-vacuous WP1 control, `:102` stub and `:49` test row.
- Astra 8, 9, 12, 13, Fable 11-12: `<` cutoff (equal skipped), `/summary /csv` rejected without `/html`, CSV field counts,
  cancel → `not attempted`, `PurgeRun.Results`, per-line log time, `ShortUsageText`.
- Not adopted: Astra 1's file-ID identity (the scanner does not record IDs; size + time + exclusive lock + final path is the
  chosen identity check).

## Amendment 2 (operator, 2026-11-18, after dispatch): size threshold `/minsize`, default 1 GB

Operator, looking at the v0.0.17 HTML report (116.7 GB red, 9.8 GB and 7.2 GB amber, 621.8 MB plain): "when we purge,
probably only want to purge the largest or we can specify threshold ... said purge file that is large than 100MB or 999MB
for example. we should be able to override this threshold". Answers: default **1 GB**; syntax **`/minsize <size>`**.

- **`Options`:** add `long PurgeMinBytes = 1L << 30` (after `Confirm`).
- **`ArgParser`:** `case "minsize"`: the next argument must match `^[0-9]+(KB|MB|GB|TB)$` (ordinal ignore-case, units 1024-based
  like `Format.Size`; no bare numbers), value 1 or more and not overflowing `long`, else
  `Error: "/minsize needs a size like 100MB or 2GB"`. After the loop, before rule 1: `/minsize` without `/purge` →
  `"/minsize requires /purge"`. (A missing argument, or a following switch, gives the same `needs a size` error.)
- **Engine:** `Purge.Apply(..., int days, long minBytes, bool confirm, ...)`. New rule between rule 3 and rule 4 (scan-time
  size, no file opened): `file.LogicalBytes < minBytes` → `skipped: smaller than {Format.Size(minBytes)}`. A file of exactly
  `minBytes` is eligible. The handle size check (rule 6, `changed since scan`) is unchanged.
- **Help text:** the `/purge` entry becomes
  ```
    /purge [days]       Delete the files /largest lists that were last
                        modified more than [days] days ago (default: 1)
                        and are at least /minsize big (default: 1GB).
                        Needs /largest with file patterns. Without /confirm
                        this is a dry run: nothing is deleted, the report
                        shows what would be.
    /minsize <size>     With /purge: smallest file to delete, e.g. 100MB,
                        999MB, 2GB (default: 1GB)
  ```
  (`/confirm` entry unchanged.) Examples: the second becomes `dirused D:\ /largest *.log /purge /confirm` /
  `Delete the listed .log files of 1GB or more not modified in the last day`; add
  `dirused D:\ /largest *.log /purge /minsize 100MB` / `Dry run: also include listed .log files from 100MB`. The closing
  paragraph's first sentence becomes "Purge only deletes files in the /largest list. It skips files smaller than /minsize,
  files modified within [days], ...". `ShortUsageText` third line: `[/largest <patterns> [/purge [days] [/minsize <size>] [/confirm]]]`.
- **README / CHANGELOG:** `/minsize` and the 1 GB default in the `/purge` section and the CHANGELOG line ("... older than days
  (default 1) and at least `/minsize` (default 1GB) ...").
- **Interface additions:** `"/minsize needs a size like 100MB or 2GB"`, `"/minsize requires /purge"`,
  `"skipped: smaller than SIZE"`.

Tests:
- **P1:** `/purge` alone → `PurgeMinBytes == 1L << 30`; `/minsize 100MB` → `100L << 20`; `999mb`, `2GB`, `1KB` accepted;
  `/minsize` errors for `100`, `1.5GB`, `0MB`, `-1GB`, `9999999999TB`, missing value, followed by `/confirm`; `/minsize 1GB`
  without `/purge` → `/minsize requires /purge`. `UsageText` contains the new lines exactly.
- **P3 (dry run) adds:** with `minBytes = 1L << 30`, files of `(1L << 30) - 1` → `skipped: smaller than 1.0 GB` and exactly
  `1L << 30` → `would delete` (both old); same run with `minBytes = 100L << 20`: the `(1L << 30) - 1` file → `would delete`.
- **P4 (confirm):** the small old file is not `MarkDelete`d and not logged; the big old file is (control in the same run).
- **Windows WP1-WP5:** their files are KB-sized, so every WP run passes `/minsize 1KB`. **WP6:** `[dir, "/largest", "*.log",
  "/purge", "/confirm"]` with no `/minsize` on WP1-style files → nothing deleted, each listed old file
  `[skipped: smaller than 1.0 GB]` (default applied end to end); the same run with `/minsize 1KB` deletes (positive control).
- **Mutation (g):** size rule removed → P3/P4/WP6 red; paste it.
- **Acceptance:** M2 gains "and at least /minsize (default 1GB)"; new must_not **N6**: "a listed old file smaller than
  /minsize is deleted or marked would delete (P3, P4, WP6) — mutation (g)".

**Amendment 2 intent approved:** operator, 2026-11-18 ("1 GB (Recommended)", "/minsize <size>").

## Amendment 3 (Claude, 2026-11-18, after resume 2: Claude review + blind Fable diff review; Claude adjudicated)

Verified in the worktree before adopting: the root is opened through the file `Open` (DELETE, share 0); `ScanResult.Target` is
`target.Display` (`RemoteScan.cs:15`) while file paths come from `Path.GetFullPath` (`Scanner.cs:39`); `+` patterns set
`largestExplicit` (`ArgParser.cs:193`) and merge with the defaults; the scanner skips reparse points (`Scanner.cs:128`), so WP5
can never list the outside file. None of these deletes a protected file; 1-2 make `/confirm` delete nothing in practice.

**Files added to scope:** `src/Dirused.Common/ScanResult.cs`, `src/Dirused.Core/Scanner.cs` (item 2 only), and
`tests/Dirused.Tests.Portable/FleetRunnerTests.cs` (accepted in resume 2). Land records `--allow-out-of-scope` for these.

1. **Root open (blocker).** Add `string? ResolveRoot(string path, out string? error)` to `IPurgeFileSystem`. Real impl:
   `CreateFileW` with access `FILE_READ_ATTRIBUTES` only, share `READ|WRITE|DELETE`, `FILE_FLAG_BACKUP_SEMANTICS` (follow a
   junction root), then `GetFinalPathNameByHandleW`; never `MarkDelete`. When it returns null, every listed file of that target
   that would otherwise be opened gets `failed: cannot open target: {error}` (counted failed, exit 3). Dry run does not call it.
   **WP7:** with a `FileSystemWatcher` running on the scratch dir (it holds a shared directory handle) and the process working
   directory set to it (restore in `finally`), `/confirm` deletes `big.log`. Red on resume-2 code (paste it, Windows CI on a
   scratch branch is acceptable — say which run).
2. **Containment root = scanned full path.** `ScanResult` gains `[JsonIgnore] public string? ScanRoot { get; init; }`, set in
   `Scanner.Scan` to the full path it scanned (`full`, `Scanner.cs:39`). `Purge` uses `ScanRoot ?? Target` for rule 1 and
   `ResolveRoot`. `RemoteScan`'s `with { Target = ... }` keeps `ScanRoot`. JSON unchanged. Tests: rule 1 with `Target` `"."`,
   `"D:"`, `"//h/s"` and a `ScanRoot` set → eligible; `ScanRoot` null and `Target` `"."` → `skipped: outside target`.
3. **No `GetFullPath` in `Open`/`ResolveRoot`.** Build the `\\?\` form exactly as `Scanner.Extended` (`Scanner.cs:196`):
   prefixing only; a non-absolute path (fails `IsStrictlyUnder`'s absolute test) → `failed: path is not absolute`.
4. **`+` patterns refused with `/purge`.** After rule 4: any pattern argument item starting with `+` →
   `"/purge needs the full pattern list; '+' adds to the default list, e.g. write /largest *.log;*.zip"`. P1: `+*.zip` refused,
   `*.log;*.zip` accepted.
5. **Log before the delete commits.** Order on the locked handle: checks → `MarkDelete()` → write the log line (status
   `deleted`) → dispose. If the log write throws: `UnmarkDelete()` (`FileDispositionInfo` false) before dispose, status
   `failed: log write failed`, file kept, then stop as before. `PurgeOpen` gains `UnmarkDelete()`. P8: the file whose log line
   fails is NOT deleted (fake records Mark then Unmark) and later files are `not attempted: log write failed`.
6. **Confirm the delete.** After dispose, `fs.Open(path)` again (or a `Exists` probe on the extended path): not found →
   `deleted`; still present → `failed: delete pending (another process has the file open)`, and the log gets a second line with
   that status. A `FILE_ATTRIBUTE_READONLY` file → `skipped: read-only` (checked on the handle before `MarkDelete`; attribute
   0x1). P5 adds read-only; P6 adds delete-pending via the fake.
7. **WP5 rewritten** to exercise the real final-path check: pass `fs` = a decorator over `RealPurgeFileSystem` that, on the
   first file `Open`, renames the scanned subfolder away and creates a junction with the same name to an `outside` folder holding
   a file with the same name, size and last-write time; assert `skipped: outside target` and the outside file still exists.
   Positive control: without the swap the inside file is deleted. Skip with a reason if junction creation fails.
8. **UNC test WP8:** WP1's confirm run against `\\localhost\{drive}$\...` of the scratch dir (skip with reason if the admin
   share is unreachable); asserts `big.log` deleted and the log line.
9. **WP1/WP3 strengthened:** WP1 asserts every status the spec lists (`b.log [skipped: modified within 1 day(s)]`, which are
   `[would delete]`), files present after the dry run, log line names `big.log` and ends `deleted`; exit codes compared to a
   no-`/purge` baseline run on the same dir. WP3 uses an `fs` decorator that counts calls and asserts zero `Open`/`ResolveRoot`
   calls and that stdout has no report (nothing scanned).
10. **P9 and P1 completed:** P9 HTML `<th>Purge</th>`, `class="purge"`, group `colspan="5"`, `would free`/`freed` headings; JSON
    `purgeStatus` only when set; CSV equal field counts with purge and the header from the flag (item 16); no-purge text, HTML
    (with a fixed `Generated` line removed before comparing), JSON and CSV equal fixed strings for one fixed input (N5). P1 adds
    `/purge 3651`, `/purge /confirm 7`, `/summary /csv /largest *.log /purge`, `/output C:\temp\dirused-purge.log /purge /confirm`,
    `/confirm` help lines and the "Purge examples" block exactly.
11. **P/Invoke:** `FileDispositionInfo.DeleteFile` as `[MarshalAs(UnmanagedType.U1)]`, size 1; remove unused `FileTime`; treat
    `len >= capacity` as failure; wrap everything after `CreateFileW` in try/dispose so an exception never leaks the handle.
12. `IsStrictlyUnder`: a root with zero segments → false.
13. A listed file whose path equals the purge log path (ordinal ignore-case) → `skipped: purge log`.
14. Log fields: replace `\t`, `\r`, `\n` in path and status with a space.
15. `/summary /csv` rule uses the effective summary value (as the renderer chooses), not the raw flag.
16. CSV purge column chosen by a flag passed from `Program` (`/purge` given), not inferred from results; keep `Format.Row`
    (revert the inlining) and append the field.
17. `ShortUsageText`: wrap so every line is ≤ 80 columns (fourth line `               [/largest <patterns> [/purge [days] [/minsize <size>] [/confirm]]]`
    with the third line ending before `/largest`); restore the 80-column test without the exemption.
18. `GetFinalPathNameByHandleW`: if flags 0 fails for the root, use `FILE_NAME_OPENED` (0x8) for the root **and** all files of
    that target, so both sides use the same form.
- **Mutation proofs to add/redo:** (h) root opened via file `Open` again → WP7 red; (i) log after dispose (item 5 reverted) → P8
  red; (j) WP5 decorator with handle final-path check removed → WP5 red. Windows-only reds may be shown from Windows CI on a
  scratch branch `m8-purge-mut-*` (name the run); delete those branches after.
- **Acceptance:** must_not N2 gains "a file is deleted without a log line (P8, mutation (i))"; new N7: "`/confirm` on a target
  whose root another process has open deletes nothing (WP7, mutation (h))".
- Not adopted: none. Item 4 narrows operator-visible behaviour within "when /largest specific"; operator told in chat.

**Intent approved:** operator, 2026-11-18
**Intent approval note:** answers to Claude's questions: listed files only (refuse '*'), skip modified < 24 h with /purge N days, permanent delete with failures reported, report + C:\temp\dirused-purge.log; plus "make clear help message for how /purge work". Rev 2 narrows (explicit patterns required); operator told in chat.
