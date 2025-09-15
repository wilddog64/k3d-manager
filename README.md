# k3d-manager

Utility scripts for creating and managing a local [k3d](https://k3d.io/) Kubernetes cluster with Istio and related tools.  The main entry point is `./scripts/k3d-manager`, which dispatches functions defined in the core libraries and lazily loads plugin files on demand.

## Usage

```bash
./scripts/k3d-manager                     # show usage and core functions
./scripts/k3d-manager <function> [args]   # invoke a core or plugin function
```

Running the script without arguments prints a short help message.  When you call a function that is not part of the core libraries, the launcher searches `scripts/plugins` and sources a matching plugin file at runtime so unused plugins do not slow startup.

Example:

```bash
./scripts/k3d-manager create_k3d_cluster mycluster             # default 8000/8443
./scripts/k3d-manager create_k3d_cluster second 9090 9443      # custom ports
./scripts/k3d-manager hello
```

Use `-h` or `--help` with any command to see a brief usage message:

```bash
./scripts/k3d-manager create_k3d_cluster -h
./scripts/k3d-manager deploy_vault -h
```

You can run multiple clusters at once by giving each a unique name and
port mapping:

```bash
./scripts/k3d-manager create_k3d_cluster alpha
./scripts/k3d-manager create_k3d_cluster beta 8001 8444
```

### Colima resource configuration (macOS)

The macOS Docker setup uses [Colima](https://github.com/abiosoft/colima). Configure the VM resources through environment variables or by passing positional arguments to the internal `_install_mac_docker` helper:

- `COLIMA_CPU` (default `4`) – number of CPUs
- `COLIMA_MEMORY` (default `8`) – memory in GiB
- `COLIMA_DISK` (default `20`) – disk size in GiB

## Directory layout

```
scripts/
  k3d-manager        # dispatcher
  lib/               # core functionality
  plugins/           # optional features loaded on demand
  etc/               # templates and configs
```

## How it fits together

```mermaid
graph TD
  U[User CLI] --> KM[./scripts/k3d-manager]
  KM --> SYS[lib/system.sh]
  KM --> CORE[lib/core.sh]
  KM --> TEST[lib/test.sh]
  KM --|_try_load_plugin(func)|--> PLUG[plugins/*.sh]
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

This diagram outlines how the CLI dispatches to core libraries and loads plugins on demand, which then use Helm and kubectl to manage the cluster.

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
  SYS->>P: source plugins/vault.sh
  SYS->>P: call deploy_vault
  P->>K: _helm install ... / _kubectl apply ...
  K->>C: apply charts/manifests
  Note over KM: public functions dispatch into plugins\nprivate helpers start with "_" and are not invokable
```

The sequence shows a user invoking a plugin function, which loads the plugin and applies resources to the cluster.

## Public functions

| Function | Location | Description |
| --- | --- | --- |
| `destroy_k3d_cluster` | `scripts/lib/core.sh` | Delete a k3d cluster |
| `create_k3d_cluster` | `scripts/lib/core.sh` | Create a k3d cluster |
| `deploy_k3d_cluster` | `scripts/lib/core.sh` | Create and configure a cluster |
| `test_istio` | `scripts/lib/test.sh` | Run Istio validation tests |
| `test_nfs_connectivity` | `scripts/lib/test.sh` | Check network connectivity to NFS |
| `test_nfs_direct` | `scripts/lib/test.sh` | Directly mount NFS for troubleshooting |
| `create_az_sp` | `scripts/plugins/azure.sh` | Create an Azure service principal |
| `deploy_azure_eso` | `scripts/plugins/azure.sh` | Deploy Azure ESO resources |
| `eso_akv` | `scripts/plugins/azure.sh` | Manage Azure Key Vault ESO integration |
| `ensure_bws_secret` | `scripts/plugins/bitwarden.sh` | Ensure Bitwarden secret exists |
| `config_bws_eso` | `scripts/plugins/bitwarden.sh` | Configure Bitwarden ESO |
| `eso_example_by_uuid` | `scripts/plugins/bitwarden.sh` | Example ESO lookup by UUID |
| `verify_bws_token` | `scripts/plugins/bitwarden.sh` | Verify Bitwarden session token |
| `deploy_eso` | `scripts/plugins/eso.sh` | Deploy External Secrets Operator |
| `hello` | `scripts/plugins/hello.sh` | Example plugin |
| `deploy_jenkins` | `scripts/plugins/jenkins.sh` | Deploy Jenkins |
| `deploy_vault` | `scripts/plugins/vault.sh` | Deploy HashiCorp Vault |

## Writing a plugin

Plugins live under `scripts/plugins/` and are sourced only when their function is invoked. Guidelines:

* Public entry points must not start with `_`.
* Keep functions idempotent and avoid side effects on load.
* Use the helper wrappers (`_run_command`, `_kubectl`, `_helm`, `_curl`) for consistent behaviour.

Skeleton:

```bash
#!/usr/bin/env bash
# scripts/plugins/mytool.sh

function mytool_do_something() {
  _kubectl apply -f my.yaml
}

function _mytool_helper() {
  :
}
```

### `_run_command` helper

The `_run_command` wrapper executes system commands with consistent error handling
and optional `sudo` support. Its general form is:

```
_run_command [--quiet] [--prefer-sudo|--require-sudo] [--probe '<subcmd>'] -- <prog> [args...]
```

Examples:

```bash
# install a package, preferring sudo but falling back to the current user
_run_command --prefer-sudo -- apt-get install -y jq

# require sudo and abort if it is unavailable
_run_command --require-sudo -- mkdir /etc/myapp

# probe a subcommand to decide if sudo is needed
_run_command --probe 'config current-context' -- kubectl get nodes
```

Use `--` to separate `_run_command` options from the command being executed.
Unless `--quiet` is specified, failures print the exit code and full command.

## Security notes

* `_failfast_on`/`_failfast_off` toggle `set -Eeuo pipefail`.
* Set `ENABLE_TRACE=1` to log trace output to `/tmp/k3d.trace`.
* `_run_command` and friends handle sudo, probing and exit codes safely.
* Use `_cleanup_register` with `mktemp` to clean up temporary files automatically.


## Tests

Run the test suites via the manager script. The `_ensure_bats` helper in
`scripts/lib/system.sh` installs [Bats](https://github.com/bats-core/bats-core)
using your system package manager when needed:

```bash
./scripts/k3d-manager test all            # run all suites
./scripts/k3d-manager test plugins        # run the plugins suite
./scripts/k3d-manager test lib            # run the lib suite
```

Test subcommands are discovered automatically by scanning `scripts/tests` for `.bats` files.
