# dirused M10b2: `/schedule /confirm`, trust check, `/schedule /list` and `/cancel` — shared contract for children b2b–b2e

**Status:** OPEN — SPEC rev 5, 2026-11-24; split into four children after Fable + Argon blind reviews of rev 3 (both NEEDS REWORK);
round-2 reviews of rev 4 applied (both tables at end). This file is the shared contract; the children are what get dispatched.
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §2, §4, §7, §8, D12, D14. Builds on M10b0 (preview, `main` `966b32b`), M10b1
(`PurgeList.Parse`, `e19783f`) and M10b2a (`TaskXml`, `cf07ace`), all on `m10b-scheduled-purge`.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (integration branch; one PR to main after M10b4)
**Filed:** 2026-11-23 (rev 4 2026-11-24)
**Intent approved:** operator, 2026-11-24 (E-B2 intent below; each child carries the part of it that its evidence proves, unchanged)
**Approval:** operator, 2026-11-23 — preview first (D12); operator, 2026-11-24 — D14 ("secure but not over restricted"), "intents approved"
**Proof before dispatch:** P-ACL (below) for b2c and b2d.

## Children and order

| Child | Scope | Files | Worker | Starts |
|---|---|---|---|---|
| [b2b](dirused-m10b2b-parser-usage.md) | parser rows 1–6d, `Options` fields, usage lines, size-line wording, interim refusal | `ArgParser.cs`, `Options.cs`, `Schedule.cs`, `Program.cs`, `ArgParserTests.cs`, `ScheduleTests.cs`, `ProgramScheduleRefusalTests.cs`, `docs/purge.md` | Luna | now |
| [b2c](dirused-m10b2c-seams-and-trust.md) | seam interfaces, `PlanTrust` rules, `/trust` and `/untrust` commands | `ScheduleSeams.cs`, `PlanTrust.cs`, `TrustCommands.cs`, `ScheduleFakes.cs` (shared test fakes and fixtures), `PlanTrustTests.cs`, `TrustCommandsTests.cs` (all new) | Luna | after P-ACL; parallel with b2b |
| [b2d](dirused-m10b2d-confirm-flow.md) | `/schedule /confirm` flow: preview, prompt, re-check, trust, plan creation, register | `Schedule.cs` (refactor), `ScheduleCommands.cs`, `ScheduleCommandsTests.cs` (new) | Luna | after b2b and b2c land |
| [b2e](dirused-m10b2e-list-cancel.md) | `/schedule /list` and `/schedule /cancel` | `SchedulePlans.cs`, `SchedulePlansTests.cs` (new) | Luna | after b2c lands; parallel with b2d |

`Program.cs` wiring (beyond b2b's interim refusal), the real Windows seam classes and `/runplan` stay in
[M10b3](dirused-m10b3-runplan-windows.md); M10b3 is revised to this contract (seams, claim and report formats, no `rootFolder`, the
scheduler never deletes plan dirs) before it is dispatched. Test fakes for every seam live in one shared file,
`tests/Dirused.Tests.Portable/ScheduleFakes.cs` (b2c), as `internal` types; b2d and b2e use them and define no fake of their own. Nothing here is
released before M10b3 and M10b4 land (the integration branch merges to main once), so usage lines added in b2b are not advertised to
users before the commands work.

## P-ACL: proof before b2c/b2d dispatch

The trust rules below assume the stock Windows ACLs on a system drive (Authenticated Users may create folders on `C:\`; `Program Files`
grants Users read and execute only). Record from the jump box, read-only, in PowerShell:
`foreach ($p in 'C:\', 'C:\Program Files', 'C:\Users', $env:USERPROFILE, "$env:USERPROFILE\AppData", $env:LOCALAPPDATA) { Get-Acl $p | Format-List Path, Owner, Sddl }`
(owner and SDDL; `icacls` prints no owner). Claude turns the output into literal ACL and owner tables in b2c's fixtures (host and
date in a comment) before b2c is dispatched. If they differ from the assumptions, the rules are revised first.

## Shared contract

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

## E-B2 intent (approved 2026-11-24)

"Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until
you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling,
dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."

## Review adjudication (rev 3, 2026-11-24)

Fable: NEEDS REWORK. Argon: NEEDS REWORK.

| Finding | Source | Action |
|---|---|---|
| D14 refuses every stock install (`Append` on `C:\`, inherit-only only exempt for CREATOR OWNER) | Fable 1, Argon 1 | Applied: leaves vs ancestors; inherit-only ignored for all SIDs; b2c stock-ACL fixture from P-ACL |
| `ReadAcl` failure undefined (fail open) | Fable 2 | Applied: `AclRead`; missing allowed only for the two folders this run creates |
| Seam signatures missing; M10b3 conflicts (`rootFolder`, `SourceExeIsProtected`) | Fable 3, Argon 4 | Applied: Interfaces section; M10b3 to follow it at its next revision |
| Sub-second `created` makes `TaskXml.Build` throw | Fable 4, Argon 2 | Applied: truncate to seconds; b2d must with 21:00:00.1234567 |
| Existing tests assert old `/schedule /list` errors (ArgParserTests.cs:328-329, ScheduleTests.cs:53-54) | Fable 5, Argon 3 | Applied: b2b may change those lines; listed as contract readers |
| Id rule undefined | Fable 6 | Applied: Ids section |
| Owner, reparse on exe chain, UNC paths, broad SIDs, elevation | Fable 7 | Applied: trust rules; elevation in b2d |
| `/trust` hint breaks on spaces | Fable 8 | Applied: quoted |
| Rights text | Fable 9 | Applied: fixed order and wording |
| `System.IO.Path` off Windows; product newlines | Fable 10 | Applied: string splits; plan.txt `"\n"` explicit |
| plan.txt inputs (`ToolVersion`, `ListFullPath`), Description | Fable 11, Argon 6 | Applied |
| Re-check by instant; "Parse once" unobservable | Fable 12, Argon 7 | Applied in b2d: compare run with fresh Now; source-scan count |
| Register error contract | Fable 13 | Applied: `error: <Register error>` verbatim |
| Parent items without acceptance (log lines, write failure, not-a-list, cancel permissions) | Fable 14 | Applied in b2d/b2e |
| Preview and list literals | Fable 15, Argon 5 | Applied: literal blocks in b2d/b2e |
| Parser positives | Fable 16 | Applied in b2b |
| Baseline wording | Fable 17 | Applied: class-absent items marked mutant-only |
| Too big for one dispatch | Fable 18 | Applied: four children |
| Scan word boundaries; circular trust residual; usage width | Fable 19-21 | Applied |

## Review adjudication (rev 4 children, round 2, 2026-11-24)

Fable: b2b, b2c, b2d, b2e READY WITH FIXES (b2c and b2d blocking items). Argon: contract, b2b, b2c, b2e READY WITH FIXES; b2d NEEDS
REWORK until step 9 and the collision rule are fixed.

| Finding | Source | Action |
|---|---|---|
| P-ACL cannot build fixtures (no owner, missing `%USERPROFILE%`) | Fable P1, C2 | Applied: `Get-Acl ... Owner, Sddl` list; b2c gets literal tables before dispatch |
| Broad list short; RID anchoring; `\A..\z` regexes | Fable P2, P6 | Applied |
| `run` offset `+00:00` from `TryRunTime` vs `-08:00` expected | Fable D1, P3 | Applied: convert to Pacific |
| Dual-role path | Fable P4 | Applied: leaf wins |
| Children table files and rows | Fable P5, Argon b2b-1 | Applied |
| Findings order (first line named `...\Local`, not the profile) | Fable C1 | Applied: shallowest path first |
| Rights merge and wording | Fable C4, Argon b2c-3 | Applied |
| CREATOR OWNER as owner; Modify mapping; path normalisation | Argon b2c-1/2/4 | Applied |
| Existing `plans` unsecured → every plan "permissions changed" | Argon b2d-1, Fable D3 | Applied in b2d: always `Secure` both folders; delete a folder created this run on failure |
| Collision updates every id-derived name | Argon b2d-2 | Applied |
| `...\dirused` link case unreachable at step 9 | Fable D2 | Applied: case moved to the plan dir |
| Shared fakes (type collisions b2d ‖ b2e) | Fable C5, D4 | Applied: `ScheduleFakes.cs` in b2c |
| `TrustPath.Path` trips the scan | Fable C3 | Applied: member `FullPath` |
| Task name in b2e; Description/size/source definitions; bytes | Argon contract 1-3 | Applied |
| b2b: five assertions change; Program mutant only on Windows CI; duplicate switches | Fable B1, B2, Argon b2b-2 | Applied |
| b2d literal preview block; `Not scheduled.` stream; `Schedule.Preview` binding | Fable D5, D6, Argon b2d-3/4 | Applied |
| b2e outcomes verbatim; plan.txt required fields; Pacific; tie-break; tolerant parse; state-2 fixture | Fable E1, E3, Argon b2e-1..4 | Applied |
| M10b3 still rev 2 | Fable (round-1 check) | Deferred by design: M10b3 is revised to this contract before its dispatch (stated above) |
