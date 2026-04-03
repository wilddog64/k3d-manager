# Issue: Frontend CrashLoopBackOff — Misdiagnosis and Root Cause

**Date:** 2026-03-21
**Repos affected:** `shopping-cart-frontend`, `shopping-cart-infra` (ArgoCD)
**Status:** Open — root cause is resource exhaustion; deferred to v1.0.0 (3-node k3sup)

---

## Symptoms

- `frontend` pod in CrashLoopBackOff on ubuntu-k3s EC2 (t3.medium)
- 12 pod instances accumulated (failed rollout attempts)
- ArgoCD showed `Progressing` / `CrashLoopBackOff`
- Logs showed: `can not modify /etc/nginx/conf.d/default.conf (read-only file system?)`
- Pod started, then received SIGQUIT ~39 seconds after startup

---

## Failed Diagnosis Path

### Gemini's diagnosis (wrong)
Gemini diagnosed the root cause as:
1. Read-only filesystem preventing nginx from writing config
2. Incorrect probe port / path

Both were incorrect. Nginx was starting successfully — the "read-only file system" message is
a non-fatal warning from the entrypoint script trying to modify a root-owned file as user 101.

### Claude's diagnosis (wrong)
Diagnosed probe port mismatch: nginx on port 80, probes on 8080.

This was also wrong. The image uses a **custom nginx config** that explicitly listens on port 8080
(non-root compatible — UID 101 cannot bind port 80). The `/health` endpoint IS defined in
`nginx.conf`. The original manifest (port 8080, path `/health`) was correct.

### Codex fix (wrong, PR closed)
PR #11 changed:
- `containerPort: 8080` → `80`
- Probe port `8080` → `80`, path `/health` → `/`
- Service `targetPort: 8080` → `80`
- Added emptyDir at `/etc/nginx/conf.d`

Copilot P1 findings correctly identified both changes as harmful:
1. Nothing in the container listens on port 80 — probes would fail immediately
2. emptyDir at `/etc/nginx/conf.d` wipes out the baked-in `default.conf` including `/health` and `/api/*` locations

PR #11 was closed without merging.

---

## Actual Root Cause

**Resource exhaustion on t3.medium (4GB RAM, 2 vCPU).**

Gemini confirmed `FailedScheduling` events — the Kubernetes scheduler could not place the
frontend pod because the node had insufficient available memory. The t3.medium was at ~95%
capacity with order-service, payment-service, data layer, and Istio all competing for RAM.

The SIGQUIT ~39 seconds after startup was Kubernetes gracefully terminating the pod after
the readiness probe failed — but the probe failed because the pod was being killed for
resource reasons, not because nginx was misconfigured.

The 12 accumulated pod instances each held resource reservations, compounding the problem.

---

## Why Every Fix Failed

1. **Gemini's kubectl patches** — reverted by ArgoCD auto-sync within minutes
2. **Port/probe manifest changes** — wrong direction (image uses 8080, not 80)
3. **Scale to 0 + back to 1** — clears pod count but root cause (resource exhaustion) unchanged

---

## Resolution

**Deferred to v1.0.0** — 3-node k3s cluster via k3sup:

| Node | Workloads |
|---|---|
| Node 1 | k3s control plane + ArgoCD + Vault + ESO |
| Node 2 | App pods (basket, frontend, order, payment, product-catalog) |
| Node 3 | Data + Identity (PostgreSQL, RabbitMQ, Redis, Samba AD DC) |

Three t3.medium nodes (within ACG 5-instance limit) distribute the load so no single node
is at 95% capacity.

**Short-term workaround:** Scale order-service and payment-service to `replicas: 0` to free
RAM on the current node, allowing frontend to schedule.

---

## Lessons Learned

1. `FailedScheduling` events are the authoritative signal for resource issues — check `kubectl describe pod` events before diagnosing probe or config problems
2. Always check the Dockerfile + nginx.conf before changing container ports in manifests
3. ArgoCD auto-sync means kubectl patches are invisible — every fix must go through Git
4. emptyDir mounts on config directories wipe out image-baked configs — use subPath mounts instead
5. Copilot caught both P1 issues that 3 agents (Gemini + Claude + Codex) missed
