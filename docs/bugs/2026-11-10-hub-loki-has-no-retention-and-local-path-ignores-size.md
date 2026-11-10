# Bug: hub Loki keeps logs forever, and its 10Gi volume is not a limit

**Status:** OPEN
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-10 (intent approval and dispatch go; disk measurements for E3 baseline)
**Introduced by:** pre-existing (`hub-loki` in `scripts/etc/argocd/applicationsets/observability.yaml:32-37` with `scripts/etc/helm/observability/loki-values.yaml`, which never set retention)
**Should have been caught by:** spec (the Loki spec set a volume size and no retention, and assumed the size bounds the data)
**Prior art:** `make find-similar-docs` not run (vector store unreachable from the M4 all day: `context "k3d-k3d-cluster" does not exist`, 2026-11-10); exact-slug glob: none; `grep -ril "loki.*retention\|retention.*loki" docs/bugs`: none
**Severity:** latent hub outage. Loki's data grows without bound on the k3d node's disk, which every hub pod shares. A full node disk brings kubelet DiskPressure evictions and kine write failures, not just lost logs.
**Approval:** operator, 2026-11-10: "can you investgiate the retention, and we need to setup that policy so it won't fillup diskspace"
**Filed:** 2026-11-10
**Detected by:** Claude, 2026-11-10, after the operator's hub check showed `loki-0`, `loki-gateway`, promtail on all four nodes and PVC `storage-loki-0` 10Gi `local-path`
**Branch:** `k3d-manager-v1.43.15`
**Release:** v1.43.15

## Symptom

On the M5 hub, 2026-11-10 (operator, `kubectl get pods,pvc -A`): `monitoring/loki-0` Running 10d, promtail on
`k3d-k3d-cluster-server-0` and agents 0–2, PVC `storage-loki-0` Bound 10Gi `local-path`. Nothing in our values sets
retention, so nothing is ever deleted. Current usage not yet measured (see E3).

## Root cause, with proof from the deployed versions

1. **Chart `loki` 18.2.0** (grafana-community, appVersion 3.7.3; `helm pull`, M4, 2026-11-10): `values.yaml` has
   `loki.compactor: {}` (line 814) and `loki.limits_config` without `retention_period` (lines 602-609). Our values
   add neither.
2. **Loki v3.7.3** (`grafana/loki` source at tag `v3.7.3`, `gh api`, 2026-11-10): `pkg/compactor/config.go:54`
   `compactor.retention-enabled` defaults to `false`; `pkg/validation/limits.go:426-427` `store.retention` defaults to
   `0s`, "a zero value of 0 or 0s disables retention". `pkg/compactor/config.go:108-109` refuses retention without
   `compactor.delete-request-store`.
3. **local-path-provisioner** (`rancher/local-path-provisioner` README, 2026-11-10, lines 16-17): "No support for the
   volume capacity limit currently. The capacity limit will be ignored for now." The 10Gi request is not enforced, so
   Loki writes into the node's disk until that disk is full.

## Fix

Add to `scripts/etc/helm/observability/loki-values.yaml`:

    loki:
      compactor:
        retention_enabled: true
        delete_request_store: filesystem
      limits_config:
        retention_period: 336h
        retention_stream:
          - selector: '{job="k3dm-dispatch-run"}'
            priority: 1
            period: 720h
          - selector: '{namespace="trivy-system"}'
            priority: 1
            period: 720h
          - selector: '{namespace="cicd"}'
            priority: 1
            period: 720h

14 days by default; 30 days only for the three streams that 30-day dashboards read (Contract readers). Helm merges
`limits_config`, so the chart's other limits (`reject_old_samples_max_age: 168h`, `query_timeout`, ...) stay.

**Offline proof of the fix (Claude, M4, 2026-11-10):** `helm template` of chart 18.2.0 with our values plus this
overlay renders ConfigMap `loki` with `compactor: {delete_request_store: filesystem, retention_enabled: true}`,
`retention_period: 336h`, the three `retention_stream` rules, `reject_old_samples_max_age: 168h` kept, and schema
index period `24h`. `docker run grafana/loki:3.7.3` (`sha256:70b9f699fc9bb868b62f1cfd4f787dfa50242f1fd92e6089787d5d7daea75fe8`)
`-verify-config` on that rendered config: `msg="config is valid"`, rc 0. Negative control, same config without
`delete_request_store`: `CONFIG ERROR: invalid compactor config: compactor.delete-request-store should be configured
when retention is enabled`.

Deletion is not immediate: the compactor runs every 10m (`compaction-interval`) and removes chunks 2h after marking
them (`retention-delete-delay`), both Loki defaults at v3.7.3 (`pkg/compactor/config.go:51,53`).

## Files

| File | Change |
|---|---|
| `scripts/etc/helm/observability/loki-values.yaml` | compactor retention and `limits_config` retention |
| `scripts/tests/plugins/argocd_loki.bats` | cases below |
| `docs/guides/` page for observability, if one names Loki storage | retention line |

## Contract readers

| Reader | Changes? |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-run-log.yaml:40` (`now-30d`, stream `job="k3dm-dispatch-run"`) | No: that stream keeps 30 days |
| `bin/k3dm-dispatch-metrics:1239-1241` `loki_url` links `from=now-30d` | No: same stream |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml:316-323` trivy-operator errors, "last 30 days" | No: `namespace="trivy-system"` keeps 30 days |
| `grafana-dashboard-argocd.yaml:139,174,209` image-updater panels (`namespace="cicd"`) | No: `cicd` keeps 30 days |
| Grafana Explore on any other namespace | Yes: logs older than 14 days are gone |
| `scripts/etc/argocd/applicationsets/observability-acg.yaml:36-39` (ACG sandbox Loki, same values file) | Yes: same retention, harmless on a short-lived sandbox |

Writers: `bin/k3dm-dispatch-logs:115-122` pushes `job="k3dm-dispatch-run"` (30 days); promtail
(`scripts/etc/observability/promtail.yaml`) ships every pod's logs (14 days unless in a 30-day namespace). Found by
`git grep -n -i loki -- bin scripts/lib scripts/etc` and `git grep -n "now-[0-9]*d"` on the Loki dashboards, 2026-11-10.

## Acceptance

```yaml
must:
  - id: M1
    text: "The hub Loki config enables compactor retention with a filesystem delete-request store and a 14-day default retention."
  - id: M2
    text: "Streams read by 30-day dashboards (job=k3dm-dispatch-run, namespace trivy-system, namespace cicd) keep 30 days."
  - id: M3
    text: "The chart's other limits_config defaults are still rendered (reject_old_samples_max_age 168h)."
must_not:
  - id: N1
    text: "The rendered Loki config never enables retention without a delete_request_store (Loki refuses to start)."
  - id: N2
    text: "The values never leave retention disabled or set retention_period to 0."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2], kind: offline, intent: "You will see argocd_loki.bats render chart 18.2.0 with the repo's values and assert retention on, the store set, 336h default, the three 720h stream rules and reject_old_samples_max_age kept; a test fails if retention is removed or the store is dropped, shown red on today's values."}
  - {id: E2, proves: [N1], kind: offline, intent: "Claude runs grafana/loki:3.7.3 -verify-config on the rendered config and sees 'config is valid'; without the store it sees the CONFIG ERROR."}
  - {id: E3, proves: [M1], kind: live, intent: "After promote, you see loki-0 restart Ready, its log show the compactor applying retention, /var/loki usage measured before and again a day later, and logs older than 14 days gone for an ordinary namespace."}
interface:
  - "scripts/etc/helm/observability/loki-values.yaml with chart loki 18.2.0 (helm template)"
  - "grafana/loki:3.7.3 -verify-config"
```

## Worker definition of done

- Tests render with `helm template` against a chart pulled at exactly 18.2.0 (skip cleanly with a clear message only
  when helm is missing; never use another version). No network beyond the chart pull, no kubectl.
- Show the N2 test red on today's values; mutants shown red: (a) drop `delete_request_store`, (b) set
  `retention_period: 0s`, (c) drop the `job="k3dm-dispatch-run"` stream rule.
- Run `bats scripts/tests/plugins/argocd_loki.bats` and `make validate-manifests`; paste command, rc and proving lines.
  Leave changes uncommitted; Claude reviews and lands.
