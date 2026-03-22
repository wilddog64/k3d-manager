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
_run_command --interactive-sudo -- apt-get install -y jq  # prompt for sudo if needed (install helpers)
_run_command --prefer-sudo -- some-cmd                     # sudo if available, else current user (non-interactive)
_run_command --require-sudo -- mkdir /etc/myapp            # fail if sudo unavailable
_run_command --probe 'config current-context' -- kubectl get nodes  # probe then decide
_run_command --quiet -- command_that_might_fail            # suppress stderr, return exit code
```

### `_detect_platform` (system.sh)

Single source of truth for OS detection. Returns: `mac`, `wsl`, `debian`, `redhat`, `linux`.

### `_cluster_provider` (core.sh)

Returns active provider string (`k3d`, `k3s`, `orbstack`). Controlled by
`CLUSTER_PROVIDER` / `K3D_MANAGER_PROVIDER` / `K3DMGR_PROVIDER`.

## Contributed Scripts and Templates

Standalone tools for the spec-driven multi-agent workflow — copy into your repo or
Claude Code installation. Not part of the Bash library.

| File | Purpose | Install to |
|---|---|---|
| `scripts/etc/contrib/agent-pickup.sh` | Agent orientation on session start | `bin/agent-pickup.sh` in your repo |
| `scripts/etc/contrib/handoff-skill.md` | Claude Code `/handoff` skill template | `~/.claude/commands/handoff.md` |
| `scripts/etc/contrib/statusline.sh` | Claude Code status line | via `/statusline-setup` skill |

[Full contrib docs →](docs/contrib.md)

---

## Development

```bash
# Run BATS tests (requires bats ≥ 1.11) — always use env -i for clean environment
env -i PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" HOME="$HOME" TMPDIR="$TMPDIR" \
  bash --norc --noprofile -c 'bats scripts/tests/lib/'

# shellcheck
shellcheck scripts/lib/core.sh scripts/lib/system.sh
```

## Code Style

- `set -euo pipefail` on all scripts
- Public functions: no leading underscore
- Private functions: prefix with `_`
- Double-quote all variable expansions
- No bare `sudo` — use `_run_command --interactive-sudo` for install helpers, `--prefer-sudo` for non-interactive contexts

---

## Releases

| Version | Date | Highlights |
|---|---|---|
| [v0.3.2](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.2) | 2026-03-16 | Sync `deploy_cluster` helpers from k3d-manager, TTY fix (`_DCRS_PROVIDER` global), BATS expanded to 36 tests |
| [v0.3.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.1) | 2026-03-16 | Route bare `sudo` in install helpers through `_run_command --interactive-sudo`; AGENTS.md, GEMINI.md, CLAUDE.md overhaul |
| [v0.3.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.0) | 2026-03-15 | `_run_command` if-count refactor, `_run_command_resolve_sudo` helper, bash 3.2 compat |

[Full release history →](docs/releases.md)
