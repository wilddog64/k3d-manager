# `ubuntu-hostinger-platform` keeps reconciling because it still tracks stale shopping-cart resources

## What I Checked

I inspected the live ArgoCD Application for `ubuntu-hostinger-platform`, its resource list, and the live metadata on a Hostinger shopping-cart deployment.

## Actual Output

The application stayed `OutOfSync / Progressing` while repeatedly syncing:

```text
ubuntu-hostinger-platform	OutOfSync	Progressing
```

Its live resource list included both ArgoCD install objects and shopping-cart workload objects:

```text
ConfigMap/argocd-cm	cicd	OutOfSync
Service/order-service	shopping-cart-apps	OutOfSync
ServiceAccount/order-service	shopping-cart-apps	OutOfSync
Deployment/order-service	shopping-cart-apps	OutOfSync
```

The live Hostinger deployment carried this ownership annotation:

```text
argocd.argoproj.io/tracking-id: ubuntu-hostinger-platform:apps/Deployment:shopping-cart-apps/order-service
```

The `platform-helm` ApplicationSet is configured with:

```yaml
syncPolicy:
  automated:
    prune: false
    selfHeal: true
```

## Root Cause

`ubuntu-hostinger-platform` still owns a mixed resource set from two different eras:

- the current ArgoCD-on-Hostinger install resources
- stale shopping-cart resources in `shopping-cart-apps`

Because `prune: false`, ArgoCD will not delete the stale shopping-cart objects even though the current desired source is the ArgoCD chart. That leaves the app permanently `OutOfSync`, which in turn keeps self-heal reconciling it over and over.

## Recommended Follow-Up

- Separate the Hostinger platform app from shopping-cart workload ownership, or
- explicitly prune/recreate the stale `shopping-cart-apps` objects after confirming they are no longer desired.

The key point is that the 10-hour churn is not a pod failure; it is a mixed-ownership ArgoCD app that can never converge while stale tracked resources remain.

## Resolution

The cleanup path is now permanent in `scripts/lib/providers/k3s-hostinger.sh`:

- it enumerates every `shopping-cart` resource in `shopping-cart-apps` by label,
- clears only the ones whose tracking ID still starts with `ubuntu-hostinger-platform:`,
- and hard-refreshes the affected hub ArgoCD applications after the stale ownership is removed.

The helper no longer depends on a hardcoded basket/product-catalog list, so the stale ownership cleanup now covers current and future shopping-cart resources that carry the same bad platform tracking prefix.
