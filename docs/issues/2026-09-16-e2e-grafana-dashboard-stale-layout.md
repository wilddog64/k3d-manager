# E2E Grafana dashboard briefly reverted to the old layout

## What was tested

The dashboard source was updated to put the failure trend/cause/spec panels above the tables and to hide the Prometheus scrape-target `service` label. The ConfigMap was applied and Grafana restarted.

## Actual output

The first live verification still returned the previous layout:

```text
[(1, 'Status by runner/service/tier/project', 0), (2, 'Last success age', 0), (3, 'Failing runs in window', 0), (4, 'Duration trend', 6), (5, 'Recent runs', 14), (6, 'Failure groups', 24), (7, 'Failure details', 34), (8, 'Failure trend by service', 48), (9, 'Failure causes by service', 56), (10, 'Top failing specs', 56)]
```

The ArgoCD application was still reporting revision `c7fe5a8b`, so its self-heal loop restored the old ConfigMap after the direct apply. Forcing an ArgoCD hard refresh moved it to `387f019e`, after which the live ConfigMap reported the new layout (`8/9/10` at `14/22/22`) and excluded the scrape-target `service` label.

## Root cause

The dashboard ConfigMap is owned by the ArgoCD `hub-grafana-dashboards` application. A direct Kubernetes apply is temporary when the Git branch revision has not yet been observed by ArgoCD.

## Resolution

Committed and pushed `387f019e` (`fix(grafana): surface e2e trend panels`), forced an ArgoCD refresh, verified revision `387f019e`, and restarted Grafana successfully.

## Recommended follow-up

When changing an ArgoCD-managed dashboard, push the branch first and force a refresh (or wait for polling) before judging the live UI. A direct apply should only be used as a short-lived recovery step.
