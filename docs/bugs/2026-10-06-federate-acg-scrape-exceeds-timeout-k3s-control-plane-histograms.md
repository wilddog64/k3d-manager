# Bug: hub `federate-acg` scrape times out — k3s kubelet endpoint federates 50k control-plane histogram series

**Filed:** 2026-10-06, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN
**Severity:** medium. The hub's `federate-acg` target is down for the whole sandbox lifetime, so
`TargetDown` fires and no sandbox metrics reach the hub, even though the sandbox Prometheus is
healthy.
**Related:** `docs/bugs/2026-10-03-acg-sandbox-prometheus-crds-missing-from-api-discovery.md`
(same symptom, different cause — that one was the sandbox Prometheus never starting; it is
mitigated and did not recur today), `docs/bugs/2026-09-20-kubeapidown-flapping-apiserver-scrape-timeout.md`
(same class on the hub's own apiserver scrape),
`docs/bugs/archive/2026-08-20-pre-v1.26/2026-06-06-prometheus-oomkill-federation-too-broad.md`
(the v1.6.3 narrowing that produced the current `match[]`).

## Observed (2026-10-06, sandbox from this morning's `make up`, k3s `v1.32.0+k3s1`)

- Sandbox side is healthy: all 10 `monitoring.coreos.com` kinds are served, the `Prometheus`
  object is Reconciled/Available, `prometheus-acg-kube-prometheus-stack-prometheus` is 1/1,
  `svc/prometheus-operated` exists, and hub ArgoCD `acg-kube-prometheus-stack` is
  Synced/Healthy/Succeeded. The local port-forward `127.0.0.1:19190/-/ready` returned 200.
- Hub `up{job="federate-acg"}` = 0. Target `lastError`: `context deadline exceeded`,
  `lastScrapeDuration` 10.0 s (the default 10 s scrape timeout).
- Timed from the Mac with the hub's exact `match[]`:
  `200 37,576,324 bytes in 15.6 s`. A second request then hung for 30 s, and afterwards every
  `/-/ready` through the port-forward timed out (10 s) — the `kubectl port-forward` (PID 13954)
  wedged under the repeated oversized transfers.
- Series selected by the hub's `match[]` on the sandbox: **75,583**. By job: `kubelet` 67,611,
  `kube-state-metrics` 4,544, `node-exporter` 3,775.
- Top `job="kubelet"` metric names — almost all control-plane histogram buckets:

  | Series | Metric |
  |---|---|
  | 10,944 | `apiserver_request_duration_seconds_bucket` |
  | 10,608 | `etcd_request_duration_seconds_bucket` |
  | 7,260 | `apiserver_request_sli_duration_seconds_bucket` |
  | 4,032 | `apiserver_request_body_size_bytes_bucket` |
  | 1,864 | `apiserver_response_sizes_bucket` |
  | 1,484 | `apiserver_watch_cache_read_wait_seconds_bucket` |
  | 1,034 | `workqueue_work_duration_seconds_bucket` |
  | 1,034 | `workqueue_queue_duration_seconds_bucket` |
  | 924 | `scheduler_plugin_execution_duration_seconds_bucket` |

## Root cause

k3s runs the apiserver, etcd client, scheduler and controller-manager inside the same process as
the kubelet, so the kubelet `/metrics` endpoint also exposes all of their metrics under
`job="kubelet"`. The v1.6.3 `match[]` (`{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"}`)
assumed `kubelet` meant node/pod metrics, and so it federates every apiserver and etcd histogram
too. The response outgrows the 10 s default scrape timeout, so every scrape fails.

Excluding the four control-plane prefixes drops the selection from **75,583 to 23,777** series
(measured on the sandbox). The hub holds **zero** `cluster="acg"` series with those prefixes today
(`count({cluster="acg",__name__=~"apiserver_.+|etcd_.+|scheduler_.+|workqueue_.+"})` is empty) and
no file under `scripts/etc` references them, so nothing depends on them.

## Fix

### 1. `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` — `federate-acg`

Old:

```yaml
      - job_name: federate-acg
        scrape_interval: 60s
        honor_labels: true
        metrics_path: /federate
        params:
          match[]:
            - '{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy", __name__!~".+:.+"}'
```

New:

```yaml
      - job_name: federate-acg
        scrape_interval: 60s
        scrape_timeout: 30s
        honor_labels: true
        metrics_path: /federate
        params:
          match[]:
            - '{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy", __name__!~".+:.+|apiserver_.+|etcd_.+|scheduler_.+|workqueue_.+"}'
```

Nothing else in the file changes. `scrape_timeout` must stay below `scrape_interval`.

### 2. `docs/guides/grafana-dashboards.md` (the "Where the alerts live" paragraph, ~line 325)

Old:

```
`scripts/etc/prometheus/rules/`, which are hub-side: the hub has no Pushgateway, its
`federate-acg` job selects only `{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"}`,
and so the hub TSDB holds zero `k3dm_test_*` series. A rule on the hub for these metrics can
```

New:

```
`scripts/etc/prometheus/rules/`, which are hub-side: the hub has no Pushgateway, its
`federate-acg` job selects only `{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"}`
(minus the k3s control-plane `apiserver_`, `etcd_`, `scheduler_` and `workqueue_` series, which
k3s exposes on the kubelet endpoint and which made the scrape outgrow its timeout),
and so the hub TSDB holds zero `k3dm_test_*` series. A rule on the hub for these metrics can
```

### 3. `CHANGELOG.md` — `## [Unreleased]` → `### Fixed`, as the first bullet

```
- The hub's `federate-acg` scrape timed out on every attempt, so no sandbox metrics reached the
  hub and `TargetDown` fired for the whole sandbox lifetime. k3s exposes the embedded apiserver,
  etcd and scheduler metrics on the kubelet endpoint, so the `job="kubelet"` match federated
  about 50,000 control-plane histogram series — a 37 MB response that took 15 s against a 10 s
  timeout. The match now excludes `apiserver_`, `etcd_`, `scheduler_` and `workqueue_` (75,583 →
  23,777 series) and the job's timeout is 30 s. See
  `docs/bugs/2026-10-06-federate-acg-scrape-exceeds-timeout-k3s-control-plane-histograms.md`.
```

### 4. BATS — append to `scripts/tests/plugins/observability_federate_self_scrape.bats`

Use `yq` against `${VALUES}` as the existing tests do:

1. `federate-acg` `params["match[]"][0]` contains each of `apiserver_.+`, `etcd_.+`,
   `scheduler_.+`, `workqueue_.+` and `.+:.+` inside the `__name__!~` matcher (assert the
   tokens, not the whole line).
2. `federate-acg` `scrape_timeout` is `30s`, and `scrape_interval` is still `60s`.
3. The `job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"` selector is unchanged
   (assert that token).

Never a bare `! grep`; use `run` or `|| false`.

## Rules

- `bats scripts/tests/plugins/observability_federate_self_scrape.bats` passes; paste the output.
- RED: the new tests 1 and 2 must fail against the pre-change values file. Prove it on a temp copy
  (`git show HEAD:<path> > "$TMPDIR/..."` and point a copy of the test at it), never by
  `git checkout`/`git stash` of the working tree.
- `yq '.' scripts/etc/helm/observability/kube-prometheus-stack-values.yaml >/dev/null` exits 0.
- `make check-doc-links` passes for the staged docs.

## Definition of Done

- [ ] values file: `match[]` exclusion + `scrape_timeout: 30s`, nothing else changed
- [ ] guide paragraph updated
- [ ] CHANGELOG `### Fixed` entry
- [ ] 3 new BATS tests `ok`, existing tests in the file still `ok`, RED shown
- [ ] `git show --stat` lists exactly: the values file, `docs/guides/grafana-dashboards.md`,
      `CHANGELOG.md`, `scripts/tests/plugins/observability_federate_self_scrape.bats`
- [ ] Commit on `k3d-manager-v1.41.0` with exactly:
      `fix(observability): stop federating k3s control-plane histograms so the federate-acg scrape fits its timeout`
- [ ] `git push origin k3d-manager-v1.41.0`; report the SHA and `git rev-parse origin/k3d-manager-v1.41.0`.
      If commit or push is denied by the sandbox, stop, leave the changes in the working tree and
      report that — do not retry with other flags.

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the four listed. In particular not
  `kube-prometheus-stack-acg-values.yaml` (the sandbox's own scrape config is fine), not
  `scripts/lib/foundation/`, not `memory-bank/`.
- Do NOT commit to `main`.
- Do NOT run `kubectl`, `helm`, `make observability*`, `make up`, or `make -n` on anything. This
  is a pure config + BATS change.

## Rollout (Claude + operator, after the commit is verified)

1. The hub `kube-prometheus-stack` Application reads this values file from the release branch;
   confirm it syncs to the new commit (ArgoCD auto-sync), then confirm the generated scrape
   config carries the new `match[]` and `scrape_timeout`.
2. The wedged port-forward on `:19190` must be restarted (operator): kill the stuck
   `kubectl port-forward svc/prometheus-operated 19190:9090` and start it again with the command
   `bin/cluster-up` Step 14b prints.
3. Confirm `up{job="federate-acg"} == 1` on the hub and a scrape duration well under 30 s.
