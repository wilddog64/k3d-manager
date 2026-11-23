# dirused M10b2: /schedule preview, plan files, /schedule /list and /cancel (with fakes)

**Status:** OPEN — SPEC rev 2, 2026-11-23; awaiting proofs P4, P7, P8, P11 and intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §1–§4, §7, §8. Second of four; starts after [M10b1](dirused-m10b1-engine-single-read-no-service.md) lands.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`
**Risk:** medium — parser changes and a new on-disk contract; no real task is registered in this child (fakes only)
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** operator, 2026-11-23 — preview first: "can we allow print out schedule for confirm before it actually scheduled" (D12)
**Operator decision pending:** O8 (multi-host lists refused by default).
**Proofs needed first:** P7 (zone), P8 (Task Scheduler constants for `PlanTask`), P11 (exe location, O7), P4 (O2 answer)

## Scope

All logic in `Dirused.Common`, tested in `Dirused.Tests.Portable` with fakes. Exactly as the parent:
- §2 parser pre-check table and `/fromlist` branch changes, `Options` fields, usage lines.
- §3 time resolution (clock and zone seams; Pacific by Windows or IANA id).
- §4 scheduling: one read, preview (exact layout), `/confirm` / `/yes` decision, re-check, source-program check (through
  `IPlanFolderSecurity.SourceExeIsProtected`), plan creation (through `IPlanFolderSecurity` and an `IPlanStore` file seam over a real
  temp dir in tests), `PlanTask` built and passed to `ITaskScheduler.Register`.
- §7 `/schedule /list` (states 1–10) and `/schedule /cancel` (claim, then delete).
- §8 seams: `ITaskScheduler`, `IPlanFolderSecurity`, `ScheduleCommands.Schedule/List/Cancel`. `RunPlan` is M10b3.
- Not here: `RealTaskScheduler`, real ACL class, `/runplan`, `Program.cs` wiring.

**Preview id choice:** the id is generated before the preview and shown there; if this invocation registers, that id is used. Not
"assigned at registration".

**Deviations from the coordinator's request (recorded for the operator):** (a) the preview prints no held rows — a list has no held
field and showing them needs a server stat and service query, which scheduling never does (O6, default no); (b) the `/yes` rule text
stays `/yes needs /purge /confirm` because `/purge` stays required.

## Files

`src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`, `src/Dirused.Common/Schedule.cs` (new),
`tests/Dirused.Tests.Portable/ScheduleTests.cs` (new), `tests/Dirused.Tests.Portable/ArgParserTests.cs`,
`tests/Dirused.Tests.Portable/PurgeListTests.cs`.

## Contract readers

- Whitelist text `ArgParser.cs:121` → new text; reader `PurgeListTests.cs:102` updated here.
- `/yes needs /purge /confirm` `ArgParser.cs:137`, `:263`; readers `ArgParserTests.cs:310,311,313`; usage `:73` — unchanged; tests stay.
- `ArgParserTests.cs:249-252` (80 columns) — new usage lines must pass it.
- `KnownSwitches` `:16` — four new names.
- `Options` constructions `ArgParser.cs:139`, `:291`, tests — new fields last, defaulted.

## What NOT to Do

- Do not read the list twice, stat or open a listed file, or query a service at schedule time.
- Do not register anything or create a plan dir without `/confirm` (and `y` or `/yes`).
- Do not write into a plan dir before `Secure` succeeded on it. Do not use `%LOCALAPPDATA%` from the environment.
- Do not touch `Program.cs`, `Purge.cs`, `PurgeList.cs`. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B2-M1
    text: "preview: clock Mon 2026-11-23 21:00 PST, zone Pacific, list of 12 rows totalling 176.2G, '/fromlist l.txt /purge /schedule 22:30' prints the parent §4.2 layout line for line (run in PST and UTC, expiry, list path, count, size, first 12 hex of sha256, the fixed Held line, task path \\dirused\\<SID>\\purge-<id>, plan dir, program copy path), every line <= 80 columns, then 'Preview only. Add /confirm to schedule it.', exit 0"
  - id: B2-M2
    text: "'/confirm' + answer 'y' (and 'YES'): the same preview, then 'Schedule this? [y/N] ' on stderr, then exactly one Register call whose PlanTask has folder \\dirused\\<SID>\\, name purge-<id> with the id shown in the preview, the SDDL D:P(A;;FA;;;<SID>)(A;;FA;;;SY)(A;;FA;;;BA), StartBoundary 2026-11-23T22:30:00-08:00, EndBoundary created+24h, DeleteExpiredTaskAfter P30D, interactive token, LUA, no password, AllowDemandStart false, StartWhenAvailable false, IgnoreNew, PT2H, action <plan dir>\\dirused.exe '/runplan \"<plan dir>\\plan.txt\"'; plan dir holds dirused.exe byte-equal to the fake exe, list.txt byte-equal to the list, plan.txt with every §4.6 field; Secure was recorded before the first file write; exit 0"
  - id: B2-M3
    text: "'/confirm /yes': preview, no question written, no input read, one Register call"
  - id: B2-M4
    text: "time rules: 20:00 at 21:00 → tomorrow; UTC, PST, PDT, PT instants; bare time on a non-Pacific zone exits 1 with the exact message; a zone with id America/Los_Angeles counts as Pacific; spring-forward 02:30 PT and fall-back 01:30 PT exit 1 with their messages; 01:30 PDT on fall-back day accepted; 1 minute away exits 1; a run 23h46m away exits 1 with the 'too far away' message and 23h44m is accepted"
  - id: B2-M5
    text: "re-check after the prompt: clock advances past run-2min while the fake reader waits → the 'less than 2 minutes' message, exit 1, no Register, no plan dir; the fake file reader records exactly one read of the list in this run"
  - id: B2-M6
    text: "every row of the parent §2 table gives its exact error (one test per row, including order: '/schedule /list 22:30' gives row 4, '/runplan p /schedule 22:30' gives row 1); '/fromlist l /purge /schedule 22:30 /yes' gives '/yes needs /purge /confirm'; the new whitelist text appears for '/fromlist l /purge /bogus'; all usage lines <= 80 columns"
  - id: B2-M7
    text: "plan creation failures: Secure fails → plan dir removed, exit 3 'error: could not secure plan folder: ...'; a reparse 'plans' dir → exit 3 '... is a link' and nothing written under it; Register fails → plan dir removed, exit 3 'error: could not schedule: ...'; source exe folder writable by others (fake) → exit 1 with the §4.5 message, no plan dir"
  - id: B2-M8
    text: "/schedule /list over fixture plan dirs shows each state 1-10 of parent §7 in that precedence (fixtures where two conditions hold show the earlier one, e.g. claim=cancel with task Running shows cancelled; claim=run, no report, task missing shows interrupted); 'No scheduled purges.' when the root is missing"
  - id: B2-M9
    text: "/schedule /cancel <id>: no claim → claim file 'cancel <time>' created, then Delete called, 'Cancelled <id>.', exit 0; claim=run → exit 1 '<id> already started; it cannot be cancelled' and no Delete; claim=cancel → '<id> is already cancelled', exit 0; bad id or missing dir → exit 1 'unknown plan id: <id>'; Delete fails → exit 3 with the 'marked cancelled' message and the claim stays"
  - id: B2-M10
    text: "target host (parent D13): a list of rows under \\\\us03p02ffm01\\d$\\... shows 'Host:     us03p02ffm01' in the preview, writes '# host: us03p02ffm01' to plan.txt, and /schedule /list shows us03p02ffm01 in that plan's row; two plans for two different single-host lists both register and both list with their own host; a list with rows on \\\\hostA and \\\\HOSTB exits 1 with '/schedule: the list covers more than one host (hostA, HOSTB); save one list per host and schedule each', no Register, no plan dir (positive control: hostA-only list registers); rows differing only in host case count as one host; a drive-letter list shows 'this machine'"
must_not:
  - id: B2-N1
    text: "preview-only (no /confirm) or /confirm + 'n'/empty/redirected input records any Register call or creates any dir under the plan root. Positive control: B2-M2's /confirm + 'y' records one Register and a plan dir. baseline: mutant-only (on a2d0508 /schedule is a parse error); mutants 'register before the decision' and 'create plan dir before the decision' turn it red"
  - id: B2-N2
    text: "scheduling calls any IPurgeFileSystem method (Stat, Open, Delete, Enumerate) or any IServiceQuery method. Positive control: the same fakes record calls in a '/fromlist l /purge' dry run. Baseline red on a2d0508: '/fromlist l /purge /schedule 22:30' reaches the whitelist error branch, and the test asserting exit 0 and the preview fails"
  - id: B2-N3
    text: "the list is read more than once in a schedule invocation (fake reader count > 1), including the /confirm y path. Positive control: count = 1 asserted in B2-M2. baseline: mutant-only; mutant 're-read the list after the answer' turns it red"
  - id: B2-N4
    text: "a file is written into the plan dir before Secure returned ok on it (fake records order). Positive control: B2-M2 order. Baseline red: mutant 'write files then secure'"
  - id: B2-N5
    text: "cancel with claim=run calls Delete. Positive control: cancel without claim calls Delete once. baseline: mutant-only; mutant 'delete before claiming' turns it red"
evidence:
  - id: E-B2
    proves: [B2-M1, B2-M2, B2-M3, B2-M4, B2-M5, B2-M6, B2-M7, B2-M8, B2-M9, B2-M10, B2-N1, B2-N2, B2-N3, B2-N4, B2-N5]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on ubuntu. New tests red on a2d0508. Mutants each red: register before the decision; plan dir created before the decision; re-read the list after the answer; skip the re-check after the answer; PST treated as DST-aware; passed time stays today; 23h45m limit off by one (>=); bare time accepted off Pacific; IANA id not recognised; write files then secure; delete before claiming; list state order swaps cancelled and running; missed computed from task LastRunTime instead of claim; id regenerated at registration; multi-host check skipped; host compared case-sensitively"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Each plan targets one server, named in the preview and the list, and you can schedule separate plans for different servers."
interface:
  - "/schedule <time> [PT|PST|PDT|UTC]"
  - "/schedule <time> ... /confirm"
  - "/schedule <time> ... /confirm /yes"
  - "/schedule /list"
  - "/schedule /cancel <id>"
  - "Scheduled purge preview (nothing is scheduled yet)"
  - "Preview only. Add /confirm to schedule it."
  - "Schedule this? [y/N] "
  - "Not scheduled."
  - "/schedule: the list covers more than one host (<hosts>); save one list per host and schedule each"
  - "/list and /cancel go with /schedule"
  - "/schedule /list cannot be combined with other switches"
  - "/schedule /cancel requires a plan id"
  - "/schedule /cancel cannot be combined with other switches"
  - "/schedule can be given only once"
  - "/schedule requires /fromlist"
  - "/schedule requires a time, e.g. /schedule 22:30 PT"
  - "/schedule: time must be HH:MM (00:00-23:59), optionally followed by PT, PST, PDT or UTC"
  - "/schedule can only be combined with /fromlist, /purge, /confirm and /yes"
  - "/fromlist can only be combined with /purge, /confirm, /html, /output, /json, /csv, /yes and /schedule"
  - "/runplan cannot be combined with other switches"
  - "/runplan requires a plan path"
```
