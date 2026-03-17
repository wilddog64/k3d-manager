# CLAUDE.md — lib-foundation

Shared Bash foundation library. Consumed by `k3d-manager`, `rigor-cli`, and `shopping-carts` via git subtree.

**Current state:** `memory-bank/activeContext.md` and `memory-bank/progress.md`
**Task specs:** `docs/plans/`

---

## Claude Session Rules

- **Memory-bank update is mandatory and immediate** — after every completed action (spec written, PR created, agent assigned, merge done, task status changed), update `memory-bank/activeContext.md` and `memory-bank/progress.md` before doing anything else. Do not wait for the user to ask.
- **PR creation gate** — do NOT create a PR until ALL of these pass: CI green, Copilot review comments addressed, Claude scope check. Draft PR is acceptable only as an explicit placeholder.
- **Verify before trust** — never trust a commit SHA or BATS result from any agent without independently verifying via `gh api`, `gh run view`, or `git log`.

---

## Layout

```
scripts/lib/
  core.sh            # Cluster lifecycle: create/destroy/deploy, provider abstraction
  system.sh          # _run_command privilege model, package helpers, OS detection, BATS install
  agent_rigor.sh     # _agent_checkpoint, _agent_audit, _agent_lint, pre-commit hook
scripts/tests/lib/
  system.bats        # Unit tests for system.sh
  core.bats          # Unit tests for core.sh
  agent_rigor.bats   # Unit tests for agent_rigor.sh
memory-bank/         # activeContext.md + progress.md — read first, update after
docs/plans/          # Task specs for Codex/Gemini assignments
docs/issues/         # Post-mortems and issue logs
```

---

## Key Contracts (do not break without versioning all consumers)

**`_run_command` (system.sh)** — privilege escalation wrapper, never call `sudo` directly:
```bash
_run_command --prefer-sudo -- <cmd>          # sudo if available, else current user
_run_command --require-sudo -- <cmd>         # fail if sudo unavailable
_run_command --probe '<subcmd>' -- <cmd>     # probe subcommand to decide privilege
_run_command --quiet -- <cmd>               # suppress stderr, return exit code
_run_command --soft -- <cmd>                # return 127 instead of exit on failure
```

**`_detect_platform` (system.sh)** — returns `mac | wsl | debian | redhat | linux`

**`_cluster_provider` (core.sh)** — reads `CLUSTER_PROVIDER` / `K3D_MANAGER_PROVIDER` / `K3DMGR_PROVIDER`

**`_resolve_script_dir` (core.sh)** — portable symlink-aware absolute path of calling script's directory

---

## Code Style

- `set -euo pipefail` mandatory on all scripts
- Public functions: no underscore prefix
- Private functions: `_` prefix
- Double-quote all variable expansions — no bare `$var` in command args
- No bare `sudo` — always `_run_command --prefer-sudo`
- LF line endings only — no CRLF
- Minimal patches — no unsolicited refactors

---

## Bash 3.2 Compatibility (hard requirement)

macOS ships `/bin/bash` at 3.2. All lib code must be compatible:

- **No `local -n`** (nameref) — use global temp vars (e.g., `_RCRS_RUNNER`) for array output
- **No `declare -A`** — no associative arrays
- **No `mapfile` / `readarray`**
- **No `(( ))` with `+=` on arrays** — use `arr=("${arr[@]}" new_element)` form

---

## Security Rules (treat violations as bugs — catch before commit)

**Shell Injection (OWASP A03)**
- Always double-quote variable expansions: `"$var"`, never bare `$var` in command arguments
- Never pass external or user-supplied input to `eval`
- Use `--` to separate options from arguments in CLI calls

**Least Privilege (OWASP A01)**
- No bare `sudo` — route through `_run_command --prefer-sudo`
- GitHub Actions workflows must use `permissions: contents: read` unless elevated access is required

**Secret Hygiene (OWASP A02)**
- No secrets in script arguments visible in shell history or CI logs

**Supply Chain Integrity (OWASP A08)**
- GitHub Actions steps must pin to a version tag (`@v4`) — never `@main` or `@latest`

---

## Testing

```bash
# BATS unit tests — ALWAYS run with clean env (mandatory)
env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" TMPDIR="$TMPDIR" \
  bash --norc --noprofile -c 'bats scripts/tests/lib/'

# shellcheck — run on every touched .sh file
shellcheck scripts/lib/system.sh scripts/lib/core.sh scripts/lib/agent_rigor.sh

# Agent rigor audit (if-count threshold)
AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/lib/system.sh
```

Always run BATS with `env -i` — ambient `SCRIPT_DIR` causes false passes.

---

## Git Subtree Integration

This repo is embedded into consumers via git subtree:

```bash
# Pull updates into a consumer
git subtree pull --prefix=scripts/lib/foundation \
  https://github.com/wilddog64/lib-foundation.git main --squash
```

Breaking changes to `_run_command`, `_detect_platform`, or `_cluster_provider` require coordination across all consumers before merging to `main`.

**Never edit `scripts/lib/foundation/` inside a consumer directly** — fix here, PR, tag, then subtree pull.
