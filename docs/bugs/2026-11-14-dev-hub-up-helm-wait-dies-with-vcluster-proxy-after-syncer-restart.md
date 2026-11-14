# Bug: dev-hub-up fails when the syncer restarts mid-install: the vCluster background proxy dies and Helm loses the cluster

**Status:** OPEN — captured 2026-11-14 by Claude
**Priority:** P2
**Waiting on:** fix running — since 2026-11-14 (`dev-hub-proxy-retry`, Luna)
**Intent approved:** operator, 2026-11-14
**Introduced by:** pre-existing
**Should have been caught by:** live check
**Prior art:** exact-slug glob: none; read `docs/bugs/2026-08-16-e2e-vcluster-kubeconfig-proxy-port-drift.md` (same proxy behaviour, e2e only; e2e got `_vcluster_refresh_connection` in its readiness loop, `scripts/plugins/e2e.sh:672`, dev-hub never did); related `docs/bugs/2026-11-13-dev-hub-up-argocd-helm-wait-times-out-after-syncer-restart.md` (leader-election cause, fixed; this run is its E2 steps 2-3)
**Approval:** operator, 2026-11-14 ("go ahead to file a P2 bug and dispatch to Luna when there's a slot for it")

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

## Recurrence check: run 3 (2026-11-14 ~20:39Z-20:42:36Z)

The plain `make dev-hub-up` rerun recovered: proxy refreshed by `_dev_hub_wait_ready`, pending argocd release uninstalled, argocd and Grafana deployed, no syncer restart. Syncer `cpu.stat` across the run (Claude's 4 s sampler caught only the end; the earlier idle read gives the baseline): from `nr_periods 5528 / nr_throttled 79 / throttled_usec 6963984` to `9823 / 208 / 23217018` at 20:42:32Z, so 129 of 4295 periods throttled (3%), 16.3 s throttled. Inconclusive for the stall: this install reused the three Argo CD CRDs, and the run-2 stall happened during CRD install. A fresh `dev-hub-down` plus `dev-hub-up` with the sampler running from the start is still the test.

## Fix (spec for dispatch)

Scope: fix direction 1 only. The CPU limit (direction 2) waits for a throttle sample from a fresh run and is not part
of this dispatch.

In `scripts/plugins/dev_hub.sh`, `_dev_hub_install_charts` (`:180-222`) runs two `helm upgrade --install ... --wait
--rollback-on-failure` steps (argocd, then dev-hub-grafana) through `_dev_hub_child_helm` (`:57`), which uses
`DEV_HUB_KUBECONFIG` and so the background proxy on `127.0.0.1:${DEV_HUB_LOCAL_PORT}`.

1. Add a private helper (name yours, for example `_dev_hub_ensure_connection`) that probes `/readyz` through
   `DEV_HUB_KUBECONFIG` with `--request-timeout=5s`, the same probe `_dev_hub_wait_ready` uses (`:257-258`). If the
   probe fails, it calls `_vcluster_refresh_connection "${DEV_HUB_NAME}"` and re-probes with a bounded retry loop
   (reuse or extract the `_dev_hub_wait_ready` loop rather than writing a second one). It fails with an `_err` message
   that names `make dev-hub-status` when the vCluster is still unreachable.
2. Call that helper before each of the two `_dev_hub_recover_release` calls, so a proxy that died during the argocd
   step is replaced before Grafana starts.
3. Wrap each of the two `helm upgrade --install` calls: when helm fails, probe `/readyz` once. If the probe succeeds,
   the failure is real (chart, values, timeout with a live cluster): return the failure, no retry. If the probe fails,
   run the helper from step 1, then `_dev_hub_recover_release <release> <namespace> "${temp_dir}"` (it uninstalls a
   `pending-install` and rolls back a `pending-upgrade`), then run the same helm command exactly once more. A second
   failure returns the failure. Never more than one retry per release.
4. Print one line to stderr when the retry path runs, naming the release and saying the vCluster connection was
   refreshed after helm lost the cluster, so the operator can see it happened.

Keep `_run_command` routing, the `set +x` around the password, and the existing error messages. No change to
`vcluster.sh`, the port, the kubeconfig path or the proxy container name.

## Files

- `scripts/plugins/dev_hub.sh`
- `scripts/tests/plugins/dev_hub.bats`
- `docs/howto/dev-hub.md` (one short paragraph: what dev-hub-up does when the syncer restarts mid-install; and that
  `make dev-hub-up` is the recovery, never a private function)
- (not `CHANGELOG.md`: `parallel-offline-tests-b` has it open; Claude adds the entry at land)

## Contract readers

No shared contract changes: `DEV_HUB_LOCAL_PORT` (`scripts/plugins/dev_hub.sh:7`), `DEV_HUB_KUBECONFIG`, the proxy
container name built in `_vcluster_remove_proxy` (`scripts/plugins/vcluster.sh:250-262`) and the Helm release names
stay as they are. Callers of `_vcluster_refresh_connection` today: `scripts/plugins/dev_hub.sh:253`,
`scripts/plugins/e2e.sh:91`, `scripts/plugins/e2e.sh:678`; this fix adds dev_hub.sh callers only and does not change
the function. The worker greps `_dev_hub_wait_ready` and lists every caller if it extracts the probe loop.

## Acceptance

```yaml
must:
  M1: when the argocd helm step fails and the readyz probe through DEV_HUB_KUBECONFIG then fails, dev_hub_up calls _vcluster_refresh_connection dev-hub, runs release recovery for argocd/cicd, runs the same argocd helm command a second time, and when that succeeds goes on to install Grafana and exits 0
  M2: the same for the dev-hub-grafana step in namespace monitoring
  M3: when a helm step fails while the readyz probe succeeds, dev_hub_up exits non-zero after exactly one helm call for that release, with no refresh and no recovery after the failure
  M4: when the retried helm call fails again, dev_hub_up exits non-zero after exactly two helm calls for that release
  M5: when the vCluster stays unreachable after the refresh, dev_hub_up exits non-zero with a message naming make dev-hub-status, and runs no further helm upgrade
  M6: the retry path prints one stderr line naming the release
must_not:
  N1: a proxy death during the argocd helm step (helm fails, readyz fails) ends dev_hub_up with a failure and no refresh-and-retry
  N2: a proxy that is dead when the argocd step finishes makes the Grafana recovery or install run against it without a readyz probe and refresh first
  N3: any test runs real helm, kubectl, vcluster, docker or security, or reads the real HOME or ~/.kube
evidence:
  - {id: E1, proves: [M1, M2, M6, N1, N2], kind: offline, intent: "You will see dev_hub.bats run dev_hub_up with stub helm, kubectl and vcluster that write every call to a log. The stub helm fails the first argocd (then, in a second test, Grafana) install, and the stub readyz probe fails until the refresh is called. The test reads the call log and finds, in order: the failed install, the refresh, the release recovery, the second install, then Grafana. On today's code dev_hub_up stops at the first failure, so these tests fail."}
  - {id: E2, proves: [N2], kind: offline, intent: "You will see a test where argocd installs fine but the stub readyz probe starts failing right after it. The call log shows a probe and a refresh before any Grafana Helm call. On today's code the Grafana steps go straight to the dead endpoint, so the test fails."}
  - {id: E3, proves: [M3, M4, M5], kind: offline, intent: "You will see three tests that count helm calls in the log: a chart failure with a healthy cluster makes one call and no refresh; a failure on the retry stops at two; a vCluster that stays unreachable stops with the dev-hub-status message. These guard against the fix hiding real failures or looping."}
  - {id: E4, proves: [N3], kind: offline, intent: "You will see each new test assert first that HOME is the scratch directory and that the stub directory is first on PATH, before it runs dev_hub_up."}
  - {id: E5, proves: [M1, N1], kind: live, intent: "On the M5, after dev-hub-down, you run make dev-hub-up and, once the log shows the argocd install has started, delete the syncer pod with kubectl --context k3d-k3d-cluster -n dev-hub delete pod dev-hub-0. The run still ends with argocd and Grafana deployed, and the log shows the refresh line. Claude samples the syncer cpu.stat every few seconds through the run, which also gives the throttle data fix direction 2 is waiting for."}
interface:
  - "make dev-hub-up (unchanged command; new stderr line on the retry path)"
  - "docs/howto/dev-hub.md recovery paragraph"
```
