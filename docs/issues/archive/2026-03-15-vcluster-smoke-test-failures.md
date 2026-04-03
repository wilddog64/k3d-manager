# Issue: vCluster plugin smoke test failures (v0.9.1)

**Date:** 2026-03-15
**Component:** `scripts/plugins/vcluster.sh`, Help System

## Description

During the Gemini smoke test of v0.9.1 on the M2 Air infra cluster, two issues were identified:

1.  **vCluster pod selector mismatch:** `vcluster_create` fails during the readiness check because it uses a pod selector that does not match the labels applied by vCluster v0.32.1.
2.  **Missing help categories:** `vcluster` functions are missing from the `./scripts/k3d-manager --help` output because the plugin script lacks `@category` tags.

## Evidence

### 1. vCluster Pod Selector Mismatch

The `_vcluster_wait_ready` function uses:
`selector="app.kubernetes.io/name=vcluster,app.kubernetes.io/instance=${name}"`

However, `kubectl get pods -n vclusters --show-labels` shows the following labels for the `smoke-test` vCluster:
`app=vcluster,release=smoke-test,apps.kubernetes.io/pod-index=0,controller-revision-hash=smoke-test-7fbf6f756,statefulset.kubernetes.io/pod-name=smoke-test-0`

This causes `kubectl wait` to fail with `error: no matching resources found`, which prevents the function from exporting the kubeconfig.

### 2. Missing Help Categories

Running `./scripts/k3d-manager --help` shows the standard categories, but `vcluster_create`, `vcluster_list`, etc., are not listed. This is because `scripts/plugins/vcluster.sh` does not contain the required `@category` comments used by the help parser in `scripts/lib/help/utils.sh`.

## Impact

-   `vcluster_create` cannot complete successfully, leaving the vCluster in an "unmanaged" state (created but without a local kubeconfig).
-   Users cannot discover vCluster functions via the built-in help system.

## Recommendation

1.  Update `scripts/plugins/vcluster.sh`:
    -   Change the pod selector in `_vcluster_wait_ready` to `app=vcluster,release=${name}`.
    -   Add `@category Cluster lifecycle` (or a new category) to the public functions.
2.  Verify the fix by re-running the Gemini smoke test.
