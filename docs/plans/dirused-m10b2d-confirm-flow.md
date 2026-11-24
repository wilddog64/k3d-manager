# dirused M10b2d: the `/schedule /confirm` flow (preview, prompt, re-check, trust, plan creation, register) with fakes

**Status:** LANDED — `ab98677` on `m10b-scheduled-purge` (2026-11-24); verifier round 1 FAIL (extras before Held; id from created), correction 1 fixed both and ported the verifier's 45 checks; Claude mutants red; windows CI run 45473345605 pending
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md) (rev 4); design [M10b](dirused-m10b-scheduled-purge.md) §4.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (after [b2b](dirused-m10b2b-parser-usage.md) and [b2c](dirused-m10b2c-seams-and-trust.md))
**Risk:** medium — creates plan folders and registers tasks through seams; real classes and Program wiring are M10b3
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job after landing
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries the approved E-B2 intent unchanged (parent); this child is its scheduling part.
**Approval:** operator, 2026-11-23 — D12 preview first; operator, 2026-11-24 — D14, "intents approved"

## Scope

1. **`Schedule.cs` refactor (behaviour-preserving for `Schedule.Run`)**: move the body of the preview into
   `internal static int Schedule.Preview(ParsedPurgeList list, string listPathAsTyped, DateTimeOffset created, TimeZoneInfo local,
   Options options, TextWriter stdout, TextWriter stderr, PreviewExtras? extras, out DateTimeOffset run, out string host)` so that
   `Schedule.Run` and the new flow share one formatter. `PreviewExtras(string Sha12, string TaskName, string PlanDir, string ExePath)`.
   With `extras == null` the output is byte-identical to today's after b2b (all existing `ScheduleTests` pass unchanged; keep b2b's
   `NotAvailableForm` and the ` in the list` size line). Inside `ScheduleCommands` call it as `Dirused.Common.Schedule.Preview(...)`
   (a bare `Schedule.` binds to the method `ScheduleCommands.Schedule`). With extras, after
   the size line comes `            sha256 <Sha12>`, and after the `Held:` line come `  Task:     <TaskName>`, `  Plan dir: <PlanDir>`,
   `  Program:  <PlanDir>\dirused.exe` and `            (copy of <ExePath>)`, each value written with the existing `WriteWrappedPath`
   rule (≤ 80 columns, 68-character chunks, 12-space continuation); `(copy of <ExePath>)` is one value wrapped the same way after a
   12-space prefix.
2. **`src/Dirused.Common/ScheduleCommands.cs`** (new):
   `public static int ScheduleCommands.Schedule(ScheduleRequest req, ScheduleSeams s, TextWriter stdout, TextWriter stderr, TextReader input, bool inputRedirected)`.
   Steps, in order:
   1. `PurgeList.Parse(req.ListBytes, out list)` — the only parse; false → stderr `not a dirused delete list: <ListPathAsTyped>`, exit 1.
   2. `created` = `s.Now()` truncated to whole seconds; `created`, `run` and `expires` in Pacific per the parent; id per the parent (one
      `IdSuffix()` draw); `Preview(... extras)` with
      `Sha12` = first 12 lower-case hex of SHA-256 of `ListBytes`. Preview errors (no files, host, time rules) keep M10b0's messages and
      exit codes.
   3. No `/confirm`: print `Preview only. Add /confirm to schedule it.`; bad lines → the M10b0 `Bad list lines:` block, exit 3; else
      exit 0. Only `Now`, `IdSuffix` and pure code ran; **no seam interface method is called**.
   4. `/confirm` and bad lines → `Bad list lines:` block, `/schedule: fix the list first; nothing was scheduled`, exit 3, no prompt.
   5. `/confirm` and `s.Token == High` → `/schedule: run from a normal (not elevated) window`, exit 1.
   6. Without `/yes`: `Schedule this? [y/N] ` on stderr (no newline); `inputRedirected` → no read, No; else one `ReadLine`; `y` or
      `yes` (trimmed, case-insensitive) is Yes. No → `Not scheduled.` on stdout, exit 0.
   7. Re-check: `run - s.Now() < 2 min` → `/schedule: <time as typed> is less than 2 minutes away; pick a later time`, exit 1. The time
      rules are not re-run (no silent roll to another day).
   8. Trust: `PlanTrust.Check(s.ExePath, s.PlanRoot, s.UserSid, s.Trust.Load(), s.Store, s.Security)`; not Ok → its lines on stderr,
      exit 1.
   9. Folders: for `<PlanRoot>`'s parent then `<PlanRoot>`: when not `Exists`, `CreateDirectory` (failure → exit 3
      `error: could not secure plan folder: <error>`); then `Secure(path, UserSid)` **always**, whether it existed or was just created
      (so an existing `plans` folder ends up user-only, as b2e's `IsIntact` requires). `Secure` failure → `DeleteTree` the folder if
      this run created it, exit 3 `error: could not secure plan folder: <error>`. (Links were already refused by step 8.)
   10. Plan dir `<PlanRoot>\<id>`: `CreateDirectory`; failure and `Exists` → draw a new suffix and retry (at most 5 draws in total; then
       exit 3 `error: could not write plan: no free plan id`); other failure → exit 3 `error: could not write plan: <error>`. After a
       new draw, `id`, plan dir, task name and `PlanTask` all use the new id.
       `IsReparsePoint` on it → `DeleteTree`, exit 3 link message. `Secure(planDir, UserSid)`; failure → `DeleteTree`, exit 3 secure
       message.
   11. `Store.ReadAll(ExePath)` null → `DeleteTree`, exit 3 `error: could not write plan: cannot read <ExePath>`. Then `WriteNew` in this
       order: `dirused.exe` (those bytes), `list.txt` (`ListBytes`), `task.xml` (`TaskXml.Build(planTask)`), `plan.txt` (parent format,
       `# trusted:` = every SID in `Trust.Load()` at step 8, sorted ordinal, joined by `,`, or `none`). Any
       failure → `DeleteTree`, exit 3 `error: could not write plan: <error>`.
   12. `Scheduler.Register(taskName, planDir + "\\task.xml", planTask)`; failure → `DeleteTree`, exit 3 `error: <Error>`.
   13. `Store.AppendLog("schedule <id> run <run yyyy-MM-ddTHH:mm:sszzz> files <n> bytes <total>")`; failure → stderr
       `warning: could not write the purge log: <error>` (still exit 0). Print `Scheduled <id> for ...` (parent string), exit 0.


## Files

- `src/Dirused.Common/Schedule.cs` (refactor only), `src/Dirused.Common/ScheduleCommands.cs` (new)
- `tests/Dirused.Tests.Portable/ScheduleCommandsTests.cs` (new; uses b2c's `ScheduleFakes.cs`, defines no fake types)

## What NOT to Do

- No other file; no change to `Schedule.Run`'s output; no `Program.cs` change (M10b3 wires it).
- No I/O outside the seams: no `File`, `Directory`, `Path`, `Process`, `Registry`, `FileInfo`, `DirectoryInfo`, `FileStream`,
  `StreamWriter`, `StreamReader`, `Console` in `ScheduleCommands.cs`.
- Product text written into files uses `"\n"` explicitly (plan.txt); tests use writers with `NewLine = "\n"` and literal `"\n"`.
- Leave changes uncommitted; do not push.

## Acceptance

Fixture: `Now` = Mon 2026-11-23 21:00:00.1234567 -08:00, Pacific local, list of 12 rows under `\\us03p02ffm01` totalling 176.2 GB typed
as `C:\Users\op\m10b.txt` (full path the same), `/fromlist ... /purge /schedule 22:30`, `PlanRoot` `C:\Users\op\AppData\Local\dirused\plans`,
`ExePath` `C:\Program Files\dirused\dirused.exe`, `UserSid` `S-1-5-21-1-2-3-1104`, `IdSuffix` → 0xa1b2, `ToolVersion` `0.0.28`, trust
fakes = b2c's `StockSystemDrive` (no trust needed).

D-M1 expected stdout (lines joined by "\n", final "\n"):

```text
Scheduled purge preview (nothing is scheduled yet)
  Run:      Mon 2026-11-23 22:30 PST (06:30 UTC Tue), in 1 h 30 min
  Expires:  Tue 2026-11-24 21:00 PST (05:00 UTC Wed)
  Host:     us03p02ffm01
  List:     C:\Users\op\m10b.txt
            12 file(s), 176.2 GB in the list
            sha256 <sha12>
  Held:     not checked now; files held open at run time are skipped
  Task:     \dirused\S-1-5-21-1-2-3-1104\purge-20261123-2230-a1b2
  Plan dir: C:\Users\op\AppData\Local\dirused\plans\20261123-2230-a1b2
  Program:  C:\Users\op\AppData\Local\dirused\plans\20261123-2230-a1b2\dirused.e
            xe
            (copy of C:\Program Files\dirused\dirused.exe)
It runs only while you are logged on to this machine (disconnected is fine).
Preview only. Add /confirm to schedule it.
```

```yaml
must:
  - id: D-M1
    text: "no /confirm: stdout is exactly the block below (ListBytes' SHA-256 first 12 hex in place of <sha12>), every line <= 80, exit 0, and every seam fake records zero calls"
  - id: D-M2
    text: "/confirm + 'y' (also 'YES', ' yes '): 'Schedule this? [y/N] ' on stderr; recorded order: Trust.Load, ReadAcl/IsReparsePoint per path, CreateDirectory+Secure for '...\\\\dirused' and 'plans', CreateDirectory+Secure plan dir, ReadAll(exe), WriteNew dirused.exe, list.txt, task.xml, plan.txt, Register, AppendLog; dirused.exe bytes = the fake exe bytes; list.txt = ListBytes; task.xml = TaskXml.Build(planTask) with Run 2026-11-23T22:30:00-08:00, Expires 2026-11-24T21:00:00-08:00 (created truncated: no exception); plan.txt equals the parent format line for line with 'created: 2026-11-23T21:00:00-08:00' and '# trusted: none', ending with '\\n' and no '\\r'; Register(taskName '\\\\dirused\\\\S-1-5-21-1-2-3-1104\\\\purge-20261123-2230-a1b2', '<plan dir>\\\\task.xml'); AppendLog 'schedule 20261123-2230-a1b2 run 2026-11-23T22:30:00-08:00 files 12 bytes <total>'; stdout ends 'Scheduled 20261123-2230-a1b2 for Mon 2026-11-23 22:30 PST (06:30 UTC Tue). Check it with: dirused /schedule /list'; exit 0"
  - id: D-M3
    text: "'/confirm /yes': no prompt written, no read, one Register. '/confirm' with inputRedirected: no read, 'Not scheduled.', exit 0, only Trust-free pure steps ran (zero seam calls). '/confirm' + 'n' or empty: 'Not scheduled.', zero seam calls"
  - id: D-M4
    text: "re-check: the fake reader advances Now to 22:28:30 before returning 'y' → '/schedule: 22:30 is less than 2 minutes away; pick a later time', exit 1, zero writes and no Register"
  - id: D-M5
    text: "Token High with /confirm → '/schedule: run from a normal (not elevated) window', exit 1, no prompt, zero seam calls; Token Medium proceeds (D-M2)"
  - id: D-M6
    text: "bad list lines with /confirm → preview (no 'Preview only' line), 'Bad list lines:' block, '/schedule: fix the list first; nothing was scheduled', exit 3, no prompt, zero seam calls; not-a-list bytes → 'not a dirused delete list: C:\\\\Users\\\\op\\\\m10b.txt', exit 1"
  - id: D-M7
    text: "trust: with b2c's JumpBoxProfile fake and an empty store → b2c's T-M3 refusal lines on stderr, exit 1, no CreateDirectory/WriteNew/Register; with PROD\\\\admin2 (S-1-5-21-1-2-3-2001) and S-1-5-21-9-9-9-8249 stored → registers and plan.txt says '# trusted: S-1-5-21-1-2-3-2001,S-1-5-21-9-9-9-8249'"
  - id: D-M8
    text: "failures: plan-dir CreateDirectory fails with Exists true twice → ids with the 2nd and 3rd suffix draws, success on the 3rd, printed id is the 3rd; five collisions → exit 3 'error: could not write plan: no free plan id'; Secure(plan dir) fails → DeleteTree(plan dir), exit 3 'error: could not secure plan folder: <error>', no WriteNew; WriteNew(task.xml) fails → DeleteTree, exit 3 'error: could not write plan: <error>', no Register; ReadAll(exe) null → exit 3 'error: could not write plan: cannot read C:\\\\Program Files\\\\dirused\\\\dirused.exe'; Register fails with 'could not schedule (schtasks exit 1)' → DeleteTree, exit 3 'error: could not schedule (schtasks exit 1)'; the plan dir reported as a reparse point after CreateDirectory → DeleteTree, exit 3 'error: could not secure plan folder: C:\\\\Users\\\\op\\\\AppData\\\\Local\\\\dirused\\\\plans\\\\20261123-2230-a1b2 is a link'; an existing 'plans' folder with inherited Administrators entries is passed to Secure (recorded) before the plan dir is created; Secure fails on a 'plans' folder this run created → DeleteTree('plans'), exit 3; AppendLog fails → warning line, exit 0"
  - id: D-M9
    text: "Schedule.Run (M10b0 entry) output and exit codes are unchanged: every existing ScheduleTests assertion passes without edits"
must_not:
  - id: D-N1
    text: "preview-only, No, redirected input, Token High, bad lines or a trust refusal records any CreateDirectory, Secure, WriteNew, Register or Trust.Add. Positive control: D-M2 records them. Mutant-only (ScheduleCommands absent on e19783f): 'register before the decision', 'create plan dir before the trust check', 'skip elevation check' each turn D-M3, D-M5 or D-M7 red"
  - id: D-N2
    text: "a WriteNew into the plan dir is recorded before Secure(plan dir) returned Ok. Positive control: D-M2 order. Mutant 'write files then secure'"
  - id: D-N3
    text: "ScheduleCommands.cs (comments stripped) contains 'PurgeList.Parse(' other than exactly once, or matches \\\\b(File|Directory|Path|Process|Registry|FileInfo|DirectoryInfo|FileStream|StreamWriter|StreamReader|Console)\\\\s*[.(]. Positive control: mutant adding a second PurgeList.Parse call turns the scan red"
evidence:
  - id: E-D
    proves: [D-M1, D-M2, D-M3, D-M4, D-M5, D-M6, D-M7, D-M8, D-M9, D-N1, D-N2, D-N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4; ScheduleCommandsTests do not compile on the pre-dispatch tip; mutants each red with the catching test named: register before the decision [D-N1]; plan dir before trust [D-N1, D-M7]; skip re-check [D-M4]; re-check re-runs the time rules [D-M4]; created not truncated [D-M2]; write then secure [D-N2]; no DeleteTree on Register failure [D-M8]; id regenerated without a collision [D-M2]; '# trusted:' omitted [D-M2, D-M7]; elevation check removed [D-M5]; Program line not wrapped [D-M1]"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling, dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."
  - id: E-DW
    proves: [D-M2, D-M9]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "ScheduleCommands.Schedule(ScheduleRequest, ScheduleSeams, TextWriter stdout, TextWriter stderr, TextReader input, bool inputRedirected) -> int"
  - "Schedule.Preview(..., PreviewExtras? extras, out run, out host) (internal)"
  - "not a dirused delete list: <path>"
  - "warning: could not write the purge log: <error>"
  - "error: could not write plan: no free plan id"
  - "error: could not write plan: cannot read <ExePath>"
```

## Shared contract (copied from the parent, rev 5, for the worker; the parent file is not in the dirused repo)

Already in the repo from earlier children: `src/Dirused.Common/ScheduleSeams.cs`, `PlanTrust.cs`, `TrustCommands.cs` (b2c, `e7970ff`)
and the shared fakes `tests/Dirused.Tests.Portable/ScheduleFakes.cs` (`StockSystemDrive()`, `JumpBoxProfile()`). b2c's T-M3 refusal
lines are asserted in `tests/Dirused.Tests.Portable/PlanTrustTests.cs`. Read those files; do not redefine their types.

## Shared contract

#### Interfaces (`src/Dirused.Common/ScheduleSeams.cs`, written by b2c; every member below, nothing more)

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

#### Ids, names and times

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

#### `plan.txt` (UTF-8 without BOM, lines end with `"\n"` written explicitly)

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

#### Trust rules (D14 as revised by the rev 3 reviews)

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

#### Exact strings used by more than one child

`Preview only. Add /confirm to schedule it.` · `Schedule this? [y/N] ` (stderr, no newline) · `Not scheduled.` ·
`Scheduled <id> for <run as on the preview Run line, without the relative part>. Check it with: dirused /schedule /list` (e.g. `Scheduled 20261123-2230-a1b2 for Mon 2026-11-23 22:30 PST (06:30 UTC Tue). Check it with: dirused /schedule /list`) ·
`/schedule: run from a normal (not elevated) window` · `/schedule: fix the list first; nothing was scheduled` ·
`error: could not secure plan folder: <error>` · `error: could not write plan: <error>` · `error: <Register error>` ·
purge-log lines `schedule <id> run <run ISO> files <n> bytes <total>` and `schedule-cancel <id>`.

#### `claim` and `report.txt` (writer M10b3 `/runplan`; reader b2e)

`claim` (UTF-8, one line): `run <yyyy-MM-ddTHH:mm:sszzz> pid <n>` or `cancel <yyyy-MM-ddTHH:mm:sszzz>`, written with `WriteNew`.
`report.txt` header lines `# outcome: <text>` (parent §6: `done`, `expired`, `refused: <reason>`, shown verbatim) and, for `done`,
`# result: <text>` and `# exit: <n>`. Readers tolerate `\r\n` and a missing final newline.

#### Notes for M10b3's real seams

- `WriteRights` from a Windows ACE: `FullControl` → `GenericAll`; `Modify` → `Write | Append | Delete`; `Delete`, `DeleteSubdirectoriesAndFiles`,
  `ChangePermissions`, `TakeOwnership`, `WriteData`/`CreateFiles`, `AppendData`/`CreateDirectories` map to their bits; generic-write
  ACEs → `GenericWrite` plus the bits they imply.

