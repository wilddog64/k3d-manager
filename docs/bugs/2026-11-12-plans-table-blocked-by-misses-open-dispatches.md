# Plans table "Blocked by" misses open dispatches: hub exporter has no ledger, and a late agent exit reopens an abandoned task

**Status:** OPEN — captured 2026-11-12
**Priority:** P3 (proposed: the column says "ready to dispatch" for plans that share files with a running dispatch; Claude checks `dispatch open` before dispatching, so no wrong dispatch has happened)
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** unknown (overlap check from `docs/plans/v1.43.8-plans-table-dispatch-waves-and-file-overlaps.md`)
**Should have been caught by:** spec
**Prior art:** not run (`make find-similar-docs` from m4-air: "vector store error: context k3d-k3d-cluster does not exist"); exact slug: none
**Component:** `bin/k3dm-vectordb-metrics` (`_open_plan_dispatches`, `_dispatch_ledger_path`), run on the hub by `bin/k3dm-hermes`

## Symptom

2026-11-12, operator screenshot of the Bugs dashboard Plans table: `dev-hub-vcluster` and `hub-deploy-one-command` show
"ready to dispatch" while the running `test-hygiene-batch` dispatch holds `Makefile`, which both plans also edit.

Running the same exporter on m4-air (where the ledger is) gives `waits on 2026-11-12-test-hygiene-batch-… (Makefile)` for
`dev-hub-vcluster`, so the check works there. It also gives `hub-deploy-one-command` and `hermes-slack-config-sensors`
"waits on 2026-11-10-hub-promote-discards-cve-promoter-commits (docs/howto/…)", a task that is closed.

## Causes

1. **The hub has no ledger.** The exporter reads `~/.local/share/k3d-manager/worktrees/ledger.jsonl` on the machine it
   runs on. Hermes runs it on the M5 hub; dispatches are started on m4-air, so on the hub every overlap check sees no
   open dispatch.
2. **A late agent exit reopens an abandoned task.** `_open_plan_dispatches` takes the last lifecycle event as the
   state. `v1.43.15 hub-promote-keeps-promoter-commits-r2` was abandoned 2026-11-11 07:44; its agent exited at 10:31
   (`scope_violation`, `agent_exit`), so the task reads as open. `bin/k3dm-codex-dispatch open` treats it as closed.
3. **A spec with no `## Files` section is never in an overlap.** `v1.44.0-deploy-hub-behind-alert` had none and showed
   "ready to dispatch" next to the deploy/hub batch that holds `bin/k3dm-repo-sync`. Fixed in the doc 2026-11-12;
   the exporter still reads a missing section as "no files", not "unknown".

## Related

`docs/bugs/2026-11-04-agy-activity-no-data-local-ledger-coverage.md` (same shape: a hub panel fed by an m4-only local file).
