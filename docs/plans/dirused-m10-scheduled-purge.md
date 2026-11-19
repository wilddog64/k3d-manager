# dirused M10: schedule a reviewed purge to run later (e.g. after 7:00 PM Pacific)

**Status:** DRAFT — operator request 2026-11-19; waits for M9 (operator: "let's wait for M9"); then spec review
(Fable + Astra blind: high risk, it deletes files unattended and stops production services), then intent approval
**Tracked:** dirused (OOB repo), not a k3d-manager release.
**Depends on:** M8b, and M9 (`docs/plans/dirused-m9-purge-stop-service-for-locked-files.md`) merged and released.
**Filed:** 2026-11-19
**Intent approved:** no

## Why

Operator, 2026-11-19: "if we hunt down large file on ffm01, is it possible to schedule a delete large files said after
7:00 PM PST?" Then: "this include stop tomecat, delete largest files if there are tomcat logfiles and java heap dump,
then start tomcat. ensure tomcat start without issue".

## Operator decisions (2026-11-19)

- **Delete only the reviewed list.** The scheduled run deletes only files from the list the operator saw. It never
  deletes new matches found at run time.
- **Wait for M9.** Held Tomcat logs and heap dumps are handled by M9's stop, delete, start and health check, run
  unattended at the scheduled time.

## Proposed behaviour (draft)

1. `dirused <targets> /largest <patterns> /purge [days] /schedule <time>` runs the dry run now and shows the list. It then writes
   a plan file with each file's path, size, last-modified time and file ID, the M9 service it would stop, and the original
   arguments. The plan goes under `%LOCALAPPDATA%\dirused\plans\`, with an ACL for the current user only.
   It asks `Schedule deleting these N file(s), SIZE, at 19:00 PST (Tue 2026-11-19)? [y/N]` (`/yes` skips the prompt).
2. On yes, it registers a one-time Windows scheduled task (Task Scheduler COM API, not a `schtasks` string) that runs
   `dirused /runplan <plan file>` as the current user, with "run whether logged on or not" (Windows asks for the password).
3. `/runplan` deletes only files in the plan. Each file still passes all of M8's checks, plus a file-ID match.
   - A file that changed since the review is skipped. The exception is M9's held-Tomcat-file path, where the stop happens
     first. Live logs change constantly, so the rule for them is settled at spec review: at minimum it is the same
     file ID and the size has not shrunk.
   - The run writes the M8 purge log and a run report next to the plan.
4. **Time:** `<time>` is `HH:MM` with an optional zone (`PST`/`PDT`/`PT`, or `UTC`). A bare `HH:MM` is accepted only when
   the laptop's time zone is Pacific; otherwise it is refused with a message asking for the zone. A time already passed
   today means tomorrow, and the prompt shows the full date.
5. `dirused /schedule /list` shows pending plans with their time, host, file count and size. `dirused /schedule /cancel <id>` removes
   the task and the plan.
6. **Plan expiry:** a plan more than 24 h old when it runs deletes nothing and reports `expired`.

## Open points for the spec review

- The changed-file rule for live logs (point 3).
- Running unattended needs stored credentials, or "run only when logged on". Choose one, and say what happens if the
  laptop sleeps or is off at 19:00 (Task Scheduler's "run as soon as possible after a missed start").
- How the operator learns the result: the run report file only, or also a Windows toast or email.
- The test seam: an `ITaskScheduler` fake for portable tests; registering a real task on CI.

## Amendment 1 (operator, 2026-11-19): name is `/schedule`; same release as M9

Operator, after the v0.0.20 live check: "can we add a /schedule so that we can schedule delete largest files at a given time?
also handle tomcat stop and start". The switch is `/schedule <time>` (was `/at`), with `/schedule /list` and
`/schedule /cancel <id>`. The scheduled run includes M9's Tomcat stop, delete and verified start. M10 still lands after M9,
since `/runplan` calls the M9 path; both go to spec review together once M9's proofs are in.
