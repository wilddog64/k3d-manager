# `PrometheusOutOfOrderTimestamps`: the hub federates recording-rule series that its own rules also write

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low–medium. The hub's Prometheus drops about 102 samples on every federate scrape (1.7/s), firing since
2026-09-27T18:46Z (the hub rebuild). The dropped samples are aggregates, so the panels built on them are fed by two
writers.
**Status:** FIXED (pending sync)
**Related:** `docs/bugs/2026-09-13-hub-federate-acg-self-scrape-duplicates-series.md`, the same job's earlier
duplicate-series defect, fixed by dropping `cluster="acg"` self-scrapes.

## Evidence (hub `k3d-k3d-cluster`, Prometheus `v3.1.0`, 2026-10-02; read-only)

- The Prometheus log has `msg="Error on ingesting out-of-order samples" scrape_pool=federate-acg` with
  `num_dropped=102` on every scrape (171 of 174 lines; three were 103 or 104), from 11:23Z through 14:21Z. No other
  scrape pool logs this. 102 per 60s scrape matches the alert's 1.7 samples/s.
- `federate-acg` scrapes `host.internal:19190`. Every one of the payload's 77,196 series is labelled
  `cluster="ubuntu-hostinger"`; the job name says `acg`, but the source is the hostinger cluster.
- The payload itself is clean:
  - no series appears twice, including after empty-valued labels are dropped;
  - no series' timestamp goes backwards between two scrapes 65s apart;
  - none is older than the hub's stored latest sample, when sampled out of band.
- The payload includes **409 recording-rule series** (names with `:`), for example
  `node_namespace_pod_container:container_memory_working_set_bytes` (100), `…:container_memory_rss` (100),
  `…:container_memory_cache` (100), `cluster:namespace:pod_*:active:kube_pod_container_resource_*` (91) and
  `instance:node_*` (≈10).
- The hub runs the same kube-prometheus-stack recording rules over the federated raw series. Its outputs carry the
  input's labels, including the source's external labels `prometheus` and `prometheus_replica`. So they land in the
  **same** series: for example, the hub has exactly 100 `node_namespace_pod_container:container_memory_working_set_bytes{cluster="ubuntu-hostinger"}`
  series, not 200.

## Cause

Two writers feed one series:

- the hub's rule evaluation, stamped at evaluation time;
- the federated copy, stamped with the source's older evaluation time.

When the hub's evaluation has already appended a newer sample, the federated sample is older and is dropped as out
of order. The set that collides varies with evaluation phase, about 102 per scrape. `honor_timestamps` (the default)
makes the federated timestamps authoritative, so they can never win.

## Fix (`scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`, job `federate-acg` only)

Federate raw series only, and let the hub compute its own aggregates. Change the `match[]` selector:

Old:
```yaml
          match[]:
            - '{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"}'
```
New:
```yaml
          match[]:
            - '{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy", __name__!~".+:.+"}'
```

Change nothing else: not the existing `metric_relabel_configs` (the 2026-09-13 fix), the target, the labels, or the
interval. Renaming the job from `federate-acg` is out of scope; the 2026-09-13 tests key on that name.

## Tests (`scripts/tests/plugins/observability_federate_self_scrape.bats`)

1. A new test: the `federate-acg` `match[]` has exactly one selector, and it contains
   `job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"` and `__name__!~".+:.+"`.
2. Existing tests stay green, including the self-scrape drop.
3. Mutation, `cp`-restored and `cmp`-proved: remove the `__name__!~` matcher → test 1 is red.

## Rules

- `bats scripts/tests/plugins/observability_federate_self_scrape.bats` is green; `yq` parses the values file.
- No cluster, network or git commits. Leave the changes uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Update this doc: Status FIXED (pending sync), plus a short Resolution section.

## Resolution

Updated the `federate-acg` selector to exclude recording-rule series, leaving the existing target, labels,
interval, and self-scrape drop unchanged. Offline YAML/BATS coverage verifies the raw-series-only selector.

## Rollout

The `observability` ApplicationSet reads this values file from the release branch, so ArgoCD applies it on the next
sync. Then confirm on the hub:

- `rate(prometheus_target_scrapes_sample_out_of_order_total[10m])` returns to 0;
- the `Error on ingesting out-of-order samples` log lines stop;
- `count({cluster="ubuntu-hostinger", __name__=~".+:.+"})` is still non-zero, because the hub's own rules now write
  those series.
