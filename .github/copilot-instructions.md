# GitHub Copilot Instructions — lib-foundation

lib-foundation is a shared Bash library consumed by `k3d-manager`, `rigor-cli`, and `shopping-carts`
via git subtree. No dispatcher, no cluster — pure Bash with BATS unit tests.

Use the rules below to shape all code suggestions and PR reviews.

---

## Architecture

- **Core libraries**: `scripts/lib/system.sh`, `scripts/lib/core.sh`, `scripts/lib/agent_rigor.sh`
- **Optional module**: `scripts/lib/acg/` for browser automation. Public shell API is `acg_*`
  (AWS sandbox lifecycle) and `gcp_*` (GCP credential extraction).
- **Privilege escalation**: always via `_run_command --prefer-sudo` or `--require-sudo` — never bare `sudo`
- **OS detection**: always via `_detect_platform` — returns `mac | wsl | debian | redhat | linux`
- **Unit tests**: `scripts/tests/lib/` — always run with `env -i` clean environment
- **Consumers** pull this repo via `git subtree` — breaking changes require cross-consumer coordination
- **Node/Playwright isolation**: the ACG module keeps its own `package-lock.json`; use `npm ci` in
  `scripts/lib/acg/` and keep browser automation changes out of core shellcheck/BATS scope.

---

## Review Focus

### Bash 3.2 Compatibility (P1 — macOS ships /bin/bash 3.2)

Flag any of the following as blocking issues:

- **`local -n`** (nameref) — requires bash 4.3+; breaks on macOS. Use a global temp var instead:
  ```bash
  # Wrong:
  local -n _out="$1"
  # Right: caller declares _MYVAR=(); callee sets _MYVAR=(...); caller reads and unsets
  ```
- **`declare -A`** (associative arrays) — not available in bash 3.2
- **`mapfile`** / **`readarray`** — not available in bash 3.2

### Privilege Escalation

- Bare `sudo` calls in lib code are a bug — all privilege escalation must go through `_run_command`
- `_run_command -- sudo <cmd>` is also wrong — `sudo` must not appear as a program argument:
  ```bash
  # Wrong:
  _run_command -- sudo apt-get install -y jq
  # Right:
  _run_command --prefer-sudo -- apt-get install -y jq
  ```
- `--prefer-sudo`: use sudo if available, fall back to current user
- `--require-sudo`: fail (return 127) if sudo unavailable
- `--probe '<subcmd>'`: run probe subcommand to decide privilege level
- Flag bare `sudo` in pipes (e.g. `echo "..." | sudo tee /etc/...`) — wrap with `_run_command --prefer-sudo -- tee`

### Shell Injection (OWASP A03)

- All variable expansions in command arguments must be double-quoted: `"$var"`, not `$var`
- Never pass user-supplied or external input to `eval`
- Use `--` to separate options from arguments where arguments may contain hyphens

### If-Block Complexity

- `_agent_audit` enforces ≤ 8 if-blocks per function (`AGENT_AUDIT_MAX_IF=8`)
- Flag functions with deeply nested conditionals — extract helpers to reduce if-count
- `_run_command` and `_run_command_resolve_sudo` are the primary targets — both must stay under threshold

### Secret Hygiene (OWASP A02)

- No hardcoded credentials, tokens, or IP addresses in any file
- New sensitive CLI flags must be registered in `_args_have_sensitive_flag` in `system.sh`

### Supply Chain (OWASP A08)

- GitHub Actions steps must pin to a version tag (`@v4`) — never `@main` or `@latest`

### Idempotency

- Every public function must be safe to run more than once
- "Resource already exists" → skip, not error

### ACG Module Review

- `scripts/lib/acg/` changes must keep `npm run check` and `npm test` green in the module dir.
- `npm run test:e2e` / `make credential-test` are manual browser checks and are not required in CI.
- Keep module Playwright code and fixtures isolated from the Bash core; do not add Node deps to
  `scripts/lib/system.sh` or `scripts/lib/core.sh`.

---

## Skip / Do Not Flag

- Pre-existing `shellcheck` warnings in lines **not changed** by the PR
- `set -euo pipefail` absence in sourced library files — these are sourced, not executed directly
- Test stubs and helper overrides in `scripts/tests/` — these intentionally override production functions
- `_RCRS_RUNNER` global temp variable pattern — this is the intentional bash 3.2 compat replacement for `local -n`
- `sudo -n` inside `_run_command_resolve_sudo` — this is the internals of the privilege resolver, not a bare sudo call

---

## Code Style

- Public functions: no leading underscore
- Private/helper functions: prefix with `_`
- All new bash scripts must have `set -euo pipefail`
- LF line endings only — no CRLF
- No inline comments unless logic is non-obvious
