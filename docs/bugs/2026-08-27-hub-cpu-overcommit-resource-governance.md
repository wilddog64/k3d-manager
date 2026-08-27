# Hub CPU overcommit — resource governance to break the reconcile/HPA death-spiral

**Filed:** 2026-08-27
**Severity:** High — hub control plane intermittently unresponsive; ArgoCD, Keycloak,
CoreDNS, repo-server in restart storms.
**Status:** SPEC

## Symptom

The hub (single k3d Docker VM, **10 CPU / 12.6 GB**) is CPU-saturated. Container-level
CPU (real, via `docker stats`) far exceeds the VM ceiling:

| k3d node container | CPU% |
|---|---|
| agent-2 | **426%** |
| agent-1 | 335% |
| server-0 (control plane) | 318% |
| agent-0 | 298% |
| **total** | **~1378% of 1000% available** |

`kubectl top nodes` hides this (reported agent-2 at ~15%) because it undercounts node
runtime/kubelet overhead. Inside agent-2: **load average 70**, 21% idle.

## Root cause (systemic, not a single component)

The hub is oversubscribed AND has **no resource governance**, so a self-reinforcing loop forms:

1. **Unbounded controllers starve the control plane.**
   - `argocd-application-controller` resources = `{}` (no request/limit) — top CPU burner.
   - `argocd-repo-server` resources = `{}`.
   - Result: apiserver `/livez` takes **1.4–5.3 s** (should be < 100 ms).

2. **Slow apiserver → slow ArgoCD status writes → hot reconcile loop.**
   - Controller logs show `persist_app_status_ms=24044`, `patch_ms=12109` — status patches
     take 12–24 s. Reconciles never "stick", so 25 Applications re-queue on a ~4 s loop,
     hammering repo-server with constant git fetches (`git_ms` 2–4 s each).
   - The `--status-processors=5 --operation-processors=2` tuning already applied to the
     controller does **not** help, because the bottleneck is apiserver write latency, not
     processor count.

3. **Slow apiserver → failed liveness probes → restart storm.**
   Pods exit `Completed`/`exit=0` (kubelet SIGTERM on probe timeout, not OOM):
   `argocd-repo-server` **216 restarts**, `svclb-istio-ingressgateway` **453**,
   `coredns` **138**, `keycloak` 51; `kube-state-metrics` + `prometheus-operator` in
   CrashLoopBackOff. Every restart re-warms/re-clones → more CPU → loop tightens.

4. **Istio HPA death-spiral.**
   `istiod` and `istio-ingressgateway` each run an HPA `minReplicas=1 maxReplicas=5`,
   both pinned at **80%/80% CPU** → **5 replicas each** live. The HPA target is 80% of a
   tiny `50m`/`100m` request, so any real usage instantly exceeds 80% and the mesh pins to
   max replicas — adding 10 istio control/gateway pods (each with an envoy) to an
   already-starved node. Under CPU pressure the HPA makes the overcommit *worse*.

**Why the prior fix (`977d9e11` federation scrape 30s→60s) didn't help:** it trims one
Prometheus job. The problem is aggregate overcommit + missing resource governance + the
crashloop/HPA feedback loops, none of which scrape frequency touches.

**Hard constraint:** the M4 Air is a 10-core machine and Docker already holds all 10 — there
is **no headroom to add CPU**. The fix must reduce demand and restore control-plane
responsiveness.

## Fix — Step 1: resource governance (this spec)

Two committed-config edits. Both are governance, not load-shedding (load-shedding — cutting
prometheus/loki/istio footprint — is a separate follow-up spec).

### 1a. Bound the ArgoCD components

File: `scripts/etc/argocd/values.yaml.tmpl`. Add `resources:` to each block. Requests keep
the control plane's fair share; limits stop any one component from monopolizing the node.

```yaml
server:
  # ...existing...
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 250m, memory: 512Mi }

repoServer:
  # ...existing...
  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits:   { cpu: 500m, memory: 1Gi }

controller:
  # ...existing (keep --status-processors=5 --operation-processors=2)...
  resources:
    requests: { cpu: 250m, memory: 512Mi }
    limits:   { cpu: "1", memory: 1Gi }

applicationSet:
  # ...existing...
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 250m, memory: 256Mi }

redis:
  resources:
    requests: { cpu: 50m, memory: 64Mi }
    limits:   { cpu: 200m, memory: 256Mi }

notifications:
  resources:
    requests: { cpu: 25m, memory: 64Mi }
    limits:   { cpu: 150m, memory: 256Mi }
```

Notes:
- The `argo-cd` umbrella chart (pinned `ARGOCD_CHART_VERSION=7.8.1`) exposes
  `<component>.resources` for all of the above — verify key names against
  `helm show values argo/argo-cd --version 7.8.1` before applying.
- `argocd-image-updater` is a **separate** install (not in this umbrella chart); if it is
  also unbounded, bound it in its own manifest — track as a sub-item, do not block 1a on it.
- The controller limit of `1` CPU is deliberate headroom, not a throttle: it needs CPU to
  reconcile 25 apps, but a ceiling prevents it from pinning the node. Once apiserver latency
  drops, `persist_app_status_ms` should fall back to double digits and the hot loop stops.

### 1b. Stop the Istio HPA scale-out on the single-node hub

Pin the mesh control plane / gateway to 1 replica; on a single node there is nothing to gain
from horizontal scaling and the 80%-of-tiny-request target guarantees max replicas.

File: `scripts/etc/argocd/applicationsets/istio-ambient.yaml`, `istiod` element values
(currently lines 22–28):

```yaml
          - name: istiod
            chart: istiod
            wave: "1"
            values: |
              profile: ambient
              pilot:
                autoscaleEnabled: false      # was defaulting to min1/max5 @80%
                resources:
                  requests:
                    cpu: 50m
                    memory: 512Mi
                  limits:
                    cpu: 500m
                    memory: 1Gi
```

Ingress gateway HPA: the live `istio-ingressgateway` HPA (max 5) must get the same
treatment. **Locate its install first** — the live cluster is ambient, but the ambient
appset does not define a gateway, so it comes from a separate path (candidate:
`scripts/etc/istio-operator.yaml.tmpl` `spec.components.ingressGateways[].k8s.hpaSpec`, or a
standalone gateway chart). Set `autoscaleEnabled: false` (or `hpaSpec.maxReplicas: 1`) there.
Do not guess the file — confirm which manifest actually renders the live gateway before
editing.

## Out of scope (follow-up specs)

- **Load-shed** (separate spec): reduce prometheus-stack footprint (15 pods in `monitoring`),
  drop `loki-canary` DaemonSet, right-size Loki. This is the durable capacity fix.
- **CreateContainerConfigError on `postgres-keycloak`**: a config/secret bug, independent of
  CPU; file separately if it persists after governance lands.

## Rollout (NOT ad-hoc kubectl edits)

1. Edit the two committed files above on branch `k3d-manager-v1.27.0`.
2. Re-render/redeploy ArgoCD values via the plugin path (`argocd.sh` upgrade), not a live
   `kubectl edit`. Reapply the istio-ambient ApplicationSet per the CLAUDE.md
   "reapply ApplicationSets on every release" rule so `$values` tracks the release branch.
3. Because ArgoCD is self-managed, apply the ArgoCD-values change in a way that survives its
   own reconcile (via the chart/values it manages, not a live patch that will be reverted).

## Verification (acceptance)

- `docker stats --no-stream` — no k3d node container sustained > ~120%; VM total < ~900%.
- `kubectl exec` into the busiest node → `uptime` load average < ~15.
- `time kubectl get --raw='/livez?verbose'` — completes in < 0.5 s across 3 tries.
- Controller log `persist_app_status_ms` and `patch_ms` back to double/low-triple digits;
  no per-app reconcile more often than the resync interval.
- `kubectl get hpa -n istio-system` — istiod / ingressgateway at 1 replica (or HPA gone).
- Restart counts stop climbing: `repo-server`, `coredns`, `svclb-istio-ingressgateway`,
  `keycloak` steady over a 15-min window.
- ArgoCD apps that were `Unknown` settle to `Synced`/`Healthy` (or a real, stable status).

## Evidence captured 2026-08-27

- `docker stats`: agent-2 426%, server-0 318%, agent-1 335%, agent-0 298%; VM 10 CPU / 12.6 GB.
- agent-2 `top`: load 70.44, 21% idle.
- apiserver `/livez`: 5.30 s / 3.25 s / 1.39 s.
- controller log: `persist_app_status_ms=24044`, `patch_ms=12109`, `git_ms` 2–4 s, ~4 s
  reconcile cadence per app.
- resources `{}` on `argocd-application-controller` and `argocd-repo-server`.
- HPAs `istiod` and `istio-ingressgateway` both 5/5 @ 80%/80%.
- restarts: repo-server 216, svclb-istio-ingressgateway 453, coredns 138, keycloak 51.
