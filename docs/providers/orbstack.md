# OrbStack Provider Guide

OrbStack is the default macOS provider when its `orb` daemon is running. The dispatcher auto-selects it — no manual configuration needed in most cases.

## Auto-Detection

When you run `./scripts/k3d-manager` on macOS:
- If OrbStack is running → `CLUSTER_PROVIDER=orbstack` (auto-selected)
- If OrbStack is not running → falls back to `k3d`

## Force OrbStack

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager create_cluster
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_cluster
```

## How It Works

The dispatcher sets `DOCKER_CONTEXT` to OrbStack's Docker context before invoking any k3d commands. Cluster lifecycle operations (create, destroy, kubeconfig) target OrbStack's runtime without extra manual steps.

## Verification

```bash
orb status                       # OrbStack daemon status
./scripts/k3d-manager deploy_cluster   # should auto-select orbstack
./scripts/k3d-manager test all         # validate all services
```
