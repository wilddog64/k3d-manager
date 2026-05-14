# Issue: Argo CD VirtualService host still defaults to `argocd.dev.local.me`

## What happened
Even after rebuilding the clusters, the Argo CD login flow can still fail with:

```text
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

The live `argocd-cm` in the `cicd` namespace was advertising:

```yaml
url: https://argocd.dev.local.me
```

while the user-facing browser entrypoint is the canonical shopping-cart hostname:

```text
https://argocd.shopping-cart.local
```

## Root cause
`k3d-manager/scripts/etc/argocd/vars.sh` still defaulted `ARGOCD_VIRTUALSERVICE_HOST` to `argocd.dev.local.me`, so a fresh Argo CD deployment kept writing the stale URL back into the Helm values and ConfigMap.

## Fix
Change the default Argo CD VirtualService host to `argocd.shopping-cart.local` so new cluster rebuilds publish the canonical browser URL consistently.

## Follow-up
Rebuild the cluster or redeploy Argo CD so the live `argocd-cm` picks up the canonical host value and `/auth/login` stops rejecting the browser return URL.
