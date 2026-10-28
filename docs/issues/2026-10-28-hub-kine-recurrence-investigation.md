# October28 hub Kine recurrence: read-only investigation evidence

Operator supplied a firing HubKineCompactionStalled email and explicitly asked
for investigation and a proper recurrence bug. No screenshot file copied into
the repo. Coordinator inspected M4's hub only, with read-only metric/log/state
checks. No service restart, database query/write, raw retention deletion,
remediation or metrics publication. Current test-all watch continues separately.

## Existing rule and probe

Rule in scripts/etc/argocd/platform-ops/prometheusrule.yaml: compaction age
above1800seconds for15minutes, severitywarning/grouphermes/clusterhub. Source
probe in bin/k3dm-hermes reads DB byte count/logs and stores last-compaction time.
Today's metric matches literal successful log evidence, rather than only a
container-start fallback. The diagnostic did not run the whole probe because
it also reads cluster registration secrets; only needed read-only evidence was
collected directly.

## Actual Prometheus initial response

```json
{
  "alert": {
    "data": {
      "result": [
        {
          "metric": {
            "__name__": "ALERTS",
            "alertname": "HubKineCompactionStalled",
            "alertstate": "firing",
            "cluster": "hub",
            "group": "hermes",
            "job": "k3dm-hub-kine",
            "severity": "warning"
          },
          "value": [
            1793213779.829,
            "1"
          ]
        }
      ],
      "resultType": "vector"
    },
    "status": "success"
  },
  "kine": {
    "data": {
      "result": [
        {
          "metric": {
            "__name__": "k3dm_hub_kine_last_compaction_timestamp_seconds",
            "job": "k3dm-hub-kine"
          },
          "value": [
            1793213779.953,
            "1793209503.378494"
          ]
        },
        {
          "metric": {
            "__name__": "k3dm_hub_kine_state_db_bytes",
            "job": "k3dm-hub-kine"
          },
          "value": [
            1793213779.953,
            "583081984"
          ]
        }
      ],
      "resultType": "vector"
    },
    "status": "success"
  },
  "sensor_up": {
    "data": {
      "result": [],
      "resultType": "vector"
    },
    "status": "success"
  }
}
```

The direct sensor_up query returned an empty vector; the Kine metrics are
published to Pushgateway. Used push_time_seconds and Hermes heartbeat instead
of treating the missing direct-up series as proof of a failed sensor.

## Actual compaction log extraction

Command: docker logs --since120h --tail120000 for the named server, retaining
only exact compaction/error lines and bounded aggregate counts. Output below
is the complete filtered command result, not the unrelated raw server log.
120001 lines includes the concatenation delimiter; the tail cap means this
is not a complete five-day history. Recent error and last success independently
match the current metric; no later success appeared in this bounded window.
The recent_slow_sql_count is a count in the last2000captured lines, not a
rate or proof of root cause.

```json
{
  "returncode": 0,
  "lines_examined": 120001,
  "compact_lines": 1381,
  "last_compact_lines": [
    "time=\"2026-10-28T17:35:03Z\" level=info msg=\"COMPACT deleted 518 rows from 517 revisions in 202.065027ms - compacted to 1772560/1773560\"",
    "time=\"2026-10-28T17:35:03Z\" level=info msg=\"COMPACT compacted from 1772043 to 1772560 in 1 transactions over 204ms\"",
    "time=\"2026-10-28T17:40:03Z\" level=info msg=\"COMPACT compactRev=1772560 targetCompactRev=1773033 currentRev=1774033\"",
    "time=\"2026-10-28T17:40:03Z\" level=info msg=\"COMPACT deleted 460 rows from 473 revisions in 32.172293ms - compacted to 1773033/1774033\"",
    "time=\"2026-10-28T17:40:03Z\" level=info msg=\"COMPACT compacted from 1772560 to 1773033 in 1 transactions over 36ms\"",
    "time=\"2026-10-28T17:45:03Z\" level=info msg=\"COMPACT compactRev=1773033 targetCompactRev=1773483 currentRev=1774483\"",
    "time=\"2026-10-28T17:45:03Z\" level=info msg=\"COMPACT deleted 462 rows from 450 revisions in 70.683595ms - compacted to 1773483/1774483\"",
    "time=\"2026-10-28T17:45:03Z\" level=info msg=\"COMPACT compacted from 1773033 to 1773483 in 1 transactions over 71ms\"",
    "time=\"2026-10-28T17:50:03Z\" level=info msg=\"COMPACT compactRev=1773483 targetCompactRev=1773955 currentRev=1774955\""
  ],
  "compaction_errors": [
    "time=\"2026-10-28T17:50:14Z\" level=error msg=\"Compact failed: failed to record compact revision: sql: transaction has already been committed or rolled back\""
  ],
  "recent_slow_sql_count": 11
}
```

## Actual freshness and size-delta queries

```json
{
  "compaction_age": {
    "data": {
      "result": [
        {
          "metric": {
            "job": "k3dm-hub-kine"
          },
          "value": [
            1793213839.714,
            "4336.335505962372"
          ]
        }
      ],
      "resultType": "vector"
    },
    "status": "success"
  },
  "db_24h_delta": {
    "data": {
      "result": [
        {
          "metric": {
            "job": "k3dm-hub-kine"
          },
          "value": [
            1793213839.801,
            "0"
          ]
        }
      ],
      "resultType": "vector"
    },
    "status": "success"
  },
  "hermes_tick_age": {
    "data": {
      "result": [
        {
          "metric": {
            "job": "k3dm-hermes"
          },
          "value": [
            1793213841.337,
            "489.9096450805664"
          ]
        }
      ],
      "resultType": "vector"
    },
    "status": "success"
  },
  "push_age": {
    "data": {
      "result": [
        {
          "metric": {
            "job": "k3dm-hub-kine"
          },
          "value": [
            1793213839.597,
            "626.543004989624"
          ]
        }
      ],
      "resultType": "vector"
    },
    "status": "success"
  }
}
```

The 24h delta query returned0 for the available series. Coverage of the whole
24h interval was not checked; do not claim a full-day growth measurement or
use this to forecast safety. Main-file allocation can also conceal retention
churn. Publisher age about10minutes and heartbeat about8minutes are explicitly
recorded; direct current logs establish the stalled compaction independently.

## Actual container metadata

```text
{"started_at":"2026-10-25T12:40:00.428960292Z","status":"running","restart_count":0,"image":"rancher/k3s:v1.32.0-k3s1","created_at":"2026-10-16T02:01:45.667273967Z"}
```

## Actual API readiness

```text
[+]ping ok
[+]log ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
[+]poststarthook/start-apiserver-admission-initializer ok
[+]poststarthook/generic-apiserver-start-informers ok
[+]poststarthook/priority-and-fairness-config-consumer ok
[+]poststarthook/priority-and-fairness-filter ok
[+]poststarthook/storage-object-count-tracker-hook ok
[+]poststarthook/start-apiextensions-informers ok
[+]poststarthook/start-apiextensions-controllers ok
[+]poststarthook/crd-informer-synced ok
[+]poststarthook/start-system-namespaces-controller ok
[+]poststarthook/start-cluster-authentication-info-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-garbage-collector ok
[+]poststarthook/start-legacy-token-tracking-controller ok
[+]poststarthook/start-service-ip-repair-controllers ok
[+]poststarthook/rbac/bootstrap-roles ok
[+]poststarthook/scheduling/bootstrap-system-priority-classes ok
[+]poststarthook/priority-and-fairness-config-producer ok
[+]poststarthook/bootstrap-controller ok
[+]poststarthook/aggregator-reload-proxy-client-cert ok
[+]poststarthook/start-kube-aggregator-informers ok
[+]poststarthook/apiservice-status-local-available-controller ok
[+]poststarthook/apiservice-status-remote-available-controller ok
[+]poststarthook/apiservice-registration-controller ok
[+]poststarthook/apiservice-discovery-controller ok
[+]poststarthook/kube-apiserver-autoregistration ok
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
[+]shutdown ok
readyz check passed
```

## Actual read-only file byte counts

Command: docker exec server sh -c with printf/wc-c on the two named files;
no SQLite database opened or modified by the check.

```text
/var/lib/rancher/k3s/server/db/state.db 583081984
/var/lib/rancher/k3s/server/db/state.db-wal 78090512
```

## Actual node readiness extraction

```json
[
  {
    "name": "k3d-k3d-cluster-agent-0",
    "ready": "True"
  },
  {
    "name": "k3d-k3d-cluster-agent-1",
    "ready": "True"
  },
  {
    "name": "k3d-k3d-cluster-agent-2",
    "ready": "True"
  },
  {
    "name": "k3d-k3d-cluster-server-0",
    "ready": "True"
  }
]
```

## Finding and follow-up

Real recurrence confirmed: last success17:45:03UTC, failed revision-record
transaction17:50:14UTC, no later successful cycle in current bounded logs.
API ready/four nodesReady, DB556MiB/WAL74MiB. Underlying trigger unknown.
Existing record names October29 controlled rebuild, not separately scheduled
or approved by this check. Require backup/restore readiness and explicit
operator go; no naive K3s restart. New recurrence bug is filing only.

Documentation was prepared while the separate M4 test-all run continued.
That run has now finished: main1913cases/no failures; test-bin622cases/two
failures (cleanup macOS stat and OrbStack non-TTY fixture); Python stage did
not run. Commit follows the run, avoiding a source change during execution.
No unit/BATS rerun for this read-only diagnosis; full operator test-all output
will be recorded separately. Normal documentation lint/audit/hooks apply.
