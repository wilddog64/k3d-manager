# hub-deploy leaves the webhook (and other long-running agents) on the old code

**Status:** OPEN — filed 2026-11-22
**Priority:** P2 (a promoted fix silently does not take effect; workaround `make restart-webhook`)
**Triage:** carry → v1.46.0 — grooming 2026-11-22, operator
**Re-triage:** 2026-11-27 — fix in v1.46.0 (operator 2026-11-27: "Go for your suggestions")
**Branch:** `k3d-manager-v1.46.0`
**Introduced by:** pre-existing (`bin/k3dm-hub-deploy` launchd reconcile, lines 186-222, keys only on plist template changes)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-22
**Prior art:** docs/bugs/2026-10-01-restart-webhook-leaves-cloud-bridge-on-stale-code.md (exact-slug pass) — read, different root cause (that one is `restart-webhook` not restarting the cloud bridge; this one is `hub-deploy` not restarting anything when only code changes)

## Symptom

2026-11-22 14:40 the operator ran `make hub-sync && make hub-deploy REF=aa920a6f && make deploy-worker`; hub-deploy
printed `deploy/hub 4217648..aa920a6; reapply skipped; ... launchd skipped 0`. At 14:43 `/k3dm help` still listed
`/hostinger-status` (operator screenshot), which `8f6de4c1` removed from `scripts/lib/webhook/make_targets.py`.

## Evidence (Claude, read-only, M5 hub over ssh, 2026-11-22)

- `git show aa920a6f:scripts/lib/webhook/make_targets.py | grep -c hostinger-status` → 0; the hub checkout is at
  `aa920a6fc` with 0 matches.
- `launchctl list`: `com.k3d-manager.webhook` PID 55782; `ps -o lstart= -p 55782` → `Thu Nov 19 16:45:01 2026`. The
  webhook process predates the fix (`8f6de4c1`, 2026-11-22 13:58) and was not restarted by hub-deploy.
- `bin/k3dm-hub-deploy:186-222`: the launchd step lists `scripts/etc/launchd/com.k3d-manager.*.plist.tmpl` files
  changed between the last reconciled commit and the new one and reinstalls only those. A change to Python code the
  agent imports (`scripts/lib/webhook/`, `bin/k3dm-webhook`, cloud bridge, Hermes) restarts nothing.

## Impact

Every promote that changes webhook, cloud-bridge or Hermes code reports success while the hub keeps serving the old
code until someone restarts the agent. Live checks then fail or, worse, pass against old code for a different reason.

## Workaround

On the hub: `make restart-webhook` (also restarts the cloud bridge). Used 2026-11-22 14:46: first bootstrap
attempt printed `Bootstrap failed: 5: Input/output error`, the target's retry loop reloaded it; new PIDs started
14:46:32 and `/k3dm help` then showed the new code.

## Proposed fix (for triage)

hub-deploy restarts each long-running agent whose code paths changed between old and new (`git diff --name-only`
mapped per agent: webhook → `bin/k3dm-webhook`, `scripts/lib/webhook/`; cloud bridge; Hermes), prints which it
restarted, and confirms the new PID started after the deploy. Paired test: a code-only diff restarts the webhook; a
docs-only diff restarts nothing.

## Recurrence — 2026-11-27 (v1.46.0 unrouted-notices live check)

Operator promoted `1c74deb3` (`make hub-deploy`, ~03:06Z), which carries the `_notify_job` fix `35d42bc8`. Claude's
unrouted probe `d812d065` (03:12Z) still recorded the second notice `route: none`, `delivered: false` (operator `cat`
of its `delivery.jsonl`), the pre-fix shape: the webhook process was still running pre-promote code. The earlier p2b
live check only worked because `make update-webhook-slack-routes` restarts the webhook. Workaround again:
`make restart-webhook` on the hub, then re-probe. This bug now blocks live verification of every webhook fix in
v1.46.0.
