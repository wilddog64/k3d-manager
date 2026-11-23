# dirused M10b: schedule a one-time purge of a reviewed delete list

**Status:** OPEN — SPEC rev 2, 2026-11-23 (Fable + Astra blind reviews of rev 1 applied; split into M10b1–M10b4); awaiting proofs and intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** `docs/plans/dirused-m10-scheduled-purge.md` Amendments 1–3 (M10b = `/schedule` over an M10a list, after M9).
Builds on M10a (`/savelist`, `/fromlist`, PR #35) and M9b (Tomcat stop/delete/start, PR #39).
**Children (sequential; the files overlap):** [M10b1 engine](dirused-m10b1-engine-single-read-no-service.md) →
[M10b2 schedule, preview, list, cancel](dirused-m10b2-schedule-preview-list-cancel.md) →
[M10b3 /runplan and the real Windows classes](dirused-m10b3-runplan-windows.md) → [M10b4 docs](dirused-m10b4-docs.md).
This file is the design all four children build to; each child carries its own Acceptance block.
**Later milestone:** [M10d unattended service stop/start](dirused-m10d-unattended-service-stop.md) (DRAFT; also carries the
"register the task on the target node" option).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (from main a2d0508, v0.0.26 pre-release); children commit to it in order
**Version:** v0.0.27 (one release after M10b4 lands)
**Risk:** high — an unattended run deletes files with nobody watching (it never stops a service in M10b)
**Review:** rev 1 Fable + Astra blind (2026-11-23), Claude adjudicated (table at the end). Design change 2026-11-23: COM adapter replaced by `schtasks.exe /xml` (section "Why schtasks.exe"). Rev 2: Fable delta review of the four children before the first dispatch.
**Implementer:** Luna (Codex) for M10b1–M10b3; Flash for M10b4
**Verifier:** Claude (offline, from each child's Acceptance only). Live checks by the operator on the office jump box.
**Filed:** 2026-11-23
**Intent approved:** pending (rev 2 intents are new; every child's intents need approval)
**Approval:** operator, 2026-11-23 — scheduled runs skip held files and stop no service ("Skip held files for now"); split into
sequential parts ("Split into sequential parts"); the growth relaxation goes only to held Tomcat logs, so it moves to M10d with them
("Held Tomcat logs only"); preview before scheduling ("can we allow print out schedule for confirm before it actually scheduled").
Baseline-red exceptions requested for the absence-of-effect tests listed in "Acceptance map" (not yet approved).

## Before You Start

- Read `docs/plans/dirused-m10a-purge-delete-list.md` (list format, `/fromlist` checks) and
  `docs/plans/dirused-m9b-stop-delete-start.md` (held-file grouping and statuses).
- Every proof below is answered and recorded in this file first. A child does not start until the proofs it names are marked.

## Why

Operator, 2026-11-19: delete the big logs at a time they choose, without sitting at the jump box. Operator, 2026-11-23, after the
`/fromlist` and M9b decline-path live checks: "we can go with scheduling". The safety model from Amendment 3 stays: what is deleted
is the list the operator reviewed, never a new scan.

## Operator decisions this spec honours

| # | Decision | Source |
|---|---|---|
| D1 | Delete only the reviewed list (a copy taken at schedule time). | Amendment 3 |
| D2 | One-time runs only. Recurring rules are a separate draft, `dirused-m10c-recurring-purge-rules.md`. | Amendment 3 |
| D3 | "Run only when user is logged on"; no stored password. | Amendment 3 |
| D4 | The list is copied into the plan dir at schedule time; the run reads only that copy. | Amendment 3 |
| D5 | Result in a run report next to the plan and in `/schedule /list`; no pop-up. | Amendment 3 |
| D6 | A plan expires 24 h after it is created; an expired plan deletes nothing. | Amendment 3 |
| D7 | `<time>` is `HH:MM` with optional `PST`, `PDT`, `PT` or `UTC`; a bare time only on a Pacific-time machine; a passed time means tomorrow. | Amendment 3 |
| D8 | dirused runs on the office jump box. | Amendment 3 |
| D9 | **Scheduled runs never stop or start a service.** A row held open by a service is skipped with `skipped: held by <service> — scheduled runs do not stop services`. Unattended stop/start moves to M10d, which needs a recovery path that survives a killed process. | operator 2026-11-23, "Skip held files for now" |
| D10 | Split into sequential children M10b1–M10b4. | operator 2026-11-23, "Split into sequential parts" |
| D11 | The growth relaxation (a grown file may still match) applies only to held Tomcat logs, so it moves to M10d. Ordinary rows keep today's exact volume, ID, size and time match. | operator 2026-11-23, "Held Tomcat logs only" |
| D13 | **The target node comes from the list.** The host is the UNC host of the list's paths; one plan per list; several plans may be scheduled for different nodes. A list spanning more than one host is refused (O8 default), so each plan is one node. Preview and `/schedule /list` show the host. | operator 2026-11-23, "can we schedule at the node we like to?" → "Both" |
| D12 | **Preview first.** `/schedule` without `/confirm` prints the plan and schedules nothing; `/confirm` previews, then asks; `/confirm /yes` previews and schedules without asking. | operator 2026-11-23, "can we allow print out schedule for confirm before it actually scheduled" |

## Facts this spec relies on (dirused main a2d0508)

- `/fromlist` branch: `ArgParser.cs:119-139`; whitelist message `:121`; `/yes` rule `:137` (fromlist) and `:263` (scan);
  `KnownSwitches` `:16`; `IsFlag` accepts `/x`, `-x`, `--x`, case-insensitive (`:8-13`); scan loop is first-error-wins (`:249`).
- `/version` and `/update` are handled in `Program.cs:32-42` before `ArgParser.Parse`.
- `Options` `Options.cs:4-9`, last field `bool Yes = false`. `Program.RunCore` is private (`Program.cs:21`); public seams
  `Run`, `RunWithReleaseSource`, `RunWithPurge` (`Program.cs:17-20`).
- `/fromlist` run: `Program.cs:67-73` (path checks, `PurgeList.Read`), `RunFromList` `:193-221`, `Purge.Apply` call `:204`.
- `Purge.Apply` signature `Purge.cs:96-114` (last param `TextWriter? error`); held groups loop `:470+`; `/yes` window uses
  `localNow()` (machine local) at `:494-507`; prompt `:509-540`; revalidation `:580`.
- Ordinary list rows: exact volume, ID, size and time `Purge.cs:1027-1033` (`skipped: file changed since list (...)`).
- `PurgeList.Read(path)` reads with `File.ReadAllLines` (`PurgeList.cs:33-37`); v1–v3 accepted; rows carry no "held" field.
- Projects: `Dirused.Common` net10.0; `Dirused.Cli` net10.0-windows; `tests/Dirused.Tests.Portable` references Common only (ubuntu
  CI job); `tests/Dirused.Tests` is Windows-only.
- Operator live checks 2026-11-23 on us03p02ffm01: `/fromlist` works; M9b decline path works (M9b spec, "Live check 2026-11-23").

## Trust boundary

- Trusted: the operator, the jump box's administrators and SYSTEM, and the `dirused.exe` the operator runs interactively to schedule.
- Not trusted: other ordinary users of the jump box, anything they can write (shared folders such as `C:\temp`), and the original
  list file after it has been read.
- What protects a scheduled run: the plan folder and the program copy inside it are owned by the operator with a protected DACL
  (one ACE, the operator), so only the operator, administrators and SYSTEM can change them. The two sha256 values in `plan.txt` are
  a corruption check, not a defence against the operator's own account (anything running as the operator can rewrite both).
- A check inside an exe cannot protect that exe's own launch; that is why the task runs a copy inside the protected folder (§4.6).

## Proofs before dispatch

"Prove external behaviour before dispatch": each item records host, date, version and the captured output here. Probes on the jump
box create and remove only probe tasks and probe folders under the operator's profile. None stops a service or writes to a server
unless marked "operator's call".

| # | Question | Who | Gates | How |
|---|---|---|---|---|
| P1 | A task created by `schtasks /create /xml` from dirused's **production XML** fires in the user's **disconnected** RDP session (one-time trigger with offset `StartBoundary`, `EndBoundary`, `DeleteExpiredTaskAfter P30D`, `AllowStartOnDemand false`, `StartWhenAvailable false`, `IgnoreNew`, `InteractiveToken`, `LeastPrivilege`, `UserId` = SID, folder `\dirused-probe\<SID>\`). Quick pre-probe already given to the operator: `\dirused-probe\t1` with `/it /sc once`, read back with `/query /xml`. | operator, jump box | b3 | Claude supplies the XML file and a `.cmd` that first creates `%LOCALAPPDATA%\dirused-probe\p1-<stamp>\` and a fresh marker path; `schtasks /create /tn ... /xml <file>`; disconnect (do not sign out) for 6 min; reconnect; record the marker, `schtasks /query /tn ... /xml`, `whoami /groups`. Remove the task and folder. |
| P2 | A missed run (signed out at the trigger, `StartWhenAvailable false`) never runs at the next logon, and a fired control shows the recorder works. | operator, jump box | b2 (`missed` state), b3 | Two probe tasks from the P1 script: one fires while connected (positive control, marker present); one fires while signed out (marker absent after the next logon). Record `schtasks /query /tn ... /xml` and the markers for both (no reliance on scheduler last-result: dirused derives `missed` from its own files). |
| P3 | Under the disconnected task token, at night after an afternoon disconnect, the run can list `\\us03p02ffm01\d$\Tomcat\Tomcat\logs` and the user's effective rights there include delete. | operator, jump box | b3 | Probe task (P1 settings) triggered ≥ 4 h after disconnecting, action `cmd.exe /c "(dir \\us03p02ffm01\d$\Tomcat\Tomcat\logs & icacls \\us03p02ffm01\d$\Tomcat\Tomcat\logs) > <marker> 2>&1"`. Read-only. A create+delete of a probe file on the server is the operator's call and is not required. |
| P4 | Session survival: disconnected-session and idle limits. | operator, jump box | b2 (O2) | `reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxDisconnectionTime` and `/v MaxIdleTime`; `qwinsta`. |
| P5 | Night logoffs and reboots: does the jump box reboot or patch at night? | operator, jump box | b3 (interrupted state is real) | `wevtutil qe System /q:"*[System[(EventID=1074 or EventID=6006 or EventID=6008)]]" /c:30 /rd:true /f:text`. Read-only. |
| P6 | `%LOCALAPPDATA%` is local, and a protected one-ACE DACL with the user as owner holds on a folder the user creates; whether the operator's shell is elevated. | operator, jump box | b3 | `echo %LOCALAPPDATA%`; create `%LOCALAPPDATA%\dirused-probe\p6`; `icacls ... /inheritance:r /grant:r "%USERNAME%":(OI)(CI)F`; `icacls ... /setowner "%USERNAME%"`; read back with `icacls` and PowerShell `(Get-Acl ...).Owner`; `whoami /groups`. Remove it. |
| P7 | The jump box time zone. | operator, jump box | b2 | `tzutil /g`. |
| P8 | (a) `schtasks /create /xml` accepts a UTF-16 LE file with BOM and `<?xml version="1.0" encoding="UTF-16"?>`; (b) the bytes `schtasks /query /tn ... /xml` writes to a redirected stdout (encoding, BOM or not) so dirused can decode them; (c) the Task Scheduler 1.2 XML schema element names and values used here (`TimeTrigger`, `StartBoundary` with offset is an absolute instant, `EndBoundary`, `LogonType InteractiveToken`, `RunLevel LeastPrivilege`, `AllowStartOnDemand`, `StartWhenAvailable`, `MultipleInstancesPolicy IgnoreNew`, `ExecutionTimeLimit`, `DeleteExpiredTaskAfter`, `Hidden`, `RegistrationInfo/SecurityDescriptor`); (d) `schtasks` exit codes 0 on success, non-zero on failure, and `/create` without `/f` fails when the name exists. | Claude (docs) + operator (a, b, d on the jump box) | b2, b3 | Microsoft Learn schtasks and Task Scheduler schema pages (record URL, date); operator runs the P1 `.cmd` variant that also creates twice without `/f` and saves `/query /xml > q.xml`, then `certutil -dump q.xml` head (first bytes) is pasted. |
| P9 | A `windows-latest` runner can `schtasks /create /xml`, `/query /xml` and `/delete /f` an interactive-token task in `\dirused-ci\` from the published single-file exe. | Claude | b3 (E-B3W) | One throwaway workflow on a scratch dirused branch; record the run URL. If not, E-B3W asserts the generated XML only and says so. |
| P10 | A standard user can create `\dirused\<SID>\` with `schtasks /create /xml`; the XML's `RegistrationInfo/SecurityDescriptor` (`D:P(A;;FA;;;<SID>)(A;;FA;;;SY)(A;;FA;;;BA)`) is honoured; a second ordinary account cannot read or change the task. | operator (second account if one exists), jump box | b3 | From the P1 `.cmd` with the descriptor; from a second account `schtasks /query /tn "\dirused-probe\<SID>\p10"` must fail. If no second account exists, record the task's security via PowerShell `(Get-ScheduledTask ...).SecurityDescriptor`. If the descriptor is not honoured, the spec falls back to the per-user folder name only and says so. |
| P12 | `AllowStartOnDemand false` blocks `schtasks /run /tn ...` (expect a non-zero exit and the task not started). | operator, jump box | b3 | On the P1 task before it fires: `schtasks /run /tn ...`; record the exit code (`echo %ERRORLEVEL%`) and that the marker stays absent. |
| P11 | Where `dirused.exe` lives on the jump box and who can write it and its folder. | operator, jump box | b2 (O7) | `where dirused`; `icacls <exe>`; `icacls <exe folder>`. |

### Probe results

**2026-11-23, jump box (operator screenshot, about 11:40 PT), quick probe `\dirused-probe\t1`:**

- **P11, partial: the exe ACL is too broad.** `icacls bin\dirused.exe`, run from the profile root, shows all entries
  inherited (`(I)`), with full control for each of:
  - SYSTEM;
  - Administrators;
  - the operator;
  - an unresolved domain SID (`S-1-5-21-…-8249`);
  - a second named domain account.

  So another account can replace the exe, which confirms the Fable B1 risk on this host. O7's default would refuse
  to schedule. The folder ACL (`icacls bin`) and where the inheritance comes from are not yet captured.
- **Quick-task creation.** `schtasks /create … /sc once /st 23:00 /it /f` succeeded as the operator. A non-default
  task folder (`\dirused-probe\`) was created by it. Whether the shell was elevated is not yet captured, so this does
  not yet prove P10's standard-user folder creation.
- **P8 (b), partial.** `/query /xml` output declares `encoding="UTF-16"` and `Task version="1.2"`, with namespace
  `http://schemas.microsoft.com/windows/2004/02/mit/task`. The bytes on redirection are not yet captured.
- **Defaults the switches leave**, read back, which confirms the switch-vs-XML table:
  - `StartBoundary` `2026-11-23T23:00:00` has **no offset**;
  - there is no `EndBoundary`;
  - there is no `AllowStartOnDemand` element, so the default allows a manual start;
  - there is no `StartWhenAvailable` element, so the default is false;
  - there is no `ExecutionTimeLimit` element, so the default applies;
  - `DisallowStartIfOnBatteries` and `StopIfGoingOnBatteries` are `true`;
  - `MultipleInstancesPolicy IgnoreNew`;
  - Principal `LogonType InteractiveToken` with the user SID, and no `RunLevel` element.

  Production XML must set `DisallowStartIfOnBatteries`/`StopIfGoingOnBatteries` false explicitly, and the read-back
  compare must include them.
- **Not a defect: `%date% %time%` expanded at create time.** cmd expands it inside the quoted `/tr`, so the action
  echoes the creation time. P1's fire evidence is the output file's last-write time plus `/query /v` Last Run Time,
  not the file's text.
- **P1 itself is pending.** It is answered after 23:00 with the session disconnected.


## Behaviour

### Why schtasks.exe with an XML file (design change 2026-11-23)

Operator asked whether `schtasks` can simplify the COM adapter; Claude recommends it, pending P8–P10 and P12. Plain `schtasks`
switches cannot express this plan; the XML file can, and `schtasks` only carries it:

| Need | `schtasks /create` switches | `/create /xml <file>` |
|---|---|---|
| `EndBoundary` for a `/sc once` task | no (`/ed` is date-only and not for once) | yes |
| `StartBoundary` with an explicit UTC offset | no (local `/st` `/sd`, locale date format) | yes |
| `AllowStartOnDemand = false` | no | yes |
| `StartWhenAvailable = false` (no catch-up) explicitly | no | yes |
| `DeleteExpiredTaskAfter`, `ExecutionTimeLimit`, `MultipleInstancesPolicy` | no (partial: `/z`, `/du` only with repeats) | yes |
| locale-independent dates | no (`/sd` follows the regional format) | yes (ISO 8601) |
| task security descriptor | no | yes (`RegistrationInfo/SecurityDescriptor`, P10) |

Rules: run `%SystemRoot%\System32\schtasks.exe` by absolute path (from `Environment.SystemDirectory`) through `ProcessStartInfo`
with `ArgumentList`, `UseShellExecute = false`, no shell and no command string. Success or failure comes from the exit code only;
`schtasks` text output is never parsed (it is localized). The only output read is `/query /xml`, which is XML.

### 1. Command line

| Form | Meaning |
|---|---|
| `dirused /fromlist <list> /purge /schedule <time> [<zone>]` | **Preview only**: print the plan (§4.2), schedule nothing, write nothing, exit 0. |
| `dirused /fromlist <list> /purge /schedule <time> [<zone>] /confirm` | Preview, then `Schedule this? [y/N] `; only `y`/`yes` schedules. |
| `dirused /fromlist <list> /purge /schedule <time> [<zone>] /confirm /yes` | Preview, then schedule without asking. |
| `dirused /schedule /list` | Show every plan and its state. |
| `dirused /schedule /cancel <id>` | Cancel a plan that has not started. |
| `dirused /runplan <id>` | Internal: what the task runs. Not in usage or help; documented in `docs/purge.md`. |

Switch order is free. `/purge` stays required (the existing `/fromlist requires /purge`). `/yes` keeps today's rule and text:
`/yes needs /purge /confirm` (so `/schedule /yes` without `/confirm` gets that error). This mirrors the `/purge` dry run.

### 2. Switch rules and precedence (exact error strings)

All scheduling switches are matched with `IsFlag` (so `/x`, `-x`, `--x`, any case). Add `schedule`, `list`, `cancel`, `runplan` to
`KnownSwitches`. A "switch-like token" below means any token `IsFlag` would treat as a flag (starts with `/` but not `//`, or `-`),
known or not. These checks run as a **pre-check before both parser branches**, in this order; the first that applies wins:

| # | Condition | Error |
|---|---|---|
| 1 | `runplan` appears more than once, or with any other token except its one id | `/runplan cannot be combined with other switches` |
| 2 | `runplan` with no following token, or the next token is switch-like | `/runplan requires a plan id` |
| 3 | `list` or `cancel` present without `schedule` | `/list and /cancel go with /schedule` |
| 4 | `schedule` and `list` both present: anything else present (including `cancel`, a time, a second `schedule`) | `/schedule /list cannot be combined with other switches` |
| 5 | `schedule` and `cancel`: no token after `cancel`, or it is switch-like | `/schedule /cancel requires a plan id` |
| 6 | `schedule` and `cancel`: anything else present | `/schedule /cancel cannot be combined with other switches` |
| 7 | `schedule` appears more than once | `/schedule can be given only once` |
| 8 | `schedule` without `fromlist` | `/schedule requires /fromlist` |
| 9 | `schedule` with no following token, or the next token is switch-like | `/schedule requires a time, e.g. /schedule 22:30 PT` |
| 10 | the token after `schedule` is not `HH:MM` (two digits each, `00:00`–`23:59`) | `/schedule: time must be HH:MM (00:00-23:59), optionally followed by PT, PST, PDT or UTC` |
| 11 | `schedule` with `html`, `output`, `json` or `csv` | `/schedule can only be combined with /fromlist, /purge, /confirm and /yes` |

Then the existing `/fromlist` branch runs with these changes: the token after the time is consumed as the zone only when it is `PT`,
`PST`, `PDT` or `UTC` (case-insensitive; given once); any other non-switch token there falls to the whitelist error, whose text
becomes `/fromlist can only be combined with /purge, /confirm, /html, /output, /json, /csv, /yes and /schedule`. `/fromlist requires
/purge` and `/yes needs /purge /confirm` are unchanged. A bare `dirused /schedule` hits rule 8. `/version` and `/update` stay
intercepted in `Program.cs` before the parser (rule 1 holds at parser level only; M10b2's tests say so). `Options` gains, appended last
and defaulted: `string? ScheduleTime = null, string? ScheduleZone = null, bool ScheduleList = false, string? ScheduleCancelId = null,
string? RunPlan = null`. `/schedule /cancel <id>` with an id not matching `^[0-9]{8}-[0-9]{4}-[0-9a-f]{4}$` → `unknown plan id: <id>`
(exit 1, at run time).

Usage text (`ShortUsageText` and `UsageText`, every line ≤ 80 columns per `ArgParserTests.cs:249-252`) gains:
`  /schedule <time>    With /fromlist /purge: preview a one-time run at HH:MM` /
`                      [PT|PST|PDT|UTC]; add /confirm to schedule it` /
`  /schedule /list     Show scheduled purges` / `  /schedule /cancel <id>  Cancel one`. The `/yes` usage line is unchanged.

### 3. Resolving `<time>` (Dirused.Common, clock seam)

- Zones: `PT` = Pacific, DST-aware; `PST` = fixed −08:00; `PDT` = fixed −07:00; `UTC` = +00:00.
- "Pacific" means a `TimeZoneInfo` whose `Id` is `Pacific Standard Time` (Windows) or `America/Los_Angeles` (IANA). Pacific is looked
  up by the Windows id with the IANA id as fallback.
- Bare time: allowed only when the machine zone is Pacific, then treated as `PT`; else exit 1
  `/schedule: this machine is not on Pacific time; add PT, PST, PDT or UTC to the time`.
- `created` = the clock when the preview is built. The run instant is the next occurrence of `HH:MM` in the zone strictly after
  `created`; if today's has passed or equals `created`, tomorrow's.
- `PT` and a nonexistent time (spring-forward gap) → exit 1 `/schedule: <date> <HH:MM> does not exist in Pacific time (clocks go forward); pick another time`.
  `PT` and a time that happens twice (fall-back) → exit 1 `/schedule: <date> <HH:MM> happens twice in Pacific time; write PST or PDT`.
- Run < `created` + 2 min → exit 1 `/schedule: <HH:MM> is less than 2 minutes away; pick a later time`.
- Run > `created` + 23 h 45 min → exit 1 `/schedule: <HH:MM> is too far away; the plan expires 24 h after it is made, so pick a time
  within 23 h 45 min`. (Fable proposed 23 h 55 min; 23 h 45 min keeps the whole start window, run + 15 min, before expiry.)
- `expires` = `created` + 24 h (elapsed). After a `y` answer both rules are re-checked against the clock before anything is written;
  a failure prints its message, exit 1, nothing written.
- Printed times: Pacific local with abbreviation and UTC, e.g. `Mon 2026-11-23 22:30 PST (06:30 UTC Tue)`.

### 4. Scheduling (`/fromlist <list> /purge /schedule <time> [...]`)

1. **One read.** Read the list's bytes once (`File.ReadAllBytes`). Everything after — parse (`PurgeList.Parse(bytes)`, M10b1), count,
   preview, `list.txt`, `list-sha256` — comes from that buffer. Not a list → `not a dirused delete list: <path>`, exit 1. No file rows
   → exit 1 `/schedule: the list has no files to delete`. Host: the distinct hosts of the rows' paths (case-insensitive UNC host after
   `\\`; a drive-letter path counts as `this machine`). More than one → exit 1
   `/schedule: the list covers more than one host (<h1>, <h2>, ...); save one list per host and schedule each` (O8), nothing written. Bad lines are reported as `/fromlist` reports them and do not stop it.
   No target is touched: no scan, no stat, no open of any listed file, no service query.
2. **Preview** (stdout, every line ≤ 80 columns; the id is generated here and reused if this run registers; a preview-only id is
   discarded):
   ```
   Scheduled purge preview (nothing is scheduled yet)
     Run:      Mon 2026-11-23 22:30 PST (06:30 UTC Tue)
     Expires:  Tue 2026-11-24 21:00 PST (05:00 UTC Wed)
     Host:     us03p02ffm01
     List:     C:\Users\op\m10b.txt
               12 file(s), 176.2G, sha256 3fa9c01b77e2
     Held:     not checked now; files held open at run time are skipped
     Task:     \dirused\S-1-5-21-...-1104\purge-20261123-2230-a1b2
     Plan dir: C:\Users\op\AppData\Local\dirused\plans\20261123-2230-a1b2
     Program:  <plan dir>\dirused.exe (copy of C:\tools\dirused.exe)
   It runs only while you are logged on to this machine (disconnected is fine).
   ```
   `sha256` shows the first 12 hex of the buffer's sha256. Long paths wrap onto a continuation line indented 12 spaces. The "Held"
   line is fixed text: a list carries no held status and scheduling touches no server (O6).
3. **Decide.** No `/confirm` → print `Preview only. Add /confirm to schedule it.`, exit 0, nothing written, nothing registered.
   `/confirm` without `/yes` → `Schedule this? [y/N] ` on stderr; answers as M9b §2.4 (`y`/`yes`, trimmed, case-insensitive); input
   redirected → no read, treated as No. No → `Not scheduled.`, exit 0. `/confirm /yes` → no question.
4. **Re-check** the time rules (§3) against the clock. The list is not read again.
5. **Source program check** (O7): the running exe (`Environment.ProcessPath`) and its folder must not grant write, append, delete or
   change-permissions to anyone other than the current user, Administrators, SYSTEM or TrustedInstaller → else exit 1
   `/schedule: dirused.exe is in a folder other users can change (<folder>); move it to a folder only you can change`.
6. **Create the plan.** Plan root = `Environment.GetFolderPath(LocalApplicationData)` + `\dirused\plans` (never the environment
   variable). Create `dirused` and `plans` if missing; any of them, or the plan dir, already present as a reparse point → exit 3
   `error: could not secure plan folder: <path> is a link`. Create the plan dir `<root>\<id>` with `CreateNew` semantics (an id
   collision draws a new suffix up to 5 times without touching the existing dir). Before writing anything into it, set owner = the
   current user's SID and a protected DACL with one ACE (current user, FullControl, this folder, subfolders and files); the same on
   `dirused` and `plans` when this run created them. Then write, each with `FileMode.CreateNew`: `dirused.exe` (byte copy of the
   running exe), `list.txt` (the buffer), `task.xml` (§4.7) and `plan.txt`:
   ```
   # dirused plan v1
   # id: <id>
   # created: <ISO 8601 with offset>
   # run: <ISO 8601 with offset>
   # expires: <created + 24 h, ISO 8601 with offset>
   # tool: <version>
   # exe-sha256: <hex of dirused.exe as written>
   # list-sha256: <hex of the buffer>
   # files: <n>
   # bytes: <total>
   # host: <host>
   # source: <full path of the original list>
   ```
   Any failure → remove the plan dir, exit 3 `error: could not secure plan folder: <error>` (security or link) or
   `error: could not write plan: <error>` (file writes).
7. **Register** through `ITaskScheduler` (real: `SchtasksTaskScheduler`). `TaskXml.Build(PlanTask)` is a pure function producing a
   Task Scheduler 1.2 document, written as `task.xml` in UTF-16 LE with BOM (P8a) and `encoding="UTF-16"`:
   `RegistrationInfo/SecurityDescriptor` `D:P(A;;FA;;;<SID>)(A;;FA;;;SY)(A;;FA;;;BA)`; one `TimeTrigger` with `StartBoundary` = run
   instant with explicit offset and `EndBoundary` = expires; `Principal` `UserId` = current user SID, `LogonType InteractiveToken`,
   `RunLevel LeastPrivilege`; `Settings` `AllowStartOnDemand false`, `StartWhenAvailable false`, `MultipleInstancesPolicy IgnoreNew`,
   `ExecutionTimeLimit PT2H` (no service is stopped, so a kill only interrupts deletes and shows as `interrupted`),
   `DeleteExpiredTaskAfter P30D`, `DisallowStartIfOnBatteries false`, `StopIfGoingOnBatteries false`, `Hidden false`, `Enabled true`;
   one `Exec` action: `Command` `<plan dir>\dirused.exe`, `Arguments` `/runplan <id>`, `WorkingDirectory` the plan dir. All text is
   XML-escaped (paths with spaces, `&`, quotes, `<`). Then run `schtasks.exe /create /tn \dirused\<SID>\purge-<id> /xml <plan
   dir>\task.xml` (no `/f`: an existing name fails). Non-zero exit → remove the plan dir, exit 3
   `error: could not schedule (schtasks exit <code>)`.
   **Verify:** run `schtasks.exe /query /tn <name> /xml`, decode per P8b, parse as XML and compare every field above to the intended
   `PlanTask` (instants compared as instants). Any difference or non-zero exit → `schtasks.exe /delete /tn <name> /f`, remove the plan
   dir, exit 3 `error: scheduled task does not match the plan (<field>); it was removed`.
8. Print `Scheduled <id> for <full time>. Check it with: dirused /schedule /list`, exit 0. Purge log
   `schedule <id> run <ISO> files <n> bytes <total>`.

### 5. The scheduled run (`/runplan <id>`)

Checked in this order. "stderr" outcomes print to stderr and the purge log only and write nothing in the plan dir. "report" outcomes
take the claim (step 6) if not already taken and write `report.txt` atomically.

| # | Check | Outcome |
|---|---|---|
| 1 | `<id>` matches `^[0-9]{8}-[0-9]{4}-[0-9a-f]{4}$` and `<root>\<id>\plan.txt` exists (root from `GetFolderPath`, never from an argument) | stderr `refused: not a plan id: <id>`, exit 1 |
| 2 | The running exe path equals `<root>\<id>\dirused.exe` | stderr `refused: not started from the plan's program copy`, exit 1 |
| 3 | None of `dirused`, `plans`, `<id>`, `plan.txt`, `list.txt`, `dirused.exe` is a reparse point | stderr `refused: plan folder contains a link`, exit 1 |
| 4 | `plans` and `<id>` and the three files: owner = current user SID; the dirs' DACLs protected; every ACE on all five is the current user | stderr `refused: plan folder permissions changed`, exit 1 |
| 5 | `plan.txt`: header, each field present once, `id` = dir name, `created < run`, `expires = created + 24 h`, `run ≤ created + 23 h 45 min` | report `refused: not a dirused plan`, exit 1 |
| 6 | **Claim**: create `claim` with `FileMode.CreateNew`, content `run <ISO now> pid <pid>`. Exists with `cancel ...` → stderr `cancelled`, exit 0. Exists with `run ...` → stderr `refused: plan already started`, exit 1. | claim taken |

Steps 6 and 7 are ordered so a too-early or too-late start changes nothing: the time checks run **before** the claim:

| # | Check (runs between 5 and 6) | Outcome |
|---|---|---|
| 5a | now ≥ `expires` | take claim, report `expired`, exit 0 |
| 5b | now < run − 1 min or now > run + 15 min | stderr `refused: not the scheduled time (scheduled <full time>)`, exit 1; no claim, no report (an early start leaves the real run usable; a late one shows as `missed`) |

After the claim:

| # | Check | Outcome |
|---|---|---|
| 7 | Read `dirused.exe`'s bytes; sha256 ≠ `exe-sha256` | report `refused: program copy changed since it was scheduled`, exit 1 |
| 8 | Read `list.txt`'s bytes **once**; sha256 ≠ `list-sha256` | report `refused: list changed since it was scheduled`, exit 1 |
| 9 | Parse those same bytes (`PurgeList.Parse`) and run `Purge.Apply` as `RunFromList` does with `confirm = true`, `yes = true`, `input = TextReader.Null`, `inputRedirected = true`, `control = null` and the new `scheduled = true` (M10b1) | report `done`; exit as `/fromlist` (0, 3) |

`scheduled = true`: held rows are skipped with `skipped: held by <service> — scheduled runs do not stop services` before any window
check, prompt or `IServiceControl` call; ordinary rows keep the exact identity, size and time match. Nothing is read from the original
list. The run never calls `IServiceControl`.

### 6. Run report

Written as `report.tmp` then renamed to `report.txt` without overwrite (a present `report.txt` is never replaced):
```
# dirused run report v1
# id: <id>
# started: <ISO>
# finished: <ISO>
# outcome: done | expired | refused: <reason>
# exit: <code>
# result: deleted <n> file(s), <size> freed; <s> skipped; <f> failed
<the text a /fromlist ... /purge /confirm run prints: rows and statuses>
<every line this run sent to the purge log, and its stderr lines>
```
`result:` only for `done`. The rename failing, or the purge log failing to open, → stderr and (if possible) the purge log; the exit code
is unchanged; `/schedule /list` then shows `interrupted` (below). No pop-up.

### 7. `/schedule /list` and `/schedule /cancel`

`/schedule /list` reads each dir under the plan root (no dir → `No scheduled purges.`, exit 0), newest run first. State comes from
dirused's own files; the scheduler is asked only whether the task exists (`ITaskScheduler.Exists`, the exit code of
`schtasks /query /tn <name>`). Row: `<id>  <run, Pacific>  <host>  <state>  <n> file(s) <size>  <source file name>` (host from
`# host:`). States, first match
wins:

1. path checks 3–4 of §5 fail for this dir → `permissions changed — not run` (nothing else read from it)
2. `plan.txt` unreadable → `unreadable plan`
3. `claim` says `cancel` → `cancelled`
4. `claim` says `run` and `report.txt` present → its `outcome`; for `done` also `result` and `exit`
5. `claim` says `run`, no report, and the claim's pid is a live process whose image path is `<plan dir>\dirused.exe` → `running`
6. `claim` says `run`, no report → `interrupted (started <time>, no report) — check the list and the report folder`
7. no claim, now > run + 15 min → `missed (did not run)`
8. `Exists` false (non-zero exit) → `task missing`
9. otherwise `scheduled`

`/schedule /cancel <id>`: id regex fails or plan dir missing → exit 1 `unknown plan id: <id>`. Path checks 3–4 fail → exit 1
`refused: plan folder permissions changed`. Create `claim` with `CreateNew`, content `cancel <ISO>`; exists with `run` → exit 1
`<id> already started; it cannot be cancelled`; exists with `cancel` → `<id> is already cancelled`, exit 0. Then delete the task (already
gone is fine). Print `Cancelled <id>.`, purge log `schedule-cancel <id>`, exit 0. Delete fails → exit 3
`error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run`. Old plan dirs are never removed in
M10b.

### 8. Seams (all logic in `Dirused.Common`)

- `ITaskScheduler`: `Register(PlanTask, xmlPath)` → (ok, error); `Exists(name)` → bool; `Delete(name)` → (ok, error).
  `SchtasksTaskScheduler(IProcessRunner runner, string rootFolder = "\\dirused")` builds argv only (`/create /tn <name> /xml <path>`,
  `/query /tn <name> /xml`, `/query /tn <name>`, `/delete /tn <name> /f`) and does the verify compare; `IProcessRunner.Run(exe, argv)`
  → (exit code, stdout bytes); the real runner is `[SupportedOSPlatform("windows")]`. `TaskXml.Build` and `TaskXml.Parse` are pure.
  No COM, no NuGet package.
- Process seam `Func<int, string?> processImagePath` (for `running`).
- `IPlanFolderSecurity`: `Secure(path)`, `Check(path)` → (ok, reason), `IsReparsePoint(path)`, `SourceExeIsProtected(exe)` →
  (ok, folder). Real one on `DirectorySecurity`/`FileSecurity`, `[SupportedOSPlatform("windows")]`.
- Clock `Func<DateTimeOffset> now`, machine zone `TimeZoneInfo`, plan root `string`, id suffix `Func<int>`, current exe path
  `Func<string>`, current user SID `string`.
- `ScheduleCommands.Schedule/List/Cancel/RunPlan(...)` in `Dirused.Common` take the seams and writers and return the exit code. The
  Portable suite calls them directly. `Program.cs` only maps `Options` to them; a public `Program.RunWithSchedule(...)` passes test
  seams through. On a non-Windows OS, `/schedule` (with `/confirm`), `/schedule /list`, `/schedule /cancel` and `/runplan` exit 1
  `/schedule needs Windows`; the preview works everywhere. `/runplan` and `/schedule` never start the update check.
- `Purge.Apply` gains optional, appended `bool scheduled = false`; `PurgeList` gains `Parse(byte[] bytes, out ParsedPurgeList?)`, and
  `Read(path)` becomes `ReadAllBytes` + `Parse`.

### 9. Docs

`docs/purge.md` "Scheduled purge" section; `README.md` usage and one example; `CHANGELOG.md` `[Unreleased]` bullets (M10b4).

## Files (by child)

| Child | Files |
|---|---|
| M10b1 | `src/Dirused.Common/PurgeList.cs`, `src/Dirused.Common/Purge.cs`, `tests/Dirused.Tests.Portable/ScheduledEngineTests.cs` (new) |
| M10b2 | `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`, `src/Dirused.Common/Schedule.cs` (new: time, preview, plan store, claim, list, cancel, seams), `src/Dirused.Common/TaskXml.cs` (new: pure `Build`/`Parse`), `tests/Dirused.Tests.Portable/ScheduleTests.cs` (new), `tests/Dirused.Tests.Portable/TaskXmlTests.cs` (new), `tests/Dirused.Tests.Portable/ArgParserTests.cs`, `tests/Dirused.Tests.Portable/PurgeListTests.cs` |
| M10b3 | `src/Dirused.Common/Schedule.cs` (`RunPlan`), `src/Dirused.Common/TaskScheduling.cs` (new: `SchtasksTaskScheduler`, `IProcessRunner` and its real runner), `src/Dirused.Common/PlanFolderSecurity.cs` (new, real), `src/Dirused.Cli/Program.cs`, `tests/Dirused.Tests.Portable/RunPlanTests.cs` (new), `tests/Dirused.Tests.Portable/SchtasksTests.cs` (new, fake runner), `tests/Dirused.Tests/TaskSchedulerWindowsTests.cs` (new), `tests/Dirused.Tests/ProgramScheduleTests.cs` (new) |
| M10b4 | `docs/purge.md`, `README.md`, `CHANGELOG.md` |

## Contract readers

`git grep` at a2d0508; each child re-runs it for its strings.
- `/fromlist` whitelist text: writer `ArgParser.cs:121`; reader `PurgeListTests.cs:102`; docs `docs/purge.md`, `README.md`. Changes (b2).
- `/yes needs /purge /confirm`: writers `ArgParser.cs:137`, `:263`; readers `ArgParserTests.cs:310,311,313`; usage `ArgParser.cs:73`.
  **Unchanged** in rev 2.
- Usage width: `ArgParserTests.cs:249-252` enforces 80 columns; new usage lines must fit (b2).
- `KnownSwitches` `ArgParser.cs:16`: adding `schedule`, `list`, `cancel`, `runplan` makes `MissingPath` (`:15`) treat them as switches
  after `/output`, `/file`, `/savelist`, `/fromlist`.
- `Options` constructed at `ArgParser.cs:139`, `:291` and in tests: new fields last, defaulted.
- `Purge.Apply`: call sites `Program.cs:119`, `:204` and 85 test call sites: `scheduled` optional and last (b1).
- `PurgeList.Read(path)`: callers `Program.cs:70` and tests; behaviour preserved (b1).
- New status `skipped: held by <service> — scheduled runs do not stop services`: writer `Purge.cs` (b1); readers `docs/purge.md`.
- Purge log `C:\temp\dirused-purge.log`: new `schedule`, `schedule-cancel`, `runplan` lines; human-read only.
- On-disk contract `%LOCALAPPDATA%\dirused\plans\<id>\{plan.txt,list.txt,dirused.exe,task.xml,claim,report.tmp,report.txt}`: writers
  `Schedule.cs`; readers `RunPlan`, `/schedule /list`, `/schedule /cancel`. Task path `\dirused\<SID>\purge-<id>`: writer and reader
  `SchtasksTaskScheduler`. Task action argument `/runplan <id>`: writer `TaskXml.Build`; reader `ArgParser` (rule 2).

## What NOT to Do (every child)

- Do not scan, add patterns, or delete anything not in `list.txt`. Do not read the original list at run time or twice at schedule time.
- Do not call `IServiceControl` from a scheduled run. Do not relax any identity, size or time check.
- Do not add a repeat or logon trigger, `StartWhenAvailable = true`, `AllowStartOnDemand = true`, a stored password, S4U, or run level highest.
- Do not run `schtasks.exe` by bare name, through a shell, or with a command string; do not parse its text output; do not pass `/f` to
  `/create`; do not use COM; do not add a NuGet package.
- Do not show a message box or toast. Do not write into a plan dir that failed the link or permission checks.
- Do not modify files outside the child's Files row. Do not push, open a PR, or skip hooks. Leave changes uncommitted. If the sandbox
  cannot restore NuGet or run tests, finish code and tests anyway and say so.

## Acceptance map

| Child | must | must_not | evidence |
|---|---|---|---|
| M10b1 | B1-M1..M3 | B1-N1..N3 | E-B1 (offline, Portable) |
| M10b2 | B2-M1..M10, B2-M2X | B2-N1..N5 | E-B2 (offline, Portable) |
| M10b3 | B3-M1..M8 | B3-N1..N5 | E-B3 (offline, Portable), E-B3W (offline, windows-latest), E-B3L1 and E-B3L2 (live) |
| M10b4 | B4-M1 | — | E-B4 (offline) |

**Baseline-red exceptions requested** (Astra A7): some must_not items assert that a new command does *not* have an effect; on a2d0508
the command does not exist, so the only red there is a parse error, which does not exercise the safeguard. These are marked
`baseline: mutant-only` in the children: each has a positive control (the recorder sees the effect in a run that should have it) and a
named mutant that turns it red. Listed: B2-N1, B2-N3, B2-N5, B3-N2, B3-N3, B3-N5. Every other must_not has a behavioural baseline red.

## Open decisions for the operator

| # | Question | Spec default |
|---|---|---|
| O2 | If the jump box logs off disconnected sessions before the run (P4), is `missed` acceptable? | Yes (D3 forbids a stored password). |
| O3 | Refuse a list older than N hours at schedule time? | No age check; the exact identity, size and time match at run time skips anything that changed. |
| O6 | The preview shows no held rows because scheduling touches no server. Do a read-only held check (stat + service query on the server) at preview time to list rows that will be skipped? | No: scheduling stays server-free; the report shows the skipped rows. |
| O8 | A list whose paths span more than one host: refuse, or schedule it as one plan touching several nodes? (Coordinator suggested O6; O6 was already the held-check question.) | Refuse with the §4.1 message, so each plan is one node. |
| O7 | Refuse to schedule when `dirused.exe` sits in a folder other users can change (P11)? | Refuse (§4.5). |

Resolved in rev 2: O1 (held files are always skipped, D9), O4 (`/confirm` is the schedule switch, D12), O5 (the task runs the program
copy, so a self-update does not affect a scheduled run).

## Review adjudication (rev 1, 2026-11-23)

Fable (F) and Astra (A) blind reviews of rev 1. Both: NEEDS FIXES. Claude's disposition:

| Finding | Disposition |
|---|---|
| F-B1 exe not protected | Fixed: program copy in the protected plan dir + `exe-sha256`; source-folder refusal (O7). §4.5–4.7, §5.2, §5.7. b2, b3. |
| F-B2 / A-B1 list read twice | Fixed: one read at schedule and at run time; `PurgeList.Parse(bytes)`. §4.1, §5.8. b1, b2, b3. |
| F-B3 / A-B4 interrupted run invisible, run/cancel race | Fixed: atomic `claim` taken by run or cancel, atomic report, `interrupted` state. §5.6, §6, §7. b2, b3. |
| F-B4 / A-B7 E1 not runnable in Portable | Fixed: logic in `Dirused.Common` (`ScheduleCommands`); Windows wiring in b3's Windows tests. §8. |
| F-B4 Pacific id on Linux | Fixed: either id. §3. |
| A-B2 plan path not trusted | Fixed: exact path shape, reparse refusal on every component, owner + DACL on dirs and files, `GetFolderPath`, unsafe → stderr only, `CreateNew` collision retry. §4.6, §5.1–5.4, §7. |
| A-B3 / F-S3 early or late start | Fixed: `AllowStartOnDemand = false`; refuse outside [run − 1 min, run + 15 min] before the claim. §5.5b. |
| A-B3 digest beside the list | Accepted as a corruption check; trust boundary stated. |
| A-B5 Tomcat stopped for an ineligible row; window on the local clock | Moot in M10b: no stop (D9). Carried to M10d. |
| A-B6 task kill strands Tomcat | Moot in M10b (D9); `ExecutionTimeLimit` cut to PT2H; a killed run shows `interrupted`. M10d must solve recovery. |
| F-S1 / A-S3 growth relaxation bypasses the age rule | Moved to M10d (D11); ordinary rows keep exact match. |
| F-S2 held identity check already exists | Moot (no held deletes in M10b). |
| F-S4 / A-S2 expiry edge, DST | Fixed: `created` = preview time; run ≤ created + 23 h 45 min; re-check after `y`; fall-back/UTC tests in b2. |
| F-S5 / A-S5 missed vs expired order | Fixed: `missed` from "no claim and run + 15 min passed"; `expired` only as a report outcome. §7. |
| F-S6 plan path checks | Fixed (as A-B2). Owner set to the user SID explicitly. |
| F-S7 sha256 is corruption-only | Stated in the trust boundary. |
| F-S8 shared task folder | Fixed: `\dirused\<SID>\` + XML security descriptor; P10. |
| F-S9 / A-S4 parser precedence | Fixed: ordered pre-check table §2. |
| F-S10 contract readers | Fixed: list above. `/yes` text no longer changes. |
| F-S11 / A-S6 missing mutants, effect evidence | Added in each child's Acceptance. |
| F-S12 / A-S1 proofs | P1–P11 rewritten with production settings, fresh markers, positive controls; P5 (M9b y path) dropped as moot; new P5 (night reboots), P10 (task security), P11 (exe location). |
| F-S13 E2 is an unattended Tomcat stop | Moot (no stop); live checks split attended (E-B3L1) and disconnected (E-B3L2). |
| F-S14 / A-N2 scope | Fixed: four sequential children. |
| A-S5 report misses purge-log events; bytes freed undercounts growth | Fixed: report includes this run's purge-log lines. Growth undercount moot (exact match). |
| F nits (exit codes, folder param, old dirs, update check, id regex, count/size in list) | Exit codes per §5 tables; `SchtasksTaskScheduler(runner, rootFolder)`; old dirs out of scope (noted); no update check (§8); id regex kept lowercase hex; list shows count and size. Console window for an interactive-token task: accepted, noted in docs (b4). |
| A-N1 refusal exit codes | Consolidated in the §5 tables. |
