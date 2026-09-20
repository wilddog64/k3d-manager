# Bugfix: v1.36.0 — `KubeAPIDown` flaps 13×/48h: apiserver scrape exceeds a 10s timeout

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** High noise, real alert fatigue — the operator received this repeatedly and it is
the alert that actually reached them, unlike the permanently-firing `TargetDown` cases.
**Cluster:** hub `k3d-k3d-cluster` (k3d/OrbStack, 4 nodes, k3s v1.32.0+k3s1)

## Symptom

Operator receives **"Target disappeared from Prometheus target discovery"** repeatedly —
reported as 4 times in one day, and the alert history shows worse.

This is the `KubeAPIDown` annotation text:

```
KubeAPI has disappeared from Prometheus target discovery.
```

Two rules in this Prometheus carry that wording (`KubeAPIDown`, `KubeletDown`). A prior triage
on 2026-09-19 wrongly concluded no rule in this Prometheus used that phrasing and that the
operator's alert was `TargetDown` on `job=istiod`. **That was wrong** and this spec supersedes
it. The giveaway: a permanently-down target fires **once** and stays firing; an alert that
arrives 4 separate times is flapping, which `istiod`'s flat 2880-minute episode cannot produce.

## Evidence

### Firing history (48h, `ALERTS{alertstate="firing"}` via `query_range`)

`KubeAPIDown` — **13 episodes**, durations 0–42m:

```
09-19 08:25->08:59 (34m)   09-19 20:00->20:32 (32m)   09-20 00:55->01:37 (42m)
09-19 09:47->10:25 (38m)   09-19 21:16->21:34 (18m)   09-20 02:17->02:18 (1m)
09-19 17:33->17:33 (0m)    09-19 22:57->23:04 (7m)    09-20 02:44->02:47 (3m)
09-19 18:12->18:28 (16m)   09-19 23:21->23:27 (6m)    09-20 03:37->04:10 (33m)
09-19 19:25->19:25 (0m)
```

Everything else flaps **in lockstep with the apiserver**, i.e. one root cause, not many:

| Alert | Episodes | Relationship |
|---|---|---|
| `KubeAPIDown` | 13 | the operator's alert |
| `TargetDown{job=apiserver}` | 18 | same windows |
| `TargetDown{job=kube-prometheus-stack-operator}` | 9 | inside apiserver windows |
| `TargetDown{job=kubelet}` | 4 | inside apiserver windows |
| `TargetDown{job=kube-state-metrics}` | 4 | inside apiserver windows |
| `TargetDown{job=argocd-server-metrics}` | 1 | 01:27–01:37, inside apiserver 00:51–01:38 |
| `TargetDown{job=istiod}` | 1 | flat 2880m — **unrelated**, fixed separately in `a255d8d5` |
| `TargetDown{job=federate-acg}` | 1 | flat 2880m — **unrelated**, dead ACG sandbox, expected |

### The rule

```
KubeAPIDown   expr: absent(up{job="apiserver"} == 1)   for: 15m
```

So `up{job="apiserver"}` must be continuously non-1 for 15 minutes. The long episodes
(16/18/32/33/34/38/42m) are exactly that.

### Root cause: the scrape times out, the target never disappears

The live scrape config for the apiserver job:

```
job: serviceMonitor/monitoring/kube-prometheus-stack-apiserver/0
  scrape_interval: 1m
  scrape_timeout:  10s
```

`scrape_duration_seconds{job="apiserver"}` over 48h (n=2881):

| p50 | p90 | p95 | p99 | max |
|---|---|---|---|---|
| **7.41s** | 11.42s | 13.41s | 16.65s | 25.33s |

- **1197 of 2881 samples (41.5%) exceed the 10s timeout.**
- **0 samples exceed 30s.**
- The median is already at 74% of the timeout budget.

The endpoint is large and slow, measured directly with `kubectl get --raw /metrics`:

```
58511 lines, 8361346 bytes (8.36 MB)
served in 1.86s / 6.10s / 2.66s across three consecutive attempts
```

Top families by series count:

```
11712  apiserver_request_duration_seconds_bucket
 6259  apiserver_request_sli_duration_seconds_bucket
 3648  apiserver_request_body_size_bytes_bucket
```

Those three are 21,619 lines — 37% of the payload.

The apiserver is **not** down and **not** restarting: k3s runs it in-process on the
control-plane node (`457182e619fc`, `192.168.97.5`), so there is no apiserver pod to restart,
and `kubectl` works throughout. With a 41.5% per-scrape failure rate, runs of 15 consecutive
failed scrapes occur regularly, which is all `for: 15m` requires.

### Why `metricRelabelings` cannot fix this

The ServiceMonitor already carries one `drop` rule for expensive
`apiserver_request_duration_seconds_bucket` buckets. **`metric_relabel_configs` are applied
after the full payload is downloaded and parsed**, so they reduce ingestion and TSDB size but
have **no effect on scrape duration**. Adding more drop rules will not fix the timeout. Do not
attempt it as the fix.

## Levers evaluated — three are dead ends, verified

| Lever | Verdict | Proof |
|---|---|---|
| `prometheus.prometheusSpec.scrapeTimeout` (global) | **REJECTED** | Prometheus requires `scrape_timeout <= scrape_interval`. 5 jobs have shorter intervals, including `serviceMonitor/monitoring/kube-prometheus-stack-kubelet/1` at **10s**. A global 45s makes the config invalid. |
| `kubeApiServer.serviceMonitor.scrapeTimeout` | **NOT AVAILABLE** | chart `kube-prometheus-stack` 67.9.0's `templates/exporters/kube-api-server/servicemonitor.yaml` renders `interval` but has no `scrapeTimeout` field, and the key is absent from `helm show values`. Upstream chart gap. |
| Prometheus `scrapeClasses` default | **NOT AVAILABLE** | live `prometheuses.monitoring.coreos.com` v1 CRD `scrapeClasses[]` exposes only `attachMetadata, authorization, default, metricRelabelings, name, relabelings, tlsConfig` — no `scrapeTimeout`. |
| Per-endpoint `scrapeTimeout` on the ServiceMonitor | **VIABLE** | live `servicemonitors.monitoring.coreos.com` CRD: `endpoints[].scrapeTimeout` exists, type `string`. |

### Why patch rather than replace the ServiceMonitor

Replacing it (`kubeApiServer.enabled: false` plus our own manifest) was considered and
**rejected** for two concrete reasons:

1. **It can silently invert the alert.** `job="apiserver"` is produced by `jobLabel: component`
   against the `default/kubernetes` Service's labels (`component=apiserver,provider=kubernetes`
   — verified). If a hand-written replacement gets that wrong, `absent(up{job="apiserver"} == 1)`
   becomes permanently true and `KubeAPIDown` fires **forever** — strictly worse than today.
2. **It opens an unmonitored gap.** Between disabling the chart's ServiceMonitor and our own
   applying successfully, there is no apiserver target at all, which also trips `absent()`.

Patching only **adds** `scrapeTimeout` to the existing endpoint. It cannot touch `jobLabel`,
the selector, or the Service, so the job label is structurally safe.

## Fix

Add `_observability_ensure_apiserver_scrape_timeout()` to `scripts/plugins/observability.sh`,
following the existing `_observability_ensure_argocd_servicemonitors()` idiom in the same file
(context argument, CRD wait guard, `_warn` + `return 0` on every degraded path, `_kubectl
--context`).

Behaviour:

1. Accept a context argument, defaulting to `k3d-k3d-cluster`.
2. Reuse the existing CRD wait guard for `servicemonitors.monitoring.coreos.com`
   (`OBSERVABILITY_CRD_WAIT_SECONDS`, default 300). On timeout: `_warn` and `return 0`.
3. Resolve the desired timeout from `OBSERVABILITY_APISERVER_SCRAPE_TIMEOUT`, default `45s`.
4. If the `kube-prometheus-stack-apiserver` ServiceMonitor in the monitoring namespace is
   absent: `_warn` and `return 0`. Never fail the deploy.
5. If `endpoints[0].scrapeTimeout` already equals the desired value: `_info` and return 0
   without patching (idempotent — this runs on every deploy).
6. Otherwise patch **only** `endpoints[0].scrapeTimeout`, then `_info` the result.

Call it from the hub deploy path immediately after the existing
`_observability_ensure_argocd_servicemonitors "${_hub_context}"` (currently line 45).

### Timeout value: `45s`

Justified by the measured distribution, not picked round: max observed 25.33s, zero samples
above 30s in 48h, so 45s is ~1.8× the observed worst case. It must also stay `<=` the job's
`1m` interval, which 45s satisfies. Do not exceed the interval.

Do **not** change the scrape interval, the metricRelabelings, or any other job.

## Tests

New suite `scripts/tests/plugins/observability_apiserver_scrape_timeout.bats`. Offline only —
stub `_kubectl`/`_helm` as the existing observability suites do; no cluster access.

Required cases:

1. **Patches when unset** — the emitted patch sets `endpoints[0].scrapeTimeout` to `45s`.
2. **Idempotent** — when the ServiceMonitor already reports `45s`, no patch call is made.
   Assert on the absence of a patch invocation via a stub marker file, not on log text alone.
3. **Honors the override** — `OBSERVABILITY_APISERVER_SCRAPE_TIMEOUT=30s` patches `30s`.
4. **Missing ServiceMonitor degrades gracefully** — returns 0 and emits no patch.
5. **The patch touches only `scrapeTimeout`** — assert the patch payload contains
   `scrapeTimeout` and does **not** contain `jobLabel`, `selector`, `namespaceSelector` or
   `targetLabels`. This is the regression guard for the job-label inversion described above.
6. **Wired into the hub path** — `_observability_ensure_apiserver_scrape_timeout` is invoked
   from the hub deploy function.

Assert against captured stub arguments or parsed JSON/YAML — never `grep -F` a whole line of
source. No bare `!` in BATS. No `run <binary>` followed only by a non-zero-status assertion.

## Definition of Done

- [ ] `_observability_ensure_apiserver_scrape_timeout()` added, following the existing ensure idiom
- [ ] Wired into the hub deploy path after `_observability_ensure_argocd_servicemonitors`
- [ ] Default `45s`, overridable via `OBSERVABILITY_APISERVER_SCRAPE_TIMEOUT`
- [ ] Idempotent: no patch when the value already matches
- [ ] Every degraded path `_warn`s and returns 0 — the deploy never fails on this
- [ ] New BATS suite with all 6 cases above
- [ ] Mutation evidence: each new assertion PASSES on the real tree and FAILS against a mutated
      copy. One `real=PASS / mutated=FAIL` row per assertion. Include specifically: changing the
      default `45s` to a value exceeding the `1m` interval must redden a test.
- [ ] `shellcheck -S warning` clean on `scripts/plugins/observability.sh`
- [ ] `make test` — paste `^ok ` / `^not ok ` counts from a captured file. **The suite takes
      ~15 minutes and ~960 cases; it is not hung. Let it finish and report `MAKE_EXIT`.**
- [ ] CHANGELOG `[Unreleased]` → `### Fixed`
- [ ] Pushed to `origin/k3d-manager-v1.36.0`, proven with `git rev-parse HEAD origin/k3d-manager-v1.36.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA

## Commit message (exact)

```
fix(observability): give the apiserver scrape a 45s timeout to stop KubeAPIDown flapping

The apiserver /metrics payload is 8.36 MB across 58511 lines and takes 7.41s
at p50, 16.65s at p99 and 25.33s at worst on the hub cluster, while the job
inherited the global 10s scrape timeout. 1197 of 2881 scrapes over 48h (41.5%)
exceeded it, and runs of 15 consecutive failures satisfied KubeAPIDown's
absent(up{job="apiserver"} == 1) for 15m, firing it 13 times in 48h and
dragging the operator, kubelet, kube-state-metrics and argocd targets with it.

The apiserver was never down: k3s runs it in-process, kubectl worked
throughout, and metricRelabelings cannot help because they apply after the
payload is already downloaded.

The chart cannot express this: kube-prometheus-stack 67.9.0's apiserver
ServiceMonitor template has no scrapeTimeout field, the Prometheus CRD's
scrapeClasses have none either, and raising the global timeout would exceed
the 10s interval on kubelet/1 and invalidate the config. Patch the existing
ServiceMonitor endpoint instead, which cannot disturb the jobLabel that
produces job="apiserver".

Refs: docs/bugs/2026-09-20-kubeapidown-flapping-apiserver-scrape-timeout.md

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## Out of scope

- **Applying this to the live cluster.** Config only; the operator runs the deploy.
- **The underlying slowness.** 7.41s at p50 to serve 8.36 MB is ~1.1 MB/s and reflects CPU
  starvation on the host — `NodeSystemSaturation` is firing on all 4 nodes and
  `CPUThrottlingHigh` on 5 targets. Raising the timeout stops a **false** alarm; it does not
  make the cluster faster. Right-sizing that load is separate work. Related:
  `reference_one_second_probes_cpu_starvation_kill_loop`.
- **Dropping the three expensive histogram families** to shrink the TSDB. Worth doing for
  memory, irrelevant to this timeout, and a cardinality change needing its own justification.
- **The ACG values file.** No evidence of the same latency on the ACG cluster, and its
  Prometheus config differs. Do not change `kube-prometheus-stack-acg-values.yaml` here.
- `TargetDown{job=istiod}` (fixed in `a255d8d5`) and `TargetDown{job=federate-acg}` (expected
  dead sandbox endpoint). Neither is this bug.
- **Do not silence or re-route `KubeAPIDown`** in `alertmanager.yaml.tmpl`. The alert is
  correct; the timeout was wrong.
