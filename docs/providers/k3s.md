# k3s Provider Guide

The `k3s` provider lets you run the same k3d-manager stack against a bare-metal or remote [k3s](https://k3s.io/) cluster. Export `CLUSTER_PROVIDER=k3s` to activate it.

---

## Auto-Install Workflow

`deploy_cluster` can install k3s for you on a Linux host with `systemd` and `sudo` access.

```bash
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster        # interactive
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster -f     # non-interactive (CI)
```

Steps performed automatically:
1. Detects a `k3s`-capable Linux host and prompts before touching the system
2. Copies the systemd unit file from `scripts/etc/k3s/` and downloads the k3s binary
3. Installs k3s, enables the service, and waits for the API server to become reachable
4. Applies the same Istio configuration as the k3d flow
5. Saves kubeconfig to `${K3S_KUBECONFIG_PATH}` (default `/etc/rancher/k3s/k3s.yaml`) — follow-on commands like `deploy_vault` work immediately

### Prerequisites for auto-install

- Linux with `systemd` (server + optional agent units)
- Root or password-less `sudo` (for `/etc/rancher/k3s/`, `/usr/local/bin/`)
- Outbound internet access (k3s binary + Istio components)
- Open ports: `6443/tcp` (API), `10250/tcp` (kubelet), `8472/udp` (flannel overlay), `30000-32767/tcp` (NodePorts)
- Writable storage: `/var/lib/rancher/k3s/storage` and `/var/lib/rancher/k3s/agent/containerd/`

---

## Existing k3s Cluster (No Auto-Install)

Use these steps when k3s is already installed:

1. Install k3s manually:
   ```bash
   curl -sfL https://get.k3s.io | sh -s - server --disable traefik
   ```
2. Copy the kubeconfig to your workstation and adjust the API server address if remote:
   ```bash
   scp ubuntu:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s.yaml
   # Edit server: https://ubuntu-ip:6443
   export KUBECONFIG=~/.kube/k3s.yaml
   ```
3. Export the provider and run deploy:
   ```bash
   export CLUSTER_PROVIDER=k3s
   ./scripts/k3d-manager deploy_cluster
   ```

### Environment variables

| Variable | Purpose |
|---|---|
| `CLUSTER_PROVIDER` | Set to `k3s` to select the k3s backend |
| `KUBECONFIG` | Path to the k3s kubeconfig |
| `K3S_KUBECONFIG_PATH` | Override default kubeconfig save location (default `/etc/rancher/k3s/k3s.yaml`) |

The `k3s` CLI must be on `PATH` for health checks and log collection.

---

## Remediation When Auto-Install Is Unavailable

Some environments (immutable hosts, no `systemd`, blocked `sudo`) cannot run the automated installer. Fallbacks:

- Provision k3s manually:
  ```bash
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -
  ```
  Then rerun `deploy_cluster -f` — the helper only applies Istio and add-ons.
- Copy `scripts/etc/k3s/k3s.service.tmpl` to the host and adjust paths for non-standard service directories.
- Ensure `/etc/rancher/k3s/k3s.yaml` is readable and export `KUBECONFIG` before running any plugins.
- If `sudo` is unavailable, pre-create `/usr/local/bin/k3s` and config directories with the desired ownership, then rerun with `-f`.

---

## k3s vs k3d: Key Differences

| | k3d | k3s |
|---|---|---|
| Runtime | Inside Docker containers | Directly on Linux host |
| Cluster lifecycle | Automated (`create_cluster`/`destroy_cluster`) | Manual or via auto-install |
| Port exposure | k3d load balancer (configured in `scripts/etc/cluster.yaml.tmpl`) | Host firewall — open ports directly |
| Kubeconfig | Written to default kubeconfig automatically | Copy `/etc/rancher/k3s/k3s.yaml` to workstation |
| Prerequisites | Docker + `k3d` CLI | Linux + `systemd` + `sudo` |

---

## Required Services on the Host

- `k3s.service` (server) enabled and active: `sudo systemctl status k3s`
- `containerd` ships with k3s — no separate Docker layer needed
- For multi-node: `k3s-agent.service` on worker nodes
