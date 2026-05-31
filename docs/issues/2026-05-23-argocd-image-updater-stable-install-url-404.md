# ArgoCD Image Updater spec references a stale raw install URL

**Date:** 2026-05-23
**Area:** `docs/plans/v1.4.9-argocd-image-updater.md`

## What was tested

Attempted to follow the spec literally with:

```bash
kubectl apply -k scripts/etc/argocd/image-updater/ --context k3d-k3s-cluster
```

## Actual output

```text
error: accumulating resources: accumulation err='accumulating resources from 'https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml': URL is a git repository': failed to run '/opt/homebrew/bin/git fetch --depth=1 https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater HEAD': remote: 404: Not Found
fatal: repository 'https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/' not found
: exit status 128
```

## Root cause

The spec points `scripts/etc/argocd/image-updater/kustomization.yaml` at a stale upstream raw URL. The current upstream manifest path is `config/install.yaml` in `argoproj-labs/argocd-image-updater` on `stable`.

## Follow-up

Keep the repo file as written per the spec, but use the current upstream `config/install.yaml` path when applying the manifest locally or in cluster automation.
