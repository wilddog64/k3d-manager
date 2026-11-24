# dirused M10b3: /runplan, the real Task Scheduler and folder-security classes, Program wiring

**Status:** OPEN — SPEC rev 2, 2026-11-23; awaiting proofs P1, P2, P3, P5, P6, P8, P9, P10, P12 and intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §4.6–§4.7, §5, §6, §8. Third of four; starts after [M10b2](dirused-m10b2-schedule-preview-list-cancel.md) lands.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`
**Risk:** high — the unattended delete path and real schtasks.exe and ACL calls
**Implementer:** Luna (Codex)
**Verifier:** Claude offline; live checks E-B3L1 and E-B3L2 by the operator on the jump box
**Filed:** 2026-11-23
**Intent approved:** operator, 2026-11-24
**Approval:** operator, 2026-11-23 — D9 (no service stop), D3 (logged-on only, no password)

## Jump-box probe script (2026-11-24)

[`assets/dirused-m10b3-probes.ps1`](assets/dirused-m10b3-probes.ps1) covers P1, P2, P3, P8 (a, b, d), P10 (descriptor readback; the
second-account check is manual) and P12. It creates tasks only under `\dirused-probe\<SID>\` and files only under
`%LOCALAPPDATA%\dirused-probe\`; P3 runs `dir` and `icacls` on the share (read-only). Run order: `setup` (afternoon, prints the
steps and times), `run12`, disconnect / sign-out steps as printed, leave disconnected, next morning `collect`, paste `report.txt`,
then `cleanup`. P5, P6 and P9 are not in it (P9 is a CI workflow, Claude's).

## Scope

- `ScheduleCommands.RunPlan(...)` in `Dirused.Common`: parent §5 tables in order (path, exe path, links, permissions, plan fields,
  expiry, start window, claim, exe hash, one read of `list.txt` + hash, `PurgeList.Parse` of the same bytes, `Purge.Apply` with
  `scheduled = true`, `control = null`), parent §6 report (tmp + rename without overwrite; includes rows and this run's purge-log and
  stderr lines).
- `SchtasksTaskScheduler(IProcessRunner runner, string rootFolder = "\\dirused")` per parent §4.7 and §8: `/create /tn <name> /xml
  <path>` (no `/f`), verify by `/query /tn <name> /xml` + `TaskXml.Parse` + field compare (mismatch → `/delete /f`, remove plan dir,
  exit 3), `Exists` = exit code of `/query /tn <name>`, `Delete` = `/delete /tn <name> /f`. Exit codes only; no text parsing.
  Real `IProcessRunner`: absolute `Path.Combine(Environment.SystemDirectory, "schtasks.exe")`, `ArgumentList`, `UseShellExecute =
  false`, `CreateNoWindow = true`, stdout as bytes, `[SupportedOSPlatform("windows")]`.
- `RealPlanFolderSecurity`: `Secure` (owner = user SID, protected DACL, one ACE), `Check`, `IsReparsePoint`,
  `SourceExeIsProtected`. `[SupportedOSPlatform("windows")]`.
- `Program.cs`: map `Options` to `ScheduleCommands`; public `Program.RunWithSchedule(...)` seam; non-Windows → `/schedule needs
  Windows` except the preview; `/runplan` and `/schedule` never run the update check.

## Files

`src/Dirused.Common/Schedule.cs`, `src/Dirused.Common/TaskScheduling.cs` (new), `src/Dirused.Common/PlanFolderSecurity.cs` (new),
`src/Dirused.Cli/Program.cs`, `tests/Dirused.Tests.Portable/RunPlanTests.cs` (new), `tests/Dirused.Tests.Portable/SchtasksTests.cs` (new), `tests/Dirused.Tests/TaskSchedulerWindowsTests.cs`
(new), `tests/Dirused.Tests/ProgramScheduleTests.cs` (new).

## What NOT to Do

- Do not call `IServiceControl` or pass a non-null `control` from `/runplan`. Do not read the original list.
- Do not take the claim before the expiry and start-window checks; do not write a report on a stderr-only refusal.
- Do not replace an existing `report.txt`. Run `schtasks.exe` only through `IProcessRunner` by absolute
  path; never a shell, a command string, `/f` on create, or text parsing; no COM; no NuGet package.
- Do not register a task in CI outside `\dirused-ci\` or leave one behind. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B3-M1
    text: "RunPlan on a plan made by M10b2's Schedule (real temp dir, fake security reporting ok, clock = run instant, fake fs with 3 listed matching not-held files and 1 held by Tomcat85): claim file 'run <time> pid <n>' created, 3 files deleted, held row skipped with the scheduled-skip status, report.txt has outcome done, result 'deleted 3 file(s), ...; 1 skipped; 0 failed', the rows, and this run's purge-log lines; no report.tmp left; exit 0"
  - id: B3-M2
    text: "stderr-only refusals, each with its exact message, exit 1, and nothing created in the plan dir (no claim, no report): id not matching the regex or no <root>\\<id>\\plan.txt ('refused: not a plan id: <id>'); exe path not <root>\\<id>\\dirused.exe; a reparse point on any of the six components; permission check fails; start 2 min early; start 16 min late"
  - id: B3-M3
    text: "report refusals, each taking the claim and writing report.txt with its outcome: bad plan.txt fields ('refused: not a dirused plan'); exe hash mismatch; list hash mismatch; clock >= expires ('expired', exit 0); and nothing in the fake fs is deleted"
  - id: B3-M4
    text: "claim already 'cancel' → stderr 'cancelled', exit 0, no delete; claim already 'run' → stderr 'refused: plan already started', exit 1, report not touched"
  - id: B3-M5
    text: "report.txt present before the run (claim absent): rename fails, the existing report is byte-identical afterwards, the error goes to stderr, and /schedule /list then shows the report's outcome"
  - id: B3-M6
    text: "SchtasksTaskScheduler with a fake IProcessRunner: Register records exe = <SystemDirectory>\\schtasks.exe and argv exactly ['/create','/tn','\\dirused\\<SID>\\purge-<id>','/xml','<plan dir>\\task.xml'] (no '/f'), then ['/query','/tn',<name>,'/xml']; a query returning Build's output passes; a query whose XML differs in any one field (AllowStartOnDemand true, StartWhenAvailable true, EndBoundary moved, LogonType Password, Arguments changed) records ['/delete','/tn',<name>,'/f'], removes the plan dir and exits 3 naming the field; create exit 1 → exit 3 'error: could not schedule (schtasks exit 1)' and no query; Exists maps exit 0/1 to true/false; no runner stdout is read except the /xml query. On windows-latest (E-B3W): the real runner creates \\dirused-ci\\<SID>\\purge-<guid> one day ahead from Build's file, the /query /xml compare passes, a second /create of the same name exits non-zero, Delete removes it (in finally)"
  - id: B3-M7
    text: "RealPlanFolderSecurity on windows-latest: Secure on a temp dir gives owner = current SID, protected DACL, one ACE; Check ok; adding an Everyone ACE, or making a junction in its place, makes Check fail with the reason; SourceExeIsProtected false for a folder granting Users write"
  - id: B3-M8
    text: "Program: '/fromlist l /purge /schedule 22:30 /confirm /yes' through RunWithSchedule with fakes reaches ScheduleCommands.Schedule; '/runplan <id>' reaches RunPlan; neither invokes the release source (update check)"
must_not:
  - id: B3-N1
    text: "RunPlan deletes a listed row whose size, last-write or file ID differs from the list — positive control: the matching row in the same run is deleted. Baseline red on a2d0508: the test cannot run /runplan (parse error) and the assertion that the matching row was deleted fails"
  - id: B3-N2
    text: "RunPlan calls any IServiceControl method (a recording control injected through RunWithSchedule). Positive control: the same seam records Stop/Start for an attended '/fromlist l /purge /confirm /yes' at 22:30. baseline: mutant-only; mutant 'pass the real control to Apply' turns it red"
  - id: B3-N3
    text: "a start outside [run-1m, run+15m] creates the claim or a report. Positive control: start at run creates the claim. baseline: mutant-only; mutant 'claim before the window check' turns it red"
  - id: B3-N4
    text: "an expired plan deletes anything — positive control: the same plan at expires-1min (and within the start window by fixture) deletes. Baseline red on a2d0508 via the deleted-file assertion of the control"
  - id: B3-N5
    text: "RunPlan reads the original list path recorded in '# source:' or reads list.txt more than once (fake reader). Positive control: list.txt read count = 1. baseline: mutant-only; mutant 'read source list' turns it red"
evidence:
  - id: E-B3
    proves: [B3-M1, B3-M2, B3-M3, B3-M4, B3-M5, B3-M6, B3-N1, B3-N2, B3-N3, B3-N4, B3-N5]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable. New tests red on a2d0508. Mutants each red: pass '/f' to create; skip the verify compare; compare ignores AllowStartOnDemand; delete not called on mismatch; claim before window check; window +30 min; expiry > instead of >=; skip exe hash; skip list hash; read list twice; read source list; pass control to Apply; scheduled false in RunPlan; report written directly (no tmp); report overwrite allowed; permission check skipped for files; reparse check skipped for plans dir"
    intent: "The scheduled run deletes only files that are exactly the ones you reviewed, never touches Tomcat, refuses if the plan, its program copy or its folder changed, and leaves a report you can read in the morning."
  - id: E-B3W
    proves: [B3-M6, B3-M7, B3-M8]
    kind: offline
    command: "windows-latest CI job: dotnet test tests/Dirused.Tests --filter TaskSchedulerWindowsTests|ProgramScheduleTests|PlanFolderSecurity. If P9 shows the runner cannot register an interactive-token task, B3-M6's Windows half asserts the generated XML only and the spec records that"
    intent: "The real Windows task and folder-permission calls are checked on a throwaway task in CI, so a wrong setting is caught before it reaches the jump box."
  - id: E-B3L1
    proves: [B3-M1]
    kind: live
    command: "operator, jump box, attended, after P1-P3 and P5-P6: save a list of 2-3 small non-held test files in a scratch share folder; dirused /fromlist t.txt /purge /schedule <now+5min> PT (preview), then the same with /confirm, answer y; stay connected; after the run: dirused /schedule /list shows done; report.txt shows them deleted; then schedule a second plan and /schedule /cancel it: list shows cancelled and the files remain"
    intent: "While you watch, a scheduled run deletes a few test files from a list you reviewed, and a cancelled plan deletes nothing."
  - id: E-B3L2
    proves: [B3-M1]
    kind: live
    command: "operator, jump box, disconnected: dirused \\\\us03p02ffm01\\d$\\Tomcat /largest *.log /purge /savelist m10b.txt; review; /schedule <evening time> PT /confirm, y; disconnect RDP (do not sign out); next morning: /schedule /list shows done; report.txt lists deleted rotated logs and the held tomcat85-stderr/stdout rows as 'skipped: held by Tomcat85 — scheduled runs do not stop services'; sc \\\\us03p02ffm01 query tomcat85 shows RUNNING with an unchanged start time; free space on d$ rose by the reported amount"
    intent: "You schedule tonight's purge, disconnect, and in the morning see the old logs gone, the logs Tomcat holds left alone, and Tomcat never restarted."
interface:
  - "/runplan <id>"
  - "refused: not a plan id: <id>"
  - "error: could not schedule (schtasks exit <code>)"
  - "error: scheduled task does not match the plan (<field>); it was removed"
  - "refused: not started from the plan's program copy"
  - "refused: plan folder contains a link"
  - "refused: plan folder permissions changed"
  - "refused: not a dirused plan"
  - "refused: not the scheduled time (scheduled <time>)"
  - "refused: plan already started"
  - "refused: program copy changed since it was scheduled"
  - "refused: list changed since it was scheduled"
  - "/schedule needs Windows"
```
