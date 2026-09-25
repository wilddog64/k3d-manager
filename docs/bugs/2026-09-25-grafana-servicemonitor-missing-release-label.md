# Bug: the Grafana ServiceMonitor lacks the `release` label its Prometheus selector requires, so Grafana has never been scraped

**Filed:** 2026-09-25
**Target branch:** `k3d-manager-v1.38.0` (held — v1.37.0 is awaiting merge)
**Files:** `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`, `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`, `CHANGELOG.md`
**Affects:** hub (`k3d-k3d-cluster`) **and** app cluster (`ubuntu-hostinger`) — identically
**Related:** `reference_grafana_no_data_is_a_missing_producer` — this is a missing producer, not a dashboard bug

---

## Problem

The Prometheus CR selects ServiceMonitors by label:

```
kube-prometheus-stack-prometheus => {"matchLabels":{"release":"kube-prometheus-stack"}}
```

Of the eight ServiceMonitors in `monitoring` on the hub, exactly one is missing that label:

| ServiceMonitor | `release` |
|---|---|
| `kube-prometheus-stack-alertmanager` | `kube-prometheus-stack` |
| `kube-prometheus-stack-apiserver` | `kube-prometheus-stack` |
| **`kube-prometheus-stack-grafana`** | **MISSING** |
| `kube-prometheus-stack-kube-state-metrics` | `kube-prometheus-stack` |
| `kube-prometheus-stack-kubelet` | `kube-prometheus-stack` |
| `kube-prometheus-stack-operator` | `kube-prometheus-stack` |
| `kube-prometheus-stack-prometheus` | `kube-prometheus-stack` |
| `kube-prometheus-stack-prometheus-node-exporter` | `kube-prometheus-stack` |

`ubuntu-hostinger` is identical with the `acg-` prefix: only
`acg-kube-prometheus-stack-grafana` is missing `release: acg-kube-prometheus-stack`.

### Confirmed consequence, not inferred

Queried against the hub Prometheus (`localhost:19091`):

```
up{job=~".*grafana.*"}                    -> status success, 0 series
__name__ values containing "grafana_"     -> 0 of 1740 metric names
```

Grafana has **never** been scraped on either cluster. Every Grafana self-monitoring panel
(dashboard load times, datasource health, alert rule evaluation, session counts) is permanently
blank. This is the missing producer behind the blank Grafana Overview panels.

## Root cause

`grafana` is an **upstream subchart** of `kube-prometheus-stack`, not one of its own templates. The
parent chart stamps `release: {{ .Release.Name }}` onto the ServiceMonitors it renders itself; the
vendored Grafana chart renders its own ServiceMonitor from `grafana.serviceMonitor.labels` and does
not inherit the parent's label. Neither values file sets it:

- `kube-prometheus-stack-values.yaml` has a `grafana:` block (line 64) with `admin`, `resources` and
  `additionalDataSources` — and no `serviceMonitor` key.
- `kube-prometheus-stack-acg-values.yaml` has a `grafana:` block (line 17) with no `serviceMonitor`
  key either.

So the ServiceMonitor is created (the chart enables it by default) but is invisible to the selector.
This is a values gap, not a chart bug, and it has been latent since the stack was first installed.

## Fix

Set the label explicitly in each values file, using **that cluster's own release name**.

### S1 — `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`

Inside the existing `grafana:` block (line 64), add, keeping the file's 2-space indentation and
leaving `admin`, `resources` and `additionalDataSources` untouched:

```yaml
  serviceMonitor:
    enabled: true
    labels:
      release: kube-prometheus-stack
```

### S2 — `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`

Inside the existing `grafana:` block (line 17), add:

```yaml
  serviceMonitor:
    enabled: true
    labels:
      release: acg-kube-prometheus-stack
```

The release names differ between the two files and must not be unified — the ACG stack is installed
as `acg-kube-prometheus-stack`, and its Prometheus selector matches that.

## Rules

- Change only the two values files plus `CHANGELOG.md`. No refactors, no reordering.
- LF endings; preserve existing indentation exactly.
- `yq -e . <file> >/dev/null` must exit 0 for both files — paste both results.
- Do not add a `release` label anywhere else, and do not widen `serviceMonitorSelector`. Loosening
  the selector would pull in unrelated ServiceMonitors cluster-wide.

## Definition of Done

- [ ] S1 and S2 applied; `git diff --stat` shows only the three files
- [ ] `yq -e . ` passes on both values files — paste both
- [ ] `grep -c 'release: kube-prometheus-stack' scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` outputs `1`
- [ ] `grep -c 'release: acg-kube-prometheus-stack' scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` outputs `1`
- [ ] `docs/guides/grafana-dashboards.md` triage table gains a row for "Grafana self-monitoring panels blank" → cause "grafana ServiceMonitor missing the `release` label" (per the doc-every-feature rule, the reader-facing page must be updated in the same release)
- [ ] CHANGELOG `[Unreleased]` → `### Fixed`: "the Grafana ServiceMonitor now carries the `release` label each cluster's `serviceMonitorSelector` requires, so Grafana self-monitoring metrics are scraped instead of silently dropped on both the hub and the app cluster"
- [ ] Commit message verbatim: `fix(observability): label the Grafana ServiceMonitor so Prometheus selects it`

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`
- Do NOT patch the live ServiceMonitor with `kubectl label` — ArgoCD self-heal reverts out-of-band
  patches (`reference_argocd_selfheal_reverts_out_of_band_patch`); the fix must land in the values file
- Do NOT run `helm upgrade` or any live command

## Operator follow-up

Reapply the `observability` ApplicationSet for **both** the hub and ACG variants at release
close-out, then confirm with `argocd_check_values_branch`. Until the sets are reapplied this change
is inert in git. Verify afterwards with:

```
curl -s 'http://localhost:19091/api/v1/query?query=up{job=~".*grafana.*"}'
```

which must return at least one series.
