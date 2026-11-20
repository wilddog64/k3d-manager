# Bug: a promoted dashboard change is not live until Argo CD is hard-refreshed by hand

**Status:** OPEN — captured 2026-11-19 by Claude
**Priority:** P2
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-19
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from this laptop: context
`k3d-k3d-cluster` missing). Read `docs/bugs/2026-11-14-plan-dashboard-lags-push-by-up-to-20-minutes.md`: different
root cause (metric data published on the Hermes cycle, not the dashboard definition); related symptom only.
**Approval:** none yet (capture only)

## Symptom

2026-11-19: operator ran `make hub-deploy REF=3d5fd9ef` (tag `hub-promote/20261120T020945Z`; `deploy/hub` confirmed at
3d5fd9ef by `make hub-promote-status`). The change in that promote, fd9bc6a4 (fixed `valueSize` on the Bugs
dashboard's Earliest/Latest panels, `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`), was still not
visible when the operator looked afterwards ("I still don't see changes reflect on release tracking dashboard").
After `kubectl -n cicd annotate application hub-grafana-dashboards argocd.argoproj.io/refresh=hard --overwrite` and a
browser reload, the change appeared (operator screenshot).

Recurrence: the same lag was seen on 2026-10-16 (commit e7c1beae unsynced for 8 min after a push; noted in Claude's
memory, never filed).

## Hub evidence (read-only, hub pane work:1.0, 2026-11-20T02:21Z, Argo CD v3.5.5 in namespace cicd)

- `cicd/hub-grafana-dashboards` tracks `deploy/hub` (repo wilddog64/k3d-manager), automated sync with prune and
  selfHeal; synced revision 3d5fd9ef.
- Its last sync started 2026-11-20T02:16:05Z, `initiatedBy: {"automated":true}`, finished 02:16:06Z. The promote tag is
  02:09:45Z, so Argo CD synced the change on its own about 6.3 minutes after the promote.
- `argocd-cm`: `timeout.reconciliation` 180s, `timeout.reconciliation.jitter` 60s; `argocd-cmd-params-cm` sets no cache
  or reconciliation keys (repo-server defaults).
- 21 applications in `cicd` track `deploy/hub` (all hub and ubuntu-hostinger apps), so every promote has the same lag.

So the change is not stuck: it lands within one or two reconcile cycles (about 3-7 minutes), and the operator looked
inside that window. Not measured: when the manual hard refresh ran relative to 02:16:05Z, and whether the repo-server
revision cache adds to the delay (not proven; no upstream source read).

## Fix direction (for triage)

If the app tracks `deploy/hub`: have `bin/k3dm-hub-deploy` set the hard-refresh annotation on the dashboard app (or on
every app tracking `deploy/hub`) as its last step after the ref moves. If it tracks the release branch, the promote
does not gate dashboards at all; decide which is intended first.
