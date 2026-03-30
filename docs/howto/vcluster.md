# How-To: vCluster (Virtual Kubernetes Clusters)

The `vcluster` plugin creates lightweight virtual Kubernetes clusters inside the infra cluster (k3d/OrbStack). Each vCluster runs as a StatefulSet in the `vclusters` namespace and exposes its own isolated API server. Use them for tenant isolation, environment separation, or ephemeral test clusters without provisioning real EC2 nodes.

## Prerequisites

- Infra cluster running (`kubectl cluster-info` succeeds)
- vcluster CLI — auto-installed by any `vcluster_*` command if missing

## Quick Start

```bash
# Create a vCluster named "dev"
./scripts/k3d-manager vcluster_create dev

# Switch to it
./scripts/k3d-manager vcluster_use dev

# List all vClusters
./scripts/k3d-manager vcluster_list

# Destroy it
./scripts/k3d-manager vcluster_destroy dev
```

---

## Commands

### `vcluster_create <name>`

Creates a vCluster and exports its kubeconfig.

```bash
./scripts/k3d-manager vcluster_create dev
./scripts/k3d-manager vcluster_create staging
```

- Deploys into namespace `vclusters` (override: `VCLUSTER_NAMESPACE`)
- Chart version: `0.32.1` (override: `VCLUSTER_VERSION`)
- Values: `scripts/etc/vcluster/values.yaml` (200m/256Mi requests, 500m/512Mi limits)
- Kubeconfig written to `~/.kube/vclusters/<name>.yaml`
- Waits up to 300s for the vCluster pod to be Ready before returning

```bash
# Dry-run — prints what would happen, makes no changes
DRY_RUN=1 ./scripts/k3d-manager vcluster_create dev
```

### `vcluster_use <name>`

Merges the vCluster kubeconfig into `~/.kube/config` and switches the active context.

```bash
./scripts/k3d-manager vcluster_use dev
```

- Requires a kubeconfig at `~/.kube/vclusters/<name>.yaml` (created by `vcluster_create`)
- Merges using `kubectl config view --flatten` — existing contexts are preserved
- Sets `kubectl` active context to the vCluster context

To switch back to the infra cluster:

```bash
kubectl config use-context k3d-k3d-cluster   # or whatever your infra context is named
```

### `vcluster_destroy <name>`

Deletes the vCluster and removes its kubeconfig file.

```bash
./scripts/k3d-manager vcluster_destroy dev
```

- Waits for full deletion (`--wait`) before returning
- Removes `~/.kube/vclusters/<name>.yaml`

```bash
# Dry-run
DRY_RUN=1 ./scripts/k3d-manager vcluster_destroy dev
```

### `vcluster_list`

Lists all vClusters in the active namespace.

```bash
./scripts/k3d-manager vcluster_list
```

### `vcluster_install_cli`

Installs the vcluster CLI manually. Called automatically by all other commands if the CLI is missing.

```bash
./scripts/k3d-manager vcluster_install_cli
```

- macOS: `brew install loft-sh/tap/vcluster`
- Linux: downloads binary from GitHub releases to `VCLUSTER_INSTALL_DIR` (`/usr/local/bin`)

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `VCLUSTER_NAMESPACE` | `vclusters` | Namespace where vClusters are deployed |
| `VCLUSTER_VERSION` | `0.32.1` | Helm chart version |
| `VCLUSTER_KUBECONFIG_DIR` | `~/.kube/vclusters` | Directory for per-vCluster kubeconfig files |
| `VCLUSTER_INSTALL_DIR` | `/usr/local/bin` | Installation path for the vcluster CLI (Linux only) |

---

## Notes

- All vClusters share the infra cluster's nodes — they are not EC2 instances
- The values file (`scripts/etc/vcluster/values.yaml`) constrains resource usage so vClusters coexist with Vault, Istio, and Jenkins on the M2 Air
- `vcluster_use` merges into `~/.kube/config` — running it multiple times for the same cluster is safe (idempotent merge)
- vCluster names must be valid DNS labels: lowercase alphanumeric and hyphens, no leading/trailing hyphen, max 63 characters
