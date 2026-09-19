# Bugfix: v1.36.0 — `istiod` scrape job has no port filter, firing TargetDown permanently

**Filed:** 2026-09-19
**Branch:** `k3d-manager-v1.36.0`
**Severity:** Low impact, high noise — a permanently-firing alert that trains the operator to ignore `TargetDown`.

## Symptom

`TargetDown` has been firing for `job=istiod` on the hub cluster since **2026-09-11T16:39:47Z**
and never clears. The operator reported it as "Target disappeared from Prometheus target
discovery" — nothing has disappeared, and istiod is healthy.

## Evidence

Live target census (read-only query against the raw Prometheus backend on `127.0.0.1:19091`,
`/api/v1/targets?state=any`, filtered to `job=istiod`):

```
up    http://10.42.0.244:15014/metrics  http-monitoring
up    http://10.42.2.126:15014/metrics  http-monitoring
down  http://10.42.0.244:15010/metrics  grpc-xds        net/http: HTTP/1.x transport ... (HTTP/2 preface)
down  http://10.42.2.126:15010/metrics  grpc-xds        net/http: HTTP/1.x transport ... (HTTP/2 preface)
down  http://10.42.0.244:15012/metrics  https-dns       EOF
down  http://10.42.2.126:15012/metrics  https-dns       EOF
down  http://10.42.0.244:15017/metrics  https-webhook   server returned HTTP status 400 Bad Request
down  http://10.42.2.126:15017/metrics  https-webhook   server returned HTTP status 400 Bad Request
down  http://10.42.0.244:8080/metrics   <empty>         server returned HTTP status 404 Not Found
down  http://10.42.2.126:8080/metrics   <empty>         server returned HTTP status 404 Not Found
```

8 of 10 targets down = 80%, which clears the kube-prometheus-stack `TargetDown` threshold:

```
100 * (count by (cluster,job,namespace,service) (up == 0)
     / count by (cluster,job,namespace,service) (up)) > 10
```

Metrics collection is **healthy**: both `http-monitoring` targets are `up` and
`count(pilot_xds)` returns 4. No telemetry is missing.

## Root cause

`scripts/etc/helm/observability/kube-prometheus-stack-values.yaml:29-38` defines the `istiod`
job under `additionalScrapeConfigs` with `role: endpoints` and a single `keep` on the
**service name** — and no filter on the **port**:

```yaml
      - job_name: istiod
        kubernetes_sd_configs:
          - role: endpoints
            namespaces:
              names: [istio-system]
        relabel_configs:
          - source_labels: [__meta_kubernetes_service_name]
            action: keep
            regex: istiod
```

Every port on the istiod Service is therefore scraped, but only `15014`
(`http-monitoring`) serves Prometheus metrics. The others are not metrics endpoints at all:

| Port | Name | What it actually is | Why the scrape fails |
|---|---|---|---|
| 15010 | `grpc-xds` | XDS over plaintext gRPC | gRPC speaks HTTP/2; the response begins with the HTTP/2 connection preface, which Prometheus's HTTP/1 client rejects as a malformed response |
| 15012 | `https-dns` | XDS over TLS | plaintext request to a TLS listener → `EOF` |
| 15017 | `https-webhook` | sidecar-injection admission webhook (HTTPS) | `400 Bad Request` |
| 8080 | *(none)* | istiod debug/readiness HTTP port | no `/metrics` handler → `404` |
| 15014 | `http-monitoring` | **the metrics endpoint** | — |

The `8080` target has an **empty** `__meta_kubernetes_endpoint_port_name`. Prometheus's
`endpoints` role emits additional targets for pod container ports that are not part of any
Endpoints subset, so `8080` arrives with no endpoint port name. A `keep` on
`__meta_kubernetes_endpoint_port_name` therefore drops it correctly — an equality test on the
port *number* would not, and a `drop` blacklist of the known-bad ports would leave `8080` and
any future port behind. **Keep the one good port; do not blacklist the bad ones.**

Verified against the live Service and Endpoints:

```
$ kubectl get endpoints istiod -n istio-system -o jsonpath='{range .subsets[*].ports[*]}{.name}{" -> "}{.port}{"\n"}{end}'
https-dns -> 15012
grpc-xds -> 15010
https-webhook -> 15017
http-monitoring -> 15014
```

Note that the **Service** publishes `https-webhook` as port `443` while the **Endpoints** resolve
it to `15017`. Relabelling runs against the Endpoints, which is why the target URL is `:15017`.

`scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml:82-91` carries a
byte-identical `istiod` job block and has the same defect.

## Fix

Add one `keep` relabel rule on the endpoint port name to **both** values files, immediately
after the existing service-name `keep`:

```yaml
        relabel_configs:
          - source_labels: [__meta_kubernetes_service_name]
            action: keep
            regex: istiod
          - source_labels: [__meta_kubernetes_endpoint_port_name]
            action: keep
            regex: http-monitoring
```

Target files:
- `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`
- `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`

Do not change the `federate-acg` or `pushgateway` jobs. Do not touch `relabel_configs`
anywhere else. Do not edit `scripts/etc/prometheus/alertmanager.yaml.tmpl` — the `TargetDown`
route there is correct and must keep working; this fix removes the false positive at the
source rather than silencing the alert.

## Tests

Extend `scripts/tests/plugins/observability_federate_self_scrape.bats`, which already asserts
on these values files with `yq` and is the established pattern. Add cases proving, **for each
of the two values files**:

1. The `istiod` job keeps only `http-monitoring`:
   ```bash
   run yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "istiod") | .relabel_configs[] | select(.source_labels[0] == "__meta_kubernetes_endpoint_port_name") | .regex' "${VALUES}"
   [ "${status}" -eq 0 ]
   [ "${output}" = "http-monitoring" ]
   ```
2. That rule's `action` is `keep` (not `drop` — a `drop` with the same regex inverts the fix
   and would silently discard the only working target).
3. The pre-existing service-name `keep` is still present and still `istiod` — the new rule must
   be additive, not a replacement.

Assert against the **parsed YAML via `yq`**, never a `grep -F` of a source line.

## Definition of Done

- [ ] `keep` on `__meta_kubernetes_endpoint_port_name` = `http-monitoring` added to the `istiod`
      job in **both** `kube-prometheus-stack-values.yaml` and `kube-prometheus-stack-acg-values.yaml`
- [ ] Both files still parse: `yq -e '.prometheus.prometheusSpec.additionalScrapeConfigs' <file>`
- [ ] New BATS cases in `scripts/tests/plugins/observability_federate_self_scrape.bats` cover
      both files, all three assertions above
- [ ] Mutation evidence: each new assertion PASSES against the real tree and FAILS against a
      scratch copy with the asserted token removed or changed. Paste one `real=PASS /
      mutated=FAIL` row per assertion.
- [ ] `make test` — paste `^ok ` and `^not ok ` counts, counted from a captured file (do **not**
      pipe through `tail` and read `$?`)
- [ ] CHANGELOG `[Unreleased]` → `### Fixed` entry
- [ ] Committed and pushed to `origin/k3d-manager-v1.36.0`, SHA proven with
      `git rev-parse HEAD origin/k3d-manager-v1.36.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA

## Commit message (exact)

```
fix(observability): filter the istiod scrape job to the http-monitoring port

The istiod additionalScrapeConfigs entry kept targets by service name with no
port filter, so Prometheus scraped all five istiod endpoint ports. Only 15014
(http-monitoring) serves metrics; 15010 is gRPC/XDS, 15012 is XDS over TLS,
15017 is the injection webhook and 8080 has no /metrics handler. 8 of 10
targets were permanently down, holding TargetDown open for job=istiod since
2026-09-11 while metrics collection was in fact healthy.

Keep only the http-monitoring endpoint port in both the hub and ACG values.

Refs: docs/bugs/2026-09-19-istiod-scrape-job-missing-port-filter.md

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## Out of scope

- **Applying the fix to the live cluster.** This is a config change only. Reapplying the Helm
  values / ApplicationSets is the operator's to run, and is not part of this task.
- `job=federate-acg` is also firing `TargetDown` (`host.internal:19190` connection refused).
  That is a **genuinely dead** endpoint — the ACG sandbox federation target with no live
  sandbox — and is expected behaviour given the 4h sandbox lifetime. Not a bug, no change.
- `serviceMonitor/monitoring/kube-prometheus-stack-apiserver/0` is down with
  `context deadline exceeded` on `https://192.168.97.5:6443/metrics`. Tracked separately;
  correlates with the firing `NodeSystemSaturation` and `CPUThrottlingHigh` alerts, so it
  reads as node CPU starvation rather than an apiserver fault.
- The HTTP/2 protocol-label work in
  `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md` is related context only
  (the 15010 scrape error is literally an HTTP/2 preface) — do not start it here.
