# dirused M10b2: `/schedule /confirm`, trust check, `/schedule /list` and `/cancel` — shared contract for children b2b–b2e

**Status:** OPEN — SPEC rev 4, 2026-11-24; split into four children after Fable + Argon blind reviews of rev 3 (both NEEDS REWORK;
table at end). This file is the shared contract; the children are what get dispatched.
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
| [b2b](dirused-m10b2b-parser-usage.md) | parser rows 1–6 and 6a–6c, `Options` fields, usage lines, size-line wording | `ArgParser.cs`, `Options.cs`, `Schedule.cs`, `ArgParserTests.cs`, `ScheduleTests.cs`, `docs/purge.md` | Luna | now |
| [b2c](dirused-m10b2c-seams-and-trust.md) | seam interfaces, `PlanTrust` rules, `/trust` and `/untrust` commands | `ScheduleSeams.cs`, `PlanTrust.cs`, `TrustCommands.cs`, `PlanTrustTests.cs`, `TrustCommandsTests.cs` (all new) | Luna | after P-ACL; parallel with b2b |
| [b2d](dirused-m10b2d-confirm-flow.md) | `/schedule /confirm` flow: preview, prompt, re-check, trust, plan creation, register | `ScheduleCommands.cs`, `ScheduleCommandsTests.cs` (new) | Luna | after b2b and b2c land |
| [b2e](dirused-m10b2e-list-cancel.md) | `/schedule /list` and `/schedule /cancel` | `SchedulePlans.cs`, `SchedulePlansTests.cs` (new) | Luna | after b2c lands; parallel with b2d |

`Program.cs` wiring, the real Windows seam classes and `/runplan` stay in [M10b3](dirused-m10b3-runplan-windows.md). Nothing here is
released before M10b3 and M10b4 land (the integration branch merges to main once), so usage lines added in b2b are not advertised to
users before the commands work.

## P-ACL: proof before b2c/b2d dispatch

The trust rules below assume the stock Windows ACLs on a system drive (Authenticated Users may create folders on `C:\`; `Program Files`
grants Users read and execute only). Record from the jump box, read-only: `icacls C:\`, `icacls "C:\Program Files"`,
`icacls C:\Users`, `icacls %LOCALAPPDATA%` and `icacls %LOCALAPPDATA%\..`. The b2c fixture `StockSystemDrive` copies those lines
(host, date in a comment). If they differ from the assumptions, the rules are revised before dispatch.

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
- Id = run instant in Pacific as `yyyyMMdd-HHmm`, `-`, then `(IdSuffix() & 0xFFFF)` as 4 lower-case hex digits; matches
  `^[0-9]{8}-[0-9]{4}-[0-9a-f]{4}$`. The preview draws the suffix once; registration uses that id unless `CreateDirectory` of the plan dir
  fails because it exists, in which case a new suffix is drawn (at most 5 draws in total), and the printed `Scheduled <id>` shows the id
  used.
- Task name `\dirused\<UserSid>\purge-<id>`. Plan dir `<PlanRoot>\<id>`. Program `<plan dir>\dirused.exe`.
- `PlanTask` for TaskXml: `Id`, `Run`, `Expires`, `UserSid`, `PlanDir`, `Description` = `dirused scheduled purge <id> (<n> file(s), <size>) from <source file name>`.

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
  Paths are split on `\` as strings, never with `System.IO.Path` (tests run on macOS and Linux too).
- **Leaves** (all write rights count): the exe file, the exe's folder, `<PlanRoot>`'s parent (`...\dirused`) and `<PlanRoot>`.
  **Ancestors** (only rights that can rename, delete or take over an existing child count: `Delete`, `DeleteChild`, `WriteDac`,
  `WriteOwner`, `GenericAll`): every other folder from the exe's folder and from `<PlanRoot>`'s parent up to the drive root,
  de-duplicated case-insensitively. Order: exe, exe folder, its ancestors upward, then `...\dirused`, `<PlanRoot>`, then the remaining
  ancestors of `...\dirused` upward.
- **Allowed writers:** the user, `S-1-5-18` SYSTEM, `S-1-5-32-544` Administrators, `S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464`
  TrustedInstaller, `S-1-3-0` CREATOR OWNER, and every SID in the trust store.
- **Per path:** a reparse point (`IsReparsePoint`) → exit 1 `/schedule: <path> is a link; dirused does not schedule through links`.
  `ReadAcl` with `Missing` → allowed only for `...\dirused` and `<PlanRoot>` (this run creates and secures them); any other missing
  path or any `Ok = false` → exit 1 `/schedule: cannot read permissions of <path>: <error or "not found">`. Deny entries and
  **inherit-only entries of any SID** are ignored (the inherited copy appears on the child's own DACL, which is checked). An owner not
  in the allowed writers counts as an entry with `WriteDac` and the right text `owner`.
- **Broad groups are never trusted:** `S-1-1-0` Everyone, `S-1-5-11` Authenticated Users, `S-1-5-32-545` Users, `S-1-5-4` INTERACTIVE,
  and any domain SID ending `-513` (Domain Users) or `-515` (Domain Computers). `/schedule /trust` refuses them; a refusal caused by
  one prints the IT line instead of the `/trust` line.
- **Refusal text** (first untrusted path and account), exit 1, nothing created:
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
