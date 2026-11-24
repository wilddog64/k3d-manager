# dirused M10b2d: the `/schedule /confirm` flow (preview, prompt, re-check, trust, plan creation, register) with fakes

**Status:** OPEN — SPEC rev 1, 2026-11-24; intents approved (carries E-B2); starts after b2b and b2c land; Fable + Argon blind reviews before dispatch
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md) (rev 4); design [M10b](dirused-m10b-scheduled-purge.md) §4.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (after [b2b](dirused-m10b2b-parser-usage.md) and [b2c](dirused-m10b2c-seams-and-trust.md))
**Risk:** medium — creates plan folders and registers tasks through seams; real classes and Program wiring are M10b3
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job after landing
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries the approved E-B2 intent unchanged (parent); this child is its scheduling part.
**Approval:** operator, 2026-11-23 — D12 preview first; operator, 2026-11-24 — D14, "intents approved"

## Scope

1. **`Schedule.cs` refactor (behaviour-preserving for `Schedule.Run`)**: move the body of the preview into
   `internal static int Schedule.Preview(ParsedPurgeList list, string listPathAsTyped, DateTimeOffset created, TimeZoneInfo local,
   Options options, TextWriter stdout, TextWriter stderr, PreviewExtras? extras, out DateTimeOffset run, out string host)` so that
   `Schedule.Run` and the new flow share one formatter. `PreviewExtras(string Sha12, string TaskName, string PlanDir, string ExePath)`.
   With `extras == null` the output is byte-identical to today's (all existing `ScheduleTests` pass unchanged). With extras, after
   the size line comes `            sha256 <Sha12>`, and after the `Held:` line come `  Task:     <TaskName>`, `  Plan dir: <PlanDir>`,
   `  Program:  <PlanDir>\dirused.exe` and `            (copy of <ExePath>)`, each value written with the existing `WriteWrappedPath`
   rule (≤ 80 columns, 68-character chunks, 12-space continuation).
2. **`src/Dirused.Common/ScheduleCommands.cs`** (new):
   `public static int ScheduleCommands.Schedule(ScheduleRequest req, ScheduleSeams s, TextWriter stdout, TextWriter stderr, TextReader input, bool inputRedirected)`.
   Steps, in order:
   1. `PurgeList.Parse(req.ListBytes, out list)` — the only parse; false → stderr `not a dirused delete list: <ListPathAsTyped>`, exit 1.
   2. `created` = `s.Now()` truncated to whole seconds; id per the parent (one `IdSuffix()` draw); `Preview(... extras)` with
      `Sha12` = first 12 lower-case hex of SHA-256 of `ListBytes`. Preview errors (no files, host, time rules) keep M10b0's messages and
      exit codes.
   3. No `/confirm`: print `Preview only. Add /confirm to schedule it.`; bad lines → the M10b0 `Bad list lines:` block, exit 3; else
      exit 0. Only `Now`, `IdSuffix` and pure code ran; **no seam interface method is called**.
   4. `/confirm` and bad lines → `Bad list lines:` block, `/schedule: fix the list first; nothing was scheduled`, exit 3, no prompt.
   5. `/confirm` and `s.Token == High` → `/schedule: run from a normal (not elevated) window`, exit 1.
   6. Without `/yes`: `Schedule this? [y/N] ` on stderr (no newline); `inputRedirected` → no read, No; else one `ReadLine`; `y` or
      `yes` (trimmed, case-insensitive) is Yes. No → `Not scheduled.`, exit 0.
   7. Re-check: `run - s.Now() < 2 min` → `/schedule: <time as typed> is less than 2 minutes away; pick a later time`, exit 1. The time
      rules are not re-run (no silent roll to another day).
   8. Trust: `PlanTrust.Check(s.ExePath, s.PlanRoot, s.UserSid, s.Trust.Load(), s.Store, s.Security)`; not Ok → its lines on stderr,
      exit 1.
   9. Folders: for `<PlanRoot>`'s parent then `<PlanRoot>`: `IsReparsePoint` → exit 3 `error: could not secure plan folder: <path> is a
      link`; when not `Exists`: `CreateDirectory` then `Secure`; failure → exit 3 `error: could not secure plan folder: <error>`.
   10. Plan dir `<PlanRoot>\<id>`: `CreateDirectory`; failure and `Exists` → draw a new suffix and retry (at most 5 draws in total; then
       exit 3 `error: could not write plan: no free plan id`); other failure → exit 3 `error: could not write plan: <error>`.
       `IsReparsePoint` on it → `DeleteTree`, exit 3 link message. `Secure(planDir, UserSid)`; failure → `DeleteTree`, exit 3 secure
       message.
   11. `Store.ReadAll(ExePath)` null → `DeleteTree`, exit 3 `error: could not write plan: cannot read <ExePath>`. Then `WriteNew` in this
       order: `dirused.exe` (those bytes), `list.txt` (`ListBytes`), `task.xml` (`TaskXml.Build(planTask)`), `plan.txt` (parent format,
       `# trusted:` = every SID in `Trust.Load()` at step 8, sorted ordinal, joined by `,`, or `none`). Any
       failure → `DeleteTree`, exit 3 `error: could not write plan: <error>`.
   12. `Scheduler.Register(taskName, planDir + "\\task.xml", planTask)`; failure → `DeleteTree`, exit 3 `error: <Error>`.
   13. `Store.AppendLog("schedule <id> run <run yyyy-MM-ddTHH:mm:sszzz> files <n> bytes <total>")`; failure → stderr
       `warning: could not write the purge log: <error>` (still exit 0). Print `Scheduled <id> for ...` (parent string), exit 0.


## Files

- `src/Dirused.Common/Schedule.cs` (refactor only), `src/Dirused.Common/ScheduleCommands.cs` (new)
- `tests/Dirused.Tests.Portable/ScheduleCommandsTests.cs` (new; fakes for every seam, recording call order)

## What NOT to Do

- No other file; no change to `Schedule.Run`'s output; no `Program.cs` change (M10b3 wires it).
- No I/O outside the seams: no `File`, `Directory`, `Path`, `Process`, `Registry`, `FileInfo`, `DirectoryInfo`, `FileStream`,
  `StreamWriter`, `StreamReader`, `Console` in `ScheduleCommands.cs`.
- Product text written into files uses `"\n"` explicitly (plan.txt); tests use writers with `NewLine = "\n"` and literal `"\n"`.
- Leave changes uncommitted; do not push.

## Acceptance

Fixture: `Now` = Mon 2026-11-23 21:00:00.1234567 -08:00, Pacific local, list of 12 rows under `\\us03p02ffm01` totalling 176.2 GB typed
as `C:\Users\op\m10b.txt` (full path the same), `/fromlist ... /purge /schedule 22:30`, `PlanRoot` `C:\Users\op\AppData\Local\dirused\plans`,
`ExePath` `C:\Program Files\dirused\dirused.exe`, `UserSid` `S-1-5-21-1-2-3-1104`, `IdSuffix` → 0xa1b2, `ToolVersion` `0.0.28`, trust
fakes = b2c's `StockSystemDrive` (no trust needed).

```yaml
must:
  - id: D-M1
    text: "no /confirm: stdout is exactly the M10b0 preview lines with '            12 file(s), 176.2 GB in the list', then '            sha256 <first 12 hex of SHA-256(ListBytes)>', 'Held:' line, '  Task:     \\\\dirused\\\\S-1-5-21-1-2-3-1104\\\\purge-20261123-2230-a1b2', '  Plan dir: C:\\\\Users\\\\op\\\\AppData\\\\Local\\\\dirused\\\\plans\\\\20261123-2230-a1b2', the Program line wrapped at 68 characters, '            (copy of C:\\\\Program Files\\\\dirused\\\\dirused.exe)', the logged-on line, 'Preview only. Add /confirm to schedule it.'; every line <= 80; exit 0; every seam fake records zero calls"
  - id: D-M2
    text: "/confirm + 'y' (also 'YES', ' yes '): 'Schedule this? [y/N] ' on stderr; recorded order: Trust.Load, ReadAcl/IsReparsePoint per path, CreateDirectory+Secure for '...\\\\dirused' and 'plans', CreateDirectory+Secure plan dir, ReadAll(exe), WriteNew dirused.exe, list.txt, task.xml, plan.txt, Register, AppendLog; dirused.exe bytes = the fake exe bytes; list.txt = ListBytes; task.xml = TaskXml.Build(planTask) with Run 2026-11-23T22:30:00-08:00, Expires 2026-11-24T21:00:00-08:00 (created truncated: no exception); plan.txt equals the parent format line for line with 'created: 2026-11-23T21:00:00-08:00' and '# trusted: none', ending with '\\n' and no '\\r'; Register(taskName '\\\\dirused\\\\S-1-5-21-1-2-3-1104\\\\purge-20261123-2230-a1b2', '<plan dir>\\\\task.xml'); AppendLog 'schedule 20261123-2230-a1b2 run 2026-11-23T22:30:00-08:00 files 12 bytes <total>'; stdout ends 'Scheduled 20261123-2230-a1b2 for Mon 2026-11-23 22:30 PST (06:30 UTC Tue). Check it with: dirused /schedule /list'; exit 0"
  - id: D-M3
    text: "'/confirm /yes': no prompt written, no read, one Register. '/confirm' with inputRedirected: no read, 'Not scheduled.', exit 0, only Trust-free pure steps ran (zero seam calls). '/confirm' + 'n' or empty: 'Not scheduled.', zero seam calls"
  - id: D-M4
    text: "re-check: the fake reader advances Now to 22:28:30 before returning 'y' → '/schedule: 22:30 is less than 2 minutes away; pick a later time', exit 1, zero writes and no Register"
  - id: D-M5
    text: "Token High with /confirm → '/schedule: run from a normal (not elevated) window', exit 1, no prompt, zero seam calls; Token Medium proceeds (D-M2)"
  - id: D-M6
    text: "bad list lines with /confirm → preview (no 'Preview only' line), 'Bad list lines:' block, '/schedule: fix the list first; nothing was scheduled', exit 3, no prompt, zero seam calls; not-a-list bytes → 'not a dirused delete list: C:\\\\Users\\\\op\\\\m10b.txt', exit 1"
  - id: D-M7
    text: "trust: with b2c's SysadminProfile fake and empty store → the two refusal lines then also-lines on stderr, exit 1, no CreateDirectory/WriteNew/Register; with PROD\\\\sysadmin stored → registers and plan.txt says '# trusted: S-1-5-21-1-2-3-2001'"
  - id: D-M8
    text: "failures: plan-dir CreateDirectory fails with Exists true twice → ids with the 2nd and 3rd suffix draws, success on the 3rd, printed id is the 3rd; five collisions → exit 3 'error: could not write plan: no free plan id'; Secure(plan dir) fails → DeleteTree(plan dir), exit 3 'error: could not secure plan folder: <error>', no WriteNew; WriteNew(task.xml) fails → DeleteTree, exit 3 'error: could not write plan: <error>', no Register; ReadAll(exe) null → exit 3 'error: could not write plan: cannot read C:\\\\Program Files\\\\dirused\\\\dirused.exe'; Register fails with 'could not schedule (schtasks exit 1)' → DeleteTree, exit 3 'error: could not schedule (schtasks exit 1)'; '...\\\\dirused' IsReparsePoint → exit 3 'error: could not secure plan folder: C:\\\\Users\\\\op\\\\AppData\\\\Local\\\\dirused is a link'; AppendLog fails → warning line, exit 0"
  - id: D-M9
    text: "Schedule.Run (M10b0 entry) output and exit codes are unchanged: every existing ScheduleTests assertion passes without edits"
must_not:
  - id: D-N1
    text: "preview-only, No, redirected input, Token High, bad lines or a trust refusal records any CreateDirectory, Secure, WriteNew, Register or Trust.Add. Positive control: D-M2 records them. Mutant-only (ScheduleCommands absent on e19783f): 'register before the decision', 'create plan dir before the trust check', 'skip elevation check' each turn D-M3, D-M5 or D-M7 red"
  - id: D-N2
    text: "a WriteNew into the plan dir is recorded before Secure(plan dir) returned Ok. Positive control: D-M2 order. Mutant 'write files then secure'"
  - id: D-N3
    text: "ScheduleCommands.cs (comments stripped) contains 'PurgeList.Parse(' other than exactly once, or matches \\\\b(File|Directory|Path|Process|Registry|FileInfo|DirectoryInfo|FileStream|StreamWriter|StreamReader|Console)\\\\s*[.(]. Positive control: mutant adding a second PurgeList.Parse call turns the scan red"
evidence:
  - id: E-D
    proves: [D-M1, D-M2, D-M3, D-M4, D-M5, D-M6, D-M7, D-M8, D-M9, D-N1, D-N2, D-N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4; ScheduleCommandsTests do not compile on the pre-dispatch tip; mutants each red with the catching test named: register before the decision [D-N1]; plan dir before trust [D-N1, D-M7]; skip re-check [D-M4]; re-check re-runs the time rules [D-M4]; created not truncated [D-M2]; write then secure [D-N2]; no DeleteTree on Register failure [D-M8]; id regenerated without a collision [D-M2]; '# trusted:' omitted [D-M2, D-M7]; elevation check removed [D-M5]; Program line not wrapped [D-M1]"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling, dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."
  - id: E-DW
    proves: [D-M2, D-M9]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "ScheduleCommands.Schedule(ScheduleRequest, ScheduleSeams, TextWriter stdout, TextWriter stderr, TextReader input, bool inputRedirected) -> int"
  - "Schedule.Preview(..., PreviewExtras? extras, out run, out host) (internal)"
  - "not a dirused delete list: <path>"
  - "warning: could not write the purge log: <error>"
  - "error: could not write plan: no free plan id"
  - "error: could not write plan: cannot read <ExePath>"
```
