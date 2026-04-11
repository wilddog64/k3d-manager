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
| `acg_get_credentials` | `scripts/plugins/acg.sh` | Extract AWS credentials from Pluralsight Cloud Access via Playwright persistent context and write to `~/.aws/credentials` |
| `acg_import_credentials` | `scripts/plugins/acg.sh` | Deprecated alias for `aws_import_credentials` — use `aws_import_credentials` instead |
| `acg_provision` | `scripts/plugins/acg.sh` | Provision ACG sandbox 3-node cluster via CloudFormation (server + 2 agents); `--recreate` tears down and re-provisions |
| `acg_status` | `scripts/plugins/acg.sh` | Show ACG instance state, public IP, and k3s health |
| `acg_extend` | `scripts/plugins/acg.sh` | Open ACG sandbox page to extend TTL (+4h) |
| `acg_watch` | `scripts/plugins/acg.sh` | Background TTL watcher — extends sandbox TTL every 3.5h while EC2 instance is alive |
| `acg_teardown` | `scripts/plugins/acg.sh` | Delete ACG CloudFormation stack and remove ubuntu-k3s kubeconfig context |
| `aws_import_credentials` | `scripts/plugins/aws.sh` | Write AWS credentials from stdin to `~/.aws/credentials`; supports CSV, quoted/unquoted export, Pluralsight label, and credentials file formats |
| `antigravity_install` | `scripts/plugins/antigravity.sh` | Verify full Antigravity stack installed (Node.js, gemini CLI, IDE, Playwright MCP) |
| `antigravity_trigger_copilot_review` | `scripts/plugins/antigravity.sh` | Trigger GitHub Copilot coding agent task via Playwright CDP automation |
| `antigravity_poll_task` | `scripts/plugins/antigravity.sh` | Poll a Copilot coding agent task until complete; print full output verbatim |
| `acg_extend_playwright` | `scripts/plugins/acg.sh` | Extend ACG sandbox TTL via Playwright automation (public dispatcher entry point for `_acg_extend_playwright`) |
| `ssm_wait` | `scripts/plugins/ssm.sh` | Wait until an EC2 instance is registered and reachable via SSM (polls `ssm describe-instance-information`) |
| `ssm_exec` | `scripts/plugins/ssm.sh` | Run a shell command on an EC2 instance via SSM `send-command`; streams stdout/stderr; requires `K3S_AWS_SSM_ENABLED=true` |
| `ssm_tunnel` | `scripts/plugins/ssm.sh` | Open an SSM port-forward tunnel to an EC2 instance (wraps `aws ssm start-session --document-name AWS-StartPortForwardingSession`) |
| `register_app_cluster` | `scripts/plugins/argocd.sh` | Register the app cluster (ubuntu-k3s) as an ArgoCD managed cluster |
| `vcluster_create` | `scripts/plugins/vcluster.sh` | Create a virtual Kubernetes cluster inside the infra cluster; exports kubeconfig to `~/.kube/vclusters/<name>.yaml` |
| `vcluster_destroy` | `scripts/plugins/vcluster.sh` | Delete a vCluster and remove its kubeconfig file |
| `vcluster_use` | `scripts/plugins/vcluster.sh` | Merge vCluster kubeconfig into `~/.kube/config` and switch active context |
| `vcluster_list` | `scripts/plugins/vcluster.sh` | List all vClusters in the active namespace |
| `vcluster_install_cli` | `scripts/plugins/vcluster.sh` | Install the vcluster CLI (brew on macOS, binary download on Linux); auto-called by other vcluster commands |
| `ldap_get_user_password` | `scripts/plugins/ldap.sh` | Retrieve an LDAP user's current password from Vault |

### `acg_get_credentials`

Extracts AWS credentials from the Pluralsight Cloud Sandbox "Cloud Access" panel via Playwright `launchPersistentContext` (persisted auth dir `~/.local/share/k3d-manager/playwright-auth`) and writes them to `~/.aws/credentials` under `[default]`. Falls back with instructions to use `acg_import_credentials` if Playwright extraction fails. Set `PLURALSIGHT_EMAIL` to assist Google Password Manager auto-fill when the session has expired.

**Usage:** `./scripts/k3d-manager acg_get_credentials [sandbox-url]`

### `aws_import_credentials`

Reads an AWS credentials block from stdin and writes to `~/.aws/credentials` under `[default]`. Supports multiple input formats:

| Format | Example |
|---|---|
| CSV (IAM Download) | `Access key ID,Secret access key` header + data row |
| Quoted export | `export AWS_ACCESS_KEY_ID="AKIA..."` |
| Unquoted export | `export AWS_ACCESS_KEY_ID=AKIA...` |
| Pluralsight label | `AWS Access Key ID: AKIA...` |
| Credentials file | `[default]` block passthrough |

**Usage:** `pbpaste | ./scripts/k3d-manager aws_import_credentials`

### `acg_import_credentials`

Deprecated alias for `aws_import_credentials`. Kept for backwards compatibility.

**Usage:** `pbpaste | ./scripts/k3d-manager acg_import_credentials`

### `acg_provision`

Provisions the ACG sandbox EC2 instance. Requires `--confirm`. With `--recreate`, tears down any existing instance first.

**Usage:** `./scripts/k3d-manager acg_provision --confirm [--recreate]`

### `acg_watch`

Starts a background loop that extends the ACG sandbox TTL via `_acg_extend_playwright` every `interval_seconds` (default 12600 = 3.5h). Stops automatically when the EC2 instance is gone.

**Usage:** `acg_watch [interval_seconds]` (typically called as `acg_watch &` from `_provider_k3s_aws_deploy_cluster`)

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
- Adds the `playwright` entry `{ "command": "npx", "args": ["-y", "@playwright/mcp@<version>"] }` if not already present; version is read from `PLAYWRIGHT_MCP_VERSION` env var (defaults to a pinned version defined in the helper — does **not** float to `latest`)

### `_antigravity_browser_ready`

Waits for Antigravity (launched with `--remote-debugging-port=9222`) to expose the WebSocket endpoint.

```
_antigravity_browser_ready [timeout_seconds]
```

Returns 0 when port 9222 responds to `curl -sf http://localhost:9222/json`; otherwise calls `_err` after the timeout.

### `_antigravity_gemini_prompt`

Model fallback helper — tries each model in `_ANTIGRAVITY_GEMINI_MODELS` (`gemini-2.5-flash → 2.0-flash → 1.5-flash`) until one succeeds. Detects 429/RESOURCE_EXHAUSTED/ModelNotFoundError and continues to the next model; any other non-zero exit is returned immediately.

```
_antigravity_gemini_prompt <prompt> [--yolo]
```

Pass `--yolo` to add `--approval-mode yolo` to the gemini call (required for Playwright script prompts that write a file and run a command). Omit for web_fetch-only prompts. Creates `${HOME}/.gemini/tmp/k3d-manager/` before the first attempt. Sleeps 2s between attempts to avoid rate-limit swarming.

### `_antigravity_ensure_github_session`

Checks whether the user is logged into GitHub in the running Antigravity browser (via Playwright CDP). If not logged in, navigates to `github.com/login` and waits up to 300s for the user to complete login interactively.

### `_antigravity_ensure_acg_session`

Checks whether the user is logged into Pluralsight's Cloud Playground (`app.pluralsight.com/cloud-playground/cloud-sandboxes`) in the running Antigravity browser (via Playwright CDP). If not logged in, navigates to the sign-in page and waits up to 300s for the user to complete login interactively. Returns 1 on timeout.

**First-run note:** On a brand new environment, the Antigravity browser will open and display the Pluralsight (ACG) sign-in page. Log in manually — the session cookie is persisted in the Antigravity browser profile and reused on all subsequent runs until it expires.

Set `K3DM_ACG_SKIP_SESSION_CHECK=1` to bypass the Pluralsight session check (e.g. for CI runs or when Playwright is unavailable).

| Env Var | Default | Description |
|---|---|---|
| `K3DM_ACG_SKIP_SESSION_CHECK` | `0` | Set to `1` to bypass the Pluralsight session check (useful for CI or if Playwright cannot launch) |
