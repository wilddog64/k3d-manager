# dirused M10c: recurring purge rules (reviewed once, renewed every 30 days)

**Status:** DRAFT — operator request 2026-11-23; waits for M10b live-verified (M10b E2); then spec review
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** `docs/plans/dirused-m10-scheduled-purge.md`; builds on `docs/plans/dirused-m10b-scheduled-purge.md` (one-time plans) and
`docs/plans/dirused-m9b-stop-delete-start.md` (stop/delete/start).
**Repo / branch:** wilddog64/dirused / TBD
**Version:** TBD (after v0.0.27)
**Risk:** high — repeated unattended deletes and service stops
**Review:** Fable + Astra blind, Claude adjudicates (when it becomes a spec)
**Implementer:** TBD
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** operator, 2026-11-23 — reverses Amendment 3's "one-time only" for rules (below)

## Why, and what it reverses

Operator, 2026-11-23: "if we find a pattern of log file growing can we schedule to delete it at the desired time". Amendment 3
and M10b allow one-time runs only, each over a list the operator reviewed. This draft reverses "one-time only" by operator decision
2026-11-23, with a different safety model: instead of reviewing a list of files each time, the operator reviews a **rule** once,
and the rule is narrow enough that what it can match is known in advance. M10b stays as it is (one-time, list only); M10c adds a
second kind of schedule beside it.

## Rule-instead-of-list safety model (to be specified)

A rule is reviewed once and holds:
- **Host** and an **exact folder** (e.g. `\\us03p02ffm01\d$\Tomcat\Tomcat\logs`). Wildcards in the folder are refused; no recursion
  into subfolders.
- A **filename pattern** that names the file kind (e.g. `tomcat85-stderr.*.log`). Broad patterns are refused: `*`, `*.*`, `*.log`
  alone, or any pattern without a literal name part (exact refusal rule to be written in the spec).
- The **one service** allowed to be stopped for held matches (e.g. `Tomcat85`), or none. Held matches for any other service are
  skipped.
- **Time and recurrence** (e.g. daily 22:30 PT), zone rules as M10b §3.
- **Minsize** (files below it are not touched).
- A **per-run cap** on bytes and on file count. Over either cap → delete nothing that run, report `over cap`.
- **Expiry: 30 days.** An expired rule deletes nothing and reports `rule expired`; the operator renews it (re-review) to continue.

Each run writes a report (matched files, deleted files and bytes, skipped with reasons, service stop and start times, health
result), and `/schedule /list` shows the rule with its last result and next run.

Open points for the spec: how a rule is shown for review and stored (ACL as M10b plan dir); identity checks without a list (age
gate, the M9b classification); whether a run that would stop the service needs the M9b 19:00–06:00 window; how the rule and its
task are renewed and cancelled; caps per run vs per day.

## Truncate in place instead of stop/delete/start (probe first)

An alternative for held Tomcat redirect logs: truncate the file to zero without stopping Tomcat. It is designed only after the
probe below answers; until then it is not in scope.

**P-T1 (operator approved 2026-11-23, read-only, operator runs it on us03p02ffm01):** can the held `tomcat85-stderr`/`-stdout` log
be truncated while Tomcat runs, and would writes continue at the new end of file?

1. Share mode of the holding handle. Truncating needs a write open, which works only if every open handle shares write
   (`FILE_SHARE_WRITE`). On us03p02ffm01, elevated, if Sysinternals Handle is already there:
   `handle64.exe -accepteula -nobanner -p Tomcat85.exe tomcat85-std` — record each line; the `(RWD)`-style field is the handle's
   share flags (R = read, W = write, D = delete shared). If Handle is not on the server, copying it there is a change to an
   outward-facing system: the operator decides; otherwise use step 2 only.
2. Granted access of the holding handle (whether the writer opened with append-only access, `FILE_APPEND_DATA` 0x4 without
   `FILE_WRITE_DATA` 0x2). Process Explorer (if present) → select `Tomcat85.exe` → lower pane Handles → add the "Access" and
   "Share Flags" columns → record the row for each redirect log. If the column is not available, say so.
3. Versions, for the upstream-source half: file version of `D:\Tomcat\Tomcat\bin\Tomcat85.exe` (commons-daemon procrun) and of the
   JVM it runs (`Get-Item ... | Select-Object -ExpandProperty VersionInfo`, and the `JavaHome`/`Jvm` value from
   `reg query "HKLM\SOFTWARE\WOW6432Node\Apache Software Foundation\Procrun 2.0\Tomcat85\Parameters\Java"`).
4. No writes, no truncation, no restart in the probe.

**P-T2 (Claude, offline, after P-T1 step 3):** at those exact versions, read the commons-daemon procrun source (how it redirects
stdout/stderr: `_wfreopen` with `"a"` or its own `CreateFile`) and the JVM's stdout/stderr write path (Windows `WriteFile` on the
std handle, with or without seeking to the end). Answer: after an external truncate, does the next write land at offset 0, or at
the old offset (which would leave a zero-filled gap as large as the old file, freeing nothing)?

Only if P-T1 shows write sharing and P-T1/P-T2 show append-at-end does truncation become a purge mode in this spec.

## Not in M10b

M10b does not depend on this draft. This draft does not start until M10b's E2 live check passes.
