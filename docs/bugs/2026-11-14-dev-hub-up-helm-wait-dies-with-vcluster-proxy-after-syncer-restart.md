# Bug: dev-hub-up fails when the syncer restarts mid-install: the vCluster background proxy dies and Helm loses the cluster

**Status:** OPEN — captured 2026-11-14 by Claude
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-14
**Introduced by:** pre-existing
**Should have been caught by:** live check
**Prior art:** exact-slug glob: none; read `docs/bugs/2026-08-16-e2e-vcluster-kubeconfig-proxy-port-drift.md` (same proxy behaviour, e2e only; e2e got `_vcluster_refresh_connection` in its readiness loop, `scripts/plugins/e2e.sh:672`, dev-hub never did); related `docs/bugs/2026-11-13-dev-hub-up-argocd-helm-wait-times-out-after-syncer-restart.md` (leader-election cause, fixed; this run is its E2 steps 2-3)
**Approval:** none yet (capture only)

## Symptom

Operator ran `make dev-hub-up` on m5-air, 2026-11-14 ~20:21Z, from a dev-hub with no namespace (checkout `849ddfcf`, contains `f1eeeb26`). It failed (operator terminal):

    Error: an error occurred while uninstalling the release. original install error: resource CustomResourceDefinition//applicationsets.argoproj.io not ready. status: InProgress, message: Install in progress
    ...
    context deadline exceeded: kubernetes cluster unreachable: Get "https://127.0.0.1:11444/version": net/http: TLS handshake timeout
    helm command failed (1): helm --kubeconfig ~/.kube/vclusters/dev-hub.yaml upgrade --install argocd argo/argo-cd -n cicd --create-namespace --version 10.10.5 -f .../argocd-values.yaml --wait --rollback-on-failure --timeout 10m
    make: *** [dev-hub-up] Error 1

Grafana was never reached.

## Evidence (Claude, read-only from m5-air over SSH, 2026-11-14 20:28Z-20:45Z)

1. The vCluster API server stalled under the Argo CD install. Previous `syncer` log (`kubectl -n dev-hub logs dev-hub-0 -c syncer --previous`): `/readyz` and `/healthz` "Post-timeout activity" at 28 s to 121 s, `http: Handler timeout`, etcd client "retrying of unary invoker failed". Events: `Container syncer failed liveness probe, will be restarted`; lastState `Error`, exit 137, at 20:25:55Z. Liveness is 3 s timeout, 2 s period, threshold 60. `argocd-server` also failed liveness (5 restarts by 20:32Z; applicationset-controller 2).
2. The local proxy died with that restart and never came back. `127.0.0.1:11444` is Docker container `vcluster_dev-hub_dev-hub_k3d-k3d-cluster_background_proxy` running `port-forward svc/dev-hub 8443:443` (started 20:21:06Z). Its log: `Failed handling connection ... error forwarding port 8443 to pod 225d2bde...` from 20:25:56Z, one second after the kill. At 20:45Z `curl https://127.0.0.1:11444/version` still timed out (10 s), while the same API through the host apiserver service proxy (`/api/v1/namespaces/dev-hub/services/https:dev-hub:443/proxy/readyz`) returned `ok`.
3. So from 20:25:56Z Helm's `--wait` and then its rollback uninstall ran against a dead endpoint. Argo CD itself came up: all five Argo CD pods Running at 20:32Z.
4. Syncer resources: requests cpu 200m / memory 256Mi, limits cpu 500m / memory 768Mi. That one container runs the vCluster apiserver, etcd, controller-manager and syncer. cgroup `cpu.stat` after the restart (idle): `nr_throttled 79` of `nr_periods 5528`, `throttled_usec 6963984`; counters before the kill are lost.

## Not yet known

- Why the apiserver stalled: CPU throttling at the 500m limit (suspected, not proven) or slow etcd writes on OrbStack. Needs `cpu.stat` sampled every few seconds during an install.
- The Argo CD release state inside the vCluster after the failed rollback (unreadable while the proxy is dead).

## Fix direction (for triage)

1. `dev_hub_up` (`scripts/plugins/dev_hub.sh`): check the proxy before each Helm step and refresh it with `_vcluster_refresh_connection` (`scripts/plugins/vcluster.sh`) as e2e does; or run Helm against a kubeconfig that does not depend on the background proxy.
2. Raise the syncer CPU limit (or drop the CPU limit, keep the request) once the throttle sample proves it; the stall is what triggers the restart.
3. Recovery today: `make dev-hub-up` again. `_dev_hub_wait_ready` (`scripts/plugins/dev_hub.sh:252`) already calls `_vcluster_refresh_connection` before the charts, so the proxy is only unprotected during the Helm steps; the pending-install recovery from `f1eeeb26` should handle the release. (`_vcluster_refresh_connection` is private and the dispatcher refuses it.)
