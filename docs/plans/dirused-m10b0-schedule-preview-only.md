# dirused M10b0: `/schedule` preview only (demo build, nothing is scheduled)

**Status:** OPEN — SPEC rev 1, 2026-11-24; awaiting intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §1–§3 and §4.1–§4.3 (preview subset). Ships before M10b1–M10b4; M10b2 builds on it.
**Repo / branch:** wilddog64/dirused / `m10b0-schedule-preview` from `main` (`a2d0508`)
**Risk:** low — parser and output only; no task, no plan folder, no file written, no server touched
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only
**Filed:** 2026-11-24
**Intent approved:** pending
**Approval:** operator, 2026-11-24 — "but I need schedule print out to demo"; "do (a) and (b). It need to be secure but not over restricted"
**Proofs:** P7 answered (jump box `Pacific Standard Time`, 2026-11-24). No other proof gates this child: it calls no Windows API.

## Why

The operator demos dirused to the team before anyone runs a scheduled purge. The demo needs the printout: when the run would
happen, against which server, how many files and how much space, and that nothing happens until `/confirm`. Task creation (M10b2,
M10b3) waits on the jump-box probes and O7, so the preview ships alone first.

## Scope

1. **Parser.** Add `schedule` to `KnownSwitches`. Parent §2 rows **7–11 only**, as a pre-check before both parser branches, with
   their exact strings. `list`, `cancel` and `runplan` are **not** added: they stay unknown switches until M10b2/M10b3. The `/fromlist`
   branch takes the zone token and the new whitelist text exactly as parent §2. `Options` gains, appended last and defaulted:
   `string? ScheduleTime = null, string? ScheduleZone = null`. Usage text (`ShortUsageText` and `UsageText`) gains only:
   `  /schedule <time>    With /fromlist /purge: preview a one-time run at HH:MM` /
   `                      [PT|PST|PDT|UTC]; add /confirm to schedule it`.
2. **Time.** Parent §3 in full (zones, bare-time rule, next occurrence, gap and overlap, 2 min, 23 h 45 min, expiry, printed form),
   in `src/Dirused.Common/Schedule.cs` with a clock seam (`Func<DateTimeOffset>`) and a local-zone seam (`TimeZoneInfo`).
3. **Preview** (`Schedule.Preview(...)` in Common, stdout, every line ≤ 80 columns, long paths wrapped onto a continuation line
   indented 12 spaces):
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
   - `in <h> h <m> min` is the whole minutes from `created` to the run (`in 45 min` under one hour).
   - Host as parent §4.1: case-insensitive UNC host; a drive-letter path shows `this machine`; more than one host exits 1 with the
     parent's O8 message and prints no preview.
   - Size uses `Format.Size` (`src/Dirused.Common/Renderers/Format.cs:6`, the `176.2 GB` form the purge summary prints).
   - The `Task`, `Plan dir`, `Program` and `sha256` lines of parent §4.2 are **not** printed here; M10b2 adds them.
4. **Read the list once** with the existing `PurgeList.Read(path, out parsed)` (the `Program.cs:71` path). No file in the list is
   stat'ed, opened or enumerated; no service is queried. Not a list → the existing message. No file rows → exit 1
   `/schedule: the list has no files to delete`.
5. **`/confirm`.** `/schedule ... /confirm` (with or without `/yes`) prints the same preview, then on stderr
   `/schedule /confirm is not available in this version; nothing was scheduled`, exit 1. No question is asked and no input is read.
   (`/yes` without `/confirm` keeps `/yes needs /purge /confirm`.)
6. **Program.cs wiring:** when `options.ScheduleTime != null`, after the existing `/fromlist` path checks and the list read, call
   `Schedule.Preview` with the real clock and `TimeZoneInfo.Local` instead of `RunFromList`. Nothing else in Program.cs changes.
7. **Docs:** `docs/purge.md` gains a "Scheduled purge (preview)" section: the form, the zones, the 2 min / 23 h 45 min rules, the
   example output above, and "scheduling itself comes in a later version". `README.md` usage block gains the two usage lines.
   `CHANGELOG.md` `[Unreleased]`: `/schedule` preview.

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

- Whitelist text `ArgParser.cs:121` → parent §2's new text; reader `PurgeListTests.cs:102` updated here.
- `/yes needs /purge /confirm` `ArgParser.cs:137`, `:263`; readers `ArgParserTests.cs:310,311,313`; usage `:73` — unchanged.
- `ArgParserTests.cs:249-252` (80 columns) — the new usage lines must pass it.
- `KnownSwitches` `ArgParser.cs:16` — one new name, `schedule`.
- `Options` constructions `ArgParser.cs:139`, `:291` and tests — two new fields last, defaulted.
- `Program.cs:67-73` `/fromlist` path (line numbers at `a2d0508`) — one new branch before `RunFromList`.

## What NOT to Do

- Do not register a task, run `schtasks`, create any folder or write any file (no plan dir, no purge log line).
- Do not stat, open or enumerate a listed file; do not query a service; do not read the list twice.
- Do not add `list`, `cancel` or `runplan`; do not ask `Schedule this?`.
- Do not change `Purge.cs`, `PurgeList.cs` or the existing `/fromlist` dry-run and delete paths.
- Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B0-M1
    text: "clock Mon 2026-11-23 21:00 PST, local zone Pacific, a list of 12 rows on \\\\us03p02ffm01 totalling 176.2 GB: '/fromlist l.txt /purge /schedule 22:30' prints the preview above line for line (Run with 'in 1 h 30 min', Expires = created + 24 h, Host us03p02ffm01, List path, '12 file(s), 176.2 GB', the fixed Held line, the logged-on line, 'Preview only. Add /confirm to schedule it.'), every line <= 80 columns, exit 0"
  - id: B0-M2
    text: "time rules as parent §3: 20:00 at 21:00 → tomorrow; PT, PST, PDT and UTC instants; bare time with local zone UTC exits 1 with the not-on-Pacific message and with zone id America/Los_Angeles is accepted; spring-forward 02:30 PT and fall-back 01:30 PT exit 1 with their messages; 01:30 PDT on fall-back day accepted; 1 minute away exits 1; 23 h 46 min away exits 1 with 'too far away' and 23 h 44 min is accepted; 'in 45 min' under an hour"
  - id: B0-M3
    text: "parent §2 rows 7-11 each give their exact error, one test per row; '/fromlist l /purge /schedule 22:30 /yes' gives '/yes needs /purge /confirm'; '/fromlist l /purge /bogus' gives the new whitelist text; '/schedule /list' and '/schedule /cancel x' are rejected as before (unknown switch), not accepted; both new usage lines are <= 80 columns"
  - id: B0-M4
    text: "'/fromlist l.txt /purge /schedule 22:30 /confirm' and '... /confirm /yes': the same preview on stdout, then '/schedule /confirm is not available in this version; nothing was scheduled' on stderr, exit 1, and the fake input reader records zero reads"
  - id: B0-M5
    text: "host: a drive-letter list shows 'Host:     this machine'; rows on \\\\hostA and \\\\HOSTB exit 1 with the parent O8 message and print no preview (positive control: a hostA-only list previews); rows differing only in host case count as one host; a list with no file rows exits 1 '/schedule: the list has no files to delete'"
  - id: B0-M6
    text: "docs/purge.md has the 'Scheduled purge (preview)' section with the example output and says scheduling comes later; README usage has the two lines; CHANGELOG [Unreleased] names the /schedule preview"
must_not:
  - id: B0-N1
    text: "a /schedule invocation (preview or /confirm) calls any IPurgeFileSystem method (Stat, Open, Delete, Enumerate), any IServiceQuery method, writes any file, or creates any directory (temp-dir fixture with a recorded file-system fake). Positive control: the same fakes record calls in a '/fromlist l /purge' dry run. Baseline red on a2d0508: '/fromlist l /purge /schedule 22:30' is a parse error, so the test asserting exit 0 and the preview fails"
  - id: B0-N2
    text: "the list is read more than once in a /schedule invocation (counting reader). Positive control: count = 1 asserted in B0-M1. Baseline: mutant-only; mutant 're-read the list to count bytes' turns it red"
evidence:
  - id: E-B0
    proves: [B0-M1, B0-M2, B0-M3, B0-M4, B0-M5, B0-N1, B0-N2]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on ubuntu and on windows-latest CI. New tests red on a2d0508. Mutants each red: PST treated as DST-aware; passed time stays today; 23h45m limit off by one (>=); bare time accepted off Pacific; IANA id not recognised; multi-host check skipped; host compared case-sensitively; /confirm reads input; preview printed after the stderr line instead of before; re-read the list"
    intent: "You type /schedule with a time and see exactly when the purge would run (Pacific and UTC, and how long from now), which server, how many files and how much space — and nothing is scheduled, written or touched on the server. Adding /confirm tells you scheduling is not in this version yet."
  - id: E-B0D
    proves: [B0-M6]
    kind: offline
    command: "git diff shows docs/purge.md, README.md and CHANGELOG.md updated; the purge.md example matches B0-M1 output byte for byte"
    intent: "The guide shows the same printout you will demo, and says plainly that scheduling itself comes in a later version."
  - id: E-B0L
    proves: [B0-M1, B0-M4]
    kind: live
    command: "operator, jump box, from the PR build: dirused /fromlist <a saved list> /purge /schedule 23:00 shows the preview with Host us03p02ffm01 and the right run time; the same with /confirm prints the not-available line; schtasks /query /tn \\dirused\\ finds no task (or no folder)"
    intent: "On the jump box you see the real printout for tonight against the real Tomcat list, and confirm afterwards that no task was created."
interface:
  - "/schedule <time> [PT|PST|PDT|UTC]"
  - "Scheduled purge preview (nothing is scheduled yet)"
  - "Preview only. Add /confirm to schedule it."
  - "/schedule /confirm is not available in this version; nothing was scheduled"
  - "/schedule: the list has no files to delete"
  - "/schedule: the list covers more than one host (<hosts>); save one list per host and schedule each"
  - "/schedule can be given only once"
  - "/schedule requires /fromlist"
  - "/schedule requires a time, e.g. /schedule 22:30 PT"
  - "/schedule: time must be HH:MM (00:00-23:59), optionally followed by PT, PST, PDT or UTC"
  - "/schedule can only be combined with /fromlist, /purge, /confirm and /yes"
  - "/fromlist can only be combined with /purge, /confirm, /html, /output, /json, /csv, /yes and /schedule"
```
