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

## Amendment 2 (operator, 2026-11-19): dirused runs on the office jump box, not a laptop

Operator: "this is not going to run from my laptop as it is running from office jump box". Every "laptop" above means the
jump box; the plan dir is `%LOCALAPPDATA%\dirused\plans\` on the jump box. The jump box is always on and on the server
network, so the laptop-asleep/VPN concern goes away and running the task on the jump box becomes the default (no copy of
dirused on each server). The remaining risk is credentials: a task that opens `\\server\d$` needs the operator's network
identity, so it runs either "only when logged on" (works while the jump-box session is open or disconnected, fails after
logoff) or "whether logged on or not" with a stored password (needs the "Log on as a batch job" right; breaks at password
rotation). Which one the jump box allows is an operator check, recorded before spec review. Bare `HH:MM` uses the jump
box's time zone rule from point 4.

## Amendment 3 (operator, 2026-11-19): session, one-time, and a reviewable delete list

1. **Session:** "disconnect will not logout account". The task uses "run only when the user is logged on", with no stored
   password. If the session has been logged off by 19:00, the task does not run and the next `/schedule /list` shows it missed.
2. **One-time only:** each `/schedule` registers a single run at one time; no repeat option. A repeat would delete files
   nobody reviewed.
3. **Delete list instead of patterns (operator: "what if next time the pattern changed and not in our list? ... files to
   delete should store in a delete.txt"):** proposed flow, pending operator confirmation:
   - `dirused <targets> /largest <patterns> /purge /out delete.txt` writes the would-delete rows to a plain text file, one
     file per line, tab-separated: size, modified time, file ID, path. A comment header records host list, date and arguments.
   - The operator reviews it and may delete lines. Lines added by hand (no matching file ID) are refused at use.
   - `dirused /purge /list delete.txt /confirm` deletes now; `dirused /purge /list delete.txt /schedule 19:00 PST` schedules.
     `/list` takes no patterns; the list is the whole selection.
   - At schedule time dirused copies the list into the plan directory and the task uses that copy, so later edits to
     delete.txt do not change a scheduled run (to change it: `/schedule /cancel <id>`, edit, schedule again).
   - At run time each line still passes the M8 checks, same file ID, size not smaller than in the list, plus M9's
     stop/delete/start for held Tomcat files.
