# dirused M10b3: `/runplan`, the real Windows seam classes, Program wiring

**Status:** OPEN — SPEC rev 3, 2026-11-24; revised to the M10b2 shared contract (rev 5) and the code landed through `ab98677`;
awaiting Fable + Argon reviews, proofs P6 (second half), P9 and P10 (readback), then dispatch
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §5, §6, §8, D14; [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md)
rev 5 (copied at the end of this file: the worker cannot read the parent). Third of four; after M10b2 (b2b–b2e all landed).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (head `ab98677`)
**Risk:** high — the unattended delete path, real `schtasks.exe` and ACL calls
**Implementer:** Luna (Codex)
**Verifier:** Claude offline from Acceptance only (independent Sonnet verifier + mutants); windows CI job; live checks E-B3L1 and
E-B3L2 by the operator on the jump box
**Filed:** 2026-11-23 (rev 3 2026-11-24)
**Intent approved:** operator, 2026-11-24
**Intent note:** the four evidence intents are unchanged from rev 2, so the approval stands.
**Approval:** operator, 2026-11-23 — D9 (no service stop), D3 (logged-on only, no password); operator, 2026-11-24 — D14, "intents approved"

## Rev 3 changes (from rev 2)

- Follows the landed seams exactly: `IPlanFolderSecurity` is `Secure` + `ReadAcl` (no `Check`, no `SourceExeIsProtected`);
  `SchtasksTaskScheduler` has no `rootFolder` (the caller passes the full task name, so CI uses `\dirused-ci\...`).
- The scheduler never deletes plan dirs; `ScheduleCommands.Schedule` (b2d) already does on a failed `Register`.
- `claim` and `report.txt` follow the formats b2e reads; outcomes are shown verbatim by `/schedule /list`.
- D14 at run time: `/runplan` re-runs `PlanTrust.Check` with the plan's `# trusted:` copy (new report outcome).
- The ACL reader maps Windows rights bit by bit (`Modify` → `Write | Append | Delete`) through a pure, portable function.
- Local fixed drives only: `ReadAcl` fails on network, mapped and `subst` drives, which turns into the existing
  `/schedule: cannot read permissions of <path>: ...` refusal.
- Program wiring replaces b2b's interim refusal; `/schedule` on Windows reads the list bytes once and goes through
  `ScheduleCommands.Schedule`.
- `/runplan` lives in a new `PlanRunner` class, so b2d's `ScheduleCommands.cs` is not edited.

## Jump-box probe script (2026-11-24)

[`assets/dirused-m10b3-probes.ps1`](assets/dirused-m10b3-probes.ps1) covers P1, P2, P3, P8 (a, b, d), P10 (descriptor readback; the
second-account check is manual) and P12. It creates tasks only under `\dirused-probe\<SID>\` and files only under
`%LOCALAPPDATA%\dirused-probe\`; P3 runs `dir` and `icacls` on the share (read-only). Run order: `setup` (afternoon, prints the
steps and times), `run12`, disconnect / sign-out steps as printed, leave disconnected, next morning `collect`, paste `report.txt`,
then `cleanup`. P5, P6 and P9 are not in it (P9 is a CI workflow, Claude's).

**P6 second half, 2026-11-24 14:07 PT, jump box (operator screenshot), normal window:** `icacls ...\dirused-probe\p6 /inheritance:r
/grant:r "%USERNAME%":(OI)(CI)F` and `/setowner "%USERNAME%"` both `Successfully processed 1 files`; readback one entry
`PROD\cliang:(OI)(CI)(F)`; `dir /q` owner of `p6` `PROD\cliang`. **PASS.** The parent `dirused-probe` shows owner
`BUILTIN\Administrators` (creation context unknown); the default owner of a new file and subfolder in a user-only folder is being
checked (`echo x> ...\p6\f.txt`, `mkdir ...\p6\sub`, `dir /q`).

**Gates.** Dispatch: P6 second half (a standard user can set owner = self and a protected one-ACE DACL; a 4-line `icacls` check the
operator runs), P9 (Claude: a scratch-branch windows-latest workflow registers, queries and deletes an interactive-token task in
`\dirused-ci\`), P10 readback (the SDDL that `/query /xml` returns for the descriptor, so the verify compare uses the right form). P8 (b)
no longer gates: `TaskXml.Parse` already decodes UTF-16 with or without BOM and UTF-8 with BOM (`TaskXml.cs:336-352`). Live checks
only: P1 production-XML form, P2, P3, P12.

## Already on the branch (do not rewrite)

| What | Where |
|---|---|
| Seam interfaces and records | `src/Dirused.Common/ScheduleSeams.cs` (contract below) |
| `/schedule /confirm` flow, plan creation, `Register` call, plan-dir removal on failure | `ScheduleCommands.Schedule`, `src/Dirused.Common/ScheduleCommands.cs:12` (`DeleteTree` at :58, :72-76, :90, :93) |
| Trust walk and refusal lines | `PlanTrust.Check(exePath, planRoot, userSid, trusted, store, security)`, `src/Dirused.Common/PlanTrust.cs:44`; first line `/schedule: <path> can be changed by <display> (<rights>).` |
| `/trust`, `/untrust` | `TrustCommands.Trust/Untrust`, `src/Dirused.Common/TrustCommands.cs:8,26` |
| `/schedule /list`, `/cancel`, plan-folder intact check | `SchedulePlans.List/Cancel/IsIntact`, `src/Dirused.Common/SchedulePlans.cs:13,30,75`; claim parse `:132`, report parse `ParseFields` `:108` |
| Task XML | `TaskXml.Build(PlanTask)` / `TaskXml.Parse(byte[])` (throws `FormatException` whose message starts `<Field>:`), `SecurityDescriptorOf(byte[])`, `src/Dirused.Common/TaskXml.cs:25,108,319` |
| Purge engine | `Purge.Apply(..., bool scheduled = false)`, `src/Dirused.Common/Purge.cs:96-115`; scheduled held-row skip `:495-497` |
| List parse | `PurgeList.Parse(byte[], out ParsedPurgeList?)`, `src/Dirused.Common/PurgeList.cs:39` |
| Attended list run | `Program.RunFromList`, `src/Dirused.Cli/Program.cs:195-231`; list-to-results grouping at `:197` |
| Interim refusal | `Program.cs:60` and `Schedule.NotAvailableForm`, `src/Dirused.Common/Schedule.cs:8` |
| Shared test fakes | `tests/Dirused.Tests.Portable/ScheduleFakes.cs` (`FakePlanStore`, `FakeFolderSecurity`, `FakeTaskScheduler`, `FakeTrustStore`, `FakeAccountResolver`, `ScheduleFakes.StockSystemDrive()`, `JumpBoxProfile()`) |

## Scope

### 1. `IPlanStore.MoveNew` (contract addition)

Add one member with a default body, so the three existing implementations (`ScheduleFakes.cs:5`, `ScheduleCommandsTests.cs:30`,
`SchedulePlansTests.cs:16`) compile unchanged:
`SeamResult MoveNew(string from, string to) => new(false, "move unavailable");` — rename `from` to `to`, failing when `to` exists.
`FakePlanStore` gets a working override only if a new test needs it; new tests may define their own in-memory store in their own file.

### 2. `PurgeList.ToResults(ParsedPurgeList list)`

Move the grouping expression at `Program.cs:197` unchanged into `public static List<ScanResult> ToResults(ParsedPurgeList list)` in
`PurgeList.cs`; `RunFromList` calls it. Behaviour-preserving; existing tests stay green.

### 3. `/runplan <id>`: `PlanRunner.RunPlan` (new `src/Dirused.Common/PlanRunner.cs`)

```csharp
public sealed record RunPlanSeams(IPurgeFileSystem Fs, IServiceQuery? Services, Func<string, bool>? IsFixedDrive,
    Func<DateTime> UtcNow, int Pid, string PurgeLogPath);
public static class PlanRunner
{
    public static int RunPlan(string id, ScheduleSeams s, RunPlanSeams r, TextWriter stdout, TextWriter stderr);
}
```

`planDir` = `<s.PlanRoot>\<id>`. Times in `claim` and `report.txt` are `s.Now()` converted to Pacific, `yyyy-MM-ddTHH:mm:sszzz`.
"stderr" outcomes write the line to `stderr` and `s.Store.AppendLog("runplan <id>: <line>")`, and create nothing in the plan dir.
"report" outcomes take the claim (below) and then write `report.txt` (§4). Checked in this order:

| # | Check | Outcome |
|---|---|---|
| 1 | `id` matches `\A[0-9]{8}-[0-9]{4}-[0-9a-f]{4}\z` and `s.Store.Exists(<planDir>\plan.txt)` | stderr `refused: not a plan id: <id>`, exit 1 |
| 2 | `s.ExePath` equals `<planDir>\dirused.exe` (ordinal ignore-case) | stderr `refused: not started from the plan's program copy`, exit 1 |
| 3 | `SchedulePlans.IsIntact(planDir, s)` is false because of a reparse point (any of `...\dirused`, `plans`, `<id>`, `plan.txt`, `list.txt`, `dirused.exe` — test `s.Store.IsReparsePoint` on these six first) | stderr `refused: plan folder contains a link`, exit 1 |
| 4 | `SchedulePlans.IsIntact(planDir, s)` is false | stderr `refused: plan folder permissions changed`, exit 1 |
| 5 | `plan.txt` (read once) is not valid: header `# dirused plan v1`; `id`, `created`, `run`, `expires`, `exe-sha256`, `list-sha256`, `trusted` each present; `id` = dir name; `created < run`; `expires = created + 24 h` (as instants); `run ≤ created + 23 h 45 min` | report `refused: not a dirused plan`, exit 1 |
| 5a | `s.Now() >= expires` | report `expired`, exit 0 |
| 5b | `s.Now() < run − 1 min` or `s.Now() > run + 15 min` | stderr `refused: not the scheduled time (scheduled <run, Pacific, ddd yyyy-MM-dd HH:mm PST/PDT>)`, exit 1 |
| 6 | Take the claim (always, even when no report follows) | see "Claim" |
| 6a | `PlanTrust.Check(s.ExePath, s.PlanRoot, s.UserSid, <trusted from plan.txt>, s.Store, s.Security)` not ok | report `refused: ` + its first line without the leading `/schedule: ` and the final `.`, exit 1 |
| 7 | sha256 of `s.Store.ReadAll(<planDir>\dirused.exe)` ≠ `exe-sha256` (or null) | report `refused: program copy changed since it was scheduled`, exit 1 |
| 8 | Read `list.txt` **once**; sha256 ≠ `list-sha256` (or null) | report `refused: list changed since it was scheduled`, exit 1 |
| 9 | `PurgeList.Parse(those same bytes)`; false → report `refused: not a dirused plan`, exit 1. Else `Purge.Apply(PurgeList.ToResults(list), list.Days, list.MinBytes, confirm: true, r.Fs, r.UtcNow, log: <capture + s.Store.AppendLog>, CancellationToken.None, purgeLogPath: r.PurgeLogPath, services: r.Services, isFixedDrive: r.IsFixedDrive, control: null, localNow: null, sleep: null, input: TextReader.Null, inputRedirected: true, yes: true, error: <capture + stderr>, scheduled: true)` | report `done`; exit as `RunFromList` (`ServiceStartFailed` → 3; list errors, failed or not attempted > 0 → 3; else 0) |

`<trusted from plan.txt>`: the `# trusted:` value split on `,`, each a `TrustedAccount(sid, sid)`; `none` → empty.

**Claim.** `s.Store.WriteNew(<planDir>\claim, UTF-8 "run <now> pid <r.Pid>\n")`. If it fails and the existing claim (read and parsed
as b2e does: first word `cancel` or `run`) says `cancel` → stderr `cancelled`, exit 0; says `run` → stderr
`refused: plan already started`, exit 1; anything else → stderr `error: could not claim plan: <error>`, exit 3. In all three cases
no report is written and nothing is deleted. A report outcome at step 5 or 5a takes the claim the same way first.

**Never:** `IServiceControl` (there is no control in `RunPlanSeams`); reading the `# source:` list; reading `list.txt` twice;
calling `s.Scheduler`; deleting the plan dir.

### 4. Run report (`report.txt`)

UTF-8 without BOM, lines end with `"\n"`. Written as `<planDir>\report.tmp` with `WriteNew` (a stale `report.tmp` is first removed
with `DeleteTree`), then `MoveNew(report.tmp, report.txt)`. A present `report.txt` is never replaced.

```
# dirused run report v1
# id: <id>
# started: <claim time>
# finished: <now when the report is built>
# outcome: <done | expired | refused: <reason>>
# exit: <code>
# result: deleted <n> file(s), <size> freed; <s> skipped; <f> failed        (only for done)
<rows: the TextRenderer output of run.Results, as /fromlist prints them>   (only for done)
<the held line exactly as RunFromList prints it, when HeldSummary.Total > 0> (only for done)
--- purge log
<each line this run sent to the purge log, in order>
--- stderr
<each line this run wrote to stderr, in order>
```

`<size>` is `Format.Size(run.DeletedBytes)`; `<s>` = `run.Skipped`; `<f>` = `run.Failed`. Write or move failure → stderr
`error: could not write report: <error>` and `s.Store.AppendLog("runplan <id>: report failed: <error>")`; the exit code is unchanged;
`report.tmp` may remain; `/schedule /list` then shows `interrupted` (b2e). `stdout` gets nothing.

### 5. `SchtasksTaskScheduler` (new `src/Dirused.Common/TaskScheduling.cs`, portable)

```csharp
public sealed record ProcessResult(int ExitCode, byte[] Stdout);
public interface IProcessRunner { ProcessResult Run(string exe, IReadOnlyList<string> args); }
public sealed class SchtasksTaskScheduler(IProcessRunner runner, string systemDirectory) : ITaskScheduler
```

`exe` = `systemDirectory.TrimEnd('\\') + "\\schtasks.exe"` (string join, not `Path`). Exit codes only; stdout is read only from the
`/xml` query.

- **Register(name, xmlPath, expected):** run `["/create", "/tn", name, "/xml", xmlPath]` (never `/f`). Non-zero `c` → Error
  `could not schedule (schtasks exit <c>)`, nothing else run. Then `["/query", "/tn", name, "/xml"]`; non-zero `q` → field
  `query exit <q>`. Else `TaskXml.Parse(stdout)`: `FormatException` → field = the message up to its first `:`; then compare to
  `expected` in this order: `Id`, `Run` (instant), `Expires` (instant), `UserSid` (ignore case), `PlanDir` (ignore case),
  `Description`, then `SecurityDescriptor` (`TaskXml.SecurityDescriptorOf(stdout)` against the form recorded by P10; until P10 the
  string `D:P(A;;FA;;;<SID>)(A;;FA;;;SY)(A;;FA;;;BA)`). First mismatch → field = its name. On any field: run
  `["/delete", "/tn", name, "/f"]`; exit 0 → Error `scheduled task does not match the plan (<field>); it was removed`; non-zero `d` →
  Error `scheduled task does not match the plan (<field>); removing it failed (schtasks exit <d>)`. All equal → Ok.
- **Exists(name):** `["/query", "/tn", name]` exit 0 → true, else false.
- **Delete(name):** `["/delete", "/tn", name, "/f"]` exit 0 → Ok. Non-zero `d` → `Exists(name)`; false → Ok (already gone); true →
  Error `schtasks exit <d>`.

### 6. Real Windows classes (new `src/Dirused.Common/ScheduleWindows.cs`, every class `[SupportedOSPlatform("windows")]`)

Framework types only (`System.Security.AccessControl`, `System.Security.Principal`, `System.Diagnostics.Process`, one
`QueryDosDeviceW` P/Invoke). No NuGet package, no COM. If a type is not in the shared framework for `net10.0`, stop and report.

- **`RealProcessRunner : IProcessRunner`:** `ProcessStartInfo(exe)` with `ArgumentList`, `UseShellExecute = false`,
  `CreateNoWindow = true`, stdout and stderr redirected (stderr drained and discarded), stdout copied as raw bytes from
  `BaseStream`; 60 s timeout → kill the process tree, `ExitCode = -1`.
- **`RealPlanStore(string purgeLogPath) : IPlanStore`:** `Exists` = file or directory; `IsReparsePoint` from
  `File.GetAttributes` (missing → false); `CreateDirectory` fails with `already exists` if present, else `Directory.CreateDirectory`;
  `WriteNew` = `FileMode.CreateNew`, `FileShare.None`, flushed; `ReadAll` = `File.ReadAllBytes`, any I/O or access error → null;
  `ListDirectoryNames` = directory names only, missing → empty; `DeleteTree` = recursive delete of a directory or delete of a file,
  missing → Ok; `AppendLog` appends `line` + `Environment.NewLine` to `purgeLogPath` (`FileMode.Append`, `FileShare.Read`, creating
  its folder) as the purge log is written today; `MoveNew` = `File.Move(from, to, overwrite: false)`. Errors → `SeamResult(false,
  ex.Message)`, never thrown.
- **`RealPlanFolderSecurity : IPlanFolderSecurity`:**
  - `ReadAcl(path)`: missing → `AclRead(false, true, null, null, [], null)`. Drive check first: the path's `X:\` root must have
    `DriveInfo.DriveType == Fixed` and `QueryDosDeviceW("X:")` must not start with `\??\` (a `subst` drive); else `Ok = false`,
    `Missing = false`, `Error = "not on a local fixed drive"`. Then `GetAccessControl(Access | Owner)` on the file or directory;
    `GetOwner(typeof(SecurityIdentifier))`; `GetAccessRules(true, true, typeof(SecurityIdentifier))`, one `AclEntry` per rule:
    `Sid`, `Display` (`NTAccount` translation, or `unresolved account <sid>` when it does not map), `Rights =
    AclRights.FromMask((int)rule.FileSystemRights)`, `InheritOnly = PropagationFlags.HasFlag(InheritOnly)`, `Allow =
    AccessControlType.Allow`. Owner display the same way. Any exception → `Ok = false`, `Error = ex.Message`.
  - `Secure(path, userSid)`: a new `DirectorySecurity`; owner = `userSid`; `SetAccessRuleProtection(true, false)`; one rule
    `userSid` `FullControl`, `ContainerInherit | ObjectInherit`, `None`, `Allow`; applied with `SetAccessControl`. Errors →
    `SeamResult(false, ex.Message)`.
- **`RealTrustStore(string path, IPlanFolderSecurity security, string userSid) : ITrustStore`**, path
  `<LocalApplicationData>\dirused\trust.txt`: UTF-8 without BOM, one line per entry `<SID>\t<display>\n`. `Load`: missing → empty;
  lines without a tab or with an empty SID are skipped. `Add`/`Remove`: create `...\dirused` if missing and `Secure` it (as
  `ScheduleCommands` does), write the whole new list to `trust.tmp`, then `File.Move(trust.tmp, trust.txt, overwrite: true)`.
- **`RealAccountResolver : IAccountResolver`:** input matching `\AS-1-[0-9]+(-[0-9]+)+\z` → `SecurityIdentifier`, display from
  `NTAccount` translation; does not map → **null** (`TrustCommands` then makes the `unresolved account <sid>` entry itself). Otherwise
  `NTAccount(input).Translate(SecurityIdentifier)` and display = the translated `NTAccount` value; failure → null.
- **`WindowsSchedule.Create(string toolVersion) : ScheduleSeams`** and **`WindowsSchedule.RunSeams() : RunPlanSeams`**: `Now =
  DateTimeOffset.Now`, `Local = TimeZoneInfo.Local`, `PlanRoot = GetFolderPath(LocalApplicationData) + "\dirused\plans"` (never the
  environment variable), `UserSid = WindowsIdentity.GetCurrent().User.Value`, `ExePath = Environment.ProcessPath`, `IdSuffix =
  RandomNumberGenerator.GetInt32(0x10000)`, `Token` = High when `WindowsPrincipal.IsInRole(Administrator)` (true only for an
  elevated token under UAC) else Medium, `Store = RealPlanStore(PurgeLog.DefaultPath)`, `Security = RealPlanFolderSecurity`,
  `Scheduler = SchtasksTaskScheduler(RealProcessRunner, Environment.SystemDirectory)`, `Trust = RealTrustStore`, `Accounts =
  RealAccountResolver`, `ProcessImagePath = pid → Process.GetProcessById(pid).MainModule?.FileName`, null on any exception. Run
  seams: `RealPurgeFileSystem`, `RealServiceQuery`, `IsFixedDrive = null` (as `RunFromList` passes today), `DateTime.UtcNow`,
  `Environment.ProcessId`, `PurgeLog.DefaultPath`.

### 7. `AclRights.FromMask(int mask)` (new `src/Dirused.Common/AclRights.cs`, portable, pure)

`(mask & 0x1F01FF) == 0x1F01FF` (FullControl) or `mask & 0x10000000` (GENERIC_ALL) → `GenericAll` only. Otherwise the union of:
`0x2` WriteData/CreateFiles → `Write`; `0x4` AppendData/CreateDirectories → `Append`; `0x10000` Delete → `Delete`; `0x40`
DeleteSubdirectoriesAndFiles → `DeleteChild`; `0x40000` ChangePermissions → `WriteDac`; `0x80000` TakeOwnership → `WriteOwner`;
`0x40000000` GENERIC_WRITE → `GenericWrite | Write | Append`. Other bits (read, execute, attributes, synchronize) → nothing. So
`Modify` (`0x301BF`) → `Write | Append | Delete`; `ReadAndExecute` → `None`.

### 8. Program wiring (`src/Dirused.Cli/Program.cs`)

- Delete the refusal at `Program.cs:60` and `Schedule.NotAvailableForm` (`Schedule.cs:8`) with its asserts
  (`ScheduleTests.cs:61-69`). `Schedule.Run` and its `/confirm` refusal stay (Program no longer calls it with `/confirm`).
- New public seam, which `RunCore` uses with real seams when called from `Main` on Windows:
  `public static int RunWithSchedule(string[] args, TextWriter output, TextWriter error, ScheduleSeams seams, RunPlanSeams runSeams,
  IReleaseSource? source = null, IServiceControl? control = null, TextReader? input = null, bool? isInputRedirected = null)`.
  `control` reaches only the attended `/fromlist` path.
- After `ArgParser.Parse` succeeds, before the path checks and before any update check:
  - `/runplan <id>` → `PlanRunner.RunPlan`.
  - `/schedule /list` → `SchedulePlans.List`; `/schedule /cancel <id>` → `SchedulePlans.Cancel`; `/schedule /trust [acct]` →
    `TrustCommands.Trust`; `/schedule /untrust <acct>` → `TrustCommands.Untrust`.
  - On a non-Windows OS (and no seams injected) each of these, and `/schedule` with `/confirm`, exits 1 with
    `/schedule needs Windows` on stderr and writes nothing to stdout.
- `/fromlist <list> ... /schedule <time>`: on Windows (or with injected seams) read the list with `File.ReadAllBytes` **once** (I/O
  error → `not a dirused delete list: <list>`, exit 1) and call `ScheduleCommands.Schedule(new ScheduleRequest(options, bytes,
  options.FromList, Path.GetFullPath(options.FromList)), seams, output, error, input, inputRedirected)`. `PurgeList.Read` is not
  called on this path. Elsewhere the preview stays on `Schedule.Run` as today.
- `/runplan` and every `/schedule` form never start the update check and never call the release source.
- Replace `tests/Dirused.Tests/ProgramScheduleRefusalTests.cs` (it asserts the removed refusal) with `ProgramScheduleTests.cs`.

## Files

New: `src/Dirused.Common/PlanRunner.cs`, `TaskScheduling.cs`, `ScheduleWindows.cs`, `AclRights.cs`;
`tests/Dirused.Tests.Portable/RunPlanTests.cs`, `SchtasksTests.cs`, `AclRightsTests.cs`;
`tests/Dirused.Tests/ScheduleWindowsTests.cs`, `ProgramScheduleTests.cs`.
Changed: `src/Dirused.Common/ScheduleSeams.cs` (one default member), `PurgeList.cs` (`ToResults`), `Schedule.cs` (remove
`NotAvailableForm`), `src/Dirused.Cli/Program.cs`, `tests/Dirused.Tests.Portable/ScheduleTests.cs` (lines 61-69 only).
Deleted: `tests/Dirused.Tests/ProgramScheduleRefusalTests.cs`.

## Contract readers

| Contract | Readers / writers (grep, `ab98677`) | Change |
|---|---|---|
| `IPlanStore` | implementers `ScheduleFakes.cs:5`, `ScheduleCommandsTests.cs:30`, `SchedulePlansTests.cs:16`; new `RealPlanStore` | `MoveNew` added with a default body; implementers unchanged |
| `claim` | writer b2e `SchedulePlans.Cancel` (`cancel <time>`); reader `SchedulePlans.ParseClaim` `:132`; new writer `PlanRunner` (`run <time> pid <n>`) | none (format as contract) |
| `report.txt` | reader `SchedulePlans.List` via `ParseFields` `:47-57,108`; new writer `PlanRunner` | none; header lines as contract, outcome verbatim |
| `plan.txt` | writer `ScheduleCommands.Schedule`; readers `SchedulePlans` `:39`, new `PlanRunner` | none |
| interim refusal | `Program.cs:60`, `Schedule.cs:8`, `ScheduleTests.cs:61-69`, `ProgramScheduleRefusalTests.cs:30` | removed |
| list grouping | `Program.cs:197` | moved to `PurgeList.ToResults`, caller updated |
| purge log path | `PurgeLog.DefaultPath` (`Purge.cs:51`); `RunFromList` | `RealPlanStore.AppendLog` writes the same file |

## What NOT to Do

- Do not edit `ScheduleCommands.cs`, `SchedulePlans.cs`, `PlanTrust.cs`, `TrustCommands.cs`, `TaskXml.cs` or `Purge.cs`. If one of
  them blocks the spec, stop and report.
- Do not call `IServiceControl` from `/runplan`, read the original list, or read `list.txt` twice.
- Do not take the claim before the expiry and start-window checks; do not write a report on a stderr outcome.
- Do not replace an existing `report.txt`. Do not delete plan dirs from the scheduler or from `/runplan`.
- Run `schtasks.exe` only through `IProcessRunner` by absolute path: no shell, no command string, no `/f` on create, no stdout text
  parsing (exit codes, plus the `/xml` document). No COM, no NuGet package.
- Do not register a task in CI outside `\dirused-ci\` or leave one behind. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B3-M1
    text: "RunPlan on a plan written by ScheduleCommands.Schedule (in-memory IPlanStore, FakeFolderSecurity reporting the plan files user-only and the ancestors as ScheduleFakes.StockSystemDrive, clock = run instant, fake IPurgeFileSystem with 3 listed files matching identity, size and time, not held, and 1 held by Tomcat85): claim = 'run <time> pid <Pid>', 3 files deleted, the held row has 'skipped: held by Tomcat85 — scheduled runs do not stop services', report.txt has outcome done, exit 0, result 'deleted 3 file(s), <size> freed; 1 skipped; 0 failed', the four rows, '--- purge log' with this run's delete lines, '--- stderr'; report.tmp absent; exit 0; SchedulePlans.List then prints the done row"
  - id: B3-M2
    text: "stderr outcomes, each with its exact line, the same line in the purge log as 'runplan <id>: <line>', exit 1, and no WriteNew of claim, report.tmp or report.txt: bad id regex; missing plan.txt; ExePath not <planDir>\\dirused.exe; a reparse point on each of the six paths ('plan folder contains a link'); an ACE for another SID on plan.txt ('plan folder permissions changed'); start at run-2min; start at run+16min"
  - id: B3-M3
    text: "report outcomes, each taking the claim then writing report.txt with that outcome and exit, and no IPurgeFileSystem delete: plan.txt missing 'trusted' ('refused: not a dirused plan', 1); expires != created+24h (same); exe bytes changed ('refused: program copy changed since it was scheduled', 1); list.txt changed ('refused: list changed since it was scheduled', 1); clock = expires ('expired', 0); JumpBoxProfile ancestors with '# trusted: none' ('refused: C:\\Users\\op can be changed by PROD\\admin2 (full control)', 1)"
  - id: B3-M3b
    text: "positive control for the trust re-check: the same JumpBoxProfile plan with '# trusted: S-1-5-21-1-2-3-2001,S-1-5-21-9-9-9-8249' deletes the matching files and reports done"
  - id: B3-M4
    text: "claim already 'cancel ...' → stderr 'cancelled', exit 0, no delete, no report; claim already 'run ...' → stderr 'refused: plan already started', exit 1, report not written; both also when the plan is expired (step 5a)"
  - id: B3-M5
    text: "report.txt present before the run (claim absent): MoveNew fails, the existing report.txt is byte-identical afterwards, stderr 'error: could not write report: <error>', the exit code equals the run's, and the purge log has 'runplan <id>: report failed: <error>'"
  - id: B3-M6
    text: "SchtasksTaskScheduler with a recording IProcessRunner and systemDirectory 'C:\\Windows\\System32': Register records exe 'C:\\Windows\\System32\\schtasks.exe' and argv exactly ['/create','/tn',<name>,'/xml',<path>] (no '/f') then ['/query','/tn',<name>,'/xml']; a query returning TaskXml.Build(expected) is Ok with no third call; a query whose XML differs in one field (AllowStartOnDemand true, StartWhenAvailable true, EndBoundary +1h, LogonType Password, Arguments changed, Description changed) records ['/delete','/tn',<name>,'/f'] and Error 'scheduled task does not match the plan (<Field>); it was removed' naming that field; delete exit 1 → '...; removing it failed (schtasks exit 1)'; create exit 1 → Error 'could not schedule (schtasks exit 1)' and no query; query exit 1 → field 'query exit 1' and the delete; Exists maps exit 0/1 to true/false; Delete exit 1 then query exit 1 → Ok, then query exit 0 → Error 'schtasks exit 1'"
  - id: B3-M7
    text: "AclRights.FromMask: FullControl 0x1F01FF → GenericAll only; GENERIC_ALL → GenericAll; Modify 0x301BF → Write|Append|Delete; ReadAndExecute 0x1200A9 → None; AppendData 0x4 → Append; 0x40 → DeleteChild; 0x40000 → WriteDac; 0x80000 → WriteOwner; GENERIC_WRITE → GenericWrite|Write|Append"
  - id: B3-M8
    text: "windows-latest: RealPlanFolderSecurity.Secure on a temp dir → ReadAcl shows owner = current SID and every entry the current SID; PlanTrust-style finding appears after adding an Everyone write ACE; a junction is IsReparsePoint true and ReadAcl is not needed; ReadAcl on a path under a 'subst' drive letter of the temp dir → Ok false, Error 'not on a local fixed drive' (positive control: the same path through C: reads Ok); RealPlanStore WriteNew on an existing file fails and MoveNew onto an existing file fails, leaving it byte-identical"
  - id: B3-M9
    text: "windows-latest: SchtasksTaskScheduler with RealProcessRunner registers '\\dirused-ci\\<SID>\\purge-<guid>' one day ahead from TaskXml.Build's file, the verify compare passes, a second Register of the same name returns 'could not schedule (schtasks exit <non-zero>)', Exists true, Delete Ok, Exists false (delete in finally)"
  - id: B3-M10
    text: "Program via RunWithSchedule with fakes: '/fromlist l /purge /schedule 22:30 /confirm /yes' reaches ScheduleCommands.Schedule (FakeTaskScheduler records Register) and reads the list file once; '/runplan <id>' reaches PlanRunner (claim written); '/schedule /list', '/schedule /cancel <id>', '/schedule /trust', '/schedule /untrust x' reach their commands; none calls the recording IReleaseSource; 'is not available in this version' appears nowhere"
must_not:
  - id: B3-N1
    text: "RunPlan deletes a listed row whose size, last-write or file ID differs from the list — positive control: the matching row in the same run is deleted. baseline: mutant-only (PlanRunner absent at ab98677); mutant 'scheduled: false' or 'skip identity match' turns it red"
  - id: B3-N2
    text: "RunPlan calls any IServiceControl method: a recording control passed to RunWithSchedule records nothing for '/runplan <id>' with a Tomcat-held row. Positive control: the same seam records Stop/Start for an attended '/fromlist l /purge /confirm /yes' at 22:30. baseline: mutant-only; mutant 'pass control to Apply' turns it red"
  - id: B3-N3
    text: "a start outside [run-1m, run+15m] creates the claim or a report. Positive control: start at run creates the claim. baseline: mutant-only; mutant 'claim before the window check' turns it red"
  - id: B3-N4
    text: "an expired plan deletes anything — positive control: the same plan at expires-1min with run moved inside the window by the fixture deletes. baseline: mutant-only; mutant '> instead of >=' turns it red"
  - id: B3-N5
    text: "RunPlan reads the '# source:' path or reads list.txt more than once (recording store). Positive control: ReadAll(list.txt) count = 1. baseline: mutant-only; mutants 'read source list' and 'read list twice' turn it red"
  - id: B3-N6
    text: "RunPlan or SchtasksTaskScheduler calls IPlanStore.DeleteTree on the plan dir (recording store), in any outcome including a Register mismatch. Positive control: ScheduleCommands.Schedule with a failing FakeTaskScheduler does DeleteTree the plan dir. baseline: mutant-only"
evidence:
  - id: E-B3
    proves: [B3-M1, B3-M2, B3-M3, B3-M3b, B3-M4, B3-M5, B3-M6, B3-M7, B3-N1, B3-N3, B3-N4, B3-N5, B3-N6]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable. Mutants each red: '/f' on create; skip the verify compare; compare ignores Description; delete not called on mismatch; claim before window check; window +30 min; expiry > instead of >=; skip exe hash; skip list hash; read list twice; read source list; scheduled false; report written directly (no tmp); MoveNew with overwrite; skip IsIntact; skip trust re-check; trust copy ignored (empty set always); Modify mapped without Delete; FullControl mapped as its bits"
    intent: "The scheduled run deletes only files that are exactly the ones you reviewed, never touches Tomcat, refuses if the plan, its program copy or its folder changed, and leaves a report you can read in the morning."
  - id: E-B3W
    proves: [B3-M8, B3-M9, B3-M10, B3-N2]
    kind: offline
    command: "windows-latest CI job (ci.yml 'windows', dotnet test -c Release). If P9 shows the runner cannot register an interactive-token task, B3-M9 asserts the generated XML only and the spec records that. Program-only mutants (wiring removed, update check started) are proved by a scratch branch whose windows job fails, then deleted"
    intent: "The real Windows task and folder-permission calls are checked on a throwaway task in CI, so a wrong setting is caught before it reaches the jump box."
  - id: E-B3L1
    proves: [B3-M1]
    kind: live
    command: "operator, jump box, attended, after P1-P3, P6, P10, P12: trust the accounts the /schedule refusal names (operator's call for S-1-5-21-…-8249); save a list of 2-3 small non-held test files in a scratch share folder; dirused /fromlist t.txt /purge /schedule <now+5min> PT (preview), then the same with /confirm, answer y; stay connected; after the run: dirused /schedule /list shows done; report.txt shows them deleted; then schedule a second plan and /schedule /cancel it: list shows cancelled and the files remain"
    intent: "While you watch, a scheduled run deletes a few test files from a list you reviewed, and a cancelled plan deletes nothing."
  - id: E-B3L2
    proves: [B3-M1]
    kind: live
    command: "operator, jump box, disconnected: dirused \\\\us03p02ffm01\\d$\\Tomcat /largest *.log /purge /savelist m10b.txt; review; /schedule <evening time> PT /confirm, y; disconnect RDP (do not sign out); next morning: /schedule /list shows done; report.txt lists deleted rotated logs and the held tomcat85-stderr/stdout rows as 'skipped: held by Tomcat85 — scheduled runs do not stop services'; sc \\\\us03p02ffm01 query tomcat85 shows RUNNING with an unchanged start time; free space on d$ rose by the reported amount"
    intent: "You schedule tonight's purge, disconnect, and in the morning see the old logs gone, the logs Tomcat holds left alone, and Tomcat never restarted."
interface:
  - "/runplan <id>"
  - "refused: not a plan id: <id>"
  - "refused: not started from the plan's program copy"
  - "refused: plan folder contains a link"
  - "refused: plan folder permissions changed"
  - "refused: not a dirused plan"
  - "refused: not the scheduled time (scheduled <time>)"
  - "refused: plan already started"
  - "cancelled"
  - "refused: <path> can be changed by <display> (<rights>)"
  - "refused: program copy changed since it was scheduled"
  - "refused: list changed since it was scheduled"
  - "error: could not claim plan: <error>"
  - "error: could not write report: <error>"
  - "could not schedule (schtasks exit <code>)"
  - "scheduled task does not match the plan (<field>); it was removed"
  - "scheduled task does not match the plan (<field>); removing it failed (schtasks exit <code>)"
  - "not on a local fixed drive"
  - "/schedule needs Windows"
```

## Deferred

- Program Files self-update notice (`ask IT to update C:\Program Files\dirused` instead of offering `/update`, D14): a follow-up
  spec, not M10b3.

## Shared contract (copied from the parent, rev 5, for the worker; the parent file is not in the dirused repo)

The code on the branch already implements this. `IPlanStore.MoveNew` (§1 above) is the only addition.


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

