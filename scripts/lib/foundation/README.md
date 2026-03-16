# lib-foundation

Shared Bash foundation library extracted from [`k3d-manager`](https://github.com/wilddog64/k3d-manager).

## Contents

| File | Purpose |
|---|---|
| `scripts/lib/core.sh` | Cluster lifecycle operations — create, destroy, deploy, provider abstraction |
| `scripts/lib/system.sh` | System utilities — `_run_command` privilege model, package helpers, OS detection, BATS install |
| `scripts/lib/agent_rigor.sh` | Agent audit tooling — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`, pre-commit hook |

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

---

## Releases

| Version | Date | Highlights |
|---|---|---|
| [v0.3.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.1) | 2026-03-15 | Route bare `sudo` in all install helpers through `_run_command --prefer-sudo` (Debian/RedHat: kubectl, helm, docker, cargo) |
| [v0.3.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.0) | 2026-03-15 | `_run_command` if-count refactor, `_run_command_resolve_sudo` helper, bash 3.2 compat, BATS coverage |
| [v0.2.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.2.0) | 2026-03-08 | `agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`, pre-commit hook |
| [v0.1.2](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.2) | 2026-03-07 | Drop Colima support |
| [v0.1.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.1) | 2026-03-07 | `_resolve_script_dir` — portable symlink-aware script locator |
| [v0.1.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.0) | 2026-03-07 | Initial extraction from k3d-manager — `core.sh`, `system.sh`, CI, branch protection |
