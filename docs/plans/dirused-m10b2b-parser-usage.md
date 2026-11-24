# dirused M10b2b: parser rows for /list, /cancel, /runplan, /trust, /untrust; usage lines; size-line wording

**Status:** OPEN — SPEC rev 1, 2026-11-24; intents approved (carries E-B2); Fable + Argon blind reviews before dispatch
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md) (rev 4); design [M10b](dirused-m10b-scheduled-purge.md) §2.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (tip `e19783f`)
**Risk:** low — parser and text only; the new commands are refused at run time until M10b3
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job on the push run after landing
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries the approved E-B2 intent unchanged (parent); this child is the command-line part of it.
**Approval:** operator, 2026-11-24 — "intents approved, and you write a spec and have Fable/Argon review then dispatch between Flash and Luna"

## Scope

1. **`KnownSwitches`** (`ArgParser.cs:16`): add `list`, `cancel`, `runplan`, `trust`, `untrust`.
2. **Pre-check rows** before the existing M10b0 schedule checks (`ArgParser.cs:121-137`), first match wins, all matched with `IsFlag`.
   "Switch-like" means a token `IsFlag` treats as a flag (starts with `/` but not `//`, or with `-`), known or not.

   | # | Condition | Error |
   |---|---|---|
   | 1 | `runplan` appears more than once, or with any other token except its one id | `/runplan cannot be combined with other switches` |
   | 2 | `runplan` with no following token, or the next token is switch-like | `/runplan requires a plan id` |
   | 3 | `list` or `cancel` present without `schedule` | `/list and /cancel go with /schedule` |
   | 3a | `trust` or `untrust` present without `schedule` | `/trust and /untrust go with /schedule` |
   | 4 | `schedule` and `list` both present: anything else present (including `cancel`, `trust`, a time, a second `schedule`) | `/schedule /list cannot be combined with other switches` |
   | 5 | `schedule` and `cancel`: no token after `cancel`, or it is switch-like | `/schedule /cancel requires a plan id` |
   | 6 | `schedule` and `cancel`: anything else present | `/schedule /cancel cannot be combined with other switches` |
   | 6b | `schedule` and `trust`: anything else present except at most one non-switch token directly after `trust` | `/schedule /trust cannot be combined with other switches` |
   | 6c | `schedule` and `untrust`: no token after `untrust`, or it is switch-like | `/schedule /untrust requires an account` |
   | 6d | `schedule` and `untrust`: anything else present | `/schedule /untrust cannot be combined with other switches` |

   Then the existing rows 7–11 run unchanged.
3. **Accepted forms** return `Options(Array.Empty<string>())` with exactly one new field set and every other field at its default:
   `/runplan <id>` → `RunPlan = <id>`; `/schedule /list` → `ScheduleList = true`; `/schedule /cancel <id>` → `ScheduleCancelId = <id>`;
   `/schedule /trust` → `ScheduleTrust = true`; `/schedule /trust <acct>` → `ScheduleTrust = true, ScheduleTrustAccount = <acct>`;
   `/schedule /untrust <acct>` → `ScheduleUntrust = <acct>`. Ids and accounts are not validated by the parser (run time does it).
   Token order is free (`/list /schedule` = `/schedule /list`); the id or account is the token directly after its switch.
4. **`Options`** (`Options.cs`) gains, appended after `ScheduleZone` and defaulted: `bool ScheduleList = false,
   string? ScheduleCancelId = null, string? RunPlan = null, bool ScheduleTrust = false, string? ScheduleTrustAccount = null,
   string? ScheduleUntrust = null`.
5. **Usage**: in `UsageText`, directly after the two existing `/schedule <time>` lines, add exactly:
   ```
     /schedule /list     Show scheduled purges
     /schedule /cancel <id>  Cancel a scheduled purge
     /schedule /trust ["acct"]  Trust a folder writer (or list them)
     /schedule /untrust "acct"  Stop trusting one
   ```
   `/runplan` is not in usage. Every usage line stays ≤ 80 columns (`ArgParserTests.cs:249-252`).
6. **Interim refusal.** New pure helper in `Schedule.cs`: `public static string? Schedule.NotAvailableForm(Options o)` returns
   `/runplan`, `/schedule /list`, `/schedule /cancel`, `/schedule /trust` or `/schedule /untrust` when the matching new field is set
   (that order when several), else null. In `src/Dirused.Cli/Program.cs`, immediately after the parser returns `Options` and before
   the path checks (`Program.cs:60`): `if (Schedule.NotAvailableForm(options) is { } form) { error.WriteLine($"{form} is not available
   in this version"); return 1; }`. M10b3 replaces this.
7. **Size line**: `Schedule.cs:34` prints `<n> file(s), <size> in the list` (live check 2026-11-24: a listed row had already gone).
   `docs/purge.md:17` example updated to match. No other preview change.

## Files

- `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`, `src/Dirused.Common/Schedule.cs`, `src/Dirused.Cli/Program.cs`
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`, `tests/Dirused.Tests.Portable/ScheduleTests.cs`
- `tests/Dirused.Tests/ProgramScheduleRefusalTests.cs` (new; Windows-only project, runs on the windows CI job)
- `docs/purge.md`

## Contract readers

- `ArgParserTests.cs:328-329` (`/schedule /list` and `/schedule /cancel x` expect `/schedule requires /fromlist`) and
  `ScheduleTests.cs:53-54` (`/schedule /list` → `/schedule requires /fromlist`; `... 22:30 /list` → `Unknown switch: /list`): these four
  assertions change to rows 4/5 behaviour (`/schedule /list` accepted; `/schedule /cancel x` accepted; `... 22:30 /list` → row 4). No
  other existing assertion changes.
- Size line: `ScheduleTests.cs` exact-preview expectations and `docs/purge.md:17`.
- `ArgParser.cs:155` (the `/fromlist` branch's own `schedule` handling) is unchanged; rows 1–6d run before it.

## What NOT to Do

- No other file; no new command behaviour (only the Program refusal); do not touch `Purge.cs`, `PurgeList.cs`, `TaskXml.cs`.
- Tests: writers with `NewLine = "\n"` and literal `"\n"` expectations; no `Environment.NewLine` in changed test files.
- Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: P-M1
    text: "each row 1, 2, 3, 3a, 4, 5, 6, 6b, 6c, 6d gives its exact error, one assertion per row: ['/runplan','a','/runplan','b'] and ['/runplan','a','/json'] → row 1; ['/runplan'] and ['/runplan','/x'] → row 2; ['/list'] and ['/cancel','x'] → row 3; ['/trust'] and ['/untrust','a'] → row 3a; ['/schedule','/list','22:30'] and ['/schedule','/list','/trust'] → row 4; ['/schedule','/cancel'] and ['/schedule','/cancel','-v'] → row 5; ['/schedule','/cancel','x','/json'] → row 6; ['/schedule','/trust','a','b'] and ['/schedule','/trust','/json'] → row 6b; ['/schedule','/untrust'] → row 6c; ['/schedule','/untrust','a','/list'] → row 4 (row order) and ['/schedule','/untrust','a','/json'] → row 6d"
  - id: P-M2
    text: "accepted forms give Options with exactly the one field set and every other field equal to a default Options(Array.Empty<string>()): ['/runplan','20261123-2230-a1b2'], ['/schedule','/list'], ['/list','/schedule'], ['/schedule','/cancel','20261123-2230-a1b2'], ['/schedule','/trust'], ['/schedule','/trust','PROD\\\\Domain Admins'] (one token with a space), ['/schedule','/untrust','S-1-5-21-1-2-3-1104']"
  - id: P-M3
    text: "M10b0 rows 7-11 unchanged: every existing ArgParserTests and ScheduleTests assertion passes except the four listed under Contract readers, which assert the new behaviour"
  - id: P-M4
    text: "UsageText contains the four new lines exactly, directly after the existing /schedule <time> lines; no usage line exceeds 80 columns; '/runplan' does not appear in UsageText or ShortUsageText"
  - id: P-M5
    text: "Schedule.NotAvailableForm returns the right form for each of the six accepted Options and null for a default Options and for an M10b0 '/fromlist l /purge /schedule 22:30' Options (Portable). On Windows CI, ProgramScheduleRefusalTests runs Program.RunWithPurge with each accepted form: stderr '<form> is not available in this version', stdout empty, returns 1, the fake purge file system records no call"
  - id: P-M6
    text: "the M10b0 preview prints '            12 file(s), 176.2 GB in the list' (12-space indent as before) and is otherwise byte-identical to the M10b0 expectations; docs/purge.md example line matches"
must_not:
  - id: P-N1
    text: "'/schedule /list' still returns '/schedule requires /fromlist'. Baseline red on e19783f (ScheduleTests.cs:53 asserts exactly that). Positive control: '/schedule 22:30' without /fromlist still returns '/schedule requires /fromlist'"
  - id: P-N2
    text: "an accepted new form reaches the scan or purge path in Program (fake purge file system records a call). Mutant-only (the fields do not exist on e19783f): removing the Program refusal line turns ProgramScheduleRefusalTests red on Windows CI; making NotAvailableForm return null for ScheduleList turns the Portable test red"
evidence:
  - id: E-P
    proves: [P-M1, P-M2, P-M3, P-M4, P-M5, P-M6, P-N1, P-N2]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4; new tests red on e19783f; mutants each red: row 4 checked after row 6b; row 3a removed; ScheduleTrustAccount not set; Program refusal removed; size line without 'in the list'"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling, dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."
  - id: E-PW
    proves: [P-M3, P-M5, P-N2]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit, including ProgramScheduleRefusalTests"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "/runplan cannot be combined with other switches"
  - "/runplan requires a plan id"
  - "/list and /cancel go with /schedule"
  - "/trust and /untrust go with /schedule"
  - "/schedule /list cannot be combined with other switches"
  - "/schedule /cancel requires a plan id"
  - "/schedule /cancel cannot be combined with other switches"
  - "/schedule /trust cannot be combined with other switches"
  - "/schedule /untrust requires an account"
  - "/schedule /untrust cannot be combined with other switches"
  - "Schedule.NotAvailableForm(Options) -> string?"
  - "<form> is not available in this version"
  - "<n> file(s), <size> in the list"
```
