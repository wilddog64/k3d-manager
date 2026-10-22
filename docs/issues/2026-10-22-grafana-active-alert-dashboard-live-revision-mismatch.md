# Grafana active-alert dashboard live revision mismatch

**Date:** 2026-10-22
**Related bug:** `docs/bugs/2026-10-21-firing-alerts-dashboard-missing-start-time-and-age.md`
**Impact:** Live verification incomplete; deployed dashboard is older than the landed fix.

## Evidence

Operator screenshot still shows the old active-alert table: Alert, Cluster, Namespace,
Severity, Active since (UTC), Active for. It has no Category or App/Pod identity columns.

Read-only Argo CD status query:

```text
$ kubectl config current-context
k3d-k3d-cluster

$ kubectl get applications.argoproj.io -A -o json | jq -r '.items[] | select(.metadata.name=="hub-grafana-dashboards") | {namespace:.metadata.namespace, sync:.status.sync, health:.status.health, reconciledAt:.status.reconciledAt, targetRevision:.spec.source.targetRevision, repoURL:.spec.source.repoURL}'
{
  "namespace": "cicd",
  "sync": {
    "comparedTo": {
      "destination": {
        "namespace": "monitoring",
        "server": "https://kubernetes.default.svc"
      },
      "source": {
        "repoURL": ""
      },
      "sources": [
        {
          "directory": {
            "include": "grafana-dashboard-*.yaml"
          },
          "path": "scripts/etc/argocd/platform-ops",
          "repoURL": "https://github.com/wilddog64/k3d-manager",
          "targetRevision": "k3d-manager-v1.43.5"
        },
        {
          "directory": {
            "include": "k3dm-tests-configmap.yaml"
          },
          "path": "scripts/etc/grafana/dashboards",
          "repoURL": "https://github.com/wilddog64/k3d-manager",
          "targetRevision": "k3d-manager-v1.43.5"
        }
      ]
    },
    "revisions": [
      "3b70efd16869a89fca3965eb8bcebf6fe9ae9d80",
      "3b70efd16869a89fca3965eb8bcebf6fe9ae9d80"
    ],
    "status": "Synced"
  },
  "health": {
    "lastTransitionTime": "2026-10-16T02:13:03Z",
    "status": "Healthy"
  },
  "reconciledAt": "2026-10-22T13:10:17Z",
  "targetRevision": null,
  "repoURL": null
}
```

Read-only ConfigMap inspection:

```text
$ kubectl get configmap grafana-dashboard-overview-readable -n monitoring -o json | jq -r '.data["grafana-overview-readable.json"] | fromjson | {timezone, panel:(.panels[] | select(.id==13) | {title, transformations})}'
{
  "timezone": "utc",
  "panel": {
    "title": "Active Alert Instances — Active Since (UTC; pending included)",
    "transformations": [
      {
        "id": "merge",
        "options": {}
      },
      {
        "id": "filterFieldsByName",
        "options": {
          "include": {
            "names": [
              "alertname",
              "severity",
              "cluster",
              "namespace",
              "instance",
              "Value #A",
              "Value #B"
            ]
          }
        }
      },
      {
        "id": "organize",
        "options": {
          "excludeByName": {
            "Time": true
          },
          "renameByName": {
            "alertname": "Alert",
            "severity": "Severity",
            "cluster": "Cluster",
            "namespace": "Namespace",
            "instance": "Instance",
            "Value #A": "Active since (UTC; pending included)",
            "Value #B": "Active for"
          }
        }
      }
    ]
  }
}
```

## Conclusion and follow-up

The dashboard application tracks `k3d-manager-v1.43.5` but currently resolves it to
`3b70efd1`, before the fix commit `28e74901`; the ConfigMap confirms the old schema is live.
The app's Synced/Healthy status therefore does not establish that the branch tip has been
observed. The screenshot is not a valid live verification of the landed fix.

Operator's requested final order is **Namespace → Cluster → Alert → Category → App/Pod
identity → Severity → Active since → Active for**. The canonical bug acceptance criteria are
being updated and a narrowly scoped follow-up is being dispatched. Do not force Argo CD refresh
or sync, or claim LIVE-VERIFIED, without separate operator approval and evidence that the
application has observed the intended revision.

The initial direct Argo CD CLI query failed authentication (`token signature is invalid`); the
read-only Kubernetes Application and ConfigMap queries above succeeded and were used instead.
