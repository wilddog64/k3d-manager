# lib-foundation API Reference

Source the relevant files and call functions directly:

```bash
source "$(dirname "$0")/lib/system.sh"
source "$(dirname "$0")/lib/core.sh"
source "$(dirname "$0")/lib/agent_rigor.sh"
```

## system.sh — Command Execution & Platform Utilities

### Command Execution

| Function | Description |
|---|---|
| `_run_command [--prefer-sudo|--require-sudo|--interactive-sudo|--probe '<subcmd>'|--quiet|--soft] -- <cmd> [args...]` | Core wrapper for every privileged or traced command. Honors `--prefer-sudo` (attempt non-interactive sudo first), `--require-sudo` (fail if sudo unavailable), `--interactive-sudo` (allow password prompts), `--probe` to test a subcommand before deciding on sudo, `--quiet` to suppress wrapper errors, and `--soft` to return exit codes instead of exiting. Example: `_run_command --prefer-sudo -- apt-get update`. |
| `_run_command_resolve_sudo <prog> <prefer> <require> <interactive> [probe_args...]` | Internal helper invoked by `_run_command`; resolves `_RCRS_RUNNER` to either the raw program or `sudo` with the correct flags, returning 127 when sudo is required but unavailable. |
| `_command_exist <prog>` | Returns 0 if `<prog>` is found on `PATH`, 1 otherwise. |
| `_args_have_sensitive_flag <args...>` | Returns 0 when CLI args contain `--password`, `--token`, or `--username` (either `--flag value` or `--flag=value` form); used to disable tracing. |

### Platform Detection

| Function | Description |
|---|---|
| `_detect_platform` | Detects the current platform (`mac`, `wsl`, `debian`, `redhat`, `linux`, or `unknown`) and caches it in `_DETECTED_PLATFORM`. |
| `_is_mac` / `_is_linux` / `_is_wsl` / `_is_redhat_family` / `_is_debian_family` | Predicates returning 0 when the current system matches the given platform family. |

### Logging & Trace Control

| Function | Description |
|---|---|
| `_info <msg>` | Print `INFO: <msg>` to stderr. |
| `_warn <msg>` | Print `WARN: <msg>` to stderr. |
| `_err <msg>` | Print `ERROR: <msg>` and exit 1. |
| `_no_trace <cmd...>` | Execute a block with `set +x` to avoid leaking secrets in traces. |

### Security & PATH Safety

| Function | Description |
|---|---|
| `_safe_path` | Construct a sanitized `PATH` that excludes world-writable directories. |
| `_is_world_writable_dir <dir>` | Returns 0 if `<dir>` is world-writable. |
| `_set_sensitive_var <name> <value>` | Assign sensitive data to a variable without leaving traces in history. |
| `_write_sensitive_file <path> <data>` | Write a secret to disk using `0600` permissions. |
| `_remove_sensitive_file <path>` | Securely remove a previously written sensitive file. |

### Tool Wrappers (inherit `_run_command` semantics)

| Function | Description |
|---|---|
| `_kubectl ...` | Ensure `kubectl` is installed and forward arguments through `_run_command`. |
| `_helm ...` | Run `helm` with `_run_command` safety wrappers. |
| `_istioctl ...` | Run `istioctl` via `_run_command`. |
| `_k3d ...` | Run `k3d` command with logging/sudo guardrails. |
| `_curl ...` | Wrapper around `curl` that enforces `_safe_path` and tracing rules. |
| `_ip ...` | Wrapper for `ip` / `ifconfig` depending on platform. |

### Secret / Credential Store

| Function | Description |
|---|---|
| `_secret_tool ...` | Linux `secret-tool` wrapper; installs prerequisites automatically. |
| `_security ...` | macOS `security` tool wrapper. |
| `_secret_store_data <service> <key> <value>` | Persist a secret in the platform credential store. |
| `_secret_load_data <service> <key>` | Load a secret from the credential store. |
| `_secret_clear_data <service> <key>` | Remove a secret from the credential store. |
| `_store_registry_credentials <registry>` | Store OCI registry credentials securely. |
| `_load_registry_credentials <registry>` | Retrieve a stored OCI registry credential set. |
| `_registry_login <registry>` | Log into an OCI registry using stored credentials. |

### Installers (require `--interactive-sudo`)

| Function | Description |
|---|---|
| `_install_helm` | Install Helm via apt/dnf/homebrew depending on platform. |
| `_install_kubernetes_cli` | Install `kubectl` (Debian/RedHat/mac). |
| `_install_orbstack` | Install OrbStack on macOS. |
| `_install_bats_from_source` | Build and install BATS from source tarball. |
| `_ensure_bats` | Ensure BATS is installed via package manager/source. |
| `_ensure_node` | Install Node.js + npm for CLI tooling. |
| `_ensure_cargo` | Install Rust `cargo` via apt/dnf/homebrew. |
| `_ensure_copilot_cli` | Install the GitHub Copilot CLI binary. |

### Utilities

| Function | Description |
|---|---|
| `_sha256_12 <data>` | Output the first 12 chars of the SHA-256 of `<data>`. |
| `_version_ge <verA> <verB>` | Return 0 when `verA ≥ verB` using semantic version comparison. |
| `_failfast_on` / `_failfast_off` | Toggle `set -e` for the current shell. |
| `_add_exit_trap <handler>` / `_cleanup_register <handler>` | Register a cleanup handler invoked on script exit. |
| `_k3dm_repo_root` | Return the repo root directory (via git or script location). |
| `_detect_cluster_name` | Derive cluster name from current kubeconfig context. |

### Internal Helpers (not for direct use)

`_install_debian_kubernetes_client`, `_install_redhat_kubernetes_client`, `_install_debian_docker`, `_install_redhat_docker`, `_install_mac_helm`, `_install_redhat_helm`, `_install_debian_helm`, `_install_debian_kubectl`, `_install_redhat_kubectl` — platform-specific installers invoked by the higher-level workflows.

## core.sh — Cluster Lifecycle

### Public Functions

| Function | Signature | Description |
|---|---|---|
| `deploy_cluster [--provider k3d\|k3s\|orbstack] [--force-k3s] [cluster_name]` | Provider-aware cluster bootstrap including Istio and provider exports; resolves provider interactively or via env. |
| `destroy_cluster [cluster_name]` | Destroy the active provider cluster. |
| `create_cluster [cluster_name]` | Create infrastructure for the active provider. |
| `create_k3d_cluster` / `create_k3s_cluster` | Create provider-specific clusters. |
| `destroy_k3d_cluster` / `destroy_k3s_cluster` | Destroy provider-specific clusters. |
| `deploy_k3d_cluster` / `deploy_k3s_cluster` | Deploy full cluster stacks for k3d/k3s. |
| `deploy_ldap` | Deploy OpenLDAP directory to the active cluster. |
| `expose_ingress [setup|status|remove]` | Expose cluster ingress externally or manage ingress forwarding. |
| `setup_ingress_forward` / `status_ingress_forward` / `remove_ingress_forward` | Manage ingress port-forwarding for local access. |

### Stable Internal Utilities

| Function | Description |
|---|---|
| `_cluster_provider` | Resolve the active provider from `CLUSTER_PROVIDER` → `K3D_MANAGER_PROVIDER` → `K3DMGR_PROVIDER` → auto-detected default. |
| `_deploy_cluster_resolve_provider <platform> <provider_cli> <force_k3s>` | Determine provider (CLI override, env overrides, mac default) and return a normalized value. |
| `_deploy_cluster_prompt_provider` | Interactive prompt for provider selection (TTY only). |
| `_resolve_script_dir` | Portable symlink-aware `SCRIPT_DIR` helper. |
| `_ensure_path_exists <dir>` | Ensure a directory exists, creating it with sudo if required. |
| `_ensure_port_available <port>` | Fail fast if a TCP port is already bound locally. |

## agent_rigor.sh — Agent Safety Checks

| Function | Signature | Description |
|---|---|---|
| `_agent_checkpoint <label>` | Commit the working tree with a checkpoint message before a risky change (no-op if clean). |
| `_agent_audit [paths...]` | Static audit covering bare `sudo`, if-count thresholds, BATS tests, and credentialed `kubectl exec` usage. |
| `_agent_lint [paths...]` | Run `shellcheck` on staged files respecting `AGENT_LINT_GATE_VAR`. |

## Global Variables

| Variable | Description |
|---|---|
| `_RCRS_RUNNER` | Populated by `_run_command_resolve_sudo` with the final runner array. |
| `_DETECTED_PLATFORM` | Cached result of `_detect_platform`; reused by platform helpers. |
| `_DCRS_PROVIDER` | Helper scratch variable set by `_deploy_cluster_resolve_provider` for downstream use.
