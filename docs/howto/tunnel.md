# How-To: SSH Tunnel (autossh)

The tunnel plugin creates a persistent SSH tunnel from the M2/M4 Air to the Ubuntu k3s node. Hostinger uses the unscoped agents and local port 6443; sandbox ACG providers use `TUNNEL_SCOPE=sandbox`, their own agents, and local port 16443 so both tunnels can run at once.

## Prerequisites

- `autossh` installed (`brew install autossh` on macOS)
- SSH access to the Ubuntu k3s node (configured in `~/.ssh/config` as `ubuntu`)
- launchd (macOS) for boot persistence

## Start the Tunnel

```bash
./scripts/k3d-manager tunnel_start
```

Starts an autossh process forwarding `localhost:6443 → ubuntu:6443`. Registers a launchd job so the tunnel restarts automatically on reboot and reconnects on network interruption. `make up`, `make down`, and `make refresh` use the sandbox scope for ACG providers: `com.k3d-manager.sandbox.ssh-tunnel` and `com.k3d-manager.sandbox.ssh-tunnel-vault`, forwarding `localhost:16443 → ubuntu:6443` with logs under `/tmp/k3d-manager-sandbox-tunnel*`.

## Check Status

```bash
./scripts/k3d-manager tunnel_status
```

Shows the autossh process state and launchd job status.

## Stop the Tunnel

```bash
./scripts/k3d-manager tunnel_stop
```

Kills the autossh process and unloads the launchd job.

## Use the App Cluster

Once the tunnel is active:

```bash
kubectl config use-context ubuntu-k3s
kubectl get nodes
```

## Notes

- The tunnel must be active before any `kubectl` commands targeting `ubuntu-k3s`
- autossh handles reconnection automatically — no manual restart needed after network drops
- Port 6443 is the Kubernetes API server port; ensure it is not in use locally
- The sandbox tunnel's hub ArgoCD endpoint is `https://host.k3d.internal:16443`; Hostinger retains `https://host.k3d.internal:6443`.
