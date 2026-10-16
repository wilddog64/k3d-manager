# Bug: `E2EVerificationStale` fires for a runner nobody uses, while another runner is green

**Branch:** `k3d-manager-v1.43.0`
**Filed:** 2026-10-11
**Status:** IMPLEMENTED — landed `90a5a463` (Codex, Claude verified: BATS 21/21 with promtool (Claude fixed the promtool test: one-sample series went stale before 5d, and the expected annotations named the static tier); pre-fix grouping turns the promtool test red. Rollout: operator `make platform-ops`.)
**Priority:** P3
**Severity:** Low — a false warning e-mail; the e2e signal itself is fresh
**Files:** `scripts/etc/argocd/platform-ops/prometheusrule.yaml`,
`scripts/tests/plugins/e2e_observability.bats`, `CHANGELOG.md`

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/prometheusrule.yaml` | File 1 below |
| `scripts/tests/plugins/e2e_observability.bats` | File 2 below |
| `CHANGELOG.md` | File 3 below |

## Symptom

The operator received, on 2026-10-11:

```
[1] Firing  alertname = E2EVerificationStale
exported_service = product-catalog  project = api+flows  runner = local-m4
summary = no passing e2e for product-catalog/vcluster (runner local-m4) in >3d
```

Hub Prometheus at the time:

```
e2e_last_success_timestamp_seconds{exported_service="product-catalog",runner="local-m4"} 2026-10-07T00:25:31Z
e2e_last_success_timestamp_seconds{exported_service="product-catalog",runner="m2"}       2026-10-10T09:09:01Z
e2e_last_run_timestamp_seconds    {...runner="local-m4"}                                 2026-10-07T00:25:31Z
```

`local-m4` did not fail. It has not **run** since 2026-10-07, because e2e now runs on the M2
(`make e2e-remote`). The product was verified 16 hours before the alert fired.

## Root cause

The rule is
`time() - max by (tier, exported_service, project, runner) (e2e_last_success_timestamp_seconds) > 259200`.
`runner` was kept when the 2026-10-05 fix
([`e2e-alert-refires-on-exporter-rollout`](2026-10-05-e2e-alert-refires-on-exporter-rollout.md))
aggregated away `pod`/`instance`, and its test asserts the same `by` clause for every e2e rule. That
is right for `E2EVerificationFailing`: a red run on any runner is a real failure. It is wrong for
staleness. The question "has this service been verified recently" is answered by **any** runner, and
the exporter keeps each runner's last payload forever, so a runner that stops being used goes stale
three days later and stays firing.

## Fix spec

### File 1 — `scripts/etc/argocd/platform-ops/prometheusrule.yaml`, `E2EVerificationStale`

Replace:

```yaml
          expr: time() - max by (tier, exported_service, project, runner) (e2e_last_success_timestamp_seconds) > 259200
```

with:

```yaml
          expr: time() - max by (tier, exported_service, project) (e2e_last_success_timestamp_seconds) > 259200
```

and drop `(runner {{ $labels.runner }})` from both annotations (the label no longer exists on the
alert):

```yaml
            summary: "no passing e2e for {{ $labels.exported_service }}/{{ $labels.tier }} on any runner in >3d"
            description: "No passing e2e run for {{ $labels.exported_service }} on the {{ $labels.tier }} substrate on any runner in over 3 days; the verification signal is stale."
```

`E2EVerificationFailing` keeps `runner`.

### File 2 — `scripts/tests/plugins/e2e_observability.bats`

In `e2e alerts aggregate away the scrape target and name the exported service`, replace the single
`by` assertion with one per rule:

```python
    want = ("max by (tier, exported_service, project)" if rule["alert"] == "E2EVerificationStale"
            else "max by (tier, exported_service, project, runner)")
    assert want + " (" in expr, (rule["alert"], expr)
```

Add a test that evaluates the staleness rule's semantics with `promtool test rules` if `promtool`
is available, else skip: series `local-m4` last success 4 days ago and `m2` 1 day ago → no alert;
both 4 days ago → one alert without a `runner` label.

### File 3 — `CHANGELOG.md` `[Unreleased]` Fixed entry.

## Verification

- The new and changed tests fail against the pre-fix rule (paste the RED output).
- After the operator applies the rule (see the v1.43.0 note below), `ALERTS{alertname="E2EVerificationStale"}`
  is empty while any runner has passed within three days.

## Deploy note

`prometheusrule.yaml` is not synced by ArgoCD (`hub-platform-ops` includes only
`app-cluster-kubeconfig-externalsecret.yaml`). It reaches the hub only through
`make platform-ops` or `kubectl apply -f scripts/etc/argocd/platform-ops/prometheusrule.yaml`,
run by the operator. See
[`2026-10-11-hub-data-export-fails-under-launchd-and-dr-alerts-never-deployed`](2026-10-11-hub-data-export-fails-under-launchd-and-dr-alerts-never-deployed.md).

## Workaround

Silence `E2EVerificationStale{runner="local-m4"}` in Alertmanager, or run one local `make e2e`.
