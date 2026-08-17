# Prometheus TSDB corruption leaves Grafana with no data

**Date:** 2026-08-16  
**Severity:** high — monitoring visibility unavailable  
**Status:** diagnosed; recovery procedure pending

## Symptoms

The CVE Auto-Patch Grafana dashboard showed `No data` across alert counts,
namespace counts, remediation outcomes, and both vulnerability tables. The
same outage affected the remediation-history panel that had originally exposed
the exporter cache issue.

## Evidence

The Kubernetes API and nodes were reachable, but Prometheus was not ready:

```text
prometheus-kube-prometheus-stack-prometheus-0   1/2   Running   11 (2m14s ago)   27d
config-reloader ready=true
prometheus ready=false
```

Monitoring events showed repeated probe failures and container restarts:

```text
Liveness probe failed: Get "http://10.42.0.77:9090/-/healthy": context deadline exceeded
Startup probe failed: HTTP probe failed with statuscode: 503
Killing pod ... prometheus ...
```

Prometheus logged TSDB corruption during startup:

```text
Loading on-disk chunks failed
err="iterate on on-disk chunks: out of sequence m-mapped chunk..."
Deleting mmapped chunk files
WAL replay, this may take a while
```

Node usage was not exhausted (metrics showed approximately 9–18% CPU and
7–39% memory), so this is not a capacity outage. The exporter pod had been
`1/1 Running`; it cannot make Grafana queries return data while Prometheus is
unready.

## Impact and data assessment

Prometheus may have gaps in the corrupted head/WAL window, but this does not
prove total data loss. Existing remediation-event ConfigMaps remain the source
audit records and were not deleted. Historical TSDB blocks that were healthy
should remain available after recovery.

## Safe recovery procedure

1. **Freeze destructive actions.** Do not delete the Prometheus PVC or recreate
   the StatefulSet until a backup exists.
2. **Snapshot the PVC** (or make a filesystem-level copy) and record the
   snapshot/PVC identity and timestamp.
3. Allow one extended WAL replay window. The default startup probe may kill the
   process before a large replay completes; record restart counts and the
   latest Prometheus log lines.
4. If replay completes, verify the pod is `2/2 Ready`, query Prometheus for
   `up`, `cve_remediation_event_info`, and `trivy_vulnerability_inventory`,
   then refresh Grafana.
5. If it continues restarting, work from the snapshot: run the Prometheus
   `promtool tsdb repair` procedure against a copied data directory, or restore
   the last known-good snapshot. Never run repair against the only copy.
6. After recovery, add a source-managed startup/recovery policy that permits
   long WAL replays and alert on Prometheus readiness/restart loops.

## Follow-up fixes

- Add a Prometheus readiness/restart alert to the platform rules.
- Review the kube-prometheus-stack startup-probe budget against observed WAL
  replay duration.
- Ensure Prometheus PVC snapshots/backups are part of the sandbox recovery
  procedure.
- Keep the exporter cache-preservation fix separately deployed; it addresses
  transient exporter API failures, not TSDB corruption.
