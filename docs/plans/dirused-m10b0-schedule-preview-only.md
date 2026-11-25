# dirused M10b0: `/schedule` preview only (demo build, nothing is scheduled)

**Status:** LIVE-VERIFIED — dirused PR #40 merged `966b32b`, v0.0.27; E-B0L passed on the jump box 2026-11-24 (operator)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §1–§3 and §4.1–§4.3 (preview subset). Ships before M10b1–M10b4; M10b2 builds on it.
**Repo / branch:** wilddog64/dirused / `m10b0-schedule-preview` from `main` (`a2d0508`)
**Risk:** low — parser and output only; no task, no plan folder, no file written, no server touched
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** rev 2 keeps the three approved intents unchanged; E-B0L's command changed (schtasks before/after capture), not its intent.
**Approval:** operator, 2026-11-24 — "but I need schedule print out to demo"; "do (a) and (b). It need to be secure but not over restricted"
**Proofs:** P7 answered (jump box `Pacific Standard Time`, 2026-11-24). No other proof gates this child: it calls no Windows API.

## Why

The operator demos dirused to the team before anyone runs a scheduled purge. The demo needs the printout: when the run would
happen, against which server, how many files and how much space, and that nothing happens until `/confirm`. Task creation (M10b2,
M10b3) waits on the jump-box probes, so the preview ships alone first.

## Where the logic lives (testability)

All behaviour is in `Dirused.Common`, so `Dirused.Tests.Portable` (Common only, runs on ubuntu and macOS) tests it:

```csharp
public static int Schedule.Run(Options options, ParsedPurgeList list, string listPathAsTyped,
    TextWriter stdout, TextWriter stderr, Func<DateTimeOffset> now, TimeZoneInfo local)
```

`Schedule.Run` writes every line and returns the exit code. It takes **no** file reader, file system, service query or input reader,
and must not call `File.*`, `Directory.*`, `Console.*` or any I/O API: the list arrives already parsed. Every B0 test calls
`Schedule.Run` or `ArgParser.Parse` from Portable.

`Program.cs` change: immediately after the list read at `Program.cs:71` (line numbers at `a2d0508`) and before the Windows guard at
`:72`, add `if (options.ScheduleTime != null) return Schedule.Run(options, parsedList!, options.FromList, output, error,
() => DateTimeOffset.Now, TimeZoneInfo.Local);`. Nothing else in Program.cs changes. Pre-existing: `CleanupUpdateFiles()`
(`Program.cs:30`) runs on every packaged invocation and is unchanged; "writes nothing" below means nothing beyond that.

## Scope

1. **Parser** (`ArgParser.cs`). Add `schedule` to `KnownSwitches`. Parent §2 rows **7–11 only**, as a pre-check before both parser
   branches, in order 7 → 8 → 9 → 10 → 11, with their exact strings. `list`, `cancel` and `runplan` are **not** added. The `/fromlist`
   branch consumes the token after the time as the zone only when it is `PT`, `PST`, `PDT` or `UTC` (case-insensitive, once), stored
   upper-case in `Options.ScheduleZone`; any other non-switch token there (`/schedule 22:30 BOGUS`) gets the new whitelist text
   `/fromlist can only be combined with /purge, /confirm, /html, /output, /json, /csv, /yes and /schedule`. `Options` gains, appended
   last and defaulted: `string? ScheduleTime = null, string? ScheduleZone = null`.
   Exact results for forms M10b2 will own later: `/schedule /list` and `/schedule /cancel x` → `/schedule requires /fromlist` (row 8);
   `/fromlist l /purge /schedule 22:30 /list` → `Unknown switch: /list` (`list` stays unknown).
2. **Usage.** `UsageText` only, immediately after the `/fromlist <file>` line (`ArgParser.cs:69`):
   `  /schedule <time>    With /fromlist /purge: preview a one-time run at HH:MM` /
   `                      [PT|PST|PDT|UTC]; add /confirm to schedule it`. `ShortUsageText` is unchanged.
3. **Time** (parent §3 in full) with these exact rules:
   - The run instant has seconds and fractions zero. `created` = `now()` as given (it may have seconds).
   - Reject when `run - created < TimeSpan.FromMinutes(2)`; reject when `run - created > TimeSpan.FromMinutes(23 * 60 + 45)`.
     Exactly 2 min and exactly 23 h 45 min are accepted.
   - `Run:` and `Expires:` always print in Pacific (`Pacific Standard Time`, falling back to `America/Los_Angeles`) whatever zone
     was typed, with `PST` or `PDT` from `IsDaylightSavingTime` at that instant, then `(HH:mm UTC ddd)`; format
     `ddd yyyy-MM-dd HH:mm` with invariant culture.
   - `in ...`: whole minutes `m = floor((run - created).TotalMinutes)`; under 60 → `in <m> min`; otherwise
     `in <h> h <m%60> min` (so `in 2 h 0 min`).
   - The §3 error messages use `<date>` = `yyyy-MM-dd` and `<HH:MM>` as typed; they go to stderr, exit 1, no preview.
4. **Order.** Program has already read the list (not a list → the existing message, exit 1). `Schedule.Run` then checks, in order:
   no file rows → `/schedule: the list has no files to delete` (stderr, exit 1); more than one host → the O8 message (stderr, exit 1);
   time rules (stderr, exit 1); then prints the preview.
5. **Host**, from each row's `Path` (`LargestFile.Path`, not `ListTarget`):
   - `\\host\...`, `\\?\UNC\host\...` and `//host/...` → `host`.
   - A drive-letter path (`C:\...`, `\\?\C:\...`) → `this machine`.
   - Hosts compare case-insensitively. The displayed name is the first-seen spelling, and lists are in first-seen order joined
     by `, `.
   - A mix of `this machine` and a UNC host counts as two hosts:
     `/schedule: the list covers more than one host (this machine, hostA); save one list per host and schedule each`.
6. **Preview** (stdout, every line ≤ 80 columns):
   ```
   Scheduled purge preview (nothing is scheduled yet)
     Run:      Mon 2026-11-23 22:30 PST (06:30 UTC Tue), in 1 h 30 min
     Expires:  Tue 2026-11-24 21:00 PST (05:00 UTC Wed)
     Host:     us03p02ffm01
     List:     C:\Users\op\m10b.txt
               12 file(s), 176.2 GB
     Held:     not checked now; files held open at run time are skipped
   It runs only while you are logged on to this machine (disconnected is fine).
   Preview only. Add /confirm to schedule it.
   ```
   - `List:` shows `listPathAsTyped` exactly. When `"  List:     " + path` exceeds 80 columns, the path is hard-split every 68
     characters; each continuation line is 12 spaces plus the next ≤ 68 characters. Only `List:` wraps.
   - Size uses `Format.Size` (`src/Dirused.Common/Renderers/Format.cs:6`) over the sum of the rows' `LogicalBytes`.
   - The parent's `Task`, `Plan dir`, `Program` and `sha256` lines are not printed here; M10b2 adds them.
   - Bad list lines (`list.Errors`): after the preview, the same block `/fromlist` prints on stderr (`Bad list lines:` then
     `  line <n>: <reason>`, as `Program.cs:224`), and exit 3, matching the `/fromlist` dry run.
7. **`/confirm`** (with or without `/yes`): the preview without its last line, then on stderr
   `/schedule /confirm is not available in this version; nothing was scheduled`, exit 1. No question, no input read.
   `/yes` without `/confirm` keeps `/yes needs /purge /confirm`.
8. **Docs:** `docs/purge.md` gains a "Scheduled purge (preview)" section that opens with "This version only previews; scheduling
   comes in a later version", then the form, the zones, the 2 min / 23 h 45 min rules and the example output above. `README.md`
   usage block gains the two usage lines. `CHANGELOG.md` `[Unreleased]`: `/schedule` preview.

## Files

- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Options.cs`
- `src/Dirused.Common/Schedule.cs` (new)
- `src/Dirused.Cli/Program.cs`
- `tests/Dirused.Tests.Portable/ScheduleTests.cs` (new)
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `tests/Dirused.Tests.Portable/PurgeListTests.cs`
- `docs/purge.md`
- `README.md`
- `CHANGELOG.md`

## Contract readers

- Whitelist text `ArgParser.cs:121` → the new text; reader `PurgeListTests.cs:102` updated here.
- `/yes needs /purge /confirm` `ArgParser.cs:137`, `:263`; readers `ArgParserTests.cs:310,311,313`; usage `:73` — unchanged.
- `ArgParserTests.cs:249-252` (80 columns) — the new usage lines must pass it.
- `KnownSwitches` `ArgParser.cs:16` — one new name, `schedule`.
- `Options` constructions `ArgParser.cs:139`, `:291` and tests — two new fields last, defaulted.
- `Program.cs:71-72` — one new line between the list read and the Windows guard.

## What NOT to Do

- Do not register a task, run `schtasks`, create any folder or write any file.
- `Schedule.Run` must not call any I/O API (`File`, `Directory`, `Console`, `Process`, registry); no reader or fs parameter.
- Do not add `list`, `cancel` or `runplan`; do not ask `Schedule this?`.
- Do not change `Purge.cs`, `PurgeList.cs`, `ShortUsageText`, or the existing `/fromlist` dry-run and delete paths.
- Leave changes uncommitted; do not push.

## Acceptance

Baseline note: on `a2d0508` the new tests do not compile (`Schedule.Run`, `Options.ScheduleTime` missing). "Red on a2d0508"
means that compile failure for the new tests, plus behavioural red where stated (the parser rows run against today's `ArgParser`).

```yaml
must:
  - id: B0-M1
    text: "Schedule.Run with now = Mon 2026-11-23 21:00:30 -08:00, local = Pacific, options from '/fromlist l.txt /purge /schedule 22:30', a parsed list of 12 rows under \\\\us03p02ffm01 totalling 176.2 GB, listPathAsTyped 'l.txt': stdout is exactly the preview (Run 'Mon 2026-11-23 22:30 PST (06:30 UTC Tue), in 1 h 29 min', Expires 'Tue 2026-11-24 21:00 PST (05:00 UTC Wed)', Host, 'List:     l.txt', '12 file(s), 176.2 GB', Held, logged-on line, 'Preview only. Add /confirm to schedule it.'), stderr empty, every line <= 80 columns, exit 0"
  - id: B0-M2
    text: "time: 20:00 at 21:00 → tomorrow; PT, PST, PDT and UTC instants (printed in Pacific with PST/PDT by date); bare time with local UTC exits 1 with the not-on-Pacific message, with local id America/Los_Angeles is accepted; spring-forward 02:30 PT and fall-back 01:30 PT exit 1 with their messages (date yyyy-MM-dd); 01:30 PDT on fall-back day accepted; exactly 2 min accepted, 1 min 59 s rejected; exactly 23 h 45 min accepted, 23 h 45 min 1 s rejected; 'in 45 min', 'in 2 h 0 min'; each error on stderr, stdout empty"
  - id: B0-M3
    text: "ArgParser: rows 7-11 each give their exact error (one test per row, and order: '/schedule 22:30 /schedule 23:00' without /fromlist gives row 7); '/fromlist l /purge /schedule 22:30 /yes' gives '/yes needs /purge /confirm'; '/fromlist l /purge /schedule 22:30 BOGUS' and '/fromlist l /purge /bogus' give the new whitelist text; '/schedule /list' and '/schedule /cancel x' give '/schedule requires /fromlist'; '/fromlist l /purge /schedule 22:30 /list' gives 'Unknown switch: /list'; zone 'pst' stored as 'PST'; both new UsageText lines <= 80 columns and placed right after the /fromlist line; ShortUsageText unchanged"
  - id: B0-M4
    text: "options with /confirm, and with /confirm /yes: stdout is the B0-M1 preview without its last line; stderr is exactly '/schedule /confirm is not available in this version; nothing was scheduled'; exit 1"
  - id: B0-M5
    text: "host: drive-letter rows show 'Host:     this machine'; \\\\?\\UNC\\h1\\x and //h1/x rows count as h1; rows on \\\\hostA and \\\\HOSTB exit 1 with '(hostA, HOSTB)' in first-seen order and no stdout (positive control: a hostA-only list previews); rows differing only in case show the first-seen spelling; a C:\\ row plus a \\\\hostA row exits 1 with '(this machine, hostA)'; a list with no file rows exits 1 '/schedule: the list has no files to delete'"
  - id: B0-M6
    text: "a 150-character listPathAsTyped wraps: first line '  List:     ' + 68 characters, continuation lines 12 spaces + <= 68 characters, the pieces joined equal the path; a list with 2 bad lines prints the full preview, then 'Bad list lines:' and both '  line <n>: <reason>' lines on stderr, exit 3"
  - id: B0-M7
    text: "docs/purge.md has the 'Scheduled purge (preview)' section opening with the preview-only sentence and the example output; README usage has the two lines; CHANGELOG [Unreleased] names the /schedule preview"
must_not:
  - id: B0-N1
    text: "Schedule.Run touches the file system: a test passes listPathAsTyped and row paths that point into a fresh temp dir where none of them exist, snapshots the temp dir (names, sizes, mtimes) before and after, and asserts the preview was printed and the snapshot is identical; a source scan of Schedule.cs finds no 'File.', 'Directory.', 'Console.', 'Process.' or 'Registry'. Positive control: the same snapshot test turns red for mutant 'File.WriteAllText(listPathAsTyped + \".seen\", \"\")', and the scan turns red for mutant 'File.Exists(row.Path)'. Baseline: compile failure on a2d0508 (Schedule.Run absent)"
  - id: B0-N2
    text: "the list is read again or a row is opened: covered structurally by B0-N1 (no I/O API and nonexistent paths still preview). Mutant 'File.ReadAllLines(listPathAsTyped)' inside Schedule.Run turns B0-N1 red (scan, and FileNotFoundException on the nonexistent path)"
evidence:
  - id: E-B0
    proves: [B0-M1, B0-M2, B0-M3, B0-M4, B0-M5, B0-M6, B0-N1, B0-N2]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable (ubuntu or macOS); CI also runs it on windows-latest. New tests fail to compile on a2d0508; parser-row tests red against today's ArgParser. Mutants each red: PST treated as DST-aware; passed time stays today; 23h45m check uses >= ; 2 min check uses <= ; bare time accepted off Pacific; IANA id not recognised; multi-host check skipped; host compared case-sensitively; \\\\?\\UNC form not recognised; /confirm keeps the 'Preview only' line; wrap at 80 instead of 68; File.WriteAllText in Schedule.Run; File.ReadAllLines in Schedule.Run"
    intent: "You type /schedule with a time and see exactly when the purge would run (Pacific and UTC, and how long from now), which server, how many files and how much space — and nothing is scheduled, written or touched on the server. Adding /confirm tells you scheduling is not in this version yet."
  - id: E-B0D
    proves: [B0-M7]
    kind: offline
    command: "git diff shows docs/purge.md, README.md and CHANGELOG.md updated; the purge.md example matches the B0-M1 layout"
    intent: "The guide shows the same printout you will demo, and says plainly that scheduling itself comes in a later version."
  - id: E-B0L
    proves: [B0-M1, B0-M4]
    kind: live
    command: "operator, jump box, from the PR build: 'schtasks /query /fo list | findstr /i dirused' before; dirused /fromlist <a saved list> /purge /schedule 23:00 shows the preview with Host us03p02ffm01 and tonight's run time; the same with /confirm prints the not-available line; the same schtasks capture after shows no new dirused task"
    intent: "On the jump box you see the real printout for tonight against the real Tomcat list, and confirm afterwards that no task was created."
interface:
  - "/schedule <time> [PT|PST|PDT|UTC]"
  - "Schedule.Run(Options, ParsedPurgeList, string, TextWriter, TextWriter, Func<DateTimeOffset>, TimeZoneInfo) -> int"
  - "Scheduled purge preview (nothing is scheduled yet)"
  - "Preview only. Add /confirm to schedule it."
  - "/schedule /confirm is not available in this version; nothing was scheduled"
  - "/schedule: the list has no files to delete"
  - "/schedule: the list covers more than one host (<hosts>); save one list per host and schedule each"
  - "/schedule: this machine is not on Pacific time; add PT, PST, PDT or UTC to the time"
  - "/schedule: <date> <HH:MM> does not exist in Pacific time (clocks go forward); pick another time"
  - "/schedule: <date> <HH:MM> happens twice in Pacific time; write PST or PDT"
  - "/schedule: <HH:MM> is less than 2 minutes away; pick a later time"
  - "/schedule: <HH:MM> is too far away; the plan expires 24 h after it is made, so pick a time within 23 h 45 min"
  - "/schedule can be given only once"
  - "/schedule requires /fromlist"
  - "/schedule requires a time, e.g. /schedule 22:30 PT"
  - "/schedule: time must be HH:MM (00:00-23:59), optionally followed by PT, PST, PDT or UTC"
  - "/schedule can only be combined with /fromlist, /purge, /confirm and /yes"
  - "/fromlist can only be combined with /purge, /confirm, /html, /output, /json, /csv, /yes and /schedule"
```

## Review adjudication (rev 1, 2026-11-24)

Fable (`claude-fable-5-2`): NEEDS REWORK. Argon (`gemini-4-argon-medium`): READY WITH FIXES.

| Finding | Source | Action |
|---|---|---|
| Exit codes, stderr and `/confirm` untestable in Program (Cli is Windows-only; no clock seam) | Fable 1 | Applied: `Schedule.Run` in Common owns all output and exit codes; Program is one line |
| N1/N2 fakes do not exist at the testable layer; no counting reader without changing `PurgeList.cs` | Fable 2, Argon 6 | Applied: structural — no I/O API, nonexistent paths, temp-dir snapshot, source scan, named mutants |
| `/schedule /list` "rejected as before" contradicts row 8 | Fable 3 | Applied: exact strings in Scope 1 and B0-M3 |
| Boundary mutants survive 23h44/23h46 | Fable 4, Argon 4 | Applied: exact 2 min and 23 h 45 min cases |
| Bad list lines unspecified | Fable 5, Argon 5 | Applied: same block on stderr after the preview, exit 3 (B0-M6) |
| `/confirm` keeps "Preview only" line? | Fable 6 | Applied: dropped under `/confirm` |
| `List:` path form; wrap rule | Fable 7-8, Argon 5 | Applied: as typed; hard split at 68; only `List:` wraps |
| Host forms, order, casing, mixed local+UNC | Fable 9, Argon 5 | Applied: Scope 5 |
| PST/PDT source, rounding, whole hours, date format, error streams, order | Fable 10, Argon 4 | Applied: Scope 3-4; five §3 strings added to `interface` |
| Usage placement; `ShortUsageText` is a synopsis | Fable 11, Argon 2 | Applied: `UsageText` only, after `/fromlist` |
| `22:30 BOGUS` result; zone casing | Argon 3 | Applied: whitelist text; stored upper-case |
| Windows guard line | Fable 12 | Applied: insert between `:71` and `:72` |
| `CleanupUpdateFiles` carve-out | Fable 13 | Applied: noted as pre-existing |
| `schtasks /query /tn \dirused\` unproven; compile-fail baseline | Fable 14 | Applied: before/after `findstr` capture; baseline note |
| Demo wording "add /confirm" vs not available | Fable 15 | Applied: docs open with the preview-only sentence |

## Live check 2026-11-24 (operator, office jump box, v0.0.27 win-x64)

- `dirused /update` → `updated dirused 0.0.26 -> 0.0.27`; `/version` → `dirused 0.0.27 (win-x64)`.
- `schtasks /query /fo list | findstr /i dirused` before: no output.
- `dirused /fromlist m9a.txt /purge /schedule 00:30` → preview: `Run: Wed 2026-11-25 00:30 PST (08:30 UTC Wed), in 15 h 27 min`,
  `Expires: Wed 2026-11-25 09:02 PST (17:02 UTC Wed)`, `Host: us03p02ffm01`, `List: m9a.txt`, `3 file(s), 156.1 GB`, the Held line,
  the logged-on line, `Preview only. Add /confirm to schedule it.` Exact spec text; UTC correct (00:30 PST = 08:30 UTC).
- Same with `/confirm` → the preview without its last line, then `/schedule /confirm is not available in this version; nothing was
  scheduled`.
- `schtasks` after: no output — no task created.
- Observation (by design, O6): the list's 3 rows total 156.1 GB while the dry run on the same list shows one row no longer exists
  (146.2 GB would be freed). Scheduling touches no server; the run re-checks each row. Candidate for M10b2 wording: make the size
  line say "in the list".
