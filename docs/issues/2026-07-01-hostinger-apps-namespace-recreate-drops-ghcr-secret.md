# Issue: Hostinger apps namespace recreation drops imperative `ghcr-pull-secret`

## What I tested

I inspected the live `ubuntu-hostinger` cluster after `shopping-cart-apps` pods entered `ImagePullBackOff`.

Relevant output:

```text
$ kubectl --context ubuntu-hostinger -n shopping-cart-apps get secret ghcr-pull-secret -o yaml
Error from server (NotFound): secrets "ghcr-pull-secret" not found

$ kubectl --context k3d-k3d-cluster -n cicd get application shopping-cart-namespace -o yaml
...
status:
  history:
  - deployedAt: "2026-07-02T00:57:30Z"
    initiatedBy:
      automated: true
  operationState:
    message: successfully synced (no more tasks)
    syncResult:
      resources:
      - kind: Namespace
        message: namespace/shopping-cart-apps created
        name: shopping-cart-apps
```

## Root cause

The `shopping-cart-namespace` ArgoCD application owns only the namespace object. The GHCR pull secret was being created imperatively by the Hostinger bootstrap path, so a namespace re-create removed it and left `shopping-cart-apps` without registry auth.

## Follow-up

Make the `shopping-cart-apps` namespace app own `ghcr-pull-secret` declaratively so namespace re-creation cannot strand private image pulls again.
