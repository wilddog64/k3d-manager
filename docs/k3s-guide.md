# k3s Deployment Notes

## Using k3s clusters

The helper scripts in this repository now understand a `k3s` provider in addition to the default k3d backend. When `CLUSTER_PROVIDER=k3s` is exported (or auto-detected), `deploy_cluster` walks through an interactive bootstrap routine that can install [k3s](https://k3s.io/) for you. The dispatcher asks for confirmation before touching the host; pass `-f` to `deploy_cluster` to run the same workflow non-interactively in CI.

### Automatic installation workflow

1. `deploy_cluster` prints the provider it detected and, if it sees a `k3s`-capable Linux host, prompts before copying the systemd unit file from `scripts/etc/k3s/` and downloading the k3s binary.
2. After you confirm (or when `-f` is supplied), the helper installs k3s, enables the service, waits for the API server to become reachable, and then applies the same Istio configuration the k3d flow uses.
3. The script saves a kubeconfig under `${K3S_KUBECONFIG_PATH}` (default `/etc/rancher/k3s/k3s.yaml`) and points `kubectl`/plugins at it, so follow-on commands such as `deploy_vault` or `deploy_jenkins` operate on the new control plane without additional setup.

### Prerequisites for the automatic k3s path

* Linux with `systemd` so the installer can register `k3s.service` (server) and optional `k3s-agent.service` units. Enable the service at boot and verify it is active with `sudo systemctl status k3s` before applying workloads.
* Root privileges (either running as root or via password-less `sudo`) so the helper can place files under `/etc/rancher/k3s/` and `/usr/local/bin/`.
* Outbound internet access to download the k3s release and Istio components.
* Open the Kubernetes API (`6443/tcp`) so your workstation can reach the cluster, along with kubelet/metrics traffic (`10250/tcp`) and, when you deploy multiple agents, the overlay network port (`8472/udp`) and NodePort range (`30000-32767/tcp`).
* Writable storage for persistent volumes under `/var/lib/rancher/k3s/storage` and for the embedded containerd runtime under `/var/lib/rancher/k3s/agent/containerd/`.

### Required environment for Jenkins and CLI integrations

The Jenkins plugin and the shell helpers discover non-k3d clusters through a few environment variables and binaries:

* `CLUSTER_PROVIDER` (preferred) or `K3D_MANAGER_PROVIDER` / `K3DMGR_PROVIDER` must be exported with the value `k3s` so the dispatcher selects the k3s backend.
* `KUBECONFIG` has to point at the kubeconfig file for your k3s control plane. Copy `/etc/rancher/k3s/k3s.yaml` from the server to a location Jenkins can read and update the cluster server hostname if necessary.
* The `k3s` CLI must be available on the PATH when you run k3s-specific helpers so health checks and log collection can call it.

### Minimal workflow for existing k3s control planes

1. Install k3s manually or through your configuration management tool by following the [official quick-start instructions](https://docs.k3s.io/quick-start) (for example `curl -sfL https://get.k3s.io | sh -s - server --disable traefik`).
2. Copy the kubeconfig (`/etc/rancher/k3s/k3s.yaml`) to the machine where you run k3d-manager and set `KUBECONFIG` to its path. Adjust the API server address in the kubeconfig if you access the control plane remotely.
3. Export `CLUSTER_PROVIDER=k3s` (or one of the supported aliases) and ensure the `k3s` binary is installed locally.
4. Run `./scripts/k3d-manager deploy_cluster` to let the helper verify the control plane and apply Istio, or call a narrower command such as `deploy_vault` to target a specific add-on.

### Remediation when automatic installation is unavailable

Some environments (for example immutable hosts, distributions without `systemd`, or machines that block `sudo`) cannot run the automated installer. Use the following fallbacks when the prompt reports that auto-install is not supported:

* Provision k3s manually with `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -` and then rerun `deploy_cluster -f` so the helper only applies Istio and add-ons.
* Copy `scripts/etc/k3s/k3s.service.tmpl` to the host and adjust the paths if your distribution uses a non-standard service directory.
* Ensure `/etc/rancher/k3s/k3s.yaml` is readable (copy it to your workstation or expose it through your secrets manager) and export `KUBECONFIG` before running any plugins.
* If `sudo` is unavailable, pre-create `/usr/local/bin/k3s` and the config directories with the desired ownership, then rerun the command with `-f` so it skips privileged operations that are already satisfied.

## k3s backend (bare-metal installations)

Some teams run the same manifests against a remote [k3s](https://k3s.io/) cluster instead of the local k3d environment. The helper functions in this repository do not provision k3s for you, but they work as soon as your `kubectl` context points at an existing k3s API server. Make sure the host satisfies the following expectations before running any plugins against it:

### Required services

* Linux with `systemd` so the installer can register `k3s.service` (server) and optional `k3s-agent.service` units. Enable the service at boot and verify it is active with `sudo systemctl status k3s` before applying workloads.
* `containerd` ships with k3s and is started by the `k3s` unit; no separate Docker or Colima layer is involved.

### Container runtime ports

* Open the Kubernetes API (`6443/tcp`) so your workstation can reach the cluster.
* Allow kubelet and metrics traffic (`10250/tcp`) when you rely on `kubectl logs`, `exec`, or the test helpers that scrape node metrics.
* Keep the default flannel VXLAN overlay port (`8472/udp`) and NodePort range (`30000-32767/tcp`) accessible between nodes if you deploy multiple agents.
* If you enable the embedded registry, expose the registry port (`5000/tcp`) so image pushes from the CI scripts succeed.

### Host storage paths

* Persistent volume data is stored under `/var/lib/rancher/k3s/storage`.
* Container images and runtime metadata live under `/var/lib/rancher/k3s/agent/containerd/`.
* The Jenkins plugin still expects a writable host path that is available on all nodes. Either reuse the default `${JENKINS_HOME_PATH}` export from `scripts/etc/cluster_var.sh` or bind it to a directory under `/var/lib/rancher/k3s/storage`.

### Setup differences compared with k3d

* k3d provisions everything inside Docker. The supplied scripts create and delete clusters automatically, so the only prerequisites are Docker (or Colima) and the `k3d` CLI. With the k3s provider the same `deploy_cluster` command can install packages directly on the host—confirm the prompt or use `-f` to run unattended, and fall back to the manual steps above when auto-install is disabled.
* k3d exposes ports through the k3d load balancer (for example HTTP/HTTPS mapping set in `scripts/etc/cluster.yaml.tmpl`). With k3s there is no Docker network layer; ensure those ports are opened directly in the host firewall.
* k3d automatically writes credentials to your default kubeconfig. For k3s you must copy `/etc/rancher/k3s/k3s.yaml` to your workstation (or export `KUBECONFIG` to point at it) so the manager script can talk to the remote cluster.

### Colima resource configuration (macOS)

The macOS Docker setup uses [Colima](https://github.com/abiosoft/colima). Configure the VM resources through environment variables or by passing positional arguments to the internal `_install_mac_docker` helper:

- `COLIMA_CPU` (default `4`) – number of CPUs
- `COLIMA_MEMORY` (default `8`) – memory in GiB
- `COLIMA_DISK` (default `20`) – disk size in GiB
