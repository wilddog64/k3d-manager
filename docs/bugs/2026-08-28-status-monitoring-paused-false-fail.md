# make status hard-FAILs when monitoring is deliberately paused

**Date:** 2026-08-28
**Status:** SPEC → FIX
**Area:** `bin/k3dm-webhook` (`_smoke_test_services`, `_smoke_test_logins`)
**Severity:** Low (cosmetic) — but it makes the `monitoring-pause` toggle and
`make status` fight each other.

## Symptom

After `make monitoring-pause` (see
`2026-08-28-monitoring-pause-resume-toggle.md`), `make status` reports:

```
✗ Prometheus: HTTP Error 502: Bad Gateway
✗ Grafana: HTTP Error 502: Bad Gateway
✗ Grafana login: HTTP 502
Overall: FAIL (3 errors, 0 warnings)
```

The 502s are **correct and expected** — the observability stack is intentionally
scaled to zero to reclaim ~1.1 cores. Yet they surface as hard errors and turn
status red, so pausing monitoring (the sanctioned CPU-relief lever) always
breaks `make status`.

## Root cause chain (why this matters)

The user's hub is CPU-oversubscribed on a fanless laptop. Live-measured: with the
full monitoring stack running, Keycloak `/realms/master` responds in **1.6–6.3s**
(erratic), tripping the login smoke harness read timeout →
`Keycloak login: The read operation timed out`. Pausing monitoring drops that to
**9–26ms** (server node CPU also recovers from `<unknown>`). So pause is the real
fix for the Keycloak false-fail — but pause then trips the Prometheus/Grafana
checks. Status must understand a deliberate pause.

## Fix (skip, don't fail, when deliberately paused)

Mirror the existing stub-skip pattern (`ok is None` → warning, not error; see the
frontend-login and Pushgateway-absent skips). Add a helper and a downgrade pass:

- `_monitoring_paused(context, argons)` — returns True iff the hub observability
  stack is **deliberately** paused. Signal: the `kube-prometheus-stack`
  ArgoCD Application exists **and** its `spec.syncPolicy.automated` is empty
  (which is exactly what `observability_pause` sets). Implemented via
  `kubectl get application kube-prometheus-stack -o jsonpath={.metadata.name}={.spec.syncPolicy.automated}`
  → paused iff output is `kube-prometheus-stack=` (name present, automated empty).
  This **distinguishes a pause from a crash**: a broken-but-managed stack still
  has `automated` set, so it stays a real FAIL.
- In `_smoke_test_services`: after probing, for any `False` result named
  `Prometheus`/`Grafana`, if `_monitoring_paused()` → downgrade to
  `(name, None, "monitoring paused (make monitoring-resume)")`.
- In `_smoke_test_logins`: same downgrade for a `False` `Grafana login`.
- **No provider gate.** Prometheus/Grafana are hub-hosted in every provider
  mode — the public `*.3ai-talk.org` URLs (used by the `k3s-hostinger` provider
  that `make status` actually resolves to) route to the hub via cloudflared, and
  `localhost:19090` (other providers) hits the hub directly. So a paused hub
  monitoring stack explains the 502 in all modes; the hub-specific
  `_monitoring_paused()` signal is the only correct gate. (An earlier
  `provider != "k3s-hostinger"` gate was wrong and left `make status` — which
  runs as `k3s-hostinger` — still FAILing.)

**Context correctness:** `_monitoring_paused()` must query the **hub/infra**
context (`INFRA_CONTEXT`, default `k3d-k3d-cluster`) where the observability
ArgoCD Applications live — NOT `_provider_context()`, which returns the app
cluster (`ubuntu-k3s`/`ubuntu-hostinger`) and has no such Application.

`_monitoring_paused()` is computed at most once per probe pass (cheap kubectl
call, `--request-timeout=5s`, tolerant of timeout/kubectl-absent → returns False,
i.e. "not known to be paused" → keep the failure).

## Why this is safe (does not mask a real outage)

- The skip fires **only** when the ArgoCD Application confirms a deliberate pause
  (`automated` empty). A genuinely-broken monitoring stack (crash, OOM, node
  down) still has `automated: {prune, selfHeal}` set → stays a hard FAIL.
- Scoped to `Prometheus`/`Grafana`/`Grafana login` only — every other service
  check is untouched.
- Remote (`k3s-hostinger`) monitoring is never downgraded.

## Verification

1. Edit `bin/k3dm-webhook`; `make restart-webhook`.
2. `make monitoring-pause`; `make status` →
   `⚪ Prometheus: monitoring paused (make monitoring-resume)` (and Grafana,
   Grafana login) as warnings; `Overall: PASS` (0 errors).
3. `make monitoring-resume`; after pods return, `make status` → Prometheus/Grafana
   back to `✓ HTTP 200`.
