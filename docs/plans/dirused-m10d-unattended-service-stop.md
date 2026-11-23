# dirused M10d: unattended service stop/start for held logs in scheduled runs

**Status:** DRAFT — operator decision 2026-11-23; starts after M10b is live-verified (M10b3 E-B3L2); then spec and blind review
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) (D9, D11); [M9b](dirused-m9b-stop-delete-start.md) (attended stop/delete/start)
**Repo / branch:** wilddog64/dirused / TBD
**Risk:** high — stops a production service with nobody watching
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** operator, 2026-11-23 — "Skip held files for now" (moved here from M10b); "Held Tomcat logs only" (growth relaxation here)

## What moves here from M10b

- A scheduled run stopping the holding service, deleting held rows, and starting it again (M9b's path, unattended).
- The growth relaxation for held Tomcat logs: a held log that grew since the list may still be deleted if it is the same file (volume
  and ID), larger and newer. Ordinary rows never get it.
- Rev 1 review findings made moot in M10b by D9: Astra A-B5 (every pre-stop check must run before Stop, and the 19:00–06:00 window
  must use the target's or Pacific time, not the machine's), Astra A-B6 (a killed run leaves Tomcat stopped), Fable F-S1/A-S3 (growth
  relaxation must not bypass the age rule), bytes freed under growth.

## Must be solved before this becomes a spec

1. **Recovery that survives a killed process.** If the run is killed between Stop and Start (task time limit, logoff, reboot, crash),
   the service must come back without the operator. Candidates: a second "restore" task registered before Stop and removed after Start;
   a stop marker checked at the next logon; service recovery options. The chosen path is **proven on a disposable service** (a test
   service created for the probe, never Tomcat) by killing the run mid-stop, before any spec is dispatched.
2. Every pre-stop check (identity, age, size, revalidation) runs before `Stop`; a row failing them never causes a stop.
3. Which time the window uses, and how it interacts with the plan's run instant.
4. Live evidence plan with the operator present for the first unattended stop.

## Option: register the task on the target node (operator 2026-11-23, "Both"; not designed further)

Instead of the jump box, dirused is installed on the server (e.g. us03p02ffm01) and the task is registered there, running as S4U (no
stored password; local resources only, which is enough because the logs are local) or SYSTEM. Needs "Log on as a batch job" for the
account, or admin setup.

- **This is a production change:** installing dirused and registering a task on the server needs the server owner's approval.
- **Trade-off vs jump-box execution:** no dependency on the operator's RDP session (no `missed` on logoff or reboot of the jump box),
  and a local stop/start is a stronger base for the kill-surviving recovery path above (the service and the recovery task live on the
  same machine). Cost: software on a production server, a second place to update, and a service account decision.
- **Amends** the 2026-11-19 decision "Run only when user is logged on" (M10b D3) for this mode only, while keeping "no stored password".
- Proofs before any design (all on the server, operator-approved; stop/start on a disposable service first, never Tomcat):
  1. an S4U task fires with nobody logged on;
  2. it can delete files under `D:\Tomcat\Tomcat\logs` (a probe file first);
  3. it can stop and start a service locally — proven on a disposable test service, then Tomcat85 only with approval.

## Related

`dirused-m10c-recurring-purge-rules.md` names a service a rule may stop; that part of M10c depends on this milestone.
