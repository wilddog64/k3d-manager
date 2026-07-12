# Bug: Grafana restarting frequently

**Filed:** 2026-07-06
**Source:** /ask agent observation

## Description

`kube-prometheus-stack-grafana-69b78bd9d9-55hfz` shows 8 restarts with the most recent 8h ago. Worth a `kubectl describe` / container logs pass to see whether it's OOM or a sidecar (dashboards/datasources sidecar) crash loop — could correlate with the missing-panel window.

## Resolution — DUPLICATE (verified 2026-07-07)

Same pod as `2026-07-06-grafana-repeatedly-killed-by-liveness-probe-under-argocd-image-updater-dashboard-load.md`. Live inspection ruled out both hypotheses in this observation:

- **Not OOM** — last termination was `reason=Completed, exitCode=0` (a graceful SIGTERM), not `OOMKilled`/137.
- **Not a sidecar crash loop** — only the `grafana` container restarts (11× by 2026-07-07); `grafana-sc-dashboard` and `grafana-sc-datasources` are at 0 restarts.

Root cause and fix are in the liveness-probe bug. **Close this as a duplicate** → see [Grafana liveness-probe kill](./2026-07-06-grafana-repeatedly-killed-by-liveness-probe-under-argocd-image-updater-dashboard-load.md).
