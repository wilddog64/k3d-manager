# dirused M10b2e: `/schedule /list` and `/schedule /cancel` (pure, with fakes)

**Status:** OPEN — SPEC rev 2, 2026-11-24; intents approved (carries E-B2); starts after b2c lands (parallel with b2d); round-2 reviews applied (parent table)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md) (rev 4); design [M10b](dirused-m10b-scheduled-purge.md) §5 path checks 3–4, §7.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (after [b2c](dirused-m10b2c-seams-and-trust.md))
**Risk:** medium — cancel must never race a started run; no real scheduler call here
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job after landing
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries the approved E-B2 intent unchanged (parent); this child is its list-and-cancel part.
**Approval:** operator, 2026-11-24 — "intents approved"

## File formats this child reads

As the parent's "`claim` and `report.txt`" section (writer M10b3) and `plan.txt` (writer b2d). Lines are read tolerant of `\r\n` and
a missing final newline. The report outcome is shown verbatim (`done`, `expired`, `refused: <reason>`, or anything else written).

## Scope

`src/Dirused.Common/SchedulePlans.cs` (new):

```csharp
public static class SchedulePlans
{
    public static bool IsIntact(string planDir, ScheduleSeams s);   // parent §5 path checks 3–4
    public static int List(ScheduleSeams s, TextWriter stdout, TextWriter stderr);
    public static int Cancel(string id, ScheduleSeams s, TextWriter stdout, TextWriter stderr);
}
```

1. **`IsIntact`**: none of `<PlanRoot>`'s parent, `<PlanRoot>`, the plan dir, `plan.txt`, `list.txt`, `dirused.exe` is a reparse point;
   `ReadAcl` of `<PlanRoot>`, the plan dir and the three files is Ok, owner = `UserSid`, and every allow entry (inherit-only included)
   has SID `UserSid`. Any miss → false.
2. **`List`**: `ListDirectoryNames(PlanRoot)`; keep names matching `\A[0-9]{8}-[0-9]{4}-[0-9a-f]{4}\z`, ignore others. Task name =
   `\dirused\<s.UserSid>\purge-<id>`. A readable plan needs: first line `# dirused plan v1`, `# id:` equal to the folder name, `# run:`
   parsing as `DateTimeOffset`, `# files:` and `# bytes:` non-negative integers, `# host:` and `# source:` non-empty; else state 2.
   A missing `plan.txt` fails `IsIntact` (its ACL cannot be read), so it shows state 1. Times print in Pacific (a private Pacific
   lookup in this file, as `Schedule.cs` does; `Schedule.cs` is not changed here). None → `No scheduled
   purges.`, exit 0. Per plan, the state is the first match:
   1. `!IsIntact` → `permissions changed — not run`
   2. `plan.txt` unreadable (`ReadAll` null) or missing a field the row needs → `unreadable plan`
   3. claim `cancel` → `cancelled`
   4. claim `run` and `report.txt` readable → its outcome verbatim; `done` → `done (<result>, exit <n>)`
   5. claim `run`, no report, `ProcessImagePath(pid)` equals `<plan dir>\dirused.exe` (ordinal, ignore case) → `running`
   6. claim `run`, no report → `interrupted (started <claim time as ddd HH:mm PST|PDT>, no report) — check the list and the report folder`
   7. no claim and `Now() > run + 15 min` → `missed (did not run)`
   8. `!Scheduler.Exists(taskName)` → `task missing`
   9. otherwise `scheduled`

   Row (two spaces between fields, no padding): `<id>  <run as ddd yyyy-MM-dd HH:mm PST|PDT>  <host>  <state>  <n> file(s) <size>  <source file name>`
   where `<size>` is `Format.Size(bytes)` and `<source file name>` is the last `\`-separated part of `# source:`. States 1–2 print
   `<id>  -  -  <state>`. Order: plans with a readable run, newest run first (ties: id descending); then the others by id descending. Exit 0.
3. **`Cancel(id)`**: id not matching the pattern, or plan dir missing → exit 1 `unknown plan id: <id>`. `!IsIntact` → exit 1
   `refused: plan folder permissions changed`. `WriteNew(<plan dir>\claim, "cancel <Now ISO>\n")`; it fails and the existing claim
   reads `run ...` → exit 1 `<id> already started; it cannot be cancelled`; reads `cancel ...` → `<id> is already cancelled`, exit 0;
   other failure → exit 3 `error: could not cancel <id>: <error>`. Then `Scheduler.Delete(taskName)`; failure → exit 3
   `error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run` (claim stays). Then
   `AppendLog("schedule-cancel <id>")` (failure → `warning: could not write the purge log: <error>`), `Cancelled <id>.`, exit 0.

## Files

- `src/Dirused.Common/SchedulePlans.cs` (new), `tests/Dirused.Tests.Portable/SchedulePlansTests.cs` (new; uses b2c's `ScheduleFakes.cs`, defines no fake types)

## What NOT to Do

- No other file; no `Program.cs` change; no real file, process or scheduler call (`ProcessImagePath` is the seam).
- No `File`, `Directory`, `Path`, `Process`, `Registry`, `Console` in `SchedulePlans.cs`; tests use `NewLine = "\n"`, literal `"\n"`.
- Never delete a plan dir. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: L-M1
    text: "List over nine fixture plans, one per state 1-9, prints each with its exact state text; two-condition fixtures (claim cancel + not intact; claim run + report + live pid; no claim + past run+15 + task missing) show the earlier state; rows match the literal format, e.g. '20261123-2230-a1b2  Mon 2026-11-23 22:30 PST  us03p02ffm01  scheduled  12 file(s) 176.2 GB  m10b.txt'; states 1-2 rows are '<id>  -  -  <state>'; order newest run first, unreadable last; a dir named 'notes' is ignored; missing plan root → 'No scheduled purges.'"
  - id: L-M2
    text: "running vs interrupted: claim 'run ... pid 42' with ProcessImagePath(42) = '<plan dir>\\\\dirused.exe' → running; = 'C:\\\\Windows\\\\notepad.exe' or null → interrupted (started Mon 22:30 PST, no report) — ...; done report → 'done (deleted 3 file(s), 52.1 GB freed; 1 skipped; 0 failed, exit 0)' for '# result: deleted 3 file(s), 52.1 GB freed; 1 skipped; 0 failed' '# exit: 0'; '# outcome: expired' → 'expired'; '# outcome: refused: plan folder contains a link' → that text; the state-2 fixture is an intact plan whose plan.txt lacks '# host:'"
  - id: L-M3
    text: "Cancel without claim: WriteNew(claim) with content 'cancel 2026-11-23T21:10:00-08:00\\n', then Delete(taskName) once, AppendLog 'schedule-cancel <id>', 'Cancelled <id>.', exit 0, in that order"
  - id: L-M4
    text: "Cancel: existing claim run → exit 1 '<id> already started; it cannot be cancelled', no Delete; existing claim cancel → '<id> is already cancelled', exit 0, no Delete; 'bad' or a missing dir → exit 1 'unknown plan id: <id>'; not intact → exit 1 'refused: plan folder permissions changed', no claim written; Delete fails → exit 3 'error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run' and the claim remains"
  - id: L-M5
    text: "IsIntact false for each single change: plans folder a reparse point; plan.txt a reparse point; owner of the plan dir another SID; an extra allow entry for Administrators on dirused.exe; an inherit-only entry for another SID on the plan dir; ReadAcl Ok=false on list.txt. True for the clean fixture"
must_not:
  - id: L-N1
    text: "Cancel calls Scheduler.Delete when the claim already says run (a cancel racing a started run). Positive control: L-M3 calls Delete once. Mutant-only (SchedulePlans absent on the pre-dispatch tip): 'delete before claiming' and 'claim with overwrite instead of WriteNew' each turn L-M4 red"
  - id: L-N2
    text: "List shows 'running' for a live pid whose image is not the plan's dirused.exe. Positive control: L-M2 running case. Mutant 'any live pid counts as running' turns L-M2 red"
  - id: L-N3
    text: "SchedulePlans.cs (comments stripped) matches \\\\b(File|Directory|Path|Process|Registry|Console)\\\\s*[.(], or calls DeleteTree. Positive control: mutant adding 'Store.DeleteTree(planDir)' to Cancel turns the scan red"
evidence:
  - id: E-L
    proves: [L-M1, L-M2, L-M3, L-M4, L-M5, L-N1, L-N2, L-N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4; SchedulePlansTests do not compile on the pre-dispatch tip; mutants each red with the catching test named: state order cancelled/running swapped [L-M1]; missed before cancelled [L-M1]; any live pid running [L-N2]; delete before claiming [L-N1]; claim overwrite [L-N1]; inherit-only ignored in IsIntact [L-M5]; owner not checked [L-M5]"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling, dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."
  - id: E-LW
    proves: [L-M1, L-M3]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "SchedulePlans.IsIntact(planDir, seams) -> bool; List(seams, stdout, stderr) -> int; Cancel(id, seams, stdout, stderr) -> int"
  - "claim: 'run <ISO> pid <n>' | 'cancel <ISO>'"
  - "report.txt: '# outcome:', '# result:', '# exit:'"
  - "No scheduled purges." / "unknown plan id: <id>" / "refused: plan folder permissions changed"
  - "<id> already started; it cannot be cancelled" / "<id> is already cancelled" / "Cancelled <id>."
  - "error: could not cancel <id>: <error>" / "error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run"
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

