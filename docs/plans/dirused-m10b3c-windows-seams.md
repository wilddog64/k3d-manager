# dirused M10b3c: the real Windows seam classes (`ScheduleWindows.cs`), tested on windows CI

**Status:** OPEN — SPEC rev 3, 2026-11-24 (rev 2: trust store refuses a junction in Add/Remove, from Claude's review; rev 3: Save sets trust.tmp's owner to the user, from windows CI run 45514086420 where the elevated runner made Administrators the owner and Load rejected the list); split from [M10b3](dirused-m10b3-runplan-windows.md) rev 3 after Fable + Argon reviews;
**gates:** after [b3a](dirused-m10b3a-runplan-engine.md) and [b3b](dirused-m10b3b-schtasks-and-rights.md) land; P6 (PASS 2026-11-24),
P6 default-owner check (PASS 2026-11-24, normal window), P9 PASS (run 45510934313)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b3](dirused-m10b3-runplan-windows.md); design [M10b](dirused-m10b-scheduled-purge.md) §8, D14; shared contract copied at
the end of this file.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`
**Risk:** high — real ACL, owner and schtasks calls; fail-open mistakes here weaken every plan
**Implementer:** Luna (Codex). Luna cannot run `tests/Dirused.Tests` (net10.0-windows) on macOS: it must build, and the windows CI job
is the test gate.
**Verifier:** Claude: code review from Acceptance, windows CI run, mutants applied inside the windows CI runner (`.github/workflows/mutants.yml`, `tests/mutants/`; no mutated code on any branch)
**Mutant method:** operator, 2026-11-25 — option 2 ("go with your recommendation 2"): mutate inside the CI runner. The scratch-branch push of mutated security code was blocked (public repo, 2026-11-24). Intent text unchanged.
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** E-B3c carries the approved E-B3W intent unchanged.
**Approval:** operator, 2026-11-23 — D3; operator, 2026-11-24 — D14

## Already on the branch after b3a and b3b

`IPlanStore` (with `MoveNew`), `IPlanFolderSecurity`, `ITrustStore`, `IAccountResolver`, `ScheduleSeams` (contract at the end);
`RunPlanSeams(Fs, Services, IsFixedDrive, UtcNow, Pid, PurgeLogPath, Sleep)` (`PlanRunner.cs`); `IProcessRunner`, `ProcessResult`,
`SchtasksTaskScheduler(runner, systemDirectory)` (`TaskScheduling.cs`); `AclRights.FromMask(int)` (`AclRights.cs`);
`RealPurgeFileSystem`, `RealServiceQuery` (existing); `PurgeLog.DefaultPath` (`Purge.cs:51`).

## Scope: `src/Dirused.Common/ScheduleWindows.cs` (new), every class `[SupportedOSPlatform("windows")]`

Framework types only (`System.Security.AccessControl`, `System.Security.Principal`, `System.Diagnostics.Process`,
`System.IO.FileSystemAclExtensions`) and one P/Invoke:
`[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern uint QueryDosDeviceW(string lpDeviceName,
char[] lpTargetPath, uint ucchMax);` with a 1024-char buffer. No NuGet package, no COM. If a type is missing from the shared framework
for `net10.0`, stop and report. No member of these classes throws: every error becomes `SeamResult(false, ex.Message)`, `null`,
`false`/`true` as stated, or `AclRead(Ok = false, ...)`.

### `RealProcessRunner(int timeoutMs = 60000) : IProcessRunner`

`ProcessStartInfo(exe)` with `ArgumentList`, `UseShellExecute = false`, `CreateNoWindow = true`, stdout and stderr redirected. Start
reading **both** streams asynchronously before waiting (stdout: `BaseStream.CopyToAsync` into a `MemoryStream`; stderr: read and
discard). `WaitForExit(timeoutMs)`; on timeout kill the process tree and return `ExitCode = -1`. Any exception (including
`Process.Start`) → `ProcessResult(-1, [])`.

### `RealPlanStore(string purgeLogPath) : IPlanStore`

- `Exists`: file or directory exists.
- `IsReparsePoint`: `File.GetAttributes(path).HasFlag(ReparsePoint)`; missing (`FileNotFound`/`DirectoryNotFound`) → false; any other
  error → **true** (fail closed).
- `CreateDirectory`: present → `SeamResult(false, "already exists")`; else `Directory.CreateDirectory`. (Check-then-create, accepted:
  every caller creates inside a user-only folder or the profile.)
- `WriteNew`: `FileMode.CreateNew`, `FileAccess.Write`, `FileShare.None`, write, flush.
- `ReadAll`: `File.ReadAllBytes`; any error → null.
- `ListDirectoryNames`: names of subdirectories; missing → empty.
- `DeleteTree`: directory → `Directory.Delete(path, true)`; file → `File.Delete`; missing → Ok.
- `AppendLog(line)`: create the log's folder if missing; open `purgeLogPath` with `FileMode.Append`, `FileAccess.Write`,
  `FileShare.Read`; write `line` + `Environment.NewLine`; close. (An attended purge holds the same log open for its whole run, so an
  append during one fails; `/runplan` then stops deleting, which is the accepted outcome.)
- `MoveNew`: `File.Move(from, to, overwrite: false)`.

### `RealPlanFolderSecurity : IPlanFolderSecurity`

- **`ReadAcl(path)`**, in this order:
  1. Drive check, whether or not the path exists: the path must start with `X:\`; `new DriveInfo("X:\\").DriveType` must be `Fixed`;
     `QueryDosDeviceW("X:")` must return non-zero and its first string must not start with `\??\` (a `subst` drive). Otherwise
     `AclRead(Ok: false, Missing: false, ..., Error: "not on a local fixed drive")`.
  2. Missing (neither file nor directory) → `AclRead(false, true, null, null, [], null)`.
  3. `GetAccessControl(AccessControlSections.Access | AccessControlSections.Owner)` on `FileInfo` or `DirectoryInfo`.
     `GetOwner(typeof(SecurityIdentifier))`. A NULL DACL (`new RawSecurityDescriptor(sec.GetSecurityDescriptorBinaryForm(), 0)
     .DiscretionaryAcl == null`) → one entry `S-1-1-0` `Everyone` `GenericAll`, not inherit-only, allow. Else one `AclEntry` per rule of
     `GetAccessRules(true, true, typeof(SecurityIdentifier))`: `Sid`, `Display`, `Rights = AclRights.FromMask((int)rule.FileSystemRights)`,
     `InheritOnly = rule.PropagationFlags.HasFlag(PropagationFlags.InheritOnly)`, `Allow = rule.AccessControlType == Allow`.
  4. `Display` and `OwnerDisplay`: `NTAccount` translation; `IdentityNotMappedException` → `""` (the trust code shows
     `unresolved account <sid>`). Translations are cached per instance (an unresolved domain SID can be slow).
  5. Any exception → `Ok = false`, `Missing = false`, `Error = ex.Message`.
  Residual (accepted, documented): .NET skips callback (conditional) ACEs.
- **`Secure(path, userSid)`**: read the current owner; build a new `DirectorySecurity`; call `SetOwner(userSid)` **only if** the current
  owner differs; `SetAccessRuleProtection(true, false)`; one rule `userSid` `FullControl`, `ContainerInherit | ObjectInherit`,
  `PropagationFlags.None`, `Allow`; apply with `new DirectoryInfo(path).SetAccessControl(...)`.

### `RealTrustStore(string folder, IPlanFolderSecurity security, string userSid) : ITrustStore`

`folder` = `<LocalApplicationData>\dirused`; file `<folder>\trust.txt`, UTF-8 without BOM, one line per entry `<SID>\t<display>\n`.
- **`Load`**: returns empty unless `<folder>` and `trust.txt` are not reparse points, are owned by `userSid`, and every allow entry on
  both is `userSid` (read with `security.ReadAcl`). This keeps an account that can write the profile from pre-creating a trust list
  naming itself. Lines without a tab or with an empty SID are skipped.
- **`Add` / `Remove`**: if `<folder>` or `trust.txt` exists and is a reparse point (`File.GetAttributes`), return
  `SeamResult(false, "<that path> is a link")` and change nothing (so `Secure` never re-permissions a junction's target); else create `<folder>` if missing; always `security.Secure(folder, userSid)` first (failure → that error); entries =
  `Load()` plus or minus the one; delete a stale `trust.tmp`; write `trust.tmp` with `CreateNew`; if `security.ReadAcl(trust.tmp).OwnerSid` differs from `userSid` (an elevated token makes
  Administrators the default owner, seen on windows-latest run 45514086420), set its owner to `userSid` (a `FileSecurity` carrying only
  the owner, `FileInfo.SetAccessControl`); on any failure delete `trust.tmp` and return the error; `File.Move(trust.tmp, trust.txt,
  overwrite: true)`. `Load` keeps requiring owner = user.
- Consequence (intended): a trust list made unreadable by a permission change is ignored, `/schedule` refuses naming the account, and
  `/schedule /trust` rewrites it in a secured folder.

### `RealAccountResolver : IAccountResolver`

Input matching `\AS-1-[0-9]+(-[0-9]+)+\z` (ignore case) → `new SecurityIdentifier(input)`, display = its `NTAccount` translation; if it
does not map → **null** (`TrustCommands` then builds the `unresolved account <sid>` entry itself, `TrustCommands.cs:18`). Otherwise
`new NTAccount(input).Translate(typeof(SecurityIdentifier))`, display = the translated SID's `NTAccount` value. Any failure → null.

### `WindowsSchedule`

- `static ScheduleSeams Create(string toolVersion)`: `Now = () => DateTimeOffset.Now`; `Local = TimeZoneInfo.Local`; `PlanRoot =
  Environment.GetFolderPath(LocalApplicationData) + "\dirused\plans"` (never the environment variable); `UserSid =
  WindowsIdentity.GetCurrent().User!.Value`; `ExePath = Environment.ProcessPath ?? ""`; `ToolVersion`; `IdSuffix = () =>
  RandomNumberGenerator.GetInt32(0x10000)`; `Token` = `High` when `new WindowsPrincipal(WindowsIdentity.GetCurrent())
  .IsInRole(WindowsBuiltInRole.Administrator)` else `Medium` (with UAC off an admin is always High and cannot schedule; accepted);
  `Store = new RealPlanStore(PurgeLog.DefaultPath)`; `Security = new RealPlanFolderSecurity()`; `Scheduler = new
  SchtasksTaskScheduler(new RealProcessRunner(), Environment.SystemDirectory)`; `Trust = new RealTrustStore(<LocalApplicationData>\dirused,
  security, sid)`; `Accounts = new RealAccountResolver()`; `ProcessImagePath = pid => Process.GetProcessById(pid).MainModule?.FileName`,
  null on any exception.
- `static RunPlanSeams RunSeams()`: `new RealPurgeFileSystem()`, `new RealServiceQuery()`, `IsFixedDrive: null`, `() =>
  DateTime.UtcNow`, `Environment.ProcessId`, `PurgeLog.DefaultPath`, `Thread.Sleep`.
- Nothing calls these yet (b3d wires Program).

## Files

New: `src/Dirused.Common/ScheduleWindows.cs`, `tests/Dirused.Tests/ScheduleWindowsTests.cs`.

## What NOT to Do

- No Program wiring (b3d). Do not edit any existing source file. No COM, no NuGet package, no shell.
- Tests register tasks only under `\dirused-ci\<SID>\` and remove them in `finally`; folders only under a fresh temp dir; a `subst`
  letter is removed in `finally`.
- Do not widen the ACL tests to the full `IsIntact` path on CI (the runner's elevated token makes Administrators the default owner of
  new files). Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B3c-M1
    text: "windows-latest: Secure on a fresh temp dir, then ReadAcl → Ok, OwnerSid = current SID, exactly one entry: current SID, GenericAll, allow, not inherit-only. Adding an Everyone FileSystemRights.Write ACE → ReadAcl shows an S-1-1-0 entry with Write. Adding an inherit-only Users Modify ACE → InheritOnly true"
  - id: B3c-M2
    text: "windows-latest: ReadAcl on a path under a subst letter mapped to the temp dir (existing and missing paths) → Ok false, Missing false, Error 'not on a local fixed drive'; positive control: the same paths through C: → Ok true, and Missing true for the missing one"
  - id: B3c-M3
    text: "windows-latest: a junction made with 'cmd /c mklink /J' → IsReparsePoint true; a plain dir → false; a missing path → false"
  - id: B3c-M4
    text: "windows-latest: RealPlanStore WriteNew on an existing file fails and leaves it byte-identical; MoveNew onto an existing file fails and leaves it byte-identical; MoveNew to a new name succeeds; CreateDirectory on an existing dir returns 'already exists'; DeleteTree on a missing path is Ok; ReadAll on a missing file is null; AppendLog appends two lines in order to a temp log"
  - id: B3c-M5
    text: "windows-latest: RealProcessRunner(timeoutMs: 2000) on 'powershell.exe -NoProfile -Command Start-Sleep 30' returns -1 within 10 s; on a nonexistent exe returns -1 without throwing; on 'cmd.exe /c echo hi' returns 0 and stdout bytes containing 'hi'"
  - id: B3c-M6
    text: "windows-latest (P9 showed the runner registers an interactive-token task): SchtasksTaskScheduler(RealProcessRunner, Environment.SystemDirectory) Register of '\\dirused-ci\\<SID>\\purge-<guid>' from a TaskXml.Build file one day ahead → Ok; a second Register of the same name → 'could not schedule (schtasks exit <non-zero>)'; Exists true; Delete Ok; Exists false; delete in finally. If P9 says it cannot, this item asserts the written XML parses with TaskXml.Parse and the spec records that"
  - id: B3c-M7
    text: "windows-latest: RealTrustStore in a temp folder: Add then Load returns the entry; Remove empties it; after Add the folder's ReadAcl is user-only; Load returns empty when trust.txt carries an extra Everyone allow ACE (positive control: the same file without it loads); with <folder> replaced by a junction (mklink /J) to another temp dir holding a valid trust.txt: Load returns empty, Add returns '<folder> is a link', and the junction target's ACL is unchanged"
  - id: B3c-M8
    text: "windows-latest: RealAccountResolver resolves the current user's 'DOMAIN\\name' to the current SID and the current SID to that name; 'S-1-5-21-1-2-3-999999' → null; 'no such account x' → null"
  - id: B3c-M9
    text: "windows-latest: WindowsSchedule.Create(\"1.2.3\"): PlanRoot = GetFolderPath(LocalApplicationData) + '\\dirused\\plans'; UserSid = current SID; ExePath = Environment.ProcessPath; ProcessImagePath(Environment.ProcessId) = Environment.ProcessPath; ProcessImagePath(-1) = null"
must_not:
  - id: B3c-N1
    text: "ReadAcl reports Ok for a path on a subst drive. Positive control: B3c-M2's C: path is Ok. baseline: mutant-only (class absent at the b3b head); mutant 'skip the QueryDosDevice check' turns it red"
  - id: B3c-N2
    text: "RealTrustStore.Load returns entries from a trust.txt with a non-user allow ACE. Positive control in B3c-M7. baseline: mutant-only; mutants 'skip the ACL check in Load' and 'skip the reparse check in Load/Add' turn it red"
evidence:
  - id: E-B3c
    proves: [B3c-M1, B3c-M2, B3c-M3, B3c-M4, B3c-M5, B3c-M6, B3c-M7, B3c-M8, B3c-M9, B3c-N1, B3c-N2]
    kind: offline
    command: "windows-latest CI job (ci.yml 'windows', dotnet test -c Release). Windows-only mutants proved by Claude in the runner (workflow `mutants`: a `control` job must pass unmutated; each mutant job applies one find/replace from `tests/mutants/mutants.json`, must build, and the suite must go red): skip QueryDosDevice check; MoveNew with overwrite true; IsReparsePoint error → false; skip Load ACL check; Secure without protection; runner reads stdout synchronously (timeout test hangs past 10 s)"
    intent: "The real Windows task and folder-permission calls are checked on a throwaway task in CI, so a wrong setting is caught before it reaches the jump box."
interface:
  - "not on a local fixed drive"
  - "already exists"
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

- 2026-11-25 review of the Luna diff (`ScheduleWindows.cs` 176 lines, tests 55 lines): code accepted for now; tests miss B3c-M1
  (Everyone / inherit-only ACEs), B3c-M2 + N1 (no subst test), B3c-M3 (IsReparsePoint), B3c-M6 (no schtasks test), B3c-M7 + N2
  (extra Everyone ACE on trust.txt). Correction 1 (tests only) sent to Luna, resume 4.
- Mutant harness drafted by Claude (workflow + `run-mutant.ps1` + `mutants.json`, 6 mutants + control); each find text matches
  exactly once in the reviewed code. Added to the branch after correction 1 lands.
