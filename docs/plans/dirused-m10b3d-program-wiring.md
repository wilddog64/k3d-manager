# dirused M10b3d: Program wiring for `/schedule` and `/runplan`, test seam, interim refusal removed

**Status:** OPEN — SPEC rev 1, 2026-11-24; split from [M10b3](dirused-m10b3-runplan-windows.md) rev 3 after Fable + Argon reviews;
**gate:** after [b3c](dirused-m10b3c-windows-seams.md) lands
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b3](dirused-m10b3-runplan-windows.md); design [M10b](dirused-m10b-scheduled-purge.md) §8; shared contract copied at the
end of this file.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`
**Risk:** medium — turns scheduling on in the shipped program
**Implementer:** Luna (Codex); builds on macOS, tests run on the windows CI job
**Verifier:** Claude: code review from Acceptance, windows CI, scratch-branch mutants
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** E-B3d carries the approved E-B3W intent unchanged.
**Approval:** operator, 2026-11-23 — D9; operator, 2026-11-24 — D14, "intents approved"

## Already on the branch after b3a–b3c

`ScheduleCommands.Schedule(ScheduleRequest, ScheduleSeams, stdout, stderr, input, inputRedirected)`; `SchedulePlans.List(s, stdout,
stderr)`, `SchedulePlans.Cancel(id, s, stdout, stderr)`; `TrustCommands.Trust(account?, store, accounts, stdout, stderr)`,
`TrustCommands.Untrust(account, store, accounts, stdout, stderr)`; `PlanRunner.RunPlan(id, s, r, stdout, stderr)` with
`RunPlanSeams`; `WindowsSchedule.Create(version)` and `WindowsSchedule.RunSeams()`; `Options` fields `RunPlan`, `ScheduleList`,
`ScheduleCancelId`, `ScheduleTrust`, `ScheduleTrustAccount`, `ScheduleUntrust`, `ScheduleTime`, `Confirm`, `Yes`, `FromList`.
`src/Dirused.Cli/Program.cs`: `Main` (:11), `RunWithPurge` (:20), `RunCore` (:21), `CleanupUpdateFiles` call (:30), interim refusal
(:60), path checks (:61-71), `PurgeList.Read` + `Schedule.Run` (:72-73), `StartUpdateCheck` (:233-238).

## Scope

### 1. Test seam

```csharp
public sealed record ProgramTestSeams(ScheduleSeams Schedule, RunPlanSeams Run, bool IsWindows, IReleaseSource? Source,
    string Version, string PurgeLogPath, IPurgeFileSystem? Fs = null, IServiceQuery? Services = null, IServiceControl? Control = null,
    TextReader? Input = null, bool? InputRedirected = null, Func<DateTime>? LocalNow = null, Action<TimeSpan>? Sleep = null,
    Func<DateTime>? UtcNow = null, string? UpdateStatePath = null, Action? Cleanup = null);
public static int RunWithSchedule(string[] args, TextWriter output, TextWriter error, ProgramTestSeams seams);
```

`RunWithSchedule` calls `RunCore` with every field forwarded (`Fs`, `Services`, `Control`, `Input`, `InputRedirected`, `LocalNow`,
`Sleep`, `UtcNow`, `PurgeLogPath`, `Source`, `Version`, `UpdateStatePath`, `Cleanup`) and the schedule seams. `RunCore` calls
`cleanup ?? CleanupUpdateFiles` where it calls `CleanupUpdateFiles` today (only when `source != null`). `RunCore` gains optional
`ScheduleSeams? scheduleSeams`, `RunPlanSeams? runSeams`, `bool? isWindows`. `Main` passes none: on Windows the seams are built
lazily with `WindowsSchedule.Create(version)` / `RunSeams()` only when a schedule form is reached; `isWindows` defaults to
`OperatingSystem.IsWindows()`. `Control` reaches only the attended paths, never `PlanRunner`.

### 2. Order in `RunCore`

1. **Before `CleanupUpdateFiles` (:30):** if any argument is `/runplan` or `/schedule` (by `ArgParser.IsFlag`), skip the cleanup (it
   creates `dirused.update.lock` next to the exe, i.e. inside a plan dir).
2. Delete the interim refusal (:60) and `Schedule.NotAvailableForm` (`Schedule.cs:8`), with the whole test method
   `NewFormsAreRefusedByInterimHelper` (`ScheduleTests.cs:58-70`). `Schedule.Run` and its `/confirm` refusal stay (still asserted at
   `ScheduleTests.cs:44,113,181`; Program no longer calls it with `/confirm`).
3. **Right after a successful parse, where :60 was:** `/runplan <id>` → `PlanRunner.RunPlan`; `/schedule /list` → `SchedulePlans.List`;
   `/schedule /cancel <id>` → `SchedulePlans.Cancel`; `/schedule /trust [acct]` → `TrustCommands.Trust`; `/schedule /untrust <acct>`
   → `TrustCommands.Untrust`. When `isWindows` is false and no seams are injected, each prints `/schedule needs Windows` to stderr,
   nothing to stdout, exit 1. None starts the update check or calls the release source.
4. The path checks at :61-71 stay as they are (they run for `/fromlist ... /schedule` too).
5. **In the `/fromlist` block, before `PurgeList.Read` (:72):** if `options.ScheduleTime != null`:
   - `isWindows` false and no seams: with `/confirm` → `/schedule needs Windows`, exit 1, the list is not read; without `/confirm` →
     the existing `PurgeList.Read` + `Schedule.Run` preview (unchanged).
   - else: `bytes = File.ReadAllBytes(options.FromList)` (any exception → `not a dirused delete list: <list>`, exit 1); return
     `ScheduleCommands.Schedule(new ScheduleRequest(options, bytes, options.FromList, Path.GetFullPath(options.FromList)), seams,
     output, error, input, inputRedirected)`. `PurgeList.Read` is not called on this branch.
6. Usage text (`ArgParser.cs:70-71`, still "preview a one-time run") is changed in M10b4 with the docs, not here.

### 3. Tests on windows CI

`tests/Dirused.Tests` cannot see the `internal` fakes in `Dirused.Tests.Portable`. Link the shared file into it:
`<Compile Include="../Dirused.Tests.Portable/ScheduleFakes.cs" Link="ScheduleFakes.cs" />` in `Dirused.Tests.csproj` (the only csproj
change). Other fakes the tests need go in `tests/Dirused.Tests/ProgramScheduleTests.cs`. Delete
`tests/Dirused.Tests/ProgramScheduleRefusalTests.cs` (it asserts the removed refusal).

## Files

Changed: `src/Dirused.Cli/Program.cs`, `src/Dirused.Common/Schedule.cs` (remove `NotAvailableForm` only),
`tests/Dirused.Tests.Portable/ScheduleTests.cs` (remove lines 58-70 only), `tests/Dirused.Tests/Dirused.Tests.csproj` (one link).
New: `tests/Dirused.Tests/ProgramScheduleTests.cs`. Deleted: `tests/Dirused.Tests/ProgramScheduleRefusalTests.cs`.

## What NOT to Do

- Do not edit `ScheduleCommands.cs`, `SchedulePlans.cs`, `PlanTrust.cs`, `TrustCommands.cs`, `PlanRunner.cs`, `TaskScheduling.cs`,
  `ScheduleWindows.cs`, `Purge.cs` or `ArgParser.cs`. Do not change any non-schedule path's behaviour.
- Do not pass `Control` (or any `IServiceControl`) to `PlanRunner`. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B3d-M1
    text: "RunWithSchedule with fakes (ScheduleFakes.StockSystemDrive security, an in-memory store, recording FakeTaskScheduler, Version '1.2.3', recording IReleaseSource): '/fromlist <temp list> /purge /schedule 22:30 /confirm /yes' → FakeTaskScheduler records Register and output has 'Scheduled <id> for '; '/runplan <id>' on that plan at its run time → a claim is written; '/schedule /list' → its row; '/schedule /cancel <id>' on a second plan → 'Cancelled <id>.'; '/schedule /trust' → 'No trusted accounts.'; '/schedule /untrust x' → 'x is not trusted.'; in every run the release source records no call and neither output contains 'is not available in this version'"
  - id: B3d-M2
    text: "with IsWindows false and no seams: '/runplan x', '/schedule /list', '/schedule /cancel x', '/schedule /trust', '/schedule /untrust x' and '/fromlist <list> /purge /schedule 22:30 /confirm' each → stderr '/schedule needs Windows', stdout empty, exit 1; '/fromlist <list> /purge /schedule 22:30' (no /confirm) → the preview on stdout, exit 0 (positive control)"
  - id: B3d-M3
    text: "'/fromlist <list> /purge /schedule 22:30 /confirm /yes' with the list path equal to PurgeLogPath → '/fromlist cannot be the purge log', exit 1, no Register (path checks still run first)"
  - id: B3d-M4
    text: "with a Source and a recording Cleanup action: '/runplan <id>', '/schedule /list' and '/fromlist <list> /purge /schedule 22:30' never call Cleanup; positive control: '/version' with the same seams calls it once"
must_not:
  - id: B3d-N1
    text: "PlanRunner reaches any IServiceControl: a recording Control passed in ProgramTestSeams records nothing for '/runplan <id>' on a plan with a Tomcat-held row. Positive control: the same Control records Stop/Start for an attended '/fromlist <list> /purge /confirm /yes' with LocalNow 22:30, Sleep no-op and the fake Fs and Services. baseline: mutant-only (seam absent at the b3c head); mutant 'pass Control into RunPlanSeams/Apply' turns it red"
  - id: B3d-N2
    text: "any schedule form calls the release source. Positive control: '/?' (usage, which forces the check) with the same seams and Version '1.2.3' calls it. baseline: mutant-only (seam absent at the b3c head); mutant 'StartUpdateCheck before the schedule dispatch' turns it red"
evidence:
  - id: E-B3d
    proves: [B3d-M1, B3d-M2, B3d-M3, B3d-M4, B3d-N1, B3d-N2]
    kind: offline
    command: "windows-latest CI job (ci.yml 'windows'). Scratch-branch mutants each red on windows CI, then the branch is deleted: interim refusal kept; update check started before dispatch; Control forwarded to PlanRunner; cleanup not skipped; isWindows check dropped; PurgeList.Read called on the schedule branch (reviewed by diff: the branch must not contain it)"
    intent: "The real Windows task and folder-permission calls are checked on a throwaway task in CI, so a wrong setting is caught before it reaches the jump box."
interface:
  - "/schedule needs Windows"
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

## Verification log (Claude)

- 2026-11-25 Luna run 1: files in scope; could not restore (NuGet audit stall; `-p:NuGetAudit=false` works). Tests 3 for 6 items:
  M1 vacuous (asserted only "not 'not available'" and exit 0..1), M3/N1/N2 missing, M2/M4 partial. Correction 1 (tests only).
- Correction 1: 7 tests mapped to M1-M4, N1, N2; M3 exposed a production message mismatch (now `/fromlist cannot be the purge
  log`). Build 0 errors; portable 391 passed. Committed on the task branch `6570688`, pushed for the first windows CI run.
- Mutants: E-B3d's "scratch-branch mutants" follow the b3c operator decision (option 2, 2026-11-25): they run in the CI runner via
  the mutant harness (per-mutant test filter). Watch item: N1's `/runplan` half asserts no Control actions but not that the plan
  reached the held row — the "Control forwarded to PlanRunner" mutant decides whether it is vacuous.
