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
| [v0.3.14](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.14) | 2026-03-27 | `agy` binary detection, `_antigravity_browser_ready` curl fast-fail, NUL-safe tab scan, doc + CHANGE.md fixes; 78 BATS |
| [v0.3.13](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.13) | 2026-03-25 | `_antigravity_browser_ready` curl probe fix — `_run_command --soft -- curl` replaces `_curl` to allow polling retries |
| [v0.3.12](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.12) | 2026-03-25 | `_ensure_antigravity_ide`, `_ensure_antigravity_mcp_playwright`, `_antigravity_browser_ready` — Antigravity IDE install + Playwright MCP config helpers; 7 BATS |

<details><summary>Older releases</summary>

| Version | Date | Highlights |
|---|---|---|
| [v0.3.11](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.11) | 2026-03-25 | `_agent_audit` YAML hardcoded-IP check — staged `.yaml`/`.yml` files with IPv4 addresses fail pre-commit |
| [v0.3.8](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.8) | 2026-03-24 | `_agent_audit` tab indentation enforcement — staged `.sh` files with tab/mixed indent fail pre-commit; 15 BATS |
| [v0.3.7](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.7) | 2026-03-24 | `system.sh` if-count cleanup — extract `_run_command_handle_failure` + `_node_install_via_redhat`; clears k3d-manager allowlist |
| [v0.3.6](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.6) | 2026-03-23 | `doc_hygiene.sh`: exclude fenced code blocks from Check 2; add CoreDNS Check 4 (21 BATS) |

</details>

[Full release history →](docs/releases.md)
