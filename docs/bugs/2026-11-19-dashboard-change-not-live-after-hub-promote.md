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

## What is not known (for triage)

- How long the operator waited between the promote and looking. Not measured.
- Which ref `cicd/hub-grafana-dashboards` tracks today (`deploy/hub` or the release branch) and its reconciliation
  interval. Read with `kubectl -n cicd get application hub-grafana-dashboards -o jsonpath='{.spec.sources[*].targetRevision} {.status.sync.revisions}'`
  and `argocd-cm` `timeout.reconciliation`.

## Fix direction (for triage)

If the app tracks `deploy/hub`: have `bin/k3dm-hub-deploy` set the hard-refresh annotation on the dashboard app (or on
every app tracking `deploy/hub`) as its last step after the ref moves. If it tracks the release branch, the promote
does not gate dashboards at all; decide which is intended first.
