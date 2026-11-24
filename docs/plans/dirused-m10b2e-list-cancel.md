# dirused M10b2e: `/schedule /list` and `/schedule /cancel` (pure, with fakes)

**Status:** OPEN — SPEC rev 1, 2026-11-24; intents approved (carries E-B2); starts after b2c lands (parallel with b2d); Fable + Argon blind reviews before dispatch
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md) (rev 4); design [M10b](dirused-m10b-scheduled-purge.md) §5 path checks 3–4, §7.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (after [b2c](dirused-m10b2c-seams-and-trust.md))
**Risk:** medium — cancel must never race a started run; no real scheduler call here
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job after landing
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries the approved E-B2 intent unchanged (parent); this child is its list-and-cancel part.
**Approval:** operator, 2026-11-24 — "intents approved"

## File formats this child reads (writers: b2d for `plan.txt`; M10b3 `/runplan` for `claim` and `report.txt`)

- `claim` (UTF-8, one line, `"\n"`): `run <yyyy-MM-ddTHH:mm:sszzz> pid <n>` or `cancel <yyyy-MM-ddTHH:mm:sszzz>`. Written with
  `WriteNew` (CreateNew), so whichever of run and cancel writes first wins.
- `report.txt` (UTF-8, `"\n"`): header lines `# outcome: <done|refused|interrupted>`, and for `done` also `# result: <text>` and
  `# exit: <n>`; other lines ignored here.

## Scope

`src/Dirused.Common/SchedulePlans.cs` (new):

```csharp
public static class SchedulePlans
{
    public static bool IsIntact(string planDir, ScheduleSeams s);   // parent §5 path checks 3–4
    public static int List(ScheduleSeams s, TextWriter stdout, TextWriter stderr);
    public static int Cancel(string id, ScheduleSeams s, TextWriter stdout, TextWriter stderr);
}
```

1. **`IsIntact`**: none of `<PlanRoot>`'s parent, `<PlanRoot>`, the plan dir, `plan.txt`, `list.txt`, `dirused.exe` is a reparse point;
   `ReadAcl` of `<PlanRoot>`, the plan dir and the three files is Ok, owner = `UserSid`, and every allow entry (inherit-only included)
   has SID `UserSid`. Any miss → false.
2. **`List`**: `ListDirectoryNames(PlanRoot)`; keep names matching `^[0-9]{8}-[0-9]{4}-[0-9a-f]{4}$`, ignore others. None → `No scheduled
   purges.`, exit 0. Per plan, the state is the first match:
   1. `!IsIntact` → `permissions changed — not run`
   2. `plan.txt` unreadable (`ReadAll` null) or missing a field the row needs → `unreadable plan`
   3. claim `cancel` → `cancelled`
   4. claim `run` and `report.txt` readable → its outcome; `done` → `done (<result>, exit <n>)`
   5. claim `run`, no report, `ProcessImagePath(pid)` equals `<plan dir>\dirused.exe` (ordinal, ignore case) → `running`
   6. claim `run`, no report → `interrupted (started <claim time as ddd HH:mm PST|PDT>, no report) — check the list and the report folder`
   7. no claim and `Now() > run + 15 min` → `missed (did not run)`
   8. `!Scheduler.Exists(taskName)` → `task missing`
   9. otherwise `scheduled`

   Row (two spaces between fields, no padding): `<id>  <run as ddd yyyy-MM-dd HH:mm PST|PDT>  <host>  <state>  <n> file(s) <size>  <source file name>`
   where `<size>` is `Format.Size(bytes)` and `<source file name>` is the last `\`-separated part of `# source:`. States 1–2 print
   `<id>  -  -  <state>`. Order: plans with a readable run, newest run first; then the others by id descending. Exit 0.
3. **`Cancel(id)`**: id not matching the pattern, or plan dir missing → exit 1 `unknown plan id: <id>`. `!IsIntact` → exit 1
   `refused: plan folder permissions changed`. `WriteNew(<plan dir>\claim, "cancel <Now ISO>\n")`; it fails and the existing claim
   reads `run ...` → exit 1 `<id> already started; it cannot be cancelled`; reads `cancel ...` → `<id> is already cancelled`, exit 0;
   other failure → exit 3 `error: could not cancel <id>: <error>`. Then `Scheduler.Delete(taskName)`; failure → exit 3
   `error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run` (claim stays). Then
   `AppendLog("schedule-cancel <id>")` (failure → `warning: could not write the purge log: <error>`), `Cancelled <id>.`, exit 0.

## Files

- `src/Dirused.Common/SchedulePlans.cs` (new), `tests/Dirused.Tests.Portable/SchedulePlansTests.cs` (new; in-memory fakes)

## What NOT to Do

- No other file; no `Program.cs` change; no real file, process or scheduler call (`ProcessImagePath` is the seam).
- No `File`, `Directory`, `Path`, `Process`, `Registry`, `Console` in `SchedulePlans.cs`; tests use `NewLine = "\n"`, literal `"\n"`.
- Never delete a plan dir. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: L-M1
    text: "List over nine fixture plans, one per state 1-9, prints each with its exact state text; two-condition fixtures (claim cancel + not intact; claim run + report + live pid; no claim + past run+15 + task missing) show the earlier state; rows match the literal format, e.g. '20261123-2230-a1b2  Mon 2026-11-23 22:30 PST  us03p02ffm01  scheduled  12 file(s) 176.2 GB  m10b.txt'; states 1-2 rows are '<id>  -  -  <state>'; order newest run first, unreadable last; a dir named 'notes' is ignored; missing plan root → 'No scheduled purges.'"
  - id: L-M2
    text: "running vs interrupted: claim 'run ... pid 42' with ProcessImagePath(42) = '<plan dir>\\\\dirused.exe' → running; = 'C:\\\\Windows\\\\notepad.exe' or null → interrupted (started Mon 22:30 PST, no report) — ...; done report → 'done (deleted 12, exit 0)' for '# result: deleted 12' '# exit: 0'"
  - id: L-M3
    text: "Cancel without claim: WriteNew(claim) with content 'cancel 2026-11-23T21:10:00-08:00\\n', then Delete(taskName) once, AppendLog 'schedule-cancel <id>', 'Cancelled <id>.', exit 0, in that order"
  - id: L-M4
    text: "Cancel: existing claim run → exit 1 '<id> already started; it cannot be cancelled', no Delete; existing claim cancel → '<id> is already cancelled', exit 0, no Delete; 'bad' or a missing dir → exit 1 'unknown plan id: <id>'; not intact → exit 1 'refused: plan folder permissions changed', no claim written; Delete fails → exit 3 'error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run' and the claim remains"
  - id: L-M5
    text: "IsIntact false for each single change: plans folder a reparse point; plan.txt a reparse point; owner of the plan dir another SID; an extra allow entry for Administrators on dirused.exe; an inherit-only entry for another SID on the plan dir; ReadAcl Ok=false on list.txt. True for the clean fixture"
must_not:
  - id: L-N1
    text: "Cancel calls Scheduler.Delete when the claim already says run (a cancel racing a started run). Positive control: L-M3 calls Delete once. Mutant-only (SchedulePlans absent on the pre-dispatch tip): 'delete before claiming' and 'claim with overwrite instead of WriteNew' each turn L-M4 red"
  - id: L-N2
    text: "List shows 'running' for a live pid whose image is not the plan's dirused.exe. Positive control: L-M2 running case. Mutant 'any live pid counts as running' turns L-M2 red"
  - id: L-N3
    text: "SchedulePlans.cs (comments stripped) matches \\\\b(File|Directory|Path|Process|Registry|Console)\\\\s*[.(], or calls DeleteTree. Positive control: mutant adding 'Store.DeleteTree(planDir)' to Cancel turns the scan red"
evidence:
  - id: E-L
    proves: [L-M1, L-M2, L-M3, L-M4, L-M5, L-N1, L-N2, L-N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4; SchedulePlansTests do not compile on the pre-dispatch tip; mutants each red with the catching test named: state order cancelled/running swapped [L-M1]; missed before cancelled [L-M1]; any live pid running [L-N2]; delete before claiming [L-N1]; claim overwrite [L-N1]; inherit-only ignored in IsIntact [L-M5]; owner not checked [L-M5]"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling, dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."
  - id: E-LW
    proves: [L-M1, L-M3]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "SchedulePlans.IsIntact(planDir, seams) -> bool; List(seams, stdout, stderr) -> int; Cancel(id, seams, stdout, stderr) -> int"
  - "claim: 'run <ISO> pid <n>' | 'cancel <ISO>'"
  - "report.txt: '# outcome:', '# result:', '# exit:'"
  - "No scheduled purges." / "unknown plan id: <id>" / "refused: plan folder permissions changed"
  - "<id> already started; it cannot be cancelled" / "<id> is already cancelled" / "Cancelled <id>."
  - "error: could not cancel <id>: <error>" / "error: could not delete task for <id>: <error>; the plan is marked cancelled and will not run"
```
