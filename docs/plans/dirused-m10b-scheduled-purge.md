# dirused M10b: schedule a one-time purge of a reviewed delete list

**Status:** OPEN — SPEC rev 1, 2026-11-23; awaiting reviews
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** `docs/plans/dirused-m10-scheduled-purge.md` Amendments 1–3 (M10b = `/schedule` over an M10a list, after M9).
Builds on M10a (`/savelist`, `/fromlist`, PR #35) and M9b (Tomcat stop/delete/start, PR #39).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (from main a2d0508, v0.0.26 pre-release)
**Version:** v0.0.27
**Risk:** high — an unattended run deletes files and may stop Tomcat with nobody watching
**Review:** Fable + Astra blind, Claude adjudicates
**Implementer:** TBD — proposed Luna (Codex) for the logic and tests; if split, Flash for `docs/purge.md` and `README.md`
**Verifier:** Claude (offline, from Acceptance only). Live check by the operator on the office jump box.
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** none needed beyond the intent approval (no exception to the shared rules)

## Before You Start

- Read `docs/plans/dirused-m10a-purge-delete-list.md` (list format, `/fromlist` checks) and
  `docs/plans/dirused-m9b-stop-delete-start.md` (held-file flow, `/yes`, the 19:00–06:00 window). M10b adds no new delete path:
  a scheduled run is a `/fromlist ... /purge /confirm /yes` run with three differences (§5).
- Every proof in "Proofs before dispatch" is answered and recorded in this file first. Do not start until the operator marks them.

## Why

Operator, 2026-11-19: delete the big logs at a time they choose, without sitting at the jump box. Operator, 2026-11-23, after the
`/fromlist` and M9b decline-path live checks: "we can go with scheduling". The safety model from Amendment 3 stays: what is deleted
is the list the operator reviewed, never a new scan.

## Operator decisions this spec honours (M10 draft, Amendments 1–3, 2026-11-23)

| # | Decision |
|---|---|
| D1 | Delete only the reviewed list (a copy taken at schedule time). |
| D2 | One-time runs only; no repeat option. (Recurring rules are a separate draft, `dirused-m10c-recurring-purge-rules.md`.) |
| D3 | "Run only when user is logged on"; no stored password. |
| D4 | The list is copied into the plan dir at schedule time; the task reads only that copy. |
| D5 | Result in a run report next to the plan and in `/schedule /list`; no pop-up. |
| D6 | A plan expires 24 h after it is created; an expired plan deletes nothing and reports `expired`. |
| D7 | `<time>` is `HH:MM` with optional `PST`, `PDT`, `PT` or `UTC`; a bare time only on a Pacific-time machine; a passed time means tomorrow, and the prompt shows the full date. |
| D8 | dirused runs on the office jump box. |

## Facts this spec relies on (dirused main a2d0508)

- `/fromlist` parsing: `ArgParser.cs:119-139`; whitelist message `ArgParser.cs:121`; `/yes` rule `ArgParser.cs:137` and `:263`;
  `KnownSwitches` `ArgParser.cs:16` (has `yes`, not `schedule`, `list`, `cancel`, `runplan`).
- `Options` record `Options.cs:4-9`, last field `bool Yes = false`.
- `/fromlist` run: `Program.cs:67-73` (path checks, `PurgeList.Read`), `RunFromList` `Program.cs:193-221`, `Purge.Apply` call `:204`.
  Seams already wired: `IServiceControl`, input, `isInputRedirected`, `localNow`, `sleep`, `utcNow` (`Program.cs:20-28`).
- List-row checks for files that are not held: exact size and time, `Purge.cs:1027-1033`
  (`skipped: file changed since list (volume|id|size or time)`).
- Held rows (M9b): `/yes` window `Purge.cs:494-507`; prompt and redirected-input refusal `Purge.cs:509-540`; revalidation
  re-runs `ClassifyHeldFile` `Purge.cs:580` (identity check inside, `ServiceQuery.cs:187+`); after-stop checks: same volume and ID,
  not smaller, `Purge.cs:1130-1141`.
- List format v3 and `PurgeList.Read`/`Write`: `PurgeList.cs:19,33,107`; header carries tool version and created time.
- Operator live checks 2026-11-23 on us03p02ffm01: `/fromlist` works; M9b decline path works (see the M9b spec, "Live check
  2026-11-23"). The held stderr log grew 165G → 166G between two runs minutes apart, so an exact-size rule would skip it every time.

## Proofs before dispatch

"Prove external behaviour before dispatch": each item records host, date, version and the captured output here before dispatch.

| # | Question | Who | How (read-only unless stated) |
|---|---|---|---|
| P1 | A task registered through the Task Scheduler COM API with a one-time `TimeTrigger` and `TASK_LOGON_INTERACTIVE_TOKEN`, no password, registers for a standard user and fires in that user's session, including a **disconnected** RDP session. | operator probe on the jump box | PowerShell's `ScheduledTasks` module uses the same COM service: `$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive`; `$t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)`; `$a = New-ScheduledTaskAction -Execute cmd.exe -Argument '/c whoami > %LOCALAPPDATA%\dirused-probe\p1.txt'`; `Register-ScheduledTask -TaskPath '\dirused-probe\' -TaskName p1 -Principal $p -Trigger $t -Action $a`; disconnect the RDP session (do not sign out); reconnect after 6 min; `type %LOCALAPPDATA%\dirused-probe\p1.txt`; `Get-ScheduledTaskInfo -TaskPath '\dirused-probe\' -TaskName p1`; `Unregister-ScheduledTask ... -Confirm:$false`. Creates and removes one probe task on the jump box; no server is touched. |
| P2 | What a missed run looks like: user signed out at the trigger time, `StartWhenAvailable = false`. Does it run at the next logon (it must not), and what do `LastRunTime` / `LastTaskResult` show (expected `267011`, `SCHED_S_TASK_HAS_NOT_RUN`)? | operator probe on the jump box | As P1 with `New-ScheduledTaskSettingsSet` (StartWhenAvailable off, the default); **sign out** before the trigger, sign in after; check `p1.txt` is absent and record `Get-ScheduledTaskInfo`. Remove the task. |
| P3 | From a task in a disconnected session, can dirused reach `\\us03p02ffm01\d$` and the remote SCM? | operator probe on the jump box | As P1 with action `cmd.exe /c "dir \\us03p02ffm01\d$\Tomcat\Tomcat\logs & sc \\us03p02ffm01 query tomcat85" > %LOCALAPPDATA%\dirused-probe\p3.txt 2>&1`. Read-only on the server (a listing and a status query). |
| P4 | Will the session survive until the run? The jump box's disconnected-session and idle limits. | operator probe on the jump box | `reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxDisconnectionTime` and `/v MaxIdleTime`; `qwinsta`. If a disconnected session is logged off before the run, the run is `missed` by design (D3); the operator decides whether that is acceptable. |
| P5 | The M9b y path (stop, delete, start, health) works live. M10b's live check needs it. | operator | M9b E2 (after 19:00 Pacific, answer y). Not yet done (M9b "Live check 2026-11-23"). |
| P6 | `%LOCALAPPDATA%` on the jump box is local (not redirected to a share), and a protected DACL with one ACE for the user holds. | operator probe on the jump box | `echo %LOCALAPPDATA%`; `icacls "%LOCALAPPDATA%"`. |
| P7 | The jump box time zone. | operator probe on the jump box | `tzutil /g` (expected `Pacific Standard Time`). Decides whether bare times work there (D7). |
| P8 | Task Scheduler constants and behaviour from the docs: `TASK_LOGON_INTERACTIVE_TOKEN = 3`, `TASK_CREATE = 2`, `TASK_TRIGGER_TIME = 1`, `ITaskSettings.StartWhenAvailable`, `ITrigger.EndBoundary` + `ITaskSettings.DeleteExpiredTaskAfter`, `MultipleInstances = TASK_INSTANCES_IGNORE_NEW`, `SCHED_S_TASK_HAS_NOT_RUN = 0x41303`. | Claude, before dispatch | Microsoft Learn Task Scheduler 2.0 reference; record URL and date here. |
| P9 | A `windows-latest` GitHub runner can register and delete an interactive-token task for its own user (E1W relies on it). | Claude, before dispatch | One throwaway workflow run on a scratch branch of dirused; record the run URL. If it cannot, E1W keeps only the read-back of the definition XML (`ITaskDefinition.XmlText`) without registering, and the spec says so. |

The truncate-in-place probe (can the held Tomcat log be truncated without a stop) belongs to M10c and does not gate M10b.

## Behaviour

### 1. Command line

| Form | Meaning |
|---|---|
| `dirused /fromlist <list> /purge /schedule <time> [<zone>] [/confirm] [/yes]` | Schedule a one-time run of the list. Asks first; `/yes` skips the question. Switch order is free. |
| `dirused /schedule /list` | Show every plan and its state. |
| `dirused /schedule /cancel <id>` | Cancel a plan that has not started. |
| `dirused /runplan <plan>` | Internal: what the task runs. Not in usage or help; documented in `docs/purge.md`. |

### 2. Switch rules (exact error strings)

Parsing order: `/runplan` first, then `/schedule /list` and `/schedule /cancel`, then the `/fromlist` branch (`ArgParser.cs:119`).

1. `/runplan` present with anything else → `/runplan cannot be combined with other switches`. No path, or the next arg is a switch
   → `/runplan requires a plan path`.
2. `/schedule /list` with anything else → `/schedule /list cannot be combined with other switches`.
3. `/schedule /cancel` with anything else → `/schedule /cancel cannot be combined with other switches`; no id →
   `/schedule /cancel requires a plan id`. An id that is not `^[0-9]{8}-[0-9]{4}-[0-9a-f]{4}$` → `unknown plan id: <id>` (exit 1).
4. `/list` or `/cancel` without `/schedule` → `/list and /cancel go with /schedule`.
5. `/schedule <time>` without `/fromlist` → `/schedule requires /fromlist`. (D1: the scan path cannot be scheduled.)
6. In the `/fromlist` branch: `/schedule` with no following arg, or the next arg is a switch →
   `/schedule requires a time, e.g. /schedule 22:30 PT`. The token after the time is taken as the zone only when it is one of
   `PT`, `PST`, `PDT`, `UTC` (case-insensitive); any other non-switch token → the existing `/fromlist` whitelist error.
7. A time that is not `HH:MM` (two digits, `00:00`–`23:59`) →
   `/schedule: time must be HH:MM (00:00-23:59), optionally followed by PT, PST, PDT or UTC`.
8. `/schedule` with `/html`, `/output`, `/json` or `/csv` →
   `/schedule can only be combined with /fromlist, /purge, /confirm and /yes`.
9. `/fromlist` whitelist message becomes
   `/fromlist can only be combined with /purge, /confirm, /html, /output, /json, /csv, /yes and /schedule`
   (asserted today at `PurgeListTests.cs:102`; update it).
10. `/schedule` without `/purge` → the existing `/fromlist requires /purge`.
11. `/confirm` with `/schedule` is allowed and changes nothing (scheduling a list means deleting it; the question or `/yes` is the
    confirmation).
12. `/yes` rule (`ArgParser.cs:137`, `:263`) becomes: valid with `/purge /confirm` or with `/schedule`; otherwise
    `/yes needs /purge /confirm or /schedule`. Update every place that prints or asserts the old text.
13. Add `schedule`, `list`, `cancel`, `runplan` to `KnownSwitches`. `Options` gains, appended last and defaulted:
    `string? ScheduleTime = null, string? ScheduleZone = null, bool ScheduleList = false, string? ScheduleCancelId = null,
    string? RunPlan = null`.

Checks that need the clock or the machine's zone (bare time on a non-Pacific machine, DST gaps, "too soon") run in the CLI, not the
parser (§3).

### 3. Resolving `<time>` (CLI, clock seam)

- Zones: `PT` = Windows zone `Pacific Standard Time` (DST-aware); `PST` = fixed −08:00; `PDT` = fixed −07:00; `UTC` = +00:00.
- Bare time: allowed only when `TimeZoneInfo.Local.Id == "Pacific Standard Time"`, then treated as `PT`. Otherwise exit 1 with
  `/schedule: this machine is not on Pacific time; add PT, PST, PDT or UTC to the time`.
- The run instant is the next occurrence of `HH:MM` in that zone strictly after now; if today's has passed (or equals now), use
  tomorrow's.
- `PT` and a time that does not exist that day (spring-forward gap) → exit 1 `/schedule: <date> <HH:MM> does not exist in Pacific time (clocks go forward); pick another time`.
  `PT` and a time that happens twice (fall-back) → exit 1 `/schedule: <date> <HH:MM> happens twice in Pacific time; write PST or PDT`.
- Run instant less than 2 minutes from now → exit 1 `/schedule: <time> is less than 2 minutes away; pick a later time`.
- Every printed time shows Pacific local with its abbreviation and UTC, e.g. `Mon 2026-11-23 22:30 PST (06:30 UTC Tue)`.

### 4. Scheduling (`/fromlist <list> /purge /schedule <time>`)

1. Read the list with `PurgeList.Read` (`not a dirused delete list: <path>`, exit 1, as today). List with no file rows → exit 1
   `/schedule: the list has no files to delete`. Bad lines are reported as `/fromlist` reports them today and do not stop scheduling.
2. No target is touched at schedule time (no scan, no open of any listed file).
3. **Ask.** To stderr: `Schedule deleting <n> file(s), <Format.Size(total)> from <list> at <full time>?` then, on its own line,
   `It runs only while you are logged on to this machine; the plan expires <full time of created + 24 h>.`; then, if the run
   instant in Pacific time is outside 19:00–06:00,
   `Note: files held by Tomcat are deleted only 19:00-06:00 Pacific; at this time they will be skipped.`; then `[y/N] `.
   Same answer rules as M9b §2.4 (`y`/`yes` trimmed, case-insensitive). Input redirected without `/yes` → no read, treated as No.
   No → `Not scheduled.`, exit 0. `/yes` → no question, the lines above are still printed.
4. **Create the plan dir** `%LOCALAPPDATA%\dirused\plans\<id>\`, id = `<yyyyMMdd>-<HHmm>-<4 hex>` from the run instant in
   Pacific time plus 4 random hex digits. Before writing anything into it, set a protected DACL (inheritance off) with one ACE:
   the current user, FullControl, this folder, subfolders and files. Setting the DACL fails → remove the dir, exit 3
   `error: could not secure plan folder: <error>`.
5. Write `list.txt` (byte copy of the list) and `plan.txt`:
   ```
   # dirused plan v1
   # id: <id>
   # created: <ISO 8601 with offset>
   # run: <ISO 8601 with offset>
   # expires: <created + 24 h, ISO 8601 with offset>
   # tool: <version>
   # exe: <full path of the running dirused.exe>
   # list-sha256: <hex of list.txt>
   # source: <full path of the original list>
   ```
6. **Register** through `ITaskScheduler` (§8): folder `\dirused\`, name `purge-<id>`, one `TimeTrigger` at the run instant
   (`StartBoundary` with offset), `EndBoundary` = expiry, `DeleteExpiredTaskAfter = P30D`; principal = current user,
   `TASK_LOGON_INTERACTIVE_TOKEN`, run level LUA (not highest); settings `StartWhenAvailable = false`,
   `MultipleInstances = IgnoreNew`, `ExecutionTimeLimit = PT4H`, `DisallowStartIfOnBatteries = false`,
   `StopIfGoingOnBatteries = false`, `Enabled = true`; one exec action: `exe` from plan.txt, arguments `/runplan "<plan dir>\plan.txt"`,
   working dir the plan dir. `RegisterTaskDefinition` with `TASK_CREATE` (never update an existing task), no user name or password.
   Registration fails → remove the plan dir, exit 3 `error: could not schedule: <error>`.
7. Print `Scheduled <id> for <full time>. Check it with: dirused /schedule /list`. Exit 0. Purge log line
   `schedule <id> run <ISO> files <n> bytes <total>` (existing `LogLine`, path = list path).

### 5. The scheduled run (`/runplan <plan>`)

`/runplan` is a `/fromlist <plan dir>\list.txt /purge /confirm /yes` run with these differences, checked in this order before any
target is touched. Every outcome, including refusals, writes `report.txt` in the plan dir (§6).

1. The plan path must be `plan.txt` directly inside a dir under `%LOCALAPPDATA%\dirused\plans\` (compared after
   `Path.GetFullPath`, case-insensitive) → else `refused: plan is not in the plan folder` (exit 1; nothing written outside it).
2. `cancelled` marker file present → outcome `cancelled`, exit 0.
3. `report.txt` already present → `refused: plan already ran` (do not overwrite the report; stderr only, exit 1).
4. Plan dir owner is not the current user, or its DACL is not protected or has any ACE other than the current user →
   `refused: plan folder permissions changed`.
5. `plan.txt` unreadable, wrong header, or a field missing → `refused: not a dirused plan`.
6. `sha256(list.txt) != list-sha256` → `refused: list changed since it was scheduled`.
7. Running tool version ≠ `tool:` → `refused: dirused was updated since this was scheduled (<old> → <new>); schedule it again`.
8. Now (clock seam) ≥ `expires` → outcome `expired`, nothing deleted, exit 0.
9. Otherwise run `Purge.Apply` exactly as `RunFromList` does with: `confirm = true`, `yes = true`, `input = TextReader.Null`,
   `inputRedirected = true`, the real `IServiceControl`, and a new optional parameter `planRun = true`. This is how `/runplan`
   confirms without a prompt: the M9b `/yes` path, including its 19:00–06:00 window check right before each group's stop.

`planRun = true` changes only list rows (`File.FromList`):
- **Files not held** (`Purge.cs:1027-1033`): volume serial and file ID must match (unchanged); then instead of exact size and time:
  current length < listed → `skipped: file changed since list (smaller)`; current last-write < listed →
  `skipped: file changed since list (older)`. Larger and newer pass. All other M8 handle checks unchanged.
- **Held Tomcat rows**: before the group is asked (here: before the `/yes` window decision) and again at revalidation
  (`Purge.cs:580`), each row is opened for attributes only (no `DELETE` access) and checked: same volume serial and file ID, length
  not smaller, last-write not older. A row that fails leaves the group with `skipped: file changed since list (id|smaller|older)`
  and never counts toward a stop. No row left → no stop. After the stop, the existing checks (`Purge.cs:1130-1141`) run unchanged,
  plus last-write not older (`skipped: file changed since list (older)`).
- `planRun = false` (every non-scheduled path) keeps today's behaviour exactly.

Exit codes as `/fromlist` (0, 3, 4; `ServiceStartFailed` → 3, M9b §5). The task's last result shows the exit code.

### 6. Run report

`report.txt`, written once at the end of `/runplan` (a refusal or `expired` writes it at once):
```
# dirused run report v1
# id: <id>
# started: <ISO>
# finished: <ISO>
# outcome: done | expired | cancelled | refused: <reason>
# exit: <code>
# result: deleted <n> file(s), <size> freed; <s> skipped; <f> failed
<the same text output a /fromlist ... /purge /confirm run prints, rows and statuses>
<stderr lines from the run: service stop/start lines and any error>
```
`result:` only for `done`. Write failure → stderr and the purge log; the exit code is unchanged. No pop-up, no message box.

### 7. `/schedule /list` and `/schedule /cancel`

`/schedule /list` reads every dir under the plan root plus the task's state from `ITaskScheduler.Query`, newest run first, one line
each: `<id>  <run, Pacific>  <state>  <source list file name>`. States, first match wins:
- `report.txt` present → its `outcome`, and for `done` its `result` and `exit`.
- `cancelled` marker → `cancelled`.
- Task state Running → `running`.
- Now ≥ expires → `expired (did not run)`.
- Now > run + 10 min and the task's last run time is before the run instant (or never) → `missed` (expected `LastTaskResult`
  267011, P2). A missed plan stays missed; the task never starts later (`StartWhenAvailable = false`).
- Task missing → `task missing`.
- Otherwise `scheduled`.
A dir without a readable `plan.txt` → `<dir name>  unreadable plan`. No plans → `No scheduled purges.` Exit 0.

`/schedule /cancel <id>`: plan dir missing → exit 1 `unknown plan id: <id>`. `report.txt` present → exit 1
`<id> already ran; nothing to cancel`. Task Running → exit 1 `<id> is running; it cannot be cancelled once it has started`
(stopping it mid-run could leave Tomcat stopped). Otherwise write the `cancelled` marker first, then delete the task; task already
gone is fine. Print `Cancelled <id>.`, purge log `schedule-cancel <id>`, exit 0. Delete fails after the marker → exit 3
`error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run`.

### 8. Seams

- `ITaskScheduler` (new, `src/Dirused.Common/TaskScheduling.cs`): `Register(PlanTask)` → (ok, error); `Query(id)` →
  `TaskInfo(State, LastRunTime, LastTaskResult)` or null; `Delete(id)` → (ok, error). `PlanTask` carries every field in §4.6.
  `RealTaskScheduler` (Windows): COM `Schedule.Service` (`ITaskService.Connect()` with no arguments, `GetFolder`, create the
  `\dirused` folder if missing, `NewTask(0)`, `RegisterTaskDefinition`). COM interop through `[ComImport]` interfaces or `dynamic`;
  **no NuGet package, never `schtasks.exe` or any command string.**
- `IPlanFolderSecurity` (new): `Secure(dir)` and `IsSecure(dir)` → (ok, reason). Real one via `DirectorySecurity`
  (`SetAccessRuleProtection(true, false)`, one `FileSystemAccessRule` for `WindowsIdentity.GetCurrent().User`), Windows only.
- Clock: `Func<DateTimeOffset> now` and `TimeZoneInfo localZone` (tests inject both; Pacific is looked up by id
  `Pacific Standard Time`, with the IANA id `America/Los_Angeles` as fallback so the Portable tests run on Linux/macOS).
- Plan root: a parameter defaulting to `%LOCALAPPDATA%\dirused\plans`; tests pass a temp dir.
- Random id suffix: `Func<int>`; tests fix it.
- `Program.RunCore` gains optional, appended: `ITaskScheduler?`, `IPlanFolderSecurity?`, `Func<DateTimeOffset>?`, `TimeZoneInfo?`,
  `string? planRoot`, `Func<int>? idRandom`; defaults to the real ones on Windows. On a non-Windows OS, `/schedule` and `/runplan`
  exit 1 `/schedule needs Windows`.
- `Purge.Apply` gains optional, appended `bool planRun = false`.

### 9. Docs

- `docs/purge.md`: a "Scheduled purge" section: the command, the question, the plan dir and its files, `/runplan` and its refusals,
  the run-time rule for growing logs (§5), held Tomcat files and the 19:00–06:00 window, `expired`/`missed`/`cancelled`, how to
  read `report.txt`, that the run needs you logged on (disconnected is fine, signed out is `missed`), new statuses.
- `README.md`: usage lines, one example, the new `/yes` text. `CHANGELOG.md`: bullets under `## [Unreleased]` only.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs` | §2 switches, errors, usage and help |
| `src/Dirused.Common/TaskScheduling.cs` (new) | `ITaskScheduler`, `PlanTask`, `TaskInfo`, `RealTaskScheduler` |
| `src/Dirused.Common/Plan.cs` (new) | plan dir, `plan.txt`/`report.txt` read and write, id, time resolution (§3), `IPlanFolderSecurity` + real |
| `src/Dirused.Common/Purge.cs` | `planRun` checks (§5) |
| `src/Dirused.Cli/Program.cs` | `/schedule`, `/schedule /list`, `/schedule /cancel`, `/runplan` wiring |
| `tests/Dirused.Tests.Portable/ScheduleTests.cs` (new) | E1 |
| `tests/Dirused.Tests.Portable/ArgParserTests.cs`, `PurgeListTests.cs` (`:102`) | switch rules, whitelist and `/yes` messages |
| `tests/Dirused.Tests/TaskSchedulerWindowsTests.cs` (new) | E1W |
| `docs/purge.md`, `README.md`, `CHANGELOG.md` | §9 |

## Contract readers

`git grep` at a2d0508 (to be re-run by the reviewers):
- `/fromlist` whitelist text: writer `ArgParser.cs:121`; reader `PurgeListTests.cs:102`; docs `docs/purge.md`, `README.md`.
- `/yes needs /purge /confirm`: writers `ArgParser.cs:137`, `:263`; readers in `ArgParserTests.cs` and `PurgeListTests.cs` (grep the
  string), `docs/purge.md`, `README.md`. Text changes (§2.12).
- `KnownSwitches` `ArgParser.cs:16`: adding `list`, `cancel`, `schedule`, `runplan` makes `MissingPath` (`ArgParser.cs:15`) treat
  `/list` etc. as a switch after `/output`, `/file`, `/savelist`, `/fromlist`. A file literally named `/list` is not a real case.
- `Options` constructed at `ArgParser.cs:139`, `:291` (and any test that builds `Options`): new fields last, defaulted.
- `Purge.Apply` call sites `Program.cs:119`, `:204`, plus the test call sites listed in the M9b spec: new parameter optional, last.
- List-row statuses `skipped: file changed since list (...)`: writers `Purge.cs:1027-1033`, `:1135`, `:1140`; new `(older)` and the
  `(smaller)` text on the not-held path only under `planRun`; readers `PurgeListTests.cs`, `docs/purge.md`.
- Purge log `C:\temp\dirused-purge.log`: new `schedule`, `schedule-cancel` lines; human-read only.
- New on-disk contract: `%LOCALAPPDATA%\dirused\plans\<id>\{plan.txt,list.txt,report.txt,cancelled}`; writers `Plan.cs`; readers
  `/runplan`, `/schedule /list`, `/schedule /cancel`. Task path `\dirused\purge-<id>`; writer `RealTaskScheduler`; reader the
  same.

## What NOT to Do

- Do not scan, add patterns, or delete anything not in `list.txt`. Do not read the original list at run time.
- Do not add a repeat trigger, a logon trigger, `StartWhenAvailable = true`, a stored password, S4U, or run level highest.
- Do not call `schtasks.exe` or build any command string; do not add a NuGet package.
- Do not stop a service for a row that failed the identity check, and do not bypass the M9b window or any M9b step.
- Do not show a message box or toast. Do not let `/schedule /cancel` stop a running task.
- Do not relax any check when `planRun` is false.
- Do not modify files outside the Files table. Do not push, open a PR, or skip hooks. Leave changes uncommitted. Your sandbox may not
  restore NuGet or run tests; finish code and tests anyway and say so.

## Acceptance

```yaml
must:
  - id: M1
    text: "with a fake ITaskScheduler, clock at Mon 2026-11-23 21:00 PST and machine zone Pacific: '/fromlist l.txt /purge /schedule 22:30 /yes' registers one task \\dirused\\purge-20261123-2230-<hex> with a one-time trigger at 2026-11-23T22:30:00-08:00, EndBoundary = created + 24 h, interactive token, no password, LUA, StartWhenAvailable false, IgnoreNew, action '/runplan \"<plan dir>\\plan.txt\"'; plan dir has list.txt byte-equal to l.txt and plan.txt with the matching sha256; Secure was called before any file was written; exit 0"
  - id: M2
    text: "time resolution: 20:00 at a 21:00 clock means tomorrow and the prompt shows the full date; 22:30 UTC, PST, PDT and PT give the right instants; a bare time on a non-Pacific machine exits 1 with the exact message; spring-forward 02:30 PT and fall-back 01:30 PT exit 1 with their messages; 01:30 PDT on fall-back day is accepted; a time 1 minute away exits 1"
  - id: M3
    text: "the question text (with the 19:00-06:00 note only for a run instant outside the window) is written before reading; 'y'/'YES' schedule; any other answer, empty input, or redirected input without /yes prints 'Not scheduled.', exit 0, no plan dir and no task"
  - id: M4
    text: "every switch rule in §2 gives its exact error string (one test per rule), and /confirm with /schedule is accepted"
  - id: M5
    text: "/runplan with a valid plan runs the list with confirm, yes, redirected input and planRun; a not-held listed log that grew and has a newer last-write is deleted; a held Tomcat row that grew is deleted through the M9b stop/delete/start path at 22:30 with no input read"
  - id: M6
    text: "/runplan refusals each write report.txt with their outcome and delete nothing: plan outside the plan root (no report, exit 1), cancelled marker, report already present (report not overwritten), DACL changed, bad plan.txt, list sha256 mismatch, tool version changed, now >= expires ('expired', exit 0)"
  - id: M7
    text: "/schedule /list shows done (with result and exit), expired (did not run), cancelled, running, missed (now > run + 10 min, task last run before run instant), task missing, scheduled, and 'unreadable plan'; 'No scheduled purges.' when empty"
  - id: M8
    text: "/schedule /cancel writes the cancelled marker and then deletes the task; refuses a running plan and a plan that already ran with the exact messages; an unknown id exits 1"
  - id: M9
    text: "registration failure or DACL failure removes the plan dir and exits 3 with the exact message"
  - id: M10
    text: "docs/purge.md has a Scheduled purge section covering §9; README usage and /yes text updated; CHANGELOG has Unreleased bullets and no new version header"
must_not:
  - id: N1
    text: "under planRun, a held Tomcat row whose file ID differs, is smaller, or has an older last-write causes Stop (paired: same-ID, larger, newer held row in the same plan that is stopped for and deleted)"
  - id: N2
    text: "under planRun, a not-held row with a different ID, smaller length or older last-write is deleted (paired: grown, newer peer deleted)"
  - id: N3
    text: "with planRun false, a listed not-held log that grew is deleted (paired: the same file under planRun is deleted) — today's exact check stays"
  - id: N4
    text: "an expired plan deletes or stops anything (paired: the same plan one minute before expiry deletes)"
  - id: N5
    text: "/runplan reads input or deletes a held row outside 19:00-06:00 (paired: 22:30 run deletes it)"
  - id: N6
    text: "/schedule touches any target (fake file system records no Open/Probe calls) or registers a task with StartWhenAvailable true, a repeat, or a password (paired: M1's registration recorded)"
  - id: N7
    text: "/schedule /cancel calls Delete or Stop on a running task (paired: cancel of a scheduled task deletes it)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, M7, M8, M9, N1, N2, N3, N4, N5, N6, N7]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable with fake ITaskScheduler, IPlanFolderSecurity, IServiceControl, IPurgeFileSystem, clock, zone, input and id random. New tests red on a2d0508. Mutants each red: StartWhenAvailable true; drop the EndBoundary; expiry check uses > instead of >=; skip the sha256 check; skip the version check; skip the DACL check; planRun relaxes the check when false; drop the 'older' check; held-row identity check only after the stop; passed time stays today; PST treated as DST-aware; bare time accepted on a non-Pacific machine; cancel deletes a running task; report written before the outcome is known and overwritten on a second run"
    intent: "A scheduled run deletes only the copy of the list you approved, refuses if anything about the plan changed, deletes nothing once it is a day old, and lets growing logs go only when they are the same file, bigger and newer — never stopping Tomcat for a file that fails that check."
  - id: E1W
    proves: [M1, M9]
    kind: offline
    command: "windows-latest CI: TaskSchedulerWindowsTests registers a real task \\dirused-ci\\purge-<guid> one day ahead through RealTaskScheduler, reads it back through the COM API (trigger type and boundaries, LogonType 3, RunLevel LUA, StartWhenAvailable false, MultipleInstances IgnoreNew, the action and arguments), queries it, and deletes it in finally; the task never fires. RealPlanFolderSecurity secures a temp dir and IsSecure reads back one ACE for the current user with inheritance off; adding an Everyone ACE makes IsSecure false. If P9 shows the runner cannot register, this test asserts the definition XML only and the spec records it"
    intent: "The real Windows task and folder-permission calls are checked on a throwaway task in CI, so a wrong setting shows up before it reaches the jump box."
  - id: E3
    proves: [M10]
    kind: offline
    command: "git diff shows docs/purge.md, README.md and CHANGELOG [Unreleased] updated; git grep '/yes needs /purge /confirm\"' finds no stale copy"
    intent: "The guide tells you how to schedule, check, cancel and read the result of a purge, and what 'missed' and 'expired' mean."
  - id: E2
    proves: [M1, M5]
    kind: live
    command: "operator, jump box, after P1-P7 and P5: dirused \\\\us03p02ffm01\\d$\\tomcat /largest *.log /purge /savelist m10b.txt; review it; dirused /fromlist m10b.txt /purge /schedule <a time after 19:00> PT, answer y; dirused /schedule /list shows scheduled; disconnect RDP; after the run, reconnect: /schedule /list shows done with the result; report.txt lists the deleted files and the Tomcat stop/start lines; sc \\\\us03p02ffm01 query tomcat85 shows RUNNING; free space on d$ rose; the operator confirms the app responds"
    intent: "You schedule tonight's purge from a list you reviewed, disconnect, and in the morning see in /schedule /list and the report that the files went, Tomcat came back, and the disk has room."
interface:
  - "/schedule <time> [PT|PST|PDT|UTC]"
  - "/schedule /list"
  - "/schedule /cancel <id>"
  - "/runplan <plan>"
  - "/runplan cannot be combined with other switches"
  - "/runplan requires a plan path"
  - "/schedule /list cannot be combined with other switches"
  - "/schedule /cancel cannot be combined with other switches"
  - "/schedule /cancel requires a plan id"
  - "/list and /cancel go with /schedule"
  - "/schedule requires /fromlist"
  - "/schedule requires a time, e.g. /schedule 22:30 PT"
  - "/schedule: time must be HH:MM (00:00-23:59), optionally followed by PT, PST, PDT or UTC"
  - "/schedule can only be combined with /fromlist, /purge, /confirm and /yes"
  - "/fromlist can only be combined with /purge, /confirm, /html, /output, /json, /csv, /yes and /schedule"
  - "/yes needs /purge /confirm or /schedule"
  - "/schedule: this machine is not on Pacific time; add PT, PST, PDT or UTC to the time"
  - "/schedule: <date> <HH:MM> does not exist in Pacific time (clocks go forward); pick another time"
  - "/schedule: <date> <HH:MM> happens twice in Pacific time; write PST or PDT"
  - "/schedule: <time> is less than 2 minutes away; pick a later time"
  - "/schedule: the list has no files to delete"
  - "/schedule needs Windows"
  - "Not scheduled."
  - "Scheduled <id> for <time>. Check it with: dirused /schedule /list"
  - "unknown plan id: <id>"
  - "<id> already ran; nothing to cancel"
  - "<id> is running; it cannot be cancelled once it has started"
  - "Cancelled <id>."
  - "error: could not secure plan folder: <error>"
  - "error: could not schedule: <error>"
  - "error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run"
  - "refused: plan is not in the plan folder / plan already ran / plan folder permissions changed / not a dirused plan / list changed since it was scheduled / dirused was updated since this was scheduled (<old> → <new>); schedule it again"
  - "outcome: done | expired | cancelled | refused: <reason>"
  - "states: scheduled | running | missed | expired (did not run) | cancelled | task missing | unreadable plan | done"
  - "skipped: file changed since list (smaller) / (older)  [planRun]"
  - "purge log: schedule <id> ... / schedule-cancel <id>"
```

## Open decisions for the operator

| # | Question | Spec default |
|---|---|---|
| O1 | Does the M9b 19:00–06:00 window still apply to held Tomcat files in a scheduled run? | Yes: `/runplan` uses the `/yes` path, window included; the schedule prompt warns when the time is outside it. The alternative (a scheduled run is "as if y" at any hour) needs an explicit operator call. |
| O2 | If the jump box logs off disconnected sessions before the run (P4), is `missed` acceptable, or is a stored-credential task wanted? | `missed` (D3 forbids a stored password). |
| O3 | Refuse a list older than N hours at schedule time? | No age check; the run-time identity checks and the 24 h plan expiry cover it. |
| O4 | `/confirm` with `/schedule`: allowed and ignored, or an error? | Allowed (§2.11). |
| O5 | A dirused self-update between scheduling and the run: refuse (spec) or run with the new version? | Refuse with `refused: dirused was updated ...`. |

## Worker definition of done

- Change only the files in the table. Report each command, its rc and proving lines; list every error seen.

## Review adjudication

(empty until the Fable and Astra blind reviews of rev 1)
