# Issue: Shopping Cart Apps — ImagePullBackOff (401 + Arch Mismatch)

**Date:** 2026-03-17
**Status:** MITIGATED (Secret Created) — Blocker (Arch Mismatch)

---

## Problem

Shopping cart microservices deployed to the Ubuntu k3s app cluster were stuck in `ImagePullBackOff` for two reasons:
1.  **401 Unauthorized:** Images on `ghcr.io/wilddog64/` are private, and the app cluster lacked a `docker-registry` pull secret.
2.  **Architecture Mismatch:** Images in `ghcr.io` were built for `linux/amd64`, but the Ubuntu k3s nodes are `arm64` (running on Apple Silicon).

---

## Findings

- **Auth:** `kubectl describe pod` revealed: `failed to authorize: failed to fetch anonymous token: 401 Unauthorized`.
- **Platform:** After creating a pull secret, the error changed to: `no match for platform in manifest: not found`.
- **Root Cause:** App repositories (e.g., `shopping-cart-basket`) use a pinned version of the `build-push-deploy.yml` reusable workflow (`8363caf`) from `shopping-cart-infra`. That specific commit lacks the `platforms: linux/amd64,linux/arm64` input added in later PRs.

---

## Fix Summary

- **ghcr-pull-secret:** Created a `docker-registry` secret in `shopping-cart-apps`, `shopping-cart-payment`, and `shopping-cart-data` namespaces on the app cluster.
- **ArgoCD sync:** Forced sync via `kubectl patch` to ensure latest manifests were applied.
- **Infra Fix (Branch):** Pushed `fix/argocd-image-pull` to `shopping-cart-infra` repo to:
  - Update `destination.server` to `host.k3d.internal:6443` for cross-cluster connectivity.
  - Add `imagePullSecrets: [{name: ghcr-pull-secret}]` patch via Kustomize.

---

## Verification

```bash
# Verify secret existence
export KUBECONFIG=~/.kube/k3s-ubuntu.yaml
kubectl get secret ghcr-pull-secret -n shopping-cart-apps

# Verify platform error
kubectl describe pod <pod-name> -n shopping-cart-apps | grep "no match for platform"
```

## Next Steps (Blocker)

- Update app repositories to use the latest `main` version of the reusable workflow in `shopping-cart-infra` to enable multi-arch builds.
- Re-run CI on all 5 app repositories to push `arm64` images to `ghcr.io`.

---

## Commits (k3d-manager)

- `1384a0d` — Initial diagnosis and memory bank update.
- `64902ba` — Final task completion and blocker documentation.
- `f1e12b1` — Fix in `shopping-cart-infra` repo (branch: `fix/argocd-image-pull`).
