# dirused M9b: /purge /confirm stops Tomcat for its held redirect logs, deletes them, starts Tomcat and checks it came up

**Status:** OPEN — SPEC rev 2, 2026-11-20; reviews adjudicated (table at end); intents approved; dispatched to Flash
**Tracked:** dirused (OOB repo), not a k3d-manager release; no `docs/ideas.md` row.
**Parent:** `docs/plans/dirused-m9-purge-stop-service-for-locked-files.md` (operator decisions, proofs 1–5, rev 1 spec, adjudication
table rows marked "M9b", and the M9b outline at the end). M9a (`docs/plans/dirused-m9a-held-file-detection.md`) is LIVE-VERIFIED.
**Repo / branch:** wilddog64/dirused / task branch from main c91e9b7 (v0.0.25)
**Version:** v0.0.26
**Risk:** medium: it stops and starts a production service (Tomcat85 on us03p02ffm01). Off-hours only under `/yes`; every path
after a stop the service may have taken must start it again. Review: Fable + Astra blind, Claude adjudicates.
**Implementer:** Flash (operator 2026-11-20: "write spec M9b and dispatch to Flash"). **Verifier:** Claude (Sonnet verifier from
Acceptance). Live check: operator, after 19:00 Pacific, on us03p02ffm01.
**Filed:** 2026-11-20
**Intent approved:** operator, 2026-11-20
**Approval:** operator 2026-11-20 ("go ahead to write spec M9b and dispatch to Flash")

## Before You Start

- Read this spec and the parent plan's adjudication table rows marked M9b.
- Work in your task worktree (branch from dirused main c91e9b7). Read `src/Dirused.Common/Purge.cs`, `ServiceQuery.cs`,
  `ArgParser.cs`, `Options.cs`, `src/Dirused.Cli/Program.cs`, `tests/Dirused.Tests.Portable/PurgeHeldTests.cs` in full before editing.
- There is no memory-bank in dirused; do not edit k3d-manager files.

## Why

Operator goal (2026-11-20): find big files easily and cut unnecessary disk alerts; the app is old and its source is out of
reach. On us03p02ffm01 procrun keeps `tomcat85-stderr.2026-11-04.log` (138G, growing about 8.6G/day from one repeating line) and
`tomcat85-stdout.2026-11-04.log` (8.5G) open. M9a reports them `would delete after stopping Tomcat85` in a dry run and
`failed: in use by Tomcat85 (stop not available yet)` under `/confirm` (`Purge.cs:381`). Only a stop frees them. The team already
restarts Tomcat after 19:00.

## Facts this spec relies on (all read-only, recorded in the parent plan)

- Proof 3: `BINARY_PATH_NAME` = `D:\Tomcat\Tomcat\bin\Tomcat85.exe //RS//Tomcat85`, service key `tomcat85`, no dependents.
- Proof 4: the operator's account can query the remote SCM; `SERVICE_STOP`/`SERVICE_START` is granted to Administrators
  (`sdshow`); a refused stop is audited on the server.
- Proof 5: starts take 9–14 s (catalina log timestamps), well inside the 120 s start timeout.
- M9a E2 (2026-11-20): held rows are identified, the scan file ID equals the handle file ID, and `ListProcrun` works with the
  jump box's rights. The held stderr grew 147999209735 → 148175219890 bytes in 26 min with the same file ID.
- **Operator decision 2026-11-20 (replaces parent amendment 1):** "as I said this is an old app so we just want to make sure we can
  stop and start tomcat that all we care about". Startup is judged by service state only (Running, still Running after a 60 s
  settle). No catalina log check, no SEVERE rule; proof 6 is no longer needed.

## Behaviour

### 1. Scope: what may cause a stop

Unchanged from M9a §4: a held file causes a stop only when `ServiceQueryHelpers.ClassifyHeldFile` returns `tomcat`
(`<Name>-stdout|stderr.*.log` in `<root>\logs` of exactly one running procrun service whose root contains it; it already refuses an
ID mismatch, `ServiceQuery.cs:252-266`). A held heap dump or any other held file never causes a stop (operator D2) and keeps its
M9a status.

### 2. Confirm flow (`/purge /confirm`, scan path and `/fromlist`), only when an `IServiceControl` is passed

1. **Hold back.** Both M9a held sites hold the row back with no status yet instead of writing
   `failed: in use by <svc> (stop not available yet)`: the recent-file path (`LastWriteUtc >= cutoff`, `ProbeHeld` →
   `RecordHeldClassification`, `Purge.cs:146-164`, status at `:110`) and the `Open` error-32 path (`Purge.cs:369-382`). The 138G
   stderr is written daily, so it normally takes the recent-file path.
2. After the pass, held-back rows are grouped by (host, service key), handled one at a time in first-seen order.
3. **Before each group** (in this order; the first that applies decides): `stopReason` set (cancel or log write failed) or
   cancellation requested → rows `not attempted: cancelled` (or the existing stopReason status); an earlier group's start was not
   verified → rows `not attempted: earlier service start failed`.
4. **Ask.** Write the whole group to stderr first: one line per file (`Format.Short` size, path), then
   `Stop service <key> on <host> to delete <n> held file(s), <Format.Size(total)>? Tomcat is down until the deletes finish. [y/N] `.
   Read one line from the input seam. Only `y` or `yes` (trimmed, case-insensitive) is yes; anything else, empty or end of input is
   No. Input redirected and no `/yes` → No without reading. No → rows `skipped: in use, not confirmed`.
5. **Window.** With `/yes` there is no prompt; instead, evaluated right before this group's Stop (not at run start): local time
   from the clock seam in 19:00–06:00 (19:00 inclusive, 06:00 exclusive) → yes; otherwise rows
   `skipped: in use, outside 19:00-06:00 for /yes`. The interactive prompt is allowed at any time.
6. **Revalidate** (after the answer, right before Stop). For each row: re-run `ClassifyHeldFile` (identity, location, name) and
   `ProbeHeld`. Still `tomcat` and held → stays. `ProbeHeld` returns false → leaves the group and goes through the normal M8 checks
   from the start (including the age gate, so a recent file that was released is `skipped: modified within <n> day(s)`).
   `ProbeHeld` null or classification no longer `tomcat` → `failed: in use (<reason>)`. No row left → no stop.
7. **Open the service.** One handle with `SERVICE_STOP | SERVICE_START | SERVICE_QUERY_STATUS | SERVICE_ENUMERATE_DEPENDENTS`.
   Open fails → rows `failed: could not stop <key>: <error>`, nothing stopped. `EnumDependentServicesW(SERVICE_ACTIVE)` (handle
   `ERROR_MORE_DATA`) fails → rows `failed: could not stop <key>: <error>`; returns any → rows
   `failed: in use (service has running dependents: <names>)`. State not RUNNING → rows `failed: in use (<key> not running)`.
   None of these stop or start anything.
8. **Stop.** Write purge-log `service-stop` first; if that write throws → `stopReason = "log write failed"`, rows
   `failed: log write failed`, no stop. Then `ControlService(SERVICE_CONTROL_STOP)`.
   - Fails with 1051 or 1062 → this run did not stop it: rows `failed: could not stop <key>: <error>`, no Start.
   - Fails with any other error → query state: RUNNING → as above (no Start); anything else or the query fails → **owned** (Start
     will run).
   - Succeeds → **owned**. Poll state every 2 s until STOPPED, 120 s. Timeout → rows `failed: could not stop <key>: timed out`,
     go to Start.
9. **Delete** (only when STOPPED). For each row: `fs.Open`; error 32 → retry every 2 s for up to 30 s (procrun's handles can close
   after STOPPED is reported), then `failed: in use after stopping <key>`; not found → `skipped: no longer exists`; other error →
   `failed: <error>`; volume serial or file ID missing or different → `skipped: changed since scan (id)` (list rows
   `skipped: file changed since list (id)`); length smaller than recorded → `skipped: changed since scan (smaller)` (list rows
   `skipped: file changed since list (smaller)`); handle final path no longer under `<root>\logs` or no longer a redirect name →
   `skipped: changed since scan (name)`; then the remaining M8 handle checks with their M8 statuses; otherwise delete exactly as M8,
   `deleted`, freed = handle length. Age and `/minsize` are not rechecked (parent decision 3). Cancellation after the stop →
   remaining rows `not attempted: cancelled`. Any exception for a row → that row `failed: <message>`; the loop continues.
10. **Start** (in a `finally`, whenever owned; `CancellationToken.None`; nothing before `StartServiceW` may throw past it):
    - Wait while STOP_PENDING (poll 2 s, up to 300 s total). Then `StartServiceW`.
    - 1056 (already running) is **not** proof of RUNNING: query; STOP_PENDING → keep waiting and call Start again; RUNNING or
      START_PENDING → go on polling.
    - Any other Start error → one more Start attempt after 5 s.
    - Poll every 2 s until RUNNING, 120 s. Then write `service-start` (a write error is caught, reported, and does not skip
      the rest).
    - **Verified** = RUNNING, and still RUNNING after a 60 s settle. Not RUNNING at either point → one more attempt of this whole
      step (no Stop). Verified → purge-log `service-started`.
    - Still not verified → purge-log `service-start-failed: <reason>` (write errors caught), stderr
      `error: <key> on <host> did not start (<reason>, state <state>). Start it with: sc \\<host> start <key>`,
      `PurgeRun.ServiceStartFailed = true`, later groups `not attempted: earlier service start failed`.
11. dirused only starts services this run owns.

### 3. Dry run

Unchanged from M9a: `would delete after stopping <key>`; no prompt; Stop and Start never called; no open requests `DELETE`.

### 4. Switch `/yes`

Valid only with `/purge /confirm` (scan path) or `/fromlist ... /purge /confirm`; otherwise usage error
`/yes needs /purge /confirm`. Add `"yes"` to `KnownSwitches` (`ArgParser.cs:16`), accept it in the `/fromlist` whitelist and its
message (`ArgParser.cs:116-125`), add it to usage and help. `Options` gains `bool Yes = false`, appended last.

### 5. Exit codes

`ServiceStartFailed` → exit 3, taking precedence over exit 4, on both the scan path (`Program.cs:175-176`) and `/fromlist`
(`Program.cs:220`). Otherwise unchanged. Update every "4 takes precedence over 3" text to name this exception.

### 6. Next-run warning

At the start of every `/purge` run (dry run or confirm), for each host mapped from the targets, from M9a `ListProcrun`: a procrun
service that is not Running and whose install root is equal to, under, or above a target (component-wise, case-insensitive, after
mapping to the host-local path; e.g. target `\\us03p02ffm01\d$\tomcat` → `D:\tomcat`, root `D:\Tomcat\Tomcat`) → stderr
`warning: <key> on <host> is not running; start it with: sc \\<host> start <key>`. For a local target (host `.`):
`warning: <key> is not running; start it with: sc start <key>` (same for the §2.10 error). The run continues.

### 7. Purge log

Existing `LogLine`, path `<key>@<host>`, bytes 0, status `service-stop`, `service-start`, `service-started`,
`service-start-failed: <reason>`. Human-read only.

### 8. Seams and wiring

- `IServiceControl` (new, `src/Dirused.Common/ServiceControl.cs`): `Open(host, key)` → handle or error; `RunningDependents`;
  `Stop()` → (ok, win32 error); `Start()` → (ok, win32 error); `QueryState()` → (state or error). States as an enum
  (Stopped, StartPending, StopPending, Running, Other). `RealServiceControl` via `advapi32` P/Invoke (`OpenSCManagerW(\\host,
  SC_MANAGER_CONNECT)`, `OpenServiceW`, `EnumDependentServicesW`, `ControlService`, `StartServiceW`, `QueryServiceStatusEx`).
  `IServiceQuery` stays query-only.
- `Purge.Apply` gains optional, appended: `IServiceControl? control`, `Func<DateTime>? localNow`, `Action<TimeSpan>? sleep`
  (real `Thread.Sleep`; tests record and never wait), `TextReader? input`, `bool inputRedirected`, `bool yes`. Null `control` keeps
  M9a statuses exactly.
- `Program.RunCore` gains optional `IServiceControl` defaulting to `RealServiceControl` on Windows (as `IServiceQuery` does at
  `Program.cs:23`), passes `Console.In` / `Console.IsInputRedirected`, the local clock, and `options.Yes`.
- No new NuGet package.

### 9. Docs

- `docs/purge.md`: the flow in the decision path and Mermaid chart, every new status, the 19:00–06:00 rule, the start check, exit
  3 precedence (`:198`), purge-log lines, a "Tomcat left stopped" recovery section (`sc \\host start tomcat85`, the next-run
  warning); replace the "stop not available yet" text.
- `README.md`: `/yes` in usage; `:116` locked-file description; `:166` exit-code precedence. `tools/PACKAGE-README.txt:35`
  precedence. `CHANGELOG.md`: bullets under `## [Unreleased]` only (leave the old line at `:10`).

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/Purge.cs` | hold back, groups, revalidate, stop/delete/start, `ServiceStartFailed`, next-run warning |
| `src/Dirused.Common/ServiceControl.cs` (new) | `IServiceControl`, `RealServiceControl`, state enum |
| `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs` | `/yes`, validation, whitelist message, usage/help, exit-code text (`:97`) |
| `src/Dirused.Cli/Program.cs` | wiring, input, exit 3 precedence on both paths |
| `tests/Dirused.Tests.Portable/PurgeServiceTests.cs` (new) | flow tests with fakes |
| `tests/Dirused.Tests.Portable/PurgeHeldTests.cs` | only tests that now pass a fake control |
| `tests/Dirused.Tests.Portable/ArgParserTests.cs`, `PurgeListTests.cs` (`:102` whitelist message) | `/yes` |
| `tests/Dirused.Tests/ServiceControlWindowsTests.cs` (new), `tests/Dirused.Tests/ProgramPurgeTests.cs` | Windows-only, E1W |
| `docs/purge.md`, `README.md`, `CHANGELOG.md`, `tools/PACKAGE-README.txt` | §9 |

## Contract readers

`git grep` across `src`, `tests` (both projects), `docs`, `README.md`, `tools` at c91e9b7:
- `failed: in use by <svc> (stop not available yet)`: writers `Purge.cs:110`, `Purge.cs:382`; readers `PurgeHeldTests.cs:249,439`,
  `docs/purge.md` (6), `CHANGELOG.md:10` (history, unchanged). Kept when no control is passed.
- `Purge.Apply` call sites: `Program.cs:114`, `:198`; tests `PurgeHeldTests.cs` (16), `PurgeTests.cs` (15), `PurgeListTests.cs` (10),
  `RendererTests.cs` (1). New parameters optional, appended.
- `Options` built at `ArgParser.cs:132`, `:243`, `:282`; new field last, defaulted.
- `KnownSwitches` `ArgParser.cs:16`; `/fromlist` whitelist and message `ArgParser.cs:116`, asserted at `PurgeListTests.cs:102`.
- Exit precedence text: `ArgParser.cs:97`, `README.md:166`, `docs/purge.md:198`, `tools/PACKAGE-README.txt:35`;
  `tools/live-check.ps1:108` (exit 4 for /summary, no purge) unchanged.
- `PurgeRun` `Purge.cs:42`; readers `Program.cs` (~:150–176, ~:198–221) and renderers; new init property defaulted.
- Windows tests asserting purge output (`ProgramPurgeTests.cs`, `HeldProbeWindowsTests.cs`): unchanged where no control is injected.
- Purge log `C:\temp\dirused-purge.log`: human-read only.

## What NOT to Do

- Do not stop a service for a non-tomcat held row, without a yes, or under `/yes` outside 19:00–06:00.
- Do not skip Start once owned; do not Start a service this run does not own; do not treat 1056 as RUNNING without a query.
- Do not stop a service a second time. Do not cascade-stop dependents. Do not call Stop/Start in a dry run.
- Do not relax any check for rows that were not held; do not recheck age or `/minsize` for held rows after the stop.
- Do not read catalina logs (operator decision 2026-11-20).
- Do not modify files outside the Files table. Do not add a NuGet package. Do not push, open a PR, or skip hooks. Leave changes
  uncommitted. Your sandbox may not restore NuGet or run tests; finish code and tests anyway and say so.

## Acceptance

```yaml
must:
  - id: M1
    text: "a held tomcat85-stderr row on the recent-file path (LastWriteUtc inside the cutoff) and one on the Open-32 path, same ID, larger than recorded, with a yes: Stop, then both deleted, then Start; verified; exit 0; purge log service-stop, service-start, service-started in order"
  - id: M2
    text: "no yes: redirected input without /yes, or typed input other than y/yes, never calls Stop; rows 'skipped: in use, not confirmed'; typed 'y' and 'YES' proceed; the file list is written before the question"
  - id: M3
    text: "/yes with the clock at 19:00 and 05:59 proceeds without reading input; at 06:00 and 18:59 no stop, rows 'skipped: in use, outside 19:00-06:00 for /yes'; the clock is read right before each group's Stop"
  - id: M4
    text: "Start runs once owned: after a delete throws, after cancellation following the stop (remaining rows 'not attempted: cancelled'), after a Stop timeout, after ControlService fails with a non-1051/1062 error and the state is not RUNNING, and when the service-start log write throws"
  - id: M5
    text: "after a Stop timeout the fake stays STOP_PENDING, Start returns 1056, then the fake goes STOPPED: dirused waits, calls Start again, reaches RUNNING, verified"
  - id: M6
    text: "not RUNNING after start or after the 60 s settle gives exactly one more start attempt and no Stop; a final failure writes service-start-failed, prints 'sc \\\\<host> start <key>', and exits 3 even when a target is at crit, on the scan path and on /fromlist with all rows deleted"
  - id: M7
    text: "Open returning 32 twice then succeeding after STOPPED deletes the row; 32 for longer than 30 s gives 'failed: in use after stopping <key>'"
  - id: M8
    text: "a recent held row that is no longer held at revalidation is not deleted ('skipped: modified within <n> day(s)') and, if it was the only row, nothing is stopped"
  - id: M9
    text: "/fromlist ... /purge /confirm /yes applies the same flow with list-row statuses"
  - id: M10
    text: "target \\\\us03p02ffm01\\d$\\tomcat with procrun root D:\\Tomcat\\Tomcat not Running prints 'warning: tomcat85 on us03p02ffm01 is not running; start it with: sc \\\\us03p02ffm01 start tomcat85' and continues; a Running service prints nothing"
  - id: M11
    text: "/yes without /purge /confirm is the usage error '/yes needs /purge /confirm'; /yes is in usage, help and the /fromlist whitelist message"
  - id: M12
    text: "docs/purge.md, README.md and tools/PACKAGE-README.txt describe the flow, statuses, window, exit 3 precedence and recovery; CHANGELOG has Unreleased bullets and no new version header"
must_not:
  - id: N1
    text: "a held non-tomcat row causes Stop (paired: a tomcat row in the same run that does)"
  - id: N2
    text: "after the stop, a row whose file ID differs, that is smaller, or whose final path left <root>\\logs is deleted (paired: same-ID larger peer deleted)"
  - id: N3
    text: "a service with running dependents, or whose handle or dependent enumeration fails, or whose Stop fails with 1051/1062, or that stays RUNNING after a failed Stop, is started or stopped (paired: a dependent-free service that is stopped and started)"
  - id: N4
    text: "a row that was not held is deleted when its size or time changed since scan (paired: held peer deleted)"
  - id: N5
    text: "after a group's start is not verified, a later group's service is stopped (paired: two groups that both succeed)"
  - id: N6
    text: "with no IServiceControl passed, any held row status differs from M9a's (existing PurgeHeldTests expectations unchanged)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, M7, M8, M9, M10, M11, N1, N2, N3, N4, N5, N6]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable with fake IServiceControl (state machine), IPurgeFileSystem, clock, sleep and input. New tests red on c91e9b7. Mutants each red: hold back only the Open-32 path; remove the finally Start; Start only on Stop success; treat 1056 as RUNNING; no second Start after 1056/STOP_PENDING; Start a 1051/1062 service; drop the tomcat check; drop the ID-after-stop check; drop the smaller check; no 32 retry; drop the dependents check; omit SERVICE_ENUMERATE_DEPENDENTS from the requested mask; window end inclusive; window read once at run start; accept 'ye'; containment test reversed (root contains target); released recent row sent past the age gate"
    intent: "Tomcat is stopped only for its own held redirect logs, only after you say yes (or /yes at night), and once dirused has stopped it, it always starts it again and waits until Windows reports it running for a full minute."
  - id: E1W
    proves: [M6, N3]
    kind: offline
    command: "windows-latest CI: ServiceControlWindowsTests creates a throwaway service with sc create (binPath cmd.exe), checks RealServiceControl opens it with the full mask, enumerates 0 running dependents, Start fails (1053) and a state query reads Stopped, Stop on it fails 1062 and is not owned; sc delete in finally. ProgramPurgeTests with an injected fake control: start failure gives exit 3 with a crit target on the scan path and on /fromlist"
    intent: "The real Windows service calls are exercised on a throwaway service in CI, and the exit code you see after a failed start is checked through the real command line."
  - id: E3
    proves: [M12]
    kind: offline
    command: "git diff shows docs/purge.md, README.md, tools/PACKAGE-README.txt and CHANGELOG [Unreleased] updated; git grep 'stop not available yet' only in CHANGELOG history and the no-control test expectations"
    intent: "The guide tells you what dirused does to Tomcat, when, and how to start it by hand if a run leaves it stopped."
  - id: E2
    proves: [M1]
    kind: live
    command: "operator, after 19:00 Pacific, jump box: dirused \\\\us03p02ffm01\\d$\\tomcat /largest *.log /purge shows 'would delete after stopping Tomcat85' for the held stderr/stdout; then dirused \\\\us03p02ffm01\\d$\\tomcat /largest *.log /purge /confirm, answer y; dirused stops tomcat85, deletes them, starts it, reports it running; free space on d$ rises; sc \\\\us03p02ffm01 query tomcat85 shows RUNNING; the operator confirms the app responds"
    intent: "In a window you choose, you will watch Tomcat stop, the two big redirect logs go, and Tomcat come back running, and the disk free space jump."
interface:
  - "/yes"
  - "/yes needs /purge /confirm"
  - "skipped: in use, not confirmed"
  - "skipped: in use, outside 19:00-06:00 for /yes"
  - "failed: in use (service has running dependents: <names>)"
  - "failed: in use (<key> not running)"
  - "failed: could not stop <key>: <error>"
  - "failed: could not stop <key>: timed out"
  - "failed: in use after stopping <key>"
  - "failed: log write failed"
  - "skipped: changed since scan (smaller) / (name)"
  - "skipped: file changed since list (smaller)"
  - "not attempted: earlier service start failed"
  - "error: <key> on <host> did not start (<reason>, state <state>). Start it with: sc \\\\<host> start <key>"
  - "warning: <key> on <host> is not running; start it with: sc \\\\<host> start <key>"
  - "service-stop / service-start / service-started / service-start-failed: <reason>"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and proving lines; list every error seen.

## Review adjudication (rev 1 → rev 2, Claude, 2026-11-20)

| # | Finding (reviewer) | Decision |
|---|---|---|
| 1 | 1056 during STOP_PENDING is not RUNNING; timeout path can leave Tomcat stopped (both) | Accepted: §2.10 wait-through-STOP_PENDING, query after 1056, re-Start; M5, mutants |
| 2 | Any ControlService failure ≠ "did not stop" (Fable); 1051/1062 not owned (Astra) | Accepted, merged: 1051/1062 not owned; other errors → query, RUNNING not owned, else owned (§2.8) |
| 3 | Recent held rows go via ProbeHeld, not Open 32 (both; verified `Purge.cs:146-164`) | Accepted: §2.1 holds back both; M1 covers both |
| 4 | Released recent row would skip the age gate (Astra) | Accepted: §2.6 sends it through the full M8 checks; M8 |
| 5 | Final ProbeHeld proves contention only; replaced file (Astra) | Accepted: §2.6 re-runs ClassifyHeldFile (identity/location/name) + §2.9 name check on handle |
| 6 | Cancel / stopReason / window not rechecked per group (Astra, Fable nit) | Accepted: §2.3, §2.5 |
| 7 | Snapshot or audit write throwing in finally skips Start (both) | Accepted for audit writes; snapshot gone with the log check (operator decision) |
| 8 | Next-run warning containment backwards (both; verified `ServiceQuery.cs:462`) | Accepted: §6 equal/under/above; M10 pins the real paths |
| 9 | Missing SERVICE_ENUMERATE_DEPENDENTS; enumeration error must refuse (both) | Accepted: §2.7, N3, mutant |
| 10 | Error 32 right after STOPPED (Fable) | Accepted: 30 s retry; M7 |
| 11 | Start errors: one retry; running-but-unverified semantics (Fable) | Accepted: one retry; unverified case gone (state-only check) |
| 12 | Exceptions in delete loop lose the run (Fable) | Accepted: per-row catch §2.9 |
| 13 | catalina FileShare, byte offsets, SEVERE, fake probe can't prove offsets (both) | Moot: operator 2026-11-20 dropped the log check |
| 14 | Undefined statuses: name change, service not running, ProbeHeld null; dead ID text (Fable) | Accepted: statuses named; §1 dead text removed |
| 15 | Wiring of IServiceControl and input seam unstated (Fable) | Accepted: §8 |
| 16 | Missed readers: PurgeListTests.cs:102, README :116/:166, purge.md:198, PACKAGE-README:35 (both) | Accepted: Files and readers updated |
| 17 | Acceptance gaps: M10 unproved, E2 overclaims, /fromlist exit 3, E1W only failure paths, CLI exit untested in portable (both) | Accepted: E3 for docs; E2 proves M1 only with patterns; M6 both paths; E1W adds ProgramPurgeTests; E1W intent narrowed to failure paths |
| 18 | Host "." form (Fable nit) | Accepted: §6 |
| 19 | Warning fires for intentionally stopped services (Fable nit) | Kept: a stopped Tomcat next to a full disk is worth a line |
| 20 | E1W fixture with an active dependent (Astra) | Rejected: cmd.exe services never reach Running; covered by fakes (N3) |
