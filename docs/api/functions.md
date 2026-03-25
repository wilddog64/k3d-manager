# Public Functions Reference

All functions callable via `./scripts/k3d-manager <function> [args]`.

Use `-h` or `--help` with any function for a brief usage message:

```bash
./scripts/k3d-manager create_cluster -h
./scripts/k3d-manager deploy_vault -h
```

## Core

| Function | Location | Description |
|---|---|---|
| `create_cluster` | `scripts/lib/core.sh` | Create a cluster for the active provider |
| `destroy_cluster` | `scripts/lib/core.sh` | Delete the active provider's cluster |
| `deploy_cluster` | `scripts/lib/core.sh` | Provider-aware bootstrap (k3d or k3s) plus Istio |
| `expose_ingress` | `scripts/lib/core.sh` | Expose the cluster ingress externally |
| `setup_ingress_forward` | `scripts/lib/core.sh` | Set up port-forwarding for the ingress |
| `status_ingress_forward` | `scripts/lib/core.sh` | Show ingress forward status |
| `remove_ingress_forward` | `scripts/lib/core.sh` | Tear down ingress port-forwarding |

## Tests

| Function | Location | Description |
|---|---|---|
| `test_istio` | `scripts/lib/test.sh` | Run Istio validation tests |
| `test_vault` | `scripts/lib/test.sh` | Run Vault smoke tests |
| `test_eso` | `scripts/lib/test.sh` | Run ESO smoke tests |
| `test_jenkins` | `scripts/lib/test.sh` | Run Jenkins smoke tests |
| `test_jenkins_smoke` | `scripts/lib/test.sh` | Run full Jenkins smoke test suite |
| `test_keycloak` | `scripts/plugins/keycloak.sh` | Run Keycloak smoke tests |
| `test_cert_rotation` | `scripts/lib/test.sh` | Validate TLS certificate rotation |
| `test_nfs_connectivity` | `scripts/lib/test.sh` | Check network connectivity to NFS |
| `test_nfs_direct` | `scripts/lib/test.sh` | Directly mount NFS for troubleshooting |

## Plugins

| Function | Location | Description |
|---|---|---|
| `deploy_vault` | `scripts/plugins/vault.sh` | Deploy HashiCorp Vault |
| `configure_vault_app_auth` | `scripts/plugins/vault.sh` | Register app cluster Kubernetes auth mount in Vault |
| `deploy_eso` | `scripts/plugins/eso.sh` | Deploy External Secrets Operator |
| `deploy_argocd` | `scripts/plugins/argocd.sh` | Deploy ArgoCD |
| `deploy_argocd_bootstrap` | `scripts/plugins/argocd.sh` | Bootstrap ArgoCD with initial apps |
| `deploy_keycloak` | `scripts/plugins/keycloak.sh` | Deploy Keycloak identity provider |
| `deploy_jenkins` | `scripts/plugins/jenkins.sh` | Deploy Jenkins |
| `deploy_ldap` | `scripts/plugins/ldap.sh` | Deploy OpenLDAP directory service |
| `deploy_ad` | `scripts/plugins/ldap.sh` | Deploy Active Directory schema (local dev) |
| `deploy_smb_csi` | `scripts/plugins/smb-csi.sh` | Deploy SMB CSI driver |
| `create_az_sp` | `scripts/plugins/azure.sh` | Create an Azure service principal |
| `deploy_azure_eso` | `scripts/plugins/azure.sh` | Deploy Azure ESO resources |
| `eso_akv` | `scripts/plugins/azure.sh` | Manage Azure Key Vault ESO integration |
| `configure_vault_argocd_repos` | `scripts/plugins/argocd.sh` | Configure Vault-managed deploy keys for ArgoCD repos |
| `deploy_cert_manager` | `scripts/plugins/cert-manager.sh` | Install cert-manager and configure ACME ClusterIssuers |
| `add_ubuntu_k3s_cluster` | `scripts/plugins/shopping_cart.sh` | Export Ubuntu kubeconfig and register cluster in ArgoCD |
| `register_shopping_cart_apps` | `scripts/plugins/shopping_cart.sh` | Apply shopping cart ArgoCD Application CRs |
| `hello` | `scripts/plugins/hello.sh` | Example plugin |
| `tunnel_start` | `scripts/plugins/tunnel.sh` | Start autossh SSH tunnel with launchd persistence |
| `tunnel_stop` | `scripts/plugins/tunnel.sh` | Stop the SSH tunnel and unload launchd job |
| `tunnel_status` | `scripts/plugins/tunnel.sh` | Show tunnel process and launchd status |
| `deploy_app_cluster` | `scripts/plugins/shopping_cart.sh` | Install k3s on EC2 via k3sup and merge kubeconfig |
| `acg_provision` | `scripts/plugins/acg.sh` | Provision ACG sandbox EC2 instance (VPC + SG + key + t3.medium) |
| `acg_status` | `scripts/plugins/acg.sh` | Show ACG instance state, public IP, and k3s health |
| `acg_extend` | `scripts/plugins/acg.sh` | Open ACG sandbox page to extend TTL (+4h) |
| `acg_teardown` | `scripts/plugins/acg.sh` | Terminate ACG instance and remove ubuntu-k3s kubeconfig context |

## Running Tests

```bash
./scripts/k3d-manager test all            # run all suites
./scripts/k3d-manager test core           # run the core suite
./scripts/k3d-manager test plugins        # run the plugins suite
./scripts/k3d-manager test lib            # run the lib suite
./scripts/k3d-manager test install_k3d    # run a single .bats file
./scripts/k3d-manager test install_k3d --case "_install_k3d exports INSTALL_DIR"
./scripts/k3d-manager test -v install_k3d --case "_install_k3d exports INSTALL_DIR"
```

Failed runs keep logs in `scratch/test-logs/<suite>/<case-hash>/<timestamp>.log`.
## Installation Helpers

### `_ensure_antigravity_ide`

Installs the Antigravity IDE if not already present.

| Platform | Method |
|---|---|
| macOS | `brew install --cask antigravity` |
| Debian/Ubuntu | `apt-get install -y antigravity` |
| RedHat/Fedora | `dnf install -y antigravity` |

Returns 0 if installed; calls `_err` if all methods fail.

### `_ensure_antigravity_mcp_playwright`

Ensures Antigravity is configured to launch the Playwright MCP server. Requires `jq`.
- Determines `mcp_config.json` path via `_antigravity_mcp_config_path()`
- Creates the file if missing
- Adds the `playwright` entry `{ "command": "npx", "args": ["-y", "@playwright/mcp@latest"] }` if not already present

### `_antigravity_browser_ready`

Waits for Antigravity (launched with `--remote-debugging-port=9222`) to expose the WebSocket endpoint.

```
_antigravity_browser_ready [timeout_seconds]
```

Returns 0 when port 9222 responds to `curl -sf http://localhost:9222/json`; otherwise calls `_err` after the timeout.
