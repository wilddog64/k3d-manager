# Trivy Operator CrashLoopBackOff due to Cache Sync Timeout

## What was checked

1. The live pod status of `trivy-operator` in both contexts:
   - Infra Cluster (`k3d-k3d-cluster`): `trivy-operator-798c657fbf-ntrcl` in `CrashLoopBackOff` (restarted 110 times in 12 hours).
   - App Cluster (`ubuntu-hostinger`): `acg-trivy-operator-64f8cf786d-wbhqr` in `CrashLoopBackOff` (restarted 110 times in 12 hours).
2. Pod logs using `kubectl logs` showing cache sync timeouts on startup:
   ```text
   unable to run trivy operator: starting controllers manager: failed to wait for configmap caches to sync kind source: *v1.ConfigMap: timed out waiting for cache to be synced for kind source: *v1.ConfigMap
   ```
3. The resource limits configured in the Helm values template:
   - `scripts/etc/helm/observability/trivy-operator-values.yaml` sets `limits.cpu: 100m` and `limits.memory: 96Mi` for the operator container.

## Actual Output

During startup, the controller-runtime manager attempts to initialize informers and sync caches for a large variety of resources (ConfigMaps, Pods, Services, CRDs, etc.). 

Due to the strict CPU throttling at `cpu: 100m`, the CPU-intensive process of parsing and caching resource states from the API server cannot complete within the default 2-minute timeout window:

```text
{"level":"error","ts":"2026-07-04T01:41:01Z","msg":"Could not wait for Cache to sync","controller":"configmap","controllerGroup":"","controllerKind":"ConfigMap","source":"kind source: *v1.ConfigMap","error":"failed to wait for configmap caches to sync kind source: *v1.ConfigMap: timed out waiting for cache to be synced for kind source: *v1.ConfigMap","stacktrace":"..."}
...
unable to run trivy operator: starting controllers manager: failed to wait for configmap caches to sync kind source: *v1.ConfigMap: timed out waiting for cache to be synced for kind source: *v1.ConfigMap
```

This causes the Go binary to terminate with exit code 1, triggering a crash loop.

## Root Cause

PR #102 upgraded the Trivy Operator image from `0.22.0` to `0.31.2` to resolve reconciliation errors on Kubernetes 1.31+ clusters. However, the newer `0.31.2` operator registers more controllers and watches more resource types, which increases CPU and memory demands during the initial cache sync process. 

The existing resource limits (`cpu: 100m` / `memory: 96Mi`) are insufficient for the upgraded operator to perform cache synchronization within the 2-minute controller-runtime window, resulting in startup timeouts.

## Recommended Follow-Up

Increase the resource requests and limits for the operator in [trivy-operator-values.yaml](file:///Users/cliang/src/gitrepo/personal/k3d-manager/scripts/etc/helm/observability/trivy-operator-values.yaml):

```yaml
operator:
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 500m
```
