# 2026-06-14 — vCluster preflight Phase 1 retargeted live ArgoCD apps

## What was attempted

I attempted the initial Phase 1 preflight implementation with a throwaway vCluster named `phase1probe`:

- created the vCluster with `./scripts/k3d-manager vcluster_create phase1probe`
- applied the new `argocd-manager` RBAC manifest inside the vCluster
- minted a token with `kubectl --kubeconfig ~/.kube/vclusters/phase1probe.yaml create token argocd-manager -n kube-system --duration=8760h`
- registered the vCluster with hub ArgoCD as `cluster-phase1probe`
- bootstrapped ArgoCD ApplicationSets with `APP_CLUSTER_NAME=phase1probe`

## Actual output

The preflight script reached the wait step and then timed out. Before cleanup, the live ArgoCD application table showed that the new destination was affecting existing hub resources:

```text
acg-kube-prometheus-stack       phase1probe   Unknown     Unknown
acg-trivy-operator              phase1probe   Unknown     Unknown
data-layer                      ubuntu-k3s    Unknown     Healthy
kube-prometheus-stack           <none>        Synced      Healthy
phase1probe-platform            <none>        Unknown     Unknown
rollout-demo-default            <none>        Synced      Healthy
rollout-demo-staging            <none>        Synced      Healthy
shopping-cart-apps              <none>        Synced      Healthy
shopping-cart-basket            phase1probe   Synced      Degraded
shopping-cart-frontend          phase1probe   Synced      Degraded
shopping-cart-identity          <none>        Synced      Healthy
shopping-cart-namespace         phase1probe   Synced      Healthy
shopping-cart-networking        <none>        Synced      Healthy
shopping-cart-order             phase1probe   Synced      Degraded
shopping-cart-payment           phase1probe   Synced      Degraded
shopping-cart-product-catalog   phase1probe   OutOfSync   Missing
shopping-cart-rules             <none>        Synced      Healthy
trivy-operator                  <none>        Synced      Healthy
```

After cleanup, I restored the live bootstrap target with:

```text
APP_CLUSTER_NAME=ubuntu-hostinger ./scripts/k3d-manager deploy_argocd_bootstrap --skip-appproject
```

That re-applied the live ApplicationSets back onto `ubuntu-hostinger`.

## Root cause

The first implementation reused the shared ArgoCD bootstrap path directly. That path re-applies the live `services-git` and `observability-acg` ApplicationSets in place, which is unsafe when targeting an additional cluster because it can retarget the live `ubuntu-hostinger` apps while the throwaway vCluster is being created.

The live cluster also showed that the platform-side apps need a destination allowlist that includes the vCluster name, so the preflight cannot rely on the current shared `platform` project as-is.

## Recommended follow-up

- Generate preflight-specific ArgoCD resources for the throwaway vCluster instead of mutating the live ApplicationSets in place.
- Keep the live `ubuntu-hostinger` ApplicationSets untouched.
- Use a preflight-specific platform AppProject clone that permits the vCluster destination.
- Prefix the preflight ApplicationSet and Application names so they can coexist with the live names.
