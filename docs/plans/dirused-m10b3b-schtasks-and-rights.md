# dirused M10b3b: `SchtasksTaskScheduler` (argv, verify, delete) and `AclRights.FromMask`, portable

**Status:** OPEN — SPEC rev 1, 2026-11-24; split from [M10b3](dirused-m10b3-runplan-windows.md) rev 3 after Fable + Argon reviews;
P10 form taken from P9 (run 45510934313: the descriptor reads back verbatim); the jump-box P10 run confirms it for a standard user
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b3](dirused-m10b3-runplan-windows.md); design [M10b](dirused-m10b-scheduled-purge.md) §4.7, §8; shared contract copied
at the end of this file.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`; parallel with [b3a](dirused-m10b3a-runplan-engine.md) (no shared file)
**Risk:** medium — decides whether a registered task matches the plan; pure code with a fake process runner
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** E-B3b carries the approved E-B3W intent unchanged; this child is its portable half (real calls are b3c).
**Approval:** operator, 2026-11-23 — D3 (logged-on only, no password)

## Already on the branch (do not edit)

- `ITaskScheduler` (`src/Dirused.Common/ScheduleSeams.cs`): `SeamResult Register(string taskName, string xmlPath, PlanTask expected)`,
  `bool Exists(string taskName)`, `SeamResult Delete(string taskName)` ("already gone counts as Ok"). On failure `Error` is the text
  that `ScheduleCommands.Schedule` prints after `error: ` (`ScheduleCommands.cs:93`), and `ScheduleCommands` removes the plan dir. The
  scheduler never removes plan dirs.
- `TaskXml.Parse(byte[])` (`TaskXml.cs:108`) returns `PlanTask(Id, Run, Expires, UserSid, PlanDir, Description)` and throws
  `FormatException` whose message starts `<Field>:` for a fixed setting that differs (e.g. `AllowStartOnDemand: expected false, got
  'true'`, `LogonType: ...`, `Arguments: expected '/runplan <id>', got ...` when the argument is not a valid id, `Command: ...`,
  `WorkingDirectory: ...`). It decodes UTF-16 with or without BOM and UTF-8 with BOM. `TaskXml.Build(PlanTask)` makes the document;
  `TaskXml.SecurityDescriptorOf(byte[])` (`:319`) returns the `RegistrationInfo/SecurityDescriptor` text.
- `WriteRights` (`ScheduleSeams.cs`): `None 0, Write 1, Append 2, Delete 4, DeleteChild 8, WriteDac 16, WriteOwner 32, GenericWrite 64,
  GenericAll 128`.

## Scope

### 1. `src/Dirused.Common/TaskScheduling.cs` (new)

```csharp
public sealed record ProcessResult(int ExitCode, byte[] Stdout);
public interface IProcessRunner { ProcessResult Run(string exe, IReadOnlyList<string> args); } // never throws; failure → ExitCode -1
public sealed class SchtasksTaskScheduler(IProcessRunner runner, string systemDirectory) : ITaskScheduler
```

`exe` = `systemDirectory.TrimEnd('\\') + "\\schtasks.exe"` (string join, not `System.IO.Path`). A runner exception is caught and
treated as exit `-1`. Exit codes only; stdout is read only from the `/xml` query.

- **Register(name, xmlPath, expected):**
  1. `["/create", "/tn", name, "/xml", xmlPath]` (never `/f`). Exit `c ≠ 0` → `Error = "could not schedule (schtasks exit <c>)"`;
     nothing else runs.
  2. `["/query", "/tn", name, "/xml"]`. Exit `q ≠ 0` → field `query exit <q>`.
  3. Else `TaskXml.Parse(stdout)`. `FormatException` → field = its message up to the first `:`.
  4. Else compare in this order; the first difference names the field: `Id` (ordinal), `Run` (as instants), `Expires` (as instants),
     `UserSid` (ordinal ignore-case), `PlanDir` (ordinal ignore-case), `Description` (ordinal), then `SecurityDescriptor`:
     `TaskXml.SecurityDescriptorOf(stdout)` equals `D:P(A;;FA;;;<expected.UserSid>)(A;;FA;;;SY)(A;;FA;;;BA)` exactly (ordinal; P9
     showed Windows returns it verbatim).
  5. On any field: `["/delete", "/tn", name, "/f"]`. Exit 0 → `Error = "scheduled task does not match the plan (<field>); it was
     removed"`; exit `d ≠ 0` → `Error = "scheduled task does not match the plan (<field>); removing it failed (schtasks exit <d>)"`.
  6. All equal → `Ok`.
- **Exists(name):** `["/query", "/tn", name]`; exit 0 → true, else false.
- **Delete(name):** `["/delete", "/tn", name, "/f"]`; exit 0 → Ok. Exit `d ≠ 0` → `Exists(name)`: false → Ok (already gone); true →
  `Error = "schtasks exit <d>"`.

Field produced by each kind of difference (so tests and the verifier agree):

| Readback differs in | Field |
|---|---|
| `AllowStartOnDemand`, `StartWhenAvailable`, `LogonType`, `RunLevel`, `ExecutionTimeLimit`, other fixed settings | that element name (from `TaskXml.Parse`) |
| `Arguments` = `/runplan <another valid id>` | `Id` |
| `Arguments` not matching `/runplan <id>` | `Arguments` |
| `StartBoundary` moved | `Run` |
| `EndBoundary` moved | `Expires` |
| `UserId` another SID | `UserSid` |
| `WorkingDirectory` and `Command` both moved to another folder | `PlanDir` |
| `Command` alone changed | `Command` |
| `Description` | `Description` |
| `SecurityDescriptor` | `SecurityDescriptor` |

### 2. `src/Dirused.Common/AclRights.cs` (new, pure)

`public static WriteRights FromMask(int mask)`: if `(mask & 0x1F01FF) == 0x1F01FF` (FullControl) or `(mask & 0x10000000) != 0`
(GENERIC_ALL) → `GenericAll` only. Otherwise the union of: `0x2` → `Write`; `0x4` → `Append`; `0x10000` → `Delete`; `0x40` →
`DeleteChild`; `0x40000` → `WriteDac`; `0x80000` → `WriteOwner`; `0x40000000` (GENERIC_WRITE) → `GenericWrite | Write | Append`. Every
other bit contributes nothing. So `Modify` `0x301BF` → `Write | Append | Delete`; `ReadAndExecute` `0x1200A9` → `None`.

## Files

New: `src/Dirused.Common/TaskScheduling.cs`, `src/Dirused.Common/AclRights.cs`,
`tests/Dirused.Tests.Portable/SchtasksTests.cs`, `tests/Dirused.Tests.Portable/AclRightsTests.cs`.

## What NOT to Do

- No real process start, no `[SupportedOSPlatform]` class (b3c). No `/f` on create, no text parsing of stdout except the `/xml`
  document, no COM, no NuGet package. Do not remove plan dirs. Do not edit existing files. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B3b-M1
    text: "Register with a recording IProcessRunner, systemDirectory 'C:\\Windows\\System32\\': exe recorded = 'C:\\Windows\\System32\\schtasks.exe'; argv exactly ['/create','/tn',<name>,'/xml',<path>] then ['/query','/tn',<name>,'/xml']; a query returning TaskXml.Build(expected) → Ok and no third call; also a query returning the P9 readback shape (defaults omitted, URI and IdleSettings added, single-byte text without BOM, built by the test from TaskXml.Build output) → Ok"
  - id: B3b-M2
    text: "one case per row of the field table: a readback with that single difference → third call ['/delete','/tn',<name>,'/f'] and Error 'scheduled task does not match the plan (<Field>); it was removed' with the table's field"
  - id: B3b-M3
    text: "create exit 1 → Error 'could not schedule (schtasks exit 1)' and exactly one call; query exit 1 → field 'query exit 1' and the delete; mismatch with delete exit 1 → '...; removing it failed (schtasks exit 1)'; a runner that throws on create → 'could not schedule (schtasks exit -1)'"
  - id: B3b-M4
    text: "Exists: exit 0 → true, 1 → false, argv ['/query','/tn',<name>]. Delete: exit 0 → Ok; exit 1 then query exit 1 → Ok; exit 1 then query exit 0 → Error 'schtasks exit 1'"
  - id: B3b-M5
    text: "AclRights.FromMask: 0x1F01FF → GenericAll; 0x10000000 → GenericAll; 0x301BF → Write|Append|Delete; 0x1200A9 → None; 0x4 → Append; 0x2 → Write; 0x40 → DeleteChild; 0x10000 → Delete; 0x40000 → WriteDac; 0x80000 → WriteOwner; 0x40000000 → GenericWrite|Write|Append; 0x1F01FF|0x40000000 → GenericAll"
must_not:
  - id: B3b-N1
    text: "Register passes '/f' or runs any call after a failed create. Positive control: a successful create is followed by the query. baseline: mutant-only (class absent at ab98677); mutant 'append /f' turns it red"
evidence:
  - id: E-B3b
    proves: [B3b-M1, B3b-M2, B3b-M3, B3b-M4, B3b-M5, B3b-N1]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable. Mutants each red: '/f' on create; skip the compare; compare ignores Description; compare ignores SecurityDescriptor; Run compared with EqualsExact instead of as an instant (B3b-M1 also checks a readback with the same instants written in +00:00 is Ok); delete not called on mismatch; Delete treats non-zero as Ok without Exists; FullControl mapped as its bits; Modify without Delete; GENERIC_WRITE without Append"
    intent: "The real Windows task and folder-permission calls are checked on a throwaway task in CI, so a wrong setting is caught before it reaches the jump box."
interface:
  - "could not schedule (schtasks exit <code>)"
  - "scheduled task does not match the plan (<field>); it was removed"
  - "scheduled task does not match the plan (<field>); removing it failed (schtasks exit <code>)"
  - "schtasks exit <code>"
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

