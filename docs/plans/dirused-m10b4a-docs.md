# dirused M10b4a: scheduled purge docs

**Status:** OPEN — SPEC rev 2, 2026-11-25; rev 1 reviewed blind by Fable and Argon, fixes applied (see parent's Review log)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b4](dirused-m10b4-docs.md). The parent's contract is repeated below because the worker cannot read the parent.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (base `009fb14`)
**Risk:** low — docs only
**Implementer:** Flash (`--agent agy --model gemini-3.8-flash-medium`)
**Verifier:** Claude, offline
**Filed:** 2026-11-25
**Intent approved:** operator, 2026-11-25
**Approval:** operator, 2026-11-25 — split across Flash and Luna

## Contract (from the parent)

You write only `docs/purge.md`, `README.md` and `CHANGELOG.md`. A sibling task adds a test that checks:

1. `docs/purge.md` has a line exactly `## Scheduled purge`. "The section" is from that line to the next line starting `## `.
2. These six lines appear in `README.md`'s `### Purging listed files` code block, in place of the two `/schedule` lines at
   `README.md:101-102`. Match the block's existing indent (switch at column 0, continuation at column 20, like `/savelist` and
   `/fromlist` above them); the test compares with leading and trailing whitespace trimmed. Write the quotes as plain `"`.
   ```
   /schedule <time>    With /fromlist /purge: preview a one-time run at HH:MM
                       [PT|PST|PDT|UTC]; add /confirm to schedule it
   /schedule /list     Show scheduled purges
   /schedule /cancel <id>  Cancel a scheduled purge
   /schedule /trust ["acct"]  Trust a folder writer (or list them)
   /schedule /untrust "acct"  Stop trusting one
   ```
3. Each of these appears in the section: `refused: error during run`, `refused: list changed since it was scheduled`,
   `refused: not a dirused plan`, `refused: not a plan id`, `refused: not started from the plan's program copy`,
   `refused: not the scheduled time`, `refused: plan already has a report`, `refused: plan already started`,
   `refused: plan folder contains a link`, `refused: plan folder permissions changed`,
   `refused: program copy changed since it was scheduled`.
4. Each of these appears in the section, in backticks exactly as shown (a trailing `(` means your text continues, e.g.
   `` `done (deleted, exit 0)` ``): `` `scheduled` ``, `` `running` ``, `` `done ( ``, `` `cancelled` ``, `` `expired` ``,
   `` `missed (did not run)` ``, `` `task missing` ``, `` `interrupted ( ``, `` `permissions changed — not run` ``,
   `` `unreadable plan` ``, `` `refused: ``. The dash in `permissions changed — not run` is an em dash (U+2014).

## Change

Read the code before writing; do not describe behaviour you have not found in it. Sources in `src/Dirused.Common/`:
`ArgParser.cs`, `Schedule.cs`, `ScheduleCommands.cs`, `SchedulePlans.cs`, `PlanRunner.cs`, `PlanTrust.cs`, `TrustCommands.cs`,
`TaskXml.cs`, `ScheduleWindows.cs`, `Purge.cs`; `src/Dirused.Cli/Program.cs`; and the tests named `Schedule*`, `RunPlan*`,
`PlanTrust*`, `TrustCommands*`, `TaskXml*`, `Schtasks*` under `tests/Dirused.Tests.Portable/`.

- `docs/purge.md`: replace `## Scheduled purge (preview)` and its body with `## Scheduled purge` (contract 1). Today's text that
  `/confirm` "reports that scheduling is unavailable and schedules nothing" is false; remove it. Do not change other sections.
  Cover, each as a short subsection:
  - **Forms:** preview (`/fromlist <file> /purge /schedule <time> [zone]`), `/confirm` (asks y/N), and `/confirm /yes` (no prompt,
    `ScheduleCommands.cs:37-41`). Show a preview as Windows prints it, including the `sha256`, `Task:`, `Plan dir:` and `Program:`
    lines (`ScheduleCommands.cs:23`; expected output in `ScheduleCommandsTests.cs:80-92`). Keep the time rules: 2 minutes to
    23 hours 45 minutes ahead (`Schedule.cs:113-114`); bare time, `PT`, `PST`, `PDT`, `UTC`; a bare time needs the machine set to
    Pacific time (`Schedule.cs:68`).
  - **Where to run it:** from a normal window; an elevated window is refused (`ScheduleCommands.cs:35`). The task runs only while
    you are logged on (`TaskXml.cs:190`); disconnected (RDP closed) is fine; signed out means the plan shows
    `` `missed (did not run)` ``. No password is stored.
  - **Held files:** skipped, and Tomcat is never stopped or started by a scheduled run (`Purge.cs:495-497`).
  - **Plan folder and program copy:** `%LOCALAPPDATA%\dirused\plans\<id>` holding `plan.txt`, `list.txt`, `dirused.exe`, and later
    `claim` and `report.txt` (`ScheduleWindows.cs:172-173`). The run uses the copied program and list, and refuses if either
    changed. A plan expires 24 hours after it is made (`ScheduleCommands.cs:28`).
  - **`/schedule /list`:** one line per plan (id, Pacific time, host, state, file count and size, list name), then a table of
    every state in contract 4 with what it means and what to do.
  - **`/schedule /cancel <id>`.**
  - **`/schedule /trust ["acct"]` and `/schedule /untrust "acct"`:** what a trusted folder writer is and when you need one
    (`PlanTrust.cs`, `TrustCommands.cs`).
  - **`/runplan <id>`:** started by the scheduled task, not by hand, and not listed in `/help`. A table of every refusal in
    contract 3, each with its cause and what to do, plus one row for trust failures: `refused:` followed by the trust message
    (`... can be changed by ...`, `... is a link ...`, `cannot read permissions of ...`; `PlanRunner.cs:91-98`). Also list the
    non-refusal results `cancelled` (exit 0), `expired` and `error: could not claim plan`. Say which results are written to
    `report.txt` (those returned through `Report`/`ReportOutcome`) and which go only to stderr and the purge log (`Refuse`).
  - **Report:** where it is written and its fields `outcome`, `exit`, and `result` (written only when a run happened;
    `PlanRunner.cs:190-193`).
  - **Scheduling per node:** the host comes from the list's UNC paths; a list naming more than one host is refused
    (`Schedule.cs:28`); save one list per server with `/savelist` and schedule each. A worked example with two servers.
    `/schedule /list` shows each plan's host.
  - **Known limits:** a console window may flash at run time (`TaskXml.cs:203`); old plan folders are not cleaned up yet.
- `README.md`: put the six lines from contract 2 in place of `README.md:101-102`. Add one example after the block: a preview,
  then the same command with `/confirm`. Do not edit the `### Switches` block.
- `CHANGELOG.md`: under `[Unreleased]`, replace the bullet saying scheduling "is not available yet" with bullets for scheduled runs
  with `/confirm`, `/schedule /list`, `/schedule /cancel`, `/schedule /trust` and `/untrust`, the plan folder and program copy, and
  `/runplan` refusals. No new version header.

## Files

`docs/purge.md`, `README.md`, `CHANGELOG.md` only. Do not edit code or tests.

## Acceptance

```yaml
must:
  - id: B4a-M1
    text: "docs/purge.md has a line exactly '## Scheduled purge' whose section covers every bullet in Change, including the two-server example, and contains every string in contract 3 and every backticked string in contract 4"
  - id: B4a-M2
    text: "README.md's '### Purging listed files' block contains the six contract 2 lines (trimmed match) and one preview-then-confirm example"
  - id: B4a-M3
    text: "CHANGELOG.md [Unreleased] has the scheduled-purge bullets, no 'not available yet' text, and no new version header"
must_not:
  - id: B4a-N1
    text: "The '## Scheduled purge' section says scheduling is unavailable or that /confirm schedules nothing"
  - id: B4a-N2
    text: "Any file outside docs/purge.md, README.md, CHANGELOG.md changes, or a docs/purge.md section other than the scheduled-purge one changes"
evidence:
  - id: E-B4a
    proves: [B4a-M1, B4a-M2, B4a-M3, B4a-N1, B4a-N2]
    kind: offline
    command: "git diff --stat 009fb14..HEAD lists only the three files; git diff 009fb14..HEAD -- docs/purge.md touches only lines inside the scheduled-purge section; with S = sed -n '/^## Scheduled purge$/,/^## /p' docs/purge.md: grep -F finds each contract 3 and contract 4 string in S, and grep -i -E 'scheduling is unavailable|schedules nothing' finds nothing in S; each contract 2 line, trimmed, is found in README.md; grep -c 'not available yet' CHANGELOG.md is 0 (1 at 009fb14); grep -c '^## \\[' CHANGELOG.md is 11 (unchanged). Coverage of each Change bullet is judged by the verifier reading the section."
    intent: "The guide tells you how to preview, schedule, check and cancel a purge, why held logs are skipped, and what each state and refusal means."
interface:
  - "docs/purge.md#scheduled-purge"
```
