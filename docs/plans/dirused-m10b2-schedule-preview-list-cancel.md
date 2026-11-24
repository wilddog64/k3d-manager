# dirused M10b2: `/schedule /confirm` with plan files, trust check, `/schedule /list` and `/cancel` (with fakes)

**Status:** OPEN — SPEC rev 3, 2026-11-24; intents approved; M10b1 (`e19783f`) and M10b2a (`cf07ace`) landed; Fable + Argon blind reviews running
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §2 (rows 1–6), §4, §7, §8 and D14. Builds on [M10b0](dirused-m10b0-schedule-preview-only.md)
(preview, live-verified in v0.0.27), [M10b1](dirused-m10b1-engine-single-read-no-service.md) (`PurgeList.Parse(bytes)`) and
[M10b2a](dirused-m10b2a-taskxml.md) (`TaskXml`).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (integration branch)
**Risk:** medium — parser changes and a new on-disk contract; no real task is registered in this child (fakes only)
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job
**Filed:** 2026-11-23 (rev 3 2026-11-24)
**Intent approved:** operator, 2026-11-24
**Approval:** operator, 2026-11-23 — preview first (D12); operator, 2026-11-24 — D14 ("secure but not over restricted"), "intents approved"
**Decisions honoured:** D9 (held files skipped, no service stop), D12 (preview first), O8 (one host per plan, already in M10b0),
D14 (shared install, remembered trust list).

## What already exists (M10b0, `main` `966b32b`)

Parser rows 7–11, `Options.ScheduleTime`/`ScheduleZone`, the two usage lines, all time rules, host rules and the preview in
`Schedule.Run` (pure: no I/O), wired in `Program.cs:71-72`. M10b2 keeps `Schedule.Run`'s behaviour and exit codes for the preview,
with two output changes (below), and adds the scheduling flow beside it. `Program.cs` is **not** changed here (M10b3 wires it).

## Scope

1. **Parser** (`ArgParser.cs`): add `list`, `cancel`, `runplan`, `trust`, `untrust` to `KnownSwitches`; parent §2 rows 1–6 before the
   existing rows 7–11, plus three new rows after row 6 (exact strings):
   - 6a `trust` or `untrust` present without `schedule` → `/trust and /untrust go with /schedule`
   - 6b `schedule` with `trust`: anything else present except at most one following non-switch token (the account) →
     `/schedule /trust cannot be combined with other switches`
   - 6c `schedule` with `untrust`: no following token, or it is switch-like → `/schedule /untrust requires an account`; anything
     else present → `/schedule /untrust cannot be combined with other switches`
   `Options` gains, appended last and defaulted: `bool ScheduleList = false, string? ScheduleCancelId = null, string? RunPlan = null,
   bool ScheduleTrust = false, string? ScheduleTrustAccount = null, string? ScheduleUntrust = null`. Usage text (`UsageText` only, after
   the existing `/schedule` lines, ≤ 80 columns): `  /schedule /list     Show scheduled purges`,
   `  /schedule /cancel <id>  Cancel one`, `  /schedule /trust [acct]  Trust a folder writer (or list)`,
   `  /schedule /untrust <acct>  Stop trusting one`. `/runplan` stays out of usage.
2. **Preview output changes** (both `Schedule.Run` and the new flow): the size line becomes `<n> file(s), <size> in the list`
   (live check 2026-11-24: one listed row had already gone); M10b0's tests and `docs/purge.md` example are updated for that one line.
   The new flow's preview also prints, after `Held:`, the parent §4.2 lines `Task:`, `Plan dir:`, `Program:` and the
   `sha256 <first 12 hex>` continuation after the size line (layout and wrapping as M10b0: 80 columns, 68-character hard split).
3. **New flow** `ScheduleCommands.Schedule(ScheduleRequest req, ScheduleSeams s, TextWriter stdout, TextWriter stderr, TextReader input,
   bool inputRedirected) -> int`, all in `Dirused.Common`:
   - `ScheduleRequest(Options Options, byte[] ListBytes, string ListPathAsTyped)`; the list is parsed once with
     `PurgeList.Parse(ListBytes)`; `list.txt` is written from the same buffer.
   - `ScheduleSeams(Func<DateTimeOffset> Now, TimeZoneInfo Local, string PlanRoot, string UserSid, string ExePath,
     Func<int> IdSuffix, IPlanStore Store, IPlanFolderSecurity Security, ITaskScheduler Scheduler, ITrustStore Trust,
     IAccountResolver Accounts, Func<int, string?> ProcessImagePath)`.
   - Order (parent §4): parse → no-files / host / time checks (M10b0 messages) → preview → decide (D12: no `/confirm` → `Preview only.
     Add /confirm to schedule it.`, exit 0, **no seam method called except reading the strings**; `/confirm` → `Schedule this? [y/N] `
     on stderr; `y`/`yes` trimmed case-insensitive; redirected input → no read, No; No → `Not scheduled.`, exit 0; `/confirm /yes` →
     no question) → re-check time → **trust check** (item 4) → create plan (parent §4.6, through `IPlanStore` and
     `IPlanFolderSecurity.Secure` before any write; `plan.txt` gains `# trusted: <sid>,<sid>` sorted, or `# trusted: none`) →
     `TaskXml.Build` → `task.xml` → `ITaskScheduler.Register` → print `Scheduled <id> for <full time>. Check it with: dirused
     /schedule /list`, exit 0. Failure messages and exit codes as parent §4.6–§4.7 and B2-M7 below.
   - Bad list lines: as M10b0 (`Bad list lines:` block on stderr); with `/confirm`, scheduling is refused when the list has bad lines:
     after the block, `/schedule: fix the list first; nothing was scheduled`, exit 3, nothing written.
4. **Trust check (D14, replaces parent §4.5)**, pure logic in `PlanTrust.cs`:
   - `PlanTrust.PathsToCheck(string exePath, string planRoot) -> IReadOnlyList<string>`: the exe file, then every ancestor folder of
     the exe up to the volume root, then the plan root and every ancestor up to the volume root, de-duplicated case-insensitively,
     in that order.
   - `IPlanFolderSecurity.ReadAcl(string path) -> IReadOnlyList<AclEntry>`;
     `AclEntry(string Path, string Sid, string Display, WriteRights Rights, bool InheritOnly, bool Allow)`; `WriteRights` flags:
     `Write, Append, Delete, DeleteChild, WriteDac, WriteOwner, GenericWrite, GenericAll`.
   - `PlanTrust.Untrusted(IEnumerable<AclEntry> entries, string userSid, IReadOnlySet<string> trusted) -> IReadOnlyList<AclEntry>`:
     allow entries with any `WriteRights` whose SID is not the user, `S-1-5-18` (SYSTEM), `S-1-5-32-544` (Administrators),
     `S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464` (TrustedInstaller), `S-1-3-0` (CREATOR OWNER) when
     `InheritOnly`, or in `trusted`. Deny entries are ignored.
   - Refusal: for the first untrusted entry, stderr
     `/schedule: <path> can be changed by <display> (<rights, comma-separated, lower-case>).` then
     `  If you trust this account, run once: dirused /schedule /trust <account>` where `<account>` is the display name, or the SID when
     the display is `unresolved account <sid>`; further untrusted entries are listed as `  also: <path> by <display>`; exit 1; no plan
     dir, no Register.
5. **Trust store commands** (`ScheduleCommands.Trust/Untrust`): `ITrustStore.Load() -> IReadOnlyList<(string Sid, string Display)>`,
   `Add(sid, display)`, `Remove(sid)`. `IAccountResolver.Resolve(string nameOrSid) -> (string Sid, string Display)?`.
   - `/schedule /trust` → each `  <sid>  <display>` sorted by display, or `No trusted accounts.`; exit 0.
   - `/schedule /trust <acct>`: resolved → `Trusted <display> (<sid>).`, exit 0; already present → `<display> is already trusted.`,
     exit 0; not resolved but matches `^S-1-[0-9]+(-[0-9]+)+$` → stored with display `unresolved account <sid>`, same message; else
     exit 1 `unknown account: <acct>`.
   - `/schedule /untrust <acct>` (name or SID, resolved the same way): present → `Removed <display>.`, exit 0; absent → exit 1
     `<acct> is not trusted.`
6. **`/schedule /list` and `/schedule /cancel <id>`**: exactly parent §7 (states 1–9 in that precedence, row format, messages), through
   the seams; `ITaskScheduler.Exists`/`Delete`; the purge-log lines go to an `IPlanStore.AppendLog` seam.
7. **Seams only here:** `IPlanStore`, `IPlanFolderSecurity`, `ITaskScheduler`, `ITrustStore`, `IAccountResolver` are interfaces with
   in-memory fakes in tests; the real Windows classes, `/runplan` and Program wiring are M10b3.

## Files

- `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`
- `src/Dirused.Common/Schedule.cs` (size-line wording; share the preview formatter)
- `src/Dirused.Common/ScheduleCommands.cs` (new), `src/Dirused.Common/PlanTrust.cs` (new), `src/Dirused.Common/ScheduleSeams.cs` (new:
  interfaces and records)
- `tests/Dirused.Tests.Portable/ScheduleCommandsTests.cs` (new), `tests/Dirused.Tests.Portable/PlanTrustTests.cs` (new),
  `tests/Dirused.Tests.Portable/ScheduleTests.cs` (size line only), `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `docs/purge.md` (example size line only; the full scheduling docs are M10b4)

## Contract readers

- Size-line text: writer `Schedule.cs`; readers `ScheduleTests.cs` (M10b0 exact-preview tests), `docs/purge.md` example.
- `KnownSwitches` `ArgParser.cs:16`; row order; usage width test `ArgParserTests.cs:249-252`.
- `Options` constructions in `ArgParser.cs` and tests — new fields last, defaulted.
- `plan.txt` fields incl. `# trusted:` — writer here; readers M10b3 `/runplan` (re-check) and `/schedule /list`.
- `TaskXml.Build` (M10b2a) — caller here; unchanged.

## What NOT to Do

- No real I/O in `Dirused.Common` scheduling code: every file, ACL, scheduler, account and process call goes through a seam.
- Preview without `/confirm` calls no seam method (fakes record zero calls) and writes nothing.
- Do not read the list twice, stat or open a listed file, or query a service at schedule time.
- Do not write into a plan dir before `Secure` succeeded; do not register before the trust check passed.
- Do not change `Program.cs`, `Purge.cs`, `PurgeList.cs`, `TaskXml.cs`. Leave changes uncommitted; do not push.
- Tests: writers with `NewLine = "\n"` and literal `"\n"` expectations only; no `Environment.NewLine` in new or changed test files.

## Acceptance

```yaml
must:
  - id: B2-M1
    text: "preview through ScheduleCommands.Schedule: now Mon 2026-11-23 21:00 -08:00, Pacific, 12 rows under \\\\us03p02ffm01 totalling 176.2 GB, '/fromlist l.txt /purge /schedule 22:30': stdout is the parent §4.2 layout line for line with '12 file(s), 176.2 GB in the list', the 'sha256 <12 hex of the bytes>' line, Task '\\dirused\\<SID>\\purge-<id>', Plan dir '<PlanRoot>\\<id>', Program '<plan dir>\\dirused.exe (copy of <ExePath>)', then 'Preview only. Add /confirm to schedule it.'; every line <= 80; exit 0; every fake records zero calls"
  - id: B2-M1b
    text: "Schedule.Run (M10b0 entry) prints '<n> file(s), <size> in the list' and is otherwise unchanged (M10b0 tests pass with only that line updated)"
  - id: B2-M2
    text: "'/confirm' + answer 'y' (and 'YES'), trust check clean: preview, 'Schedule this? [y/N] ' on stderr, exactly one Register with name \\dirused\\<SID>\\purge-<id> (the previewed id) and <plan dir>\\task.xml; the store holds dirused.exe byte-equal to the fake exe bytes, list.txt byte-equal to ListBytes, task.xml equal to TaskXml.Build of the PlanTask, plan.txt with every parent §4.6 field plus '# trusted: none'; Secure recorded before the first write; stdout ends with 'Scheduled <id> for ...'; exit 0"
  - id: B2-M3
    text: "'/confirm /yes': no question written, no input read, one Register; '/confirm' with inputRedirected true: no read, 'Not scheduled.', exit 0, no Register"
  - id: B2-M4
    text: "re-check after the prompt: the clock advances past run-2 min while the fake reader waits → the 'less than 2 minutes' message, exit 1, no Register, no plan dir; PurgeList.Parse is called once per invocation"
  - id: B2-M5
    text: "parser: parent rows 1-6 and new rows 6a-6c each give their exact error (one test per row), and order ('/schedule /list 22:30' gives row 4; '/runplan 20261123-2230-a1b2 /schedule 22:30' gives row 1; '/trust' alone gives 6a); M10b0 rows 7-11 unchanged; the four new usage lines <= 80 columns, after the existing /schedule lines"
  - id: B2-M6
    text: "plan creation failures: Secure fails → plan dir removed, exit 3 'error: could not secure plan folder: ...'; a reparse 'plans' dir → exit 3 '... is a link', nothing written under it; Register fails → plan dir removed, exit 3 'error: could not schedule: ...'; bad list lines with /confirm → block, '/schedule: fix the list first; nothing was scheduled', exit 3, no plan dir"
  - id: B2-M7
    text: "trust check: PathsToCheck('C:\\Program Files\\dirused\\dirused.exe', 'C:\\Users\\op\\AppData\\Local\\dirused\\plans') returns the exe, 'C:\\Program Files\\dirused', 'C:\\Program Files', 'C:\\', then the plan root and its ancestors up to 'C:\\Users' (C:\\ not repeated); a fake ACL giving PROD\\sysadmin GenericAll on 'C:\\Users\\op' refuses with exactly '/schedule: C:\\Users\\op can be changed by PROD\\sysadmin (genericall).' and '  If you trust this account, run once: dirused /schedule /trust PROD\\sysadmin', exit 1, no plan dir, no Register; after Trust.Add of that SID the same run registers and plan.txt says '# trusted: <that sid>'; an unresolved SID entry prints the SID in the /trust command; SYSTEM, Administrators, TrustedInstaller, the user and inherit-only CREATOR OWNER never refuse; a Deny entry never refuses; an entry with only read rights never refuses"
  - id: B2-M8
    text: "/schedule /trust lists sorted or 'No trusted accounts.'; /trust <name> resolved → 'Trusted <display> (<sid>).'; again → 'already trusted'; unknown non-SID → exit 1 'unknown account: <acct>'; literal SID unresolved → stored as 'unresolved account <sid>'; /untrust present → 'Removed <display>.'; absent → exit 1 '<acct> is not trusted.'"
  - id: B2-M9
    text: "/schedule /list over fixture plan dirs shows each state 1-9 of parent §7 in that precedence (two-condition fixtures show the earlier one), the host column from '# host:', and 'No scheduled purges.' when the root is missing"
  - id: B2-M10
    text: "/schedule /cancel <id>: no claim → claim 'cancel <time>' created, then Delete, 'Cancelled <id>.', exit 0; claim=run → exit 1 '<id> already started; it cannot be cancelled', no Delete; claim=cancel → '<id> is already cancelled', exit 0; bad id or missing dir → exit 1 'unknown plan id: <id>'; Delete fails → exit 3 with the 'marked cancelled' message and the claim stays"
must_not:
  - id: B2-N1
    text: "preview-only (no /confirm) or /confirm + 'n'/empty/redirected input records any seam call that writes (Secure, Write, Register, Trust.Add) or creates a plan dir. Positive control: B2-M2's 'y' records one Register and a plan dir. Mutants 'register before the decision' and 'create plan dir before the decision' turn it red"
  - id: B2-N2
    text: "Register is called, or a plan dir is created, when PlanTrust.Untrusted is non-empty. Positive control: the same fixture after Trust.Add registers. Mutants 'trust check after Register' and 'trust check ignores ancestors' turn it red"
  - id: B2-N3
    text: "a file is written into the plan dir before Secure returned ok (fake records order). Positive control: B2-M2 order. Mutant 'write files then secure'"
  - id: B2-N4
    text: "cancel with claim=run calls Delete. Positive control: cancel without claim calls Delete once. Mutant 'delete before claiming'"
  - id: B2-N5
    text: "the list is parsed more than once or any IPurgeFileSystem/IServiceQuery method is reachable from ScheduleCommands (source scan of ScheduleCommands.cs and PlanTrust.cs for File., Directory., Process., Registry, FileInfo, DirectoryInfo, FileStream, IPurgeFileSystem, IServiceQuery). Positive control: mutant adding 'File.ReadAllBytes(req.ListPathAsTyped)' turns the scan red"
evidence:
  - id: E-B2
    proves: [B2-M1, B2-M1b, B2-M2, B2-M3, B2-M4, B2-M5, B2-M6, B2-M7, B2-M8, B2-M9, B2-M10, B2-N1, B2-N2, B2-N3, B2-N4, B2-N5]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4 and the windows CI job on the integration branch head. New tests red on the integration branch before this child. Mutants each red: register before the decision; plan dir before the decision; skip the re-check; trust check after Register; trust check ignores ancestors; CREATOR OWNER trusted without InheritOnly; Deny entry treated as a writer; read-only entry treated as a writer; write files then secure; delete before claiming; list state order swaps cancelled and running; running accepted for any live pid; id regenerated at registration; '# trusted:' omitted"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling, dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."
interface:
  - "ScheduleCommands.Schedule/Trust/Untrust/List/Cancel(...) -> int"
  - "PlanTrust.PathsToCheck(exePath, planRoot); PlanTrust.Untrusted(entries, userSid, trusted)"
  - "<n> file(s), <size> in the list"
  - "Schedule this? [y/N] "
  - "Not scheduled."
  - "Scheduled <id> for <full time>. Check it with: dirused /schedule /list"
  - "/schedule: <path> can be changed by <display> (<rights>)."
  - "  If you trust this account, run once: dirused /schedule /trust <account>"
  - "/schedule: fix the list first; nothing was scheduled"
  - "Trusted <display> (<sid>)."
  - "<display> is already trusted."
  - "unknown account: <acct>"
  - "Removed <display>."
  - "<acct> is not trusted."
  - "No trusted accounts."
  - "/trust and /untrust go with /schedule"
  - "/schedule /trust cannot be combined with other switches"
  - "/schedule /untrust requires an account"
  - "/schedule /untrust cannot be combined with other switches"
  - "/list and /cancel go with /schedule"
  - "/schedule /list cannot be combined with other switches"
  - "/schedule /cancel requires a plan id"
  - "/schedule /cancel cannot be combined with other switches"
  - "/runplan cannot be combined with other switches"
  - "/runplan requires a plan id"
```

## Rev 3 changes (2026-11-24)

- Rebased on M10b0 (preview, parser rows 7–11, time and host rules already in `main`); `TaskXml` moved to M10b2a.
- D14 trust check and trust store commands added (O7 resolved); `IPlanFolderSecurity.SourceExeIsProtected` replaced by `ReadAcl` +
  pure `PlanTrust`.
- Size line says "in the list" (live check 2026-11-24).
- `/confirm` with bad list lines refuses (exit 3) instead of scheduling a partly bad list.
- Windows newline rule for tests.
