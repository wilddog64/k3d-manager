# dirused M10b4a: scheduled purge docs

**Status:** OPEN — SPEC rev 1, 2026-11-25; awaiting blind review and intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b4](dirused-m10b4-docs.md). Read the parent's "Contract between the children"; it is repeated below because the worker cannot read the parent.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (base `009fb14`)
**Risk:** low — docs only
**Implementer:** Flash (`--agent agy --model gemini-3.8-flash-medium`)
**Verifier:** Claude, offline
**Filed:** 2026-11-25
**Intent approved:** pending
**Approval:** operator, 2026-11-25 — split across Flash and Luna

## Contract (from the parent)

You write only `docs/purge.md`, `README.md` and `CHANGELOG.md`. A sibling task adds a test that will check:

1. Every `ArgParser.UsageText` line starting with `  /schedule`, with its indented continuation lines
   (`src/Dirused.Common/ArgParser.cs:70-75`), appears verbatim in `README.md`, ignoring line endings.
2. Each of these appears verbatim in `docs/purge.md`: `refused: error during run`, `refused: list changed since it was scheduled`,
   `refused: not a dirused plan`, `refused: not a plan id`, `refused: not started from the plan's program copy`,
   `refused: not the scheduled time`, `refused: plan already has a report`, `refused: plan already started`,
   `refused: plan folder contains a link`, `refused: plan folder permissions changed`,
   `refused: program copy changed since it was scheduled`.
3. Each `/schedule /list` state appears in `docs/purge.md`: `scheduled`, `running`, `done (`, `cancelled`, `missed (did not run)`,
   `task missing`, `interrupted (`, `permissions changed — not run`, `unreadable plan`.
4. `docs/purge.md` has the heading `## Scheduled purge`.

## Change

Read the code before writing; do not describe behaviour you have not found in it. Sources: `src/Dirused.Common/ArgParser.cs`,
`SchedulePlans.cs`, `PlanRunner.cs`, `src/Dirused.Cli/Program.cs`, and the tests named `Schedule*`, `RunPlan*`, `PlanTrust*`,
`Schtasks*` under `tests/Dirused.Tests.Portable/`.

- `docs/purge.md`: replace `## Scheduled purge (preview)` with `## Scheduled purge`. Its text that `/confirm` "reports that
  scheduling is unavailable and schedules nothing" is no longer true; remove it. Cover, each as a short subsection:
  - The three forms: preview (`/fromlist <file> /purge /schedule <time> [zone]`), `/confirm`, and `/confirm /yes`, with a preview
    shown as the program prints it. Keep the existing time and zone rules (2 minutes to 23 hours 45 minutes ahead; bare time,
    `PT`, `PST`, `PDT`, `UTC`).
  - Logged-on only: the task runs only while the scheduling user is logged on. Disconnected (RDP closed) is fine; signed out means
    the plan shows `missed (did not run)`. No password is stored.
  - Held files are skipped and Tomcat is never stopped or started by a scheduled run.
  - The plan folder and the program copy: where they are, what is in them, and why the run uses the copy (the plan is checked
    against the copy and the list, so a changed program or list is refused).
  - `/schedule /list`: one line per plan (id, Pacific time, host, state, file count and size, list name), then a table of every
    state in contract item 3 with what it means and what to do.
  - `/schedule /cancel <id>`.
  - `/schedule /trust ["acct"]` and `/schedule /untrust "acct"`: what a trusted folder writer is and when you need one.
  - `/runplan <id>`: run by the scheduled task, not by hand. A table of every refusal in contract item 2, each with its cause and
    what to do.
  - The report: where it is written and its fields (`outcome`, `result`, `exit`).
  - Scheduling per node: the host comes from the list's UNC paths; a list naming more than one host is refused; save one list per
    server with `/savelist` and schedule each. Give a worked example with two servers. `/schedule /list` shows each plan's host.
  - Known limits: a console window may flash at run time; old plan folders are not cleaned up yet.
- `README.md`: replace the two `/schedule` lines with every `/schedule` line from `UsageText` (contract item 1), copied
  verbatim. Add one example: preview, then the same command with `/confirm`.
- `CHANGELOG.md`: under `[Unreleased]`, replace the "scheduling is not available yet" bullet with bullets for M10b1–M10b3
  (scheduled runs with `/confirm`, `/schedule /list`, `/schedule /cancel`, `/schedule /trust` and `/untrust`, the plan folder and
  program copy, `/runplan` refusals). No new version header.

## Files

`docs/purge.md`, `README.md`, `CHANGELOG.md` only. Do not edit code or tests.

## Acceptance

```yaml
must:
  - id: B4a-M1
    text: "docs/purge.md has a '## Scheduled purge' section covering every bullet in Change, including the two-server example; every string in contract items 2 and 3 appears in it"
  - id: B4a-M2
    text: "README.md contains every UsageText /schedule line verbatim, and one preview-then-confirm example"
  - id: B4a-M3
    text: "CHANGELOG.md [Unreleased] has the M10b1-M10b3 bullets, no 'not available yet' bullet, and no new version header"
must_not:
  - id: B4a-N1
    text: "docs/purge.md says scheduling is unavailable or that /confirm schedules nothing"
  - id: B4a-N2
    text: "any file outside docs/purge.md, README.md, CHANGELOG.md changes"
evidence:
  - id: E-B4a
    proves: [B4a-M1, B4a-M2, B4a-M3, B4a-N1, B4a-N2]
    kind: offline
    command: "git diff --stat 009fb14..HEAD lists only the three files; for each string in contract items 2 and 3, grep -F finds it in docs/purge.md; for each UsageText /schedule line, grep -F finds it in README.md; grep -i 'unavailable\\|schedules nothing' docs/purge.md returns nothing; grep -c '^## \\[' CHANGELOG.md is unchanged from 009fb14"
    intent: "The guide tells you how to preview, schedule, check and cancel a purge, why held logs are skipped, and what each state and refusal means."
interface:
  - "docs/purge.md#scheduled-purge"
```
