# dev-hub: `dev-hub-up` Argo CD `helm --wait` times out when the vCluster syncer restarts during startup

**Status:** OPEN
**Priority:** P1 (Claude proposal, raised 2026-11-13: a rerun cannot recover, and the only way back is down/up, which can hit the same timeout; blocks the plan E2 live check)
**Classified:** pending (Argon, from this doc alone)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** b2067ad3 or later Part B commit that added the Argo CD install with `--wait` and no `--timeout` (unknown which)
**Should have been caught by:** live check (offline tests cannot see startup timing)
**Prior art:** exact-slug glob, no match; `make find-similar-docs` not run (vector store context missing on m4-air)
**Approval:** pending

## Symptom

m5-air, 2026-11-13, second `make dev-hub-down` then `make dev-hub-up` (5c253d1b promoted):

    context deadline exceeded
    helm command failed (1): helm --kubeconfig ~/.kube/vclusters/dev-hub.yaml upgrade --install argocd argo/argo-cd -n cicd --create-namespace --version 10.10.5 -f scripts/etc/dev-hub/argocd-values.yaml --wait
    make: *** [dev-hub-up] Error 1

Grafana was never installed, because the run stopped first. About 4 minutes later:
- All 7 host pods in namespace `dev-hub` were Running and 1/1.
- The quota was not near its cap: 2304Mi of 3Gi in memory limits.
- No image pulls happened: every image was "already present on machine".

## What the events show

- `dev-hub-0` failed its `/readyz` readiness probe several times, then restarted its `syncer` container once, about 40 s after its first start.
- During that window, `argocd-server` and `application-controller` probes got connection refused.
- `argocd-applicationset-controller` restarted twice and went into `BackOff`. Its last start came about 4.5 minutes after the pod was created, just about when Helm's 5-minute default timeout ran out.

## Likely cause (not yet proven)

1. The vCluster API restarted while Argo CD was starting.
2. `applicationset-controller` exits when its API is unreachable and lands in CrashLoopBackOff, whose back-off delay doubles each time.
3. `--wait` without `--timeout` gives up after Helm's 5-minute default.

The first run on 2026-11-13 succeeded only because the syncer did not restart that time. To prove it: `kubectl --context k3d-k3d-cluster -n dev-hub logs <applicationset pod> --previous` at the next recurrence.

Separately, after the failure `~/.kube/vclusters/dev-hub.yaml` points to 127.0.0.1:11444 and the connection is refused, because the connect proxy is gone. `dev-hub-up` and its readiness wait refresh the connection (`_vcluster_refresh_connection`), so a rerun recovers it.

## Workaround

**Rerunning does NOT work.** Claude first wrote here that a rerun recovers; that was wrong and was never checked. The operator's rerun on m5-air, 2026-11-13:

    Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
    helm command failed (1): helm --kubeconfig ~/.kube/vclusters/dev-hub.yaml upgrade --install argocd argo/argo-cd ... --wait

The timed-out install left the `argocd` release in a pending state, and Helm refuses every later operation on it. The only way back is `make dev-hub-down`, which deletes the vCluster together with its Helm release Secrets, followed by `make dev-hub-up`. That can time out again in the same way.

## Fix options (for triage)

The fix needs all three:
1. **Recover a stuck release before installing.** If `helm status` reports `pending-install`, `pending-upgrade` or `pending-rollback`, roll the release back, or uninstall it if it has no deployed revision. Then `dev-hub-up` can be rerun.
2. **Do not leave a pending release behind.** Use the deployed Helm's own failure rollback, `--rollback-on-failure` in Helm 4 (the old `--atomic`), so a timeout cleans up after itself. This has to be proven against the Helm version on the M5 before dispatch.
3. **Give startup time.** Set an explicit `--timeout`, for example 10m, on both chart installs. Optionally, wait for the vCluster to settle first.

Evidence to capture before the spec, read-only on the M5: `helm version --short`; `helm --kubeconfig ~/.kube/vclusters/dev-hub.yaml -n cicd history argocd`; the `applicationset-controller` previous-container log.
