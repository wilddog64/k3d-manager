# CLAUDE.md — lib-foundation

Shared Bash foundation library. Consumed by `k3d-manager`, `rigor-cli`, and `shopping-carts` via git subtree.

## Layout

```
scripts/lib/
  core.sh       # Cluster lifecycle: create/destroy/deploy, provider abstraction
  system.sh     # System utilities: _run_command, _detect_platform, package helpers, BATS
scripts/tests/
  lib/          # BATS unit tests for lib functions
memory-bank/    # Persistent agent context
```

## Key Contracts (do not break without versioning)

**`_run_command` (system.sh)** — privilege escalation wrapper, never call `sudo` directly:
```bash
_run_command --prefer-sudo -- <cmd>   # sudo if available, else current user
_run_command --require-sudo -- <cmd>  # fail if sudo unavailable
_run_command --probe '<subcmd>' -- <cmd>  # probe subcommand to decide privilege
_run_command --quiet -- <cmd>         # suppress stderr
```

**`_detect_platform` (system.sh)** — returns `debian | rhel | arch | darwin | unknown`

**`_cluster_provider` (core.sh)** — reads `CLUSTER_PROVIDER` / `K3D_MANAGER_PROVIDER` / `K3DMGR_PROVIDER`

## Code Style

- `set -euo pipefail` mandatory on all scripts
- Public functions: no underscore prefix
- Private functions: `_` prefix
- Double-quote all variable expansions — no bare `$var` in command args
- No bare `sudo` — always `_run_command --prefer-sudo`
- LF line endings only

## Security Rules (OWASP-aligned)

- No `eval` with external input
- Use `--` to separate options from arguments
- New Vault policies: minimum required paths only
- No `--insecure` / `-k` in scripts that may run against production endpoints
- Vault tokens via env var or stdin — never CLI args

## Testing

```bash
# BATS unit tests (clean env — mandatory)
env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/lib/

# shellcheck
shellcheck scripts/lib/core.sh scripts/lib/system.sh
```

Always verify BATS in a clean environment (`env -i`) — ambient `SCRIPT_DIR` causes false passes.

## Git Subtree Integration

This repo is embedded into consumers via git subtree. Breaking changes require coordination
across all consumers before merging to `main`.
