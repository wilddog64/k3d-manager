# dirused M10b3a: the `/runplan` engine (`PlanRunner`), portable, with fakes

**Status:** LANDED — `f4c117e` on `m10b-scheduled-purge` (2026-11-24); verifier PASS (all items, 17/17 mutants), correction 1 landed the verifier's tests as `RunPlanAcceptanceTests.cs`; Claude mutants red; windows CI run 45502759684 green (windows + portable)
(both READY WITH FIXES, both: split); review fixes applied (adjudication in M10b3)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b3](dirused-m10b3-runplan-windows.md); design [M10b](dirused-m10b-scheduled-purge.md) §5, §6, D14; shared contract
copied at the end of this file (the worker cannot read the parent).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (head `ab98677`)
**Risk:** high — the unattended delete decision; all through seams, no real Windows call
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only (independent verifier + mutants)
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** E-B3a carries the approved E-B3 intent unchanged; this child is its run-time part.
**Approval:** operator, 2026-11-23 — D9 (no service stop); operator, 2026-11-24 — D14, "intents approved"

## Already on the branch (do not rewrite or edit)

| What | Where |
|---|---|
| Seam interfaces and records | `src/Dirused.Common/ScheduleSeams.cs` (contract at the end) |
| Plan creation (writes `plan.txt`, `list.txt`, `dirused.exe`, `task.xml`) | `ScheduleCommands.Schedule`, `src/Dirused.Common/ScheduleCommands.cs:12` |
| Trust walk | `PlanTrust.Check(exePath, planRoot, userSid, trusted, store, security)`, `src/Dirused.Common/PlanTrust.cs:44`. First line shapes: `/schedule: <path> can be changed by <display> (<rights>).` (:69), `/schedule: <path> is a link; dirused does not schedule through links` (:53), `/schedule: cannot read permissions of <path>: <error>` (:58), and the two drive lines (:25-26) |
| Plan-folder intact check | `SchedulePlans.IsIntact(planDir, s)`, `src/Dirused.Common/SchedulePlans.cs:13` |
| `/schedule /list` reader of `claim` and `report.txt` | `SchedulePlans.List` `:30-70` (`ParseFields` `:108`, `ParseClaim` `:132`, `ValidPlan` `:125`) |
| Purge engine | `Purge.Apply(..., bool scheduled = false)`, `src/Dirused.Common/Purge.cs:96-115`; identity and size/time match `:1036-1046`; a `log` callback that **throws** undoes the delete (`:1050-1064`) |
| List parse | `PurgeList.Parse(byte[], out ParsedPurgeList?)`, `src/Dirused.Common/PurgeList.cs:39` |
| Attended list run (for its exit rule and held line) | `Program.RunFromList`, `src/Dirused.Cli/Program.cs:195-231`; grouping expression `:197` |
| Shared fakes (`internal`) | `tests/Dirused.Tests.Portable/ScheduleFakes.cs`: `FakeFolderSecurity` (ACLs by path; `Secure` records only), `ScheduleFakes.StockSystemDrive()`, `JumpBoxProfile()`, SIDs `UserSid`, `AdminSid`, `UnknownSid`. `FakePlanStore` holds no files: write an in-memory store in your own test file |

## Scope

### 1. `IPlanStore.MoveNew` (contract addition, `ScheduleSeams.cs`)

One member with a default body, so the three existing implementers (`ScheduleFakes.cs:5`, `ScheduleCommandsTests.cs:30`,
`SchedulePlansTests.cs:16`) compile unchanged:
`SeamResult MoveNew(string from, string to) => new(false, "move unavailable");` — rename `from` to `to`; fails when `to` exists.

### 2. `PurgeList.ToResults(ParsedPurgeList list)`

Move the grouping expression at `Program.cs:197` unchanged into `public static List<ScanResult> ToResults(ParsedPurgeList list)` in
`PurgeList.cs`; `RunFromList` calls it. Its `System.IO.Path.GetDirectoryName` fallback is accepted (parsed rows always carry
`ListTarget`, `PurgeList.cs:112`). Existing tests stay green.

### 3. `PlanRunner.RunPlan` (new `src/Dirused.Common/PlanRunner.cs`)

```csharp
public sealed record RunPlanSeams(IPurgeFileSystem Fs, IServiceQuery? Services, Func<string, bool>? IsFixedDrive,
    Func<DateTime> UtcNow, int Pid, string PurgeLogPath, Action<TimeSpan> Sleep);
public static class PlanRunner
{
    public static int RunPlan(string id, ScheduleSeams s, RunPlanSeams r, TextWriter stdout, TextWriter stderr);
}
```

`planDir` = `<s.PlanRoot>\<id>` (string join with `\`). `<now>` = `s.Now()` converted to Pacific (`Pacific Standard Time`, falling back
to `America/Los_Angeles`), written `yyyy-MM-ddTHH:mm:sszzz`. **stderr outcome:** write the line to `stderr` and
`s.Store.AppendLog("runplan <id>: <line>")`; create nothing in the plan dir. **report outcome:** take the claim (below), then write
`report.txt` (§4). Checked in this order:

| # | Check | Outcome |
|---|---|---|
| 1 | `id` matches `\A[0-9]{8}-[0-9]{4}-[0-9a-f]{4}\z` and `s.Store.Exists(<planDir>\plan.txt)` | stderr `refused: not a plan id: <id>`, exit 1 |
| 2 | `s.ExePath` equals `<planDir>\dirused.exe` (ordinal ignore-case) | stderr `refused: not started from the plan's program copy`, exit 1 |
| 3 | `s.Store.IsReparsePoint` is true for any of `<PlanRoot parent>` (`...\dirused`), `<PlanRoot>`, `<planDir>`, `plan.txt`, `list.txt`, `dirused.exe` | stderr `refused: plan folder contains a link`, exit 1 |
| 4 | `SchedulePlans.IsIntact(planDir, s)` is false | stderr `refused: plan folder permissions changed`, exit 1 |
| 5 | `plan.txt` (read once with `ReadAll`) is not a valid plan (rules below) | report `refused: not a dirused plan`, exit 1 |
| 5a | `s.Now() >= expires` | report `expired`, exit 0 |
| 5b | `s.Now() < run − 1 min` or `s.Now() > run + 15 min` | stderr `refused: not the scheduled time (scheduled <run in Pacific as ddd yyyy-MM-dd HH:mm> <PST or PDT>)`, e.g. `refused: not the scheduled time (scheduled Mon 2026-11-23 22:30 PST)`, exit 1 |
| 5c | `s.Store.Exists(<planDir>\report.txt)` (a report with no claim was planted or left) | stderr `refused: plan already has a report`, exit 1 |
| 6 | Take the claim | see "Claim"; when taken, continue |
| 6a | `PlanTrust.Check(s.ExePath, s.PlanRoot, s.UserSid, <trusted>, s.Store, s.Security)` not ok | report `refused: ` + its first line with the leading `/schedule: ` removed and one trailing `.` removed if present, exit 1 |
| 7 | sha256 of `s.Store.ReadAll(<planDir>\dirused.exe)` ≠ `exe-sha256` (null counts as different) | report `refused: program copy changed since it was scheduled`, exit 1 |
| 8 | Read `list.txt` **once**; sha256 ≠ `list-sha256` (null counts as different) | report `refused: list changed since it was scheduled`, exit 1 |
| 9 | `PurgeList.Parse(those same bytes)` false, or `list.Errors.Count > 0`, or `list.Files.Count == 0` → report `refused: not a dirused plan`, exit 1. Else run `Purge.Apply` (below) | report `done`, exit per the rule below |

**Valid plan (step 5).** Decode as strict UTF-8 (invalid bytes → invalid). Split on `\n`, strip one trailing `\r` per line. First line
exactly `# dirused plan v1`. Every other line starting `# ` is `key: value` (value after the first `:` with leading spaces removed); a
key seen twice → invalid. Required, each non-empty: `id`, `created`, `run`, `expires`, `exe-sha256`, `list-sha256`, `files`, `bytes`,
`host`, `source`, `trusted` (the same set `/schedule /list` needs, plus the hashes and `trusted`). `id` equals the dir name; `created`,
`run`, `expires` parse with `DateTimeOffset.TryParseExact(value, "yyyy-MM-ddTHH:mm:sszzz", InvariantCulture)`; `files` and `bytes`
are non-negative integers; the hashes are 64 lower-case hex; `created < run`; `expires == created + 24 h` (as instants);
`run <= created + 23 h 45 min`.

**`<trusted>`:** the `trusted` value `none` → empty; otherwise split on `,`, each entry a `TrustedAccount(sid, sid)`.

**Claim.** `s.Store.WriteNew(<planDir>\claim, UTF-8 "run <now> pid <r.Pid>\n")`. If it fails, read `claim` (up to 3 reads,
`r.Sleep(100 ms)` between, while it is null or does not parse) and parse it as `/schedule /list` does (first word `cancel` with a time,
or `run <time> pid <n>`): `cancel` → stderr `cancelled`, exit 0; `run` → stderr `refused: plan already started`, exit 1; still
unparsed → stderr `error: could not claim plan: <WriteNew error>`, exit 3. In those three cases no report is written and nothing is
deleted. A report outcome at step 5 or 5a takes the claim the same way first.

**Step 9 run.** `Purge.Apply(PurgeList.ToResults(list), list.Days, list.MinBytes, confirm: true, r.Fs, r.UtcNow, log: L,
CancellationToken.None, purgeLogPath: r.PurgeLogPath, services: r.Services, isFixedDrive: r.IsFixedDrive, control: null,
localNow: null, sleep: null, input: TextReader.Null, inputRedirected: true, yes: true, error: E, scheduled: true)`.
- `L(line)`: add `line` to the captured purge-log lines, then `s.Store.AppendLog(line)`; if that returns not Ok, **throw**
  `IOException(error)` (so `Purge` undoes that delete and stops, `Purge.cs:1050-1064`).
- `E`: a `StringWriter { NewLine = "\n" }` whose text is copied line by line to `stderr` and to the captured stderr lines after `Apply`
  returns.
- Exit: `run.ServiceStartFailed` → 3; `run.Failed > 0` or `run.NotAttempted > 0` → 3; else 0 (as `RunFromList`, with no list errors).
- An exception that escapes `Apply` (per-file I/O exceptions do not: `Purge` turns them into `failed: <message>` rows) or building the
  report → report `refused: error during run: <exception message>`, exit 3.

**Never:** call `IServiceControl` (there is none in `RunPlanSeams`); read the `# source:` path; read `list.txt` or `plan.txt` twice;
call `s.Scheduler`; call `s.Store.DeleteTree` on `<planDir>` or `<PlanRoot>`.

### 4. Run report (`report.txt`)

UTF-8 without BOM; every line ends with `"\n"` (render into `StringWriter { NewLine = "\n" }`). If `<planDir>\report.tmp` exists, remove
it with `DeleteTree` first. Write `<planDir>\report.tmp` with `WriteNew`, then `MoveNew(report.tmp, report.txt)`.

```
# dirused run report v1
# id: <id>
# started: <claim time as written in claim>
# finished: <now when the report is built>
# outcome: <done | expired | refused: <reason>>
# exit: <code>
# result: deleted <run.Deleted> file(s), <Format.Size(run.DeletedBytes)> freed; <run.Skipped> skipped; <run.Failed> failed   (done only)
<new TextRenderer().Render(writer, run.Results) output>                                                                       (done only)
<the held line exactly as RunFromList prints it for text output, when run.HeldSummary.Total > 0>                              (done only)
--- purge log
<each captured purge-log line, in order>
--- stderr
<each captured stderr line, in order>
```

`WriteNew` or `MoveNew` failure → stderr `error: could not write report: <error>` and
`s.Store.AppendLog("runplan <id>: report failed: <error>")`; the exit code is unchanged; `report.tmp` may remain (`/schedule /list` then
shows `interrupted`). `stdout` gets nothing.

## Files

New: `src/Dirused.Common/PlanRunner.cs`, `tests/Dirused.Tests.Portable/RunPlanAcceptanceTests.cs` (correction 1: the verifier's
acceptance tests, verbatim), `tests/Dirused.Tests.Portable/RunPlanTests.cs` (with its own in-memory `IPlanStore` and
`IPurgeFileSystem` fakes, or reuse `ScheduledEngineTests.cs`'s pattern by copying, not by editing that file).
Changed: `src/Dirused.Common/ScheduleSeams.cs` (one default member), `src/Dirused.Common/PurgeList.cs` (`ToResults`),
`src/Dirused.Cli/Program.cs` (line 197 only: call `PurgeList.ToResults`).

## What NOT to Do

- Do not edit `ScheduleCommands.cs`, `SchedulePlans.cs`, `PlanTrust.cs`, `TrustCommands.cs`, `TaskXml.cs`, `Purge.cs` or any existing
  test file. If one of them blocks the spec, stop and report.
- Do not add real Windows classes, Program wiring or schtasks code (M10b3b–d).
- Do not take the claim before steps 5a/5b/5c; do not write a report on a stderr outcome; do not replace an existing `report.txt`.
- Leave changes uncommitted; do not push.

## Acceptance

Fixture facts for every test: an in-memory `IPlanStore` (files and dirs by path, a call log, `MoveNew` refusing an existing target,
`AppendLog` capturing lines); `FakeFolderSecurity` from `ScheduleFakes.StockSystemDrive()` or `JumpBoxProfile()` **plus** user-only ACLs
(owner `UserSid`, one allow entry `UserSid` `GenericAll`) set by the test for `...\dirused`, `plans`, the plan dir, `plan.txt`,
`list.txt`, `dirused.exe`; a plan made by `ScheduleCommands.Schedule` with a schedule-time seam set (`ExePath` = the Program Files exe,
clock = created), then `RunPlan` with a run-time seam set (`ExePath` = `<planDir>\dirused.exe`, clock = run); `r.UtcNow` matching;
a fake `IPurgeFileSystem` and `IServiceQuery` as in `ScheduledEngineTests.cs`.

```yaml
must:
  - id: B3a-M1
    text: "happy path: 3 listed files matching identity, size and time, not held, and 1 held by Tomcat85; claim = 'run <time> pid <Pid>\\n'; the 3 are deleted; the held row's status is 'skipped: held by Tomcat85 — scheduled runs do not stop services'; the store log shows WriteNew <planDir>\\report.tmp then MoveNew <planDir>\\report.tmp <planDir>\\report.txt; report.txt is UTF-8 with only \\n line ends, header lines id/started/finished, '# outcome: done', '# exit: 0', '# result: deleted 3 file(s), <size> freed; 1 skipped; 0 failed', the rendered rows, '--- purge log' with the 3 delete lines, '--- stderr'; report.tmp absent; exit 0; SchedulePlans.List then prints 'done (deleted 3 file(s), ...; 1 skipped; 0 failed, exit 0)' for this id"
  - id: B3a-M2
    text: "stderr outcomes, each with its exact line on stderr, the purge log line 'runplan <id>: <line>', exit 1, and no WriteNew of claim, report.tmp or report.txt: id 'bad'; valid id with no plan.txt; ExePath not <planDir>\\dirused.exe; a reparse point on each of the six paths (six cases, 'refused: plan folder contains a link'); an extra allow entry for AdminSid on plan.txt ('refused: plan folder permissions changed'); clock = run-2min and run+16min ('refused: not the scheduled time (scheduled <ddd yyyy-MM-dd HH:mm> PST)'); report.txt present and no claim ('refused: plan already has a report', and report.txt byte-identical)"
  - id: B3a-M3
    text: "report outcomes, each with the claim written first, then report.txt with that outcome and exit, and no file deleted: plan.txt without '# trusted:' ('refused: not a dirused plan', 1); a duplicated '# run:' line (same); expires = created+25h (same); dirused.exe bytes changed ('refused: program copy changed since it was scheduled', 1); list.txt changed ('refused: list changed since it was scheduled', 1); clock = expires ('expired', 0); JumpBoxProfile ancestors with '# trusted: none' ('refused: C:\\Users\\op can be changed by PROD\\admin2 (full control)', 1)"
  - id: B3a-M3b
    text: "positive control for the trust re-check: the same JumpBoxProfile plan with '# trusted: S-1-5-21-1-2-3-2001,S-1-5-21-9-9-9-8249' deletes the matching files and reports done"
  - id: B3a-M4
    text: "claim already 'cancel <time>' → stderr 'cancelled', exit 0; claim already 'run <time> pid 7' → stderr 'refused: plan already started', exit 1; claim present but empty on all 3 reads → stderr 'error: could not claim plan: <error>', exit 3 and r.Sleep called twice; in all three no delete and no report; the first two also at clock = expires"
  - id: B3a-M5
    text: "a store whose MoveNew fails: stderr 'error: could not write report: <error>', purge log 'runplan <id>: report failed: <error>', exit equals the run's (0 for the happy path)"
  - id: B3a-M6
    text: "an AppendLog that fails on the first delete line: that file is not deleted (the fake records UnmarkDelete or no delete), its status is 'failed: log write failed', the report outcome is done with exit 3"
  - id: B3a-M7
    text: "an r.UtcNow that throws (Purge swallows per-file Open/Stat/ResolveRoot exceptions into row statuses, so they are not this case): report '# outcome: refused: error during run: <message>', exit 3"
must_not:
  - id: B3a-N1
    text: "RunPlan deletes a listed row whose size, last-write or file ID differs from the list. Positive control: the matching row in the same run is deleted. baseline: mutant-only (PlanRunner absent at ab98677); mutant 'PlanRunner copies size, LastWriteUtc and FileId from r.Fs.Stat into the rows before Apply' turns it red"
  - id: B3a-N3
    text: "a start outside [run-1m, run+15m] writes the claim or a report. Positive control: start at run writes the claim. baseline: mutant-only; mutants 'claim before the window check' and 'window +30 min' turn it red"
  - id: B3a-N4
    text: "an expired plan deletes anything. Positive control: a plan with run = created + 23h45m at clock = run (inside the window, before expires) deletes. baseline: mutant-only; mutant '> instead of >=' turns it red"
  - id: B3a-N5
    text: "RunPlan reads the '# source:' path, or calls ReadAll on list.txt or plan.txt more than once (store call log). Positive control: ReadAll(list.txt) count = 1 in the happy path. baseline: mutant-only; mutants 'read source list' and 'read list twice' turn it red"
  - id: B3a-N6
    text: "RunPlan calls DeleteTree with a path equal to <planDir> or <PlanRoot>, in any outcome of B3a-M1..M7. Positive control: DeleteTree(<planDir>\\report.tmp) is recorded when a stale report.tmp exists. baseline: mutant-only; mutant 'DeleteTree(planDir) on a refusal' turns it red"
evidence:
  - id: E-B3a
    proves: [B3a-M1, B3a-M2, B3a-M3, B3a-M3b, B3a-M4, B3a-M5, B3a-M6, B3a-M7, B3a-N1, B3a-N3, B3a-N4, B3a-N5, B3a-N6]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable. Mutants each red: claim before window check; window +30 min; expiry > instead of >=; skip 5c; skip exe hash; skip list hash; read list twice; read source list; scheduled false; report written directly to report.txt (no tmp); skip IsIntact; skip the link check; skip trust re-check; trusted copy ignored (always empty); AppendLog result ignored in L; copy Stat into rows; DeleteTree(planDir) on refusal"
    intent: "The scheduled run deletes only files that are exactly the ones you reviewed, never touches Tomcat, refuses if the plan, its program copy or its folder changed, and leaves a report you can read in the morning."
interface:
  - "refused: not a plan id: <id>"
  - "refused: not started from the plan's program copy"
  - "refused: plan folder contains a link"
  - "refused: plan folder permissions changed"
  - "refused: not a dirused plan"
  - "refused: not the scheduled time (scheduled <time>)"
  - "refused: plan already has a report"
  - "refused: plan already started"
  - "cancelled"
  - "refused: <path> can be changed by <display> (<rights>)"
  - "refused: program copy changed since it was scheduled"
  - "refused: list changed since it was scheduled"
  - "refused: error during run: <message>"
  - "error: could not claim plan: <error>"
  - "error: could not write report: <error>"
```

## Shared contract (copied from the parent, rev 5, for the worker; the parent file is not in the dirused repo)

The branch already implements this. M10b3a adds `IPlanStore.MoveNew` (default body).


### Interfaces (`src/Dirused.Common/ScheduleSeams.cs`, written by b2c; every member below, nothing more)

```csharp
public sealed record SeamResult(bool Ok, string? Error = null);

[Flags] public enum WriteRights { None = 0, Write = 1, Append = 2, Delete = 4, DeleteChild = 8, WriteDac = 16, WriteOwner = 32, GenericWrite = 64, GenericAll = 128 }
public sealed record AclEntry(string Sid, string Display, WriteRights Rights, bool InheritOnly, bool Allow);
public sealed record AclRead(bool Ok, bool Missing, string? OwnerSid, string? OwnerDisplay, IReadOnlyList<AclEntry> Entries, string? Error);
public sealed record TrustedAccount(string Sid, string Display);
public enum TokenLevel { Medium, High }

public interface IPlanStore                     // paths: absolute Windows paths built by string joins with "\\"
{
    bool Exists(string path);                   // file or directory
    bool IsReparsePoint(string path);           // false when missing
    SeamResult CreateDirectory(string path);    // fails when it already exists (CreateNew semantics)
    SeamResult WriteNew(string path, byte[] bytes); // FileMode.CreateNew
    byte[]? ReadAll(string path);               // null when missing or unreadable
    IReadOnlyList<string> ListDirectoryNames(string path); // empty when missing
    SeamResult DeleteTree(string path);
    SeamResult AppendLog(string line);          // one purge-log line, without newline
}
public interface IPlanFolderSecurity
{
    SeamResult Secure(string path, string userSid);  // owner = user; protected DACL, one ACE: user FullControl, OI CI
    AclRead ReadAcl(string path);                    // Missing = true and Ok = false when the path does not exist
}
public interface ITaskScheduler
{
    SeamResult Register(string taskName, string xmlPath, PlanTask expected); // real (M10b3): create, read back, verify; on failure Error is the text printed after "error: "
    bool Exists(string taskName);
    SeamResult Delete(string taskName);              // already gone counts as Ok
}
public interface ITrustStore
{
    IReadOnlyList<TrustedAccount> Load();            // empty when no file
    SeamResult Add(TrustedAccount account);
    SeamResult Remove(string sid);
}
public interface IAccountResolver { TrustedAccount? Resolve(string nameOrSid); }

public sealed record ScheduleSeams(
    Func<DateTimeOffset> Now, TimeZoneInfo Local, string PlanRoot, string UserSid, string ExePath, string ToolVersion,
    Func<int> IdSuffix, TokenLevel Token, IPlanStore Store, IPlanFolderSecurity Security, ITaskScheduler Scheduler,
    ITrustStore Trust, IAccountResolver Accounts, Func<int, string?> ProcessImagePath);

public sealed record ScheduleRequest(Options Options, byte[] ListBytes, string ListPathAsTyped, string ListFullPath);
```

### Ids, names and times

- `created` = `Now()` truncated to whole seconds (TaskXml.Build refuses sub-second values). `expires` = `created + 24 h`.
- `created`, `run` and `expires` are converted to Pacific time (`TimeZoneInfo.ConvertTime` with the Pacific zone, so the offset is
  `-08:00` or `-07:00`) before they build `PlanTask` or are written to `plan.txt` or the purge log. (`Schedule.TryRunTime` returns
  `run` with offset `+00:00`.)
- Id = run instant in Pacific as `yyyyMMdd-HHmm`, `-`, then `(IdSuffix() & 0xFFFF)` as 4 lower-case hex digits; matches
  `\A[0-9]{8}-[0-9]{4}-[0-9a-f]{4}\z`. The preview draws the suffix once; registration uses that id unless `CreateDirectory` of the plan dir
  fails because it exists, in which case a new suffix is drawn (at most 5 draws in total); `id`, plan dir, task name and `PlanTask`
  all take the new id, and the printed `Scheduled <id>` shows it.
- Task name `\dirused\<UserSid>\purge-<id>`, always built from `ScheduleSeams.UserSid` and the id (b2e builds it the same way). Plan dir `<PlanRoot>\<id>`. Program `<plan dir>\dirused.exe`.
- `PlanTask` for TaskXml: `Id`, `Run`, `Expires`, `UserSid`, `PlanDir`, `Description` = `dirused scheduled purge <id> (<n> file(s), <size>) from <source file name>`.
- `<total>` / `<total logical bytes>` = decimal integer sum of the rows' `LogicalBytes`; `<size>` = `Format.Size(<total>)`; `<source
  file name>` = the last non-empty `\`-separated segment of `ListFullPath`.

### `plan.txt` (UTF-8 without BOM, lines end with `"\n"` written explicitly)

```
# dirused plan v1
# id: <id>
# created: <created, yyyy-MM-ddTHH:mm:sszzz>
# run: <run, same format>
# expires: <expires, same format>
# tool: <ToolVersion>
# exe-sha256: <lower-case hex of dirused.exe as written>
# list-sha256: <lower-case hex of ListBytes>
# files: <n>
# bytes: <total logical bytes>
# host: <host>
# source: <ListFullPath>
# trusted: <every SID in the trust store when scheduled, sorted ordinal, joined by ","> | none
```

### Trust rules (D14 as revised by the rev 3 reviews)

- **Paths.** The exe path and the plan root must start with a drive letter and `:\` (`^[A-Za-z]:\\`), else exit 1
  `/schedule: dirused.exe must be on a local drive to schedule (<path>)` or `/schedule: the plan folder must be on a local drive (<path>)`.
  Paths are split on `\` as strings, never with `System.IO.Path` (tests run on macOS and Linux too). Normalisation: repeated `\`
  collapse to one; a trailing `\` is removed except on a drive root, which is written `X:\`. M10b3's real seam also refuses network,
  mapped and subst drives (DriveType check); the pure check sees only the string. SIDs compare ordinal ignore-case.
- **Leaves** (all write rights count): the exe file, the exe's folder, `<PlanRoot>`'s parent (`...\dirused`) and `<PlanRoot>`.
  **Ancestors** (only rights that can rename, delete or take over an existing child count: `Delete`, `DeleteChild`, `WriteDac`,
  `WriteOwner`, `GenericAll`): every other folder from the exe's folder and from `<PlanRoot>`'s parent up to the drive root,
  de-duplicated case-insensitively. Order: exe, exe folder, its ancestors upward, then `...\dirused`, `<PlanRoot>`, then the remaining
  ancestors of `...\dirused` upward. A path that is both a leaf and an ancestor is a leaf.
- **Allowed writers:** the user, `S-1-5-18` SYSTEM, `S-1-5-32-544` Administrators, `S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464`
  TrustedInstaller, and every SID in the trust store; `S-1-3-0` CREATOR OWNER only on ACL entries (never as an owner).
- **Per path:** a reparse point (`IsReparsePoint`) → exit 1 `/schedule: <path> is a link; dirused does not schedule through links`.
  `ReadAcl` with `Missing` → allowed only for `...\dirused` and `<PlanRoot>` (this run creates and secures them); any other missing
  path or any `Ok = false` → exit 1 `/schedule: cannot read permissions of <path>: <error or "not found">`. Deny entries and
  **inherit-only entries of any SID** are ignored (the inherited copy appears on the child's own DACL, which is checked). An owner not
  in the allowed writers counts as an entry with `WriteDac` and the right text `owner`.
- **Broad groups are never trusted:** `S-1-1-0` Everyone, `S-1-2-0` LOCAL, `S-1-5-2` NETWORK, `S-1-5-4` INTERACTIVE, `S-1-5-7`
  ANONYMOUS, `S-1-5-11` Authenticated Users, `S-1-5-13` Terminal Server Users, `S-1-5-14` Remote Interactive Logon, `S-1-5-15` This
  Organization, `S-1-15-2-1` All Application Packages, `S-1-5-32-545` Users, `S-1-5-32-546` Guests, `S-1-5-32-555` Remote Desktop
  Users, and any SID matching `\AS-1-5-21-[0-9-]+-(513|514|515)\z` (Domain Users, Domain Guests, Domain Computers). `/schedule /trust` refuses them; a refusal caused by
  one prints the IT line instead of the `/trust` line.
- **Findings** merge per (path, SID): the union of that SID's counted rights on that path, plus `owner` when it is the untrusted
  owner. Order: shallowest path first (fewest `\` segments), then `PathsToCheck` order, then SID ordinal. On ancestors only counted
  rights print. `GenericAll` prints only `full control`. A reparse or read failure stops the check at that path; it is the only line,
  and `ReadAcl` is not called on a link.
- **Refusal text** (first finding), exit 1, nothing created:
  ```
  /schedule: <path> can be changed by <display> (<rights>).
    If you trust this account, run once: dirused /schedule /trust "<account>"
    also: <path> by <display>                      (one line per further untrusted path/account pair)
  ```
  where `<rights>` is the matching rights in this order and wording, comma-separated: `full control`, `write`, `append`, `delete`,
  `delete child`, `change permissions`, `take ownership`, `generic write`, `owner`; `<account>` is the display name, or the SID when
  the display is `unresolved account <sid>`. For a broad group the second line is
  `  This group is too wide to trust; ask IT to remove this permission or move dirused.exe.`
- **Residual accepted:** an account trusted by the user can also write `trust.txt` in the user's profile; trusting is a statement
  that the account already controls the profile (parent D14 rationale).

### Exact strings used by more than one child

`Preview only. Add /confirm to schedule it.` · `Schedule this? [y/N] ` (stderr, no newline) · `Not scheduled.` ·
`Scheduled <id> for <run as on the preview Run line, without the relative part>. Check it with: dirused /schedule /list` (e.g. `Scheduled 20261123-2230-a1b2 for Mon 2026-11-23 22:30 PST (06:30 UTC Tue). Check it with: dirused /schedule /list`) ·
`/schedule: run from a normal (not elevated) window` · `/schedule: fix the list first; nothing was scheduled` ·
`error: could not secure plan folder: <error>` · `error: could not write plan: <error>` · `error: <Register error>` ·
purge-log lines `schedule <id> run <run ISO> files <n> bytes <total>` and `schedule-cancel <id>`.

### `claim` and `report.txt` (writer M10b3 `/runplan`; reader b2e)

`claim` (UTF-8, one line): `run <yyyy-MM-ddTHH:mm:sszzz> pid <n>` or `cancel <yyyy-MM-ddTHH:mm:sszzz>`, written with `WriteNew`.
`report.txt` header lines `# outcome: <text>` (parent §6: `done`, `expired`, `refused: <reason>`, shown verbatim) and, for `done`,
`# result: <text>` and `# exit: <n>`. Readers tolerate `\r\n` and a missing final newline.

### Notes for M10b3's real seams

- `WriteRights` from a Windows ACE: `FullControl` → `GenericAll`; `Modify` → `Write | Append | Delete`; `Delete`, `DeleteSubdirectoriesAndFiles`,
  `ChangePermissions`, `TakeOwnership`, `WriteData`/`CreateFiles`, `AppendData`/`CreateDirectories` map to their bits; generic-write
  ACEs → `GenericWrite` plus the bits they imply.

