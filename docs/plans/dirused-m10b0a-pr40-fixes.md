# dirused M10b0a: PR #40 fixes (Windows newline tests, DST roll-over, host and parser edge cases)

**Status:** OPEN — SPEC rev 1, 2026-11-24
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b0](dirused-m10b0-schedule-preview-only.md) (landed `c8520de` on `m10b0-schedule-preview`, PR #40). Same feature, same intents.
**Repo / branch:** wilddog64/dirused / `m10b0-schedule-preview` (tip `c8520de`)
**Risk:** low — same preview code; no I/O added
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the PR's windows CI job
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries M10b0's approved E-B0 intent unchanged; these are fixes inside that behaviour found by the PR review and windows CI.
**Approval:** operator, 2026-11-24 — M10b0 PR flow ("preview first then move to actual scheduling")

## Why

PR #40's windows CI failed 3 tests, and Argon's blind PR review (CHANGES REQUESTED) found four real edge cases. Adjudication:
Argon 1 (`}/schedule` syntax error) rejected — the file ends `}\n` and portable CI compiles it; Argon 5 (test Program's list read)
rejected — the spec has Program read the list once by design; its source-scan widening is accepted (item 6).

## Scope (all in `Schedule.cs`, `ArgParser.cs` and their tests)

1. **Windows newlines in tests.** Tests assert strings ending in `"\n"` but `TextWriter.WriteLine` writes `Environment.NewLine`
   (`"\r\n"` on Windows): `ConfirmPreviewDoesNotClaimToSchedule`, `ConfirmAndYesAlsoRefusesScheduling`,
   `RejectsMultipleHostsAndEmptyLists` fail on windows CI. Fix the tests, not the product: set `NewLine = "\n"` on every
   `StringWriter` the M10b0 tests create (or build expectations with `Environment.NewLine`). Check every assertion added in
   `ScheduleTests.cs` and `ArgParserTests.cs` for the same issue.
2. **DST roll-over by instants** (PT and bare-time branch). "Already passed" is decided by instants, not wall-clock compare:
   - Fall-back day, today's HH:MM ambiguous: if its later (PST) occurrence is after `created`, refuse with
     `/schedule: <date> <HH:MM> happens twice in Pacific time; write PST or PDT`; roll to tomorrow only when both have passed.
   - Spring-forward day, today's HH:MM in the gap: if `created` is before the gap's end (03:00 PDT), refuse with
     `/schedule: <date> <HH:MM> does not exist in Pacific time (clocks go forward); pick another time`; otherwise roll to tomorrow.
3. **Bad list lines with `/confirm`:** print the preview (without its last line), then the `Bad list lines:` block on stderr, then
   the not-available line on stderr, exit 1. (Without `/confirm` unchanged: preview, block, exit 3.)
4. **Host of device or malformed paths** (`GetHost`): `\\.\X:\...` → `this machine`. A UNC path whose server part is empty, `.`
   or `?` (`\\`, `\\\x`, `\\?\UNC\`, `\\.\pipe\x`) → stderr `/schedule: cannot tell which server <path> is on`, no stdout, exit 1,
   checked with the other host rules before the time rules.
5. **Parser row 9:** any switch-like token after `/schedule` (starts with `/` but not `//`, or `-`; the same test `IsFlag` and
   `MissingPath` use) gives `/schedule requires a time, e.g. /schedule 22:30 PT`. Today only four named switches are checked
   (`ArgParser.cs:129`).
6. **Source scan** in `PreviewDoesNotTouchListOrRowPathsOrUseIoApis` also refuses `FileInfo`, `DirectoryInfo`, `FileStream`,
   `StreamWriter`, `StreamReader`, `System.IO.File`, `DllImport`, `TaskService`.
7. `CHANGELOG.md` `[Unreleased]` line unchanged unless wording needs the new host message; `docs/purge.md` gains one line: a
   list whose server cannot be read is refused.

## Files

- `src/Dirused.Common/Schedule.cs`
- `src/Dirused.Common/ArgParser.cs`
- `tests/Dirused.Tests.Portable/ScheduleTests.cs`
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `docs/purge.md`

## What NOT to Do

- No I/O in `Schedule.Run`; no new parameters; no change to Program.cs, Purge.cs or PurgeList.cs.
- Do not weaken or delete an existing test; only fix newline expectations.
- Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: A-M1
    text: "every M10b0 test passes with writers whose NewLine is '\\r\\n' as well as '\\n' (the worker shows a scratch run with the test StringWriters forced to NewLine='\\r\\n' passing, simulating Windows), and the PR's windows CI job is green on the new head"
  - id: A-M2
    text: "created 2026-11-01 01:45 -07:00, '/schedule 01:30 PT' → stderr '/schedule: 2026-11-01 01:30 happens twice in Pacific time; write PST or PDT', exit 1; created 2026-11-01 00:30 -07:00, '01:30 PT' → same message; created 2026-11-01 01:15 -08:00, '01:30 PT' → same message; created 2026-11-01 03:00 -08:00, '01:30 PT' → rolls to 2026-11-02 01:30 PST (accepted, 22 h 30 min); created 2026-03-08 01:00 -08:00, '02:30 PT' → '/schedule: 2026-03-08 02:30 does not exist in Pacific time (clocks go forward); pick another time'; created 2026-03-08 05:00 -07:00, '02:30 PT' → accepted for 2026-03-09 02:30 PDT"
  - id: A-M3
    text: "a list with 2 bad lines and '/confirm': stdout = preview without its last line; stderr = 'Bad list lines:' block then the not-available line; exit 1"
  - id: A-M4
    text: "'\\\\.\\C:\\x' rows → 'Host:     this machine'; rows '\\\\', '\\\\\\x', '\\\\?\\UNC\\', '\\\\.\\pipe\\x' each → stderr '/schedule: cannot tell which server <path> is on', stdout empty, exit 1"
  - id: A-M5
    text: "'/fromlist l /purge /schedule /html', '/fromlist l /purge /schedule -x' and '/fromlist l /purge /schedule /bogus' each give '/schedule requires a time, e.g. /schedule 22:30 PT'"
must_not:
  - id: A-N1
    text: "the fall-back case created 2026-11-01 01:45 -07:00 with '01:30 PT' is accepted or reported 'too far away'. Positive control: created 2026-11-01 03:00 -08:00 is accepted for the next day. Baseline red on c8520de (reports 'too far away')"
  - id: A-N2
    text: "Schedule.cs contains any of File., Directory., Console., Process., Registry, FileInfo, DirectoryInfo, FileStream, StreamWriter, StreamReader, System.IO.File, DllImport, TaskService. Positive control: mutant adding 'new FileInfo(row.Path)' turns the scan red"
evidence:
  - id: E-A
    proves: [A-M1, A-M2, A-M3, A-M4, A-M5, A-N1, A-N2]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4 and the PR windows CI job; new tests red on c8520de where behaviour changed (A-M2 fall-back, A-M3, A-M4, A-M5); mutants red: wall-clock roll-over restored; /confirm returns before bad lines; empty host accepted; row 9 limited to the four named switches; FileInfo in Schedule.cs"
    intent: "You type /schedule with a time and see exactly when the purge would run (Pacific and UTC, and how long from now), which server, how many files and how much space — and nothing is scheduled, written or touched on the server. Adding /confirm tells you scheduling is not in this version yet."
interface:
  - "/schedule: cannot tell which server <path> is on"
```
