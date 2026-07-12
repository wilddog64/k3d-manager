# Bug: Grafana repeatedly killed by liveness probe under argocd-image-updater dashboard load

**Filed:** 2026-07-06 (observation) / 2026-07-07 (live root cause + fix spec)
**Source:** /ask agent observation, root-caused live on `k3d-k3d-cluster` 2026-07-07
**Branch:** `k3d-manager-v1.14.0`
**Cluster:** `k3d-k3d-cluster` (laptop hub) — NOT the app cluster
**Files:** `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`

## Description

`kube-prometheus-stack-grafana` has restarted repeatedly (8× when filed, **11× by 2026-07-07**, most recent 7h before inspection). Previous-container logs show many `/api/ds/query` and `/api/live/ws` requests from `grafana.3ai-talk.org/d/argocd-image-updater-hub/...?from=now-30d` running 1–5 minutes and returning 401/500 before shutdown ("Shutdown started reason: System signal: terminated").

## Live root cause (verified 2026-07-07)

Pod `kube-prometheus-stack-grafana-69b78bd9d9-55hfz` on `k3d-k3d-cluster`, namespace `monitoring`.

- **Only the `grafana` container restarts** (11×); `grafana-sc-dashboard` and `grafana-sc-datasources` sidecars are at **0 restarts**. → rules out the sidecar-crash theory in the dup bug `2026-07-06-grafana-restarting-frequently.md`.
- **Last termination: `reason=Completed, exitCode=0`** — a *graceful SIGTERM*, not `OOMKilled` (which would be exitCode 137). This is the signature of a **liveness-probe kill**: kubelet marks the container unhealthy, sends SIGTERM, Grafana shuts down cleanly (matching the "System signal: terminated" log line).
- **Memory pressure is the enabler.** Live idle usage is **141Mi against a 192Mi limit (73%)** (`kubectl top pod ... --containers`). The limit is set at `kube-prometheus-stack-values.yaml:56` (`memory: 192Mi`). Under the argocd-image-updater dashboard's **30-day** range (many concurrent `/api/ds/query`), Grafana's Go heap spikes toward the limit → GC thrash → `/api/health` slows past the liveness `timeoutSeconds: 30` → 10 consecutive failures (`failureThreshold: 10 × periodSeconds: 10` ≈ 100s) → SIGTERM → restart.
- **Secondary: persistent `/api/live/ws` 401.** Current logs still show `path=/api/live/ws status=401 remote_addr=208.185.193.88` — a failing live-websocket auth loop from the dashboard. It adds load but is not the kill trigger; worth fixing separately so the dashboard stops hammering a 401.

## Fix

### Change 1 — `kube-prometheus-stack-values.yaml`: raise Grafana memory headroom

**Exact old block (lines 50-57):**

```yaml
grafana:
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 192Mi
      cpu: 200m
```

**Exact new block:**

```yaml
grafana:
  resources:
    requests:
      memory: 128Mi
      cpu: 50m
    limits:
      memory: 512Mi
      cpu: 200m
```

512Mi gives ~3.6× the idle footprint so a 30d dashboard render no longer pushes `/api/health` past the liveness timeout.

### Secondary (separate, optional follow-ups — not required to stop the restarts)

- **Reduce the argocd-image-updater dashboard default range** from `now-30d` to `now-6h`/`now-24h` so a cold open is cheap. (Dashboard JSON, not in this values file.)
- **Fix the `/api/live/ws` 401** — datasource/live auth on the argocd-image-updater dashboard.

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` | Grafana `limits.memory` `192Mi` → `512Mi`; `requests.memory` `64Mi` → `128Mi` |

## Rules

- `helm template`/lint parses the values file.
- No other files touched in this change (dashboard range + live/ws 401 are separate).

## Definition of Done

- [ ] `kube-prometheus-stack-values.yaml` Grafana `limits.memory: 512Mi`
- [ ] After redeploy: `kubectl --context k3d-k3d-cluster -n monitoring get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[*].status.containerStatuses[?(@.name=="grafana")].restartCount}'` stops climbing over a 30d-dashboard open
- [ ] Committed and pushed to `k3d-manager-v1.14.0`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
fix(observability): raise hub Grafana memory limit to stop liveness-probe restarts
```

## What NOT to Do

- Do NOT relax the liveness probe (raising `failureThreshold`/`timeoutSeconds`) instead of the memory limit — that masks the stall rather than fixing it.
- Do NOT create a PR, skip hooks, or commit to `main`.
