# k3d-manager

Lightweight tooling for creating and operating a local Kubernetes environment with Istio, Vault, and Jenkins. Run `./scripts/k3d-manager <command>` to dispatch into the shell helpers and plugin modules.

## Quick start

1. Ensure prerequisites are available: Docker (or Colima), the [`k3d`](https://k3d.io/) CLI, `kubectl`, `helm`, GNU `envsubst`, and the LastPass CLI if you plan to sync Jenkins credentials. `./scripts/k3d-manager` will attempt to install any missing tools automatically via Homebrew/apt/dnf when possible; install them manually if you are in a locked-down environment.
2. Clone this repository and `cd` into it.
3. Provision a cluster: `./scripts/k3d-manager create_cluster dev`.
4. Bootstrap Vault: `./scripts/k3d-manager deploy_vault ha`.
5. Deploy Jenkins: `./scripts/k3d-manager deploy_jenkins`.

### Example session

```bash
# list available commands
./scripts/k3d-manager

# spin up a throwaway cluster
./scripts/k3d-manager create_cluster demo

# apply core add-ons
./scripts/k3d-manager deploy_cluster

# clean up
./scripts/k3d-manager delete_cluster demo
```

## Common tasks

| Command | Purpose |
| --- | --- |
| `create_cluster <name> [http-port https-port]` | Create a k3d cluster with optional custom ports. |
| `delete_cluster <name>` | Remove the cluster and associated resources. |
| `deploy_cluster [-f]` | Provider-aware bootstrap that installs Istio and supporting add-ons. |
| `deploy_vault ha` | Install HashiCorp Vault (HA) and configure PKI helpers. |
| `deploy_jenkins [--live-update] [--no-sync-from-lastpass]` | Render and install (or upgrade) Jenkins, seeding Vault with AD credentials by default unless disabled. |
| `deploy_eso` | Deploy External Secrets Operator. |

Use `./scripts/k3d-manager <command> -h` for command-specific flags. Custom providers can be added under `scripts/lib/providers/`; see [`docs/cluster-providers.md`](docs/cluster-providers.md).

The Jenkins helper now supports in-place upgrades: pass `--live-update` to run a Helm upgrade against an existing release while the script still waits for the controller pod to become Ready. Skip automatic LastPass syncing with `--no-sync-from-lastpass` if credentials are already in Vault.

### Dependency bootstrap

Most commands call `_ensure_*` helpers before using external CLIs. When a tool such as `curl`, `helm`, `istioctl`, `docker`, `k3d`, `jq`, `envsubst`, or `lpass` is missing, `k3d-manager` will install it through the detected package manager or emit guidance if installation is not possible (for example, no sudo or network access). Watch the output for warnings if an automatic install fails and follow the provided manual instructions.

## Documentation map

- [`docs/k3s-guide.md`](docs/k3s-guide.md) — running against native k3s environments and bare-metal clusters.
- [`docs/jenkins-deployment.md`](docs/jenkins-deployment.md) — Jenkins templates, Vault PKI, LastPass integration, and air-gapped guidance.
- [`docs/cluster-providers.md`](docs/cluster-providers.md) — authoring additional provider modules.
- [`docs/phase1-no-credentials.md`](docs/phase1-no-credentials.md) → [`docs/phase4-storage-smb.md`](docs/phase4-storage-smb.md) — project milestones and historical notes.
- [`docs/readme-refactor-plan.md`](docs/readme-refactor-plan.md) — current plan for this documentation split.

## Testing

Run BATS suites before sending changes:

```bash
./scripts/tests/run.sh
# or a narrower scope
bats scripts/tests/lib
bats scripts/tests/plugins/jenkins.bats
```

## Directory layout

```
├── docs/                # reference docs and how-to guides
├── scripts/
│   ├── etc/             # static manifests and template variables
│   ├── lib/             # core functions (system setup, providers, helpers)
│   ├── plugins/         # lazily loaded feature modules (vault, jenkins, etc.)
│   └── tests/           # bats test suites
└── scripts/k3d-manager  # entrypoint dispatcher
```
