# Hostinger Istio ambient reconciliation drift

## What was tested

Live ArgoCD Application status and computed diffs for the Hostinger Istio ambient applications, followed by read-only workload inspection on the Hostinger k3s cluster.

## Actual output

```text
istio-base-ubuntu-hostinger
admissionregistration.k8s.io/ValidatingWebhookConfiguration /istiod-default-validator health=
sync=OutOfSync health=Healthy rev=1.24.2

istio-cni-ubuntu-hostinger
apps/DaemonSet istio-system/istio-cni-node health=
sync=OutOfSync health=Progressing rev=1.24.2

istiod-ubuntu-hostinger
admissionregistration.k8s.io/ValidatingWebhookConfiguration /istio-validator-istio-system health=
apps/Deployment istio-system/istiod health=
sync=OutOfSync health=Healthy rev=1.24.2
```

ArgoCD's computed diffs showed the same Istio-owned bootstrap transition for both validation webhooks:

```diff
<   failurePolicy: Fail
---
>   failurePolicy: Ignore
```

The CNI DaemonSet was not healthy:

```text
NAME             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
istio-cni-node   1         1         0       1            0

Warning  Unhealthy  ... (x119994 over 13d)  kubelet
spec.containers{install-cni}: Readiness probe failed: HTTP probe failed with statuscode: 503
```

The Hostinger node identifies itself as `v1.36.2+k3s1`. Application history showed the earlier k3s CNI directories before a later render replaced them with generic Cilium paths.

## Root cause

1. Helm intentionally emits validating webhooks with `failurePolicy: Ignore`; Istiod changes the policy to `Fail` and injects a CA bundle once it is ready. ArgoCD interpreted those controller-owned changes as Git drift and retried reconciliation thousands of times.
2. Hostinger's k3s cluster was rendered with `/etc/cni/net.d` and `/opt/cni/bin`, rather than `/var/lib/rancher/k3s/agent/etc/cni/net.d` and `/var/lib/rancher/k3s/data/cni`. The Istio CNI agent consequently remained unready.

## Fix and follow-up

Source fix `fb3df7d4` adds exact ArgoCD ignore rules for the two controller-owned webhooks and renders the k3s CNI paths from the Hostinger provider. A second source fix, `0510e1f8`, enables ArgoCD Server-Side Diff for this ApplicationSet. This is required because `ServerSideApply=true` otherwise selects structured-merge comparison, which retains false drift on Kubernetes defaulted fields. Kubernetes server-side dry-run reported no changes with the `argocd-controller` field manager.

The ApplicationSet was deployed with `deploy_istio_ambient --confirm`. Final live verification:

```text
istio-base-ubuntu-hostinger sync=Synced health=Healthy
istio-cni-ubuntu-hostinger sync=Synced health=Healthy
istiod-ubuntu-hostinger sync=Synced health=Healthy

istio-cni-node   1   1   1   1   1
```

Repeat verification with:

```text
kubectl --context ubuntu-hostinger -n istio-system get daemonset istio-cni-node
kubectl --context k3d-k3d-cluster -n cicd get applications.argoproj.io \
  istio-base-ubuntu-hostinger istio-cni-ubuntu-hostinger istiod-ubuntu-hostinger
```
