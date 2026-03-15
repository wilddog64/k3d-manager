# lib-foundation

Shared Bash foundation library extracted from [`k3d-manager`](https://github.com/wilddog64/k3d-manager).

## Contents

| File | Purpose |
|---|---|
| `scripts/lib/core.sh` | Cluster lifecycle operations — create, destroy, deploy, provider abstraction |
| `scripts/lib/system.sh` | System utilities — `_run_command` privilege model, package helpers, OS detection, BATS install |

## Integration

This library is embedded into consumers via **git subtree**:

```bash
# Add as subtree (first time)
git subtree add --prefix=scripts/lib/foundation \
  https://github.com/wilddog64/lib-foundation.git main --squash

# Pull updates
git subtree pull --prefix=scripts/lib/foundation \
  https://github.com/wilddog64/lib-foundation.git main --squash
```

## Consumers

- [`k3d-manager`](https://github.com/wilddog64/k3d-manager) — local Kubernetes platform manager
- `rigor-cli` — agent audit tooling (planned)
- `shopping-carts` — app cluster deployment (planned)

## Key Contracts

### `_run_command` (system.sh)

Privilege escalation wrapper. Never call `sudo` directly — use this instead.

```bash
_run_command --prefer-sudo -- apt-get install -y jq   # sudo if available, else current user
_run_command --require-sudo -- mkdir /etc/myapp        # fail if sudo unavailable
_run_command --probe 'config current-context' -- kubectl get nodes  # probe then decide
_run_command --quiet -- command_that_might_fail        # suppress stderr, return exit code
```

### `_detect_platform` (system.sh)

Single source of truth for OS detection. Returns: `debian`, `rhel`, `arch`, `darwin`, `unknown`.

### `_cluster_provider` (core.sh)

Returns active provider string (`k3d`, `k3s`, `orbstack`). Controlled by
`CLUSTER_PROVIDER` / `K3D_MANAGER_PROVIDER` / `K3DMGR_PROVIDER`.

## Development

```bash
# Run BATS tests (requires bats ≥ 1.11)
bats scripts/tests/

# shellcheck
shellcheck scripts/lib/core.sh scripts/lib/system.sh
```

## Code Style

- `set -euo pipefail` on all scripts
- Public functions: no leading underscore
- Private functions: prefix with `_`
- Double-quote all variable expansions
- No bare `sudo` — use `_run_command --prefer-sudo`
