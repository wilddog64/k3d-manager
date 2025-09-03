# k3d-manager

This update adds:

1. **Directory structure** (what's in `scripts/`, `plugins/`, etc.)
2. **Script diagrams** showing how the pieces communicate.
3. **Public functions** table.
4. **Private helpers** table.
5. **How to write a plugin** (conventions & skeleton).
6. **Shell script security considerations** tailored to this repo.

> Tip: run `./scripts/k3d-manager <function>` to invoke any public function directly.

## Directory structure

```
scratch/
  enable_kv2
  failfast
  k3d-fix
  unseal.sh
  vault.sh
  vault_init_if_needed
  vault_init_unseal
scripts/
  etc/
    azure/
      az-eso.yaml.tmpl
      azure-eso.yaml.tmpl
      azure-vars.sh
    bitwarden/
      bws-eso.yaml.tmpl
    cluster.yaml.tmpl
    cluster_var.sh
    istio-operator.yaml.tmpl
    istio_var.sh
    jenkins/
  lib/
    core.sh
    system.sh
    test.sh
  plugins/
    azure.sh
    bitwarden.sh
    eso.sh
    hello.sh
    jenkins.sh
    vault.sh
  storage/
    jenkins_home/
      jenkins-plugins.txt
  k3d-manager
LICENSE
README.md
```

## How the system fits together (high level)

```mermaid
flowchart TD
  U[User CLI] --> KM[./scripts/k3d-manager]
  KM --> SYS[lib/system.sh<br/>wrappers: _run_command/_kubectl/_helm]
  KM --> CORE[lib/core.sh<br/>cluster & Istio orchestration]
  KM --> TEST[lib/test.sh]
  KM -->|_try_load_plugin(func)| PLUG[plugins/*.sh]
  PLUG --> HELM[helm]
  PLUG --> KUB[kubectl]
  CORE --> HELM
  CORE --> KUB
  subgraph Cluster
     K3D[k3d/k3s API] --> K8S[Kubernetes]
     ISTIO[Istio] --> K8S
     ESO[External Secrets Operator] --> K8S
  end
  HELM --> K3D
  KUB --> K3D

  subgraph Providers
     VAULT[HashiCorp Vault]
     AZ[Azure Key Vault]
     BWD[Bitwarden]
     JNK[Jenkins]
  end
  ESO <-- sync/reads --> VAULT
  ESO <-- sync/reads --> AZ
  ESO <-- sync/reads --> BWD
```

```mermaid
sequenceDiagram
  participant U as user
  participant KM as k3d-manager
  participant SYS as _try_load_plugin / wrappers
  participant P as plugin fn
  participant K as kubectl/helm
  participant C as k3d cluster

  U->>KM: ./k3d-manager deploy_vault
  KM->>SYS: _try_load_plugin("deploy_vault")
  SYS->>P: source plugins/vault.sh; call deploy_vault
  P->>K: _helm install ... / _kubectl apply ...
  K->>C: apply charts/manifests
  Note over KM: public functions dispatch into plugins<br/>private helpers start with "_" and are not invokable
```

## Public functions

| Function                        | Location                       | Description                   |
| ------------------------------- | ------------------------------ | ----------------------------- |
| `cleanup_on_success`            | `scripts/lib/core.sh`          | Cleanup on success            |
| `configure_k3d_cluster_istio`   | `scripts/lib/core.sh`          | Configure k3d cluster istio   |
| `create_k3d_cluster`            | `scripts/lib/core.sh`          | Create k3d cluster            |
| `create_nfs_share`              | `scripts/lib/core.sh`          | Create nfs share              |
| `deploy_k3d_cluster`            | `scripts/lib/core.sh`          | Deploy k3d cluster            |
| `install_docker`                | `scripts/lib/core.sh`          | Install docker                |
| `install_istioctl`              | `scripts/lib/core.sh`          | Install istioctl              |
| `install_k3d`                   | `scripts/lib/core.sh`          | Install k3d                   |
| `command_exist`                 | `scripts/lib/system.sh`        | Command exist                 |
| `install_colima`                | `scripts/lib/system.sh`        | Install colima                |
| `install_kubernetes_cli`        | `scripts/lib/system.sh`        | Install kubernetes cli        |
| `install_mac_helm`              | `scripts/lib/system.sh`        | Install mac helm              |
| `install_redhat_helm`           | `scripts/lib/system.sh`        | Install redhat helm           |
| `is_debian_family`              | `scripts/lib/system.sh`        | Is debian family              |
| `is_linux`                      | `scripts/lib/system.sh`        | Is linux                      |
| `is_mac`                        | `scripts/lib/system.sh`        | Is mac                        |
| `is_redhat_family`              | `scripts/lib/system.sh`        | Is redhat family              |
| `is_wsl`                        | `scripts/lib/system.sh`        | Is wsl                        |
| `list_k3d_cluster`              | `scripts/lib/system.sh`        | List k3d cluster              |
| `maybe_setup_smb`               | `scripts/lib/system.sh`        | Maybe setup smb               |
| `reset_colima`                  | `scripts/lib/system.sh`        | Reset colima                  |
| `setup_smb_csi_driver`          | `scripts/lib/system.sh`        | Setup smb csi driver          |
| `_try_load_plugin`              | `scripts/lib/system.sh`        | Try load plugin               |
| `test_failfast_demo`            | `scripts/lib/test.sh`          | Test failfast demo            |
| `test_k3d_install`              | `scripts/lib/test.sh`          | Test k3d install              |
| `test_minikube_install`         | `scripts/lib/test.sh`          | Test minikube install         |
| `test_plugins_loader`           | `scripts/lib/test.sh`          | Test plugins loader           |
| `test_run_command_wrapper`      | `scripts/lib/test.sh`          | Test run command wrapper      |
| `azure_deploy_eso`              | `scripts/plugins/azure.sh`     | Azure deploy eso              |
| `azure_setup_workload_identity` | `scripts/plugins/azure.sh`     | Azure setup workload identity |
| `bws_apply_secret`              | `scripts/plugins/bitwarden.sh` | Bws apply secret              |
| `bws_install_cli`               | `scripts/plugins/bitwarden.sh` | Bws install cli               |
| `eso_install`                   | `scripts/plugins/eso.sh`       | Eso install                   |
| `hello`                         | `scripts/plugins/hello.sh`     | Hello                         |
| `jenkins_bootstrap_admin`       | `scripts/plugins/jenkins.sh`   | Jenkins bootstrap admin       |
| `jenkins_create_secret`         | `scripts/plugins/jenkins.sh`   | Jenkins create secret         |
| `jenkins_install`               | `scripts/plugins/jenkins.sh`   | Jenkins install               |
| `deploy_vault`                  | `scripts/plugins/vault.sh`     | Deploy vault                  |

## Private helpers

| Function                            | Location                   | Description                      |
| ----------------------------------- | -------------------------- | -------------------------------- |
| `_add_exit_trap`                    | `scripts/lib/system.sh`    | Add exit trap                    |
| `_cleanup_register`                 | `scripts/lib/system.sh`    | Cleanup register                 |
| `_create_k3d_cluster`               | `scripts/lib/system.sh`    | Create k3d cluster               |
| `_curl`                             | `scripts/lib/system.sh`    | Curl                             |
| `_ensure_cargo`                     | `scripts/lib/system.sh`    | Ensure cargo                     |
| `_ensure_secret_tool`               | `scripts/lib/system.sh`    | Ensure secret tool               |
| `_err`                              | `scripts/lib/system.sh`    | Err                              |
| `_failfast_off`                     | `scripts/lib/system.sh`    | Failfast off                     |
| `_failfast_on`                      | `scripts/lib/system.sh`    | Failfast on                      |
| `_helm`                             | `scripts/lib/system.sh`    | Helm                             |
| `_info`                             | `scripts/lib/system.sh`    | Info                             |
| `_install_debian_docker`            | `scripts/lib/system.sh`    | Install debian docker            |
| `_install_debian_kubernetes_client` | `scripts/lib/system.sh`    | Install debian kubernetes client |
| `_install_helm`                     | `scripts/lib/system.sh`    | Install helm                     |
| `_install_mac_docker`               | `scripts/lib/system.sh`    | Install mac docker               |
| `_install_mac_kubernetes_client`    | `scripts/lib/system.sh`    | Install mac kubernetes client    |
| `_install_redhat_docker`            | `scripts/lib/system.sh`    | Install redhat docker            |
| `_install_redhat_kubernetes_client` | `scripts/lib/system.sh`    | Install redhat kubernetes client |
| `_is_k3d_installed`                 | `scripts/lib/system.sh`    | Is k3d installed                 |
| `_kubectl`                          | `scripts/lib/system.sh`    | Kubectl                          |
| `_list_k3d_cluster`                 | `scripts/lib/system.sh`    | List k3d cluster                 |
| `_no_trace`                         | `scripts/lib/system.sh`    | No trace                         |
| `_run_command`                      | `scripts/lib/system.sh`    | Run command                      |
| `_setup_debian_smb_client`          | `scripts/lib/system.sh`    | Setup debian smb client          |
| `_setup_linux_smb_mount`            | `scripts/lib/system.sh`    | Setup linux smb mount            |
| `_setup_mac_smb_sharing`            | `scripts/lib/system.sh`    | Setup mac smb sharing            |
| `_setup_smb_mac`                    | `scripts/lib/system.sh`    | Setup smb mac                    |
| `_setup_smb_redhat`                 | `scripts/lib/system.sh`    | Setup smb redhat                 |
| `_setup_smb_wsl`                    | `scripts/lib/system.sh`    | Setup smb wsl                    |
| `_try_load_plugin`                  | `scripts/lib/system.sh`    | Try load plugin                  |
| `_vault_ns_ensure`                  | `scripts/plugins/vault.sh` | Vault ns ensure                  |
| `_vault_repo_setup`                 | `scripts/plugins/vault.sh` | Vault repo setup                 |
| `_vault_values_dev`                 | `scripts/plugins/vault.sh` | Vault values dev                 |
| `_vault_values_ha`                  | `scripts/plugins/vault.sh` | Vault values ha                  |
| `_vault_wait_ready`                 | `scripts/plugins/vault.sh` | Vault wait ready                 |
| `_is_vault_deployed`                | `scripts/plugins/vault.sh` | Is vault deployed                |
| `_vault_bootstrap_ha`               | `scripts/plugins/vault.sh` | Vault bootstrap ha               |
| `_vault_portforward_help`           | `scripts/plugins/vault.sh` | Vault portforward help           |
| `_is_vault_health`                  | `scripts/plugins/vault.sh` | Is vault health                  |

> Note: This table is generated from the repo; brief descriptions are name-based. For authoritative details, open the function in its file.

## Writing a plugin

Plugins live in `scripts/plugins/*.sh`. The launcher will **lazy‑load** a plugin that
defines the function name you request. Rules:

* **Public vs private:** public functions **do not** start with `_`. Private helpers **must** start with `_`.
  `_try_load_plugin` refuses to execute names beginning with `_`.
* **Idempotent:** design functions to be safe to re-run.
* **Use wrappers:** prefer `_run_command`, `_kubectl`, `_helm`, `_curl` for consistent probing, sudo handling,
  quiet mode, and tracing control.
* **No side effects on load:** files are `source`d. Avoid top‑level code that executes on load.
* **Namespacing:** prefix helpers with your area, e.g. `_vault_*`, `_azure_*`.
* **Usage strings:** add a brief comment above each function; it will be surfaced in docs like this.

Skeleton:

```bash
#!/usr/bin/env bash
# scripts/plugins/mytool.sh

# Public entry point
function mytool_do_something() {
  local ns="${1:-default}"
  _failfast_on
  # Example: apply a manifest safely and quietly
  _kubectl --quiet -n "$ns" apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata: { name: example }
YAML
  _failfast_off
}

# Private helpers (not directly invokable)
function _mytool_render_values() {
  # produce a temp file and register for cleanup
  local f; f="$(mktemp)"
  _cleanup_register "$f"
  printf 'key: value\n' >"$f"
  echo "$f"
}
```

Invoking your plugin:

```bash
./scripts/k3d-manager mytool_do_something dev
```

## Shell script security considerations

This repo already includes several safety primitives (see `lib/system.sh`):

* **Fail‑fast mode:** `_failfast_on` enables `set -Eeuo pipefail` with an ERR trap; `_failfast_off` disables.
* **Redaction‑friendly tracing:** set `ENABLE_TRACE=1` to enable xtrace to `BASH_XTRACEFD` (a file), then wrap
  sensitive calls with `_no_trace <cmd ...>` to avoid leaking secrets.
* **Least privilege exec:** `_run_command` supports `--probe`, `--prefer-sudo`, `--require-sudo` and returns the
  wrapped program's *real* exit code; use it instead of raw `sudo`/`kubectl`.
* **Temp files & cleanup:** use `mktemp` and `_cleanup_register` to ensure files are removed via an EXIT trap.
* **Quoting & arrays:** always `"$var"` quote expansions; pass arrays—`cmd "${arr[@]}"`—to avoid word-splitting.
* **Secret handling:** Prefer files or environment variables scoped to a single command. Do **not** echo secrets.
  Avoid exporting secrets globally; pass via process environment only where needed.
* **External inputs:** validate function arguments; reject unexpected function names (already enforced in `_try_load_plugin`).

Example of avoiding secret leakage in traces:

```bash
VAULT_TOKEN="$(security find-generic-password -a me -s vault -w)"
_no_trace _helm upgrade --install vault hashicorp/vault --set "server.extraEnvironmentVars.VAULT_TOKEN=${VAULT_TOKEN}"
unset VAULT_TOKEN
```
