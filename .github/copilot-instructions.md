# GitHub Copilot Instructions — k3d-manager

k3d-manager is a modular Bash utility for managing local Kubernetes development clusters.
Use the rules below to shape all code suggestions and PR reviews.

---

## Architecture

- **Entry point**: `scripts/k3d-manager` — dispatcher with lazy plugin loading.
- **Core libraries**: `scripts/lib/system.sh`, `scripts/lib/core.sh`, `scripts/lib/agent_rigor.sh`.
- **Plugins**: `scripts/plugins/` — sourced on demand, no side effects at source time.
- **Privilege escalation**: always via `_run_command --prefer-sudo` or `--require-sudo` — never bare `sudo`.
- **OS detection**: always via `_detect_platform` — never inline `_is_mac`/`_is_debian_family` dispatch chains.
- **Secret backends**: interface in `scripts/lib/secret_backends/` — Vault is complete, others stubbed.
- **Cluster providers**: `scripts/lib/providers/` — `k3d`, `orbstack`, `k3s-aws`.
- **ACG plugin**: `scripts/plugins/acg.sh` — `acg_get_credentials`, `acg_provision`, `acg_status`, `acg_extend`, `acg_watch`, `acg_teardown`. Manages Pluralsight ACG sandbox lifecycle via CloudFormation + k3sup.
- **Playwright**: `scripts/playwright/acg_credentials.js` — static Node.js script; primarily uses Playwright `launchPersistentContext` to drive Chrome and extract AWS credentials from the Pluralsight sandbox UI; CDP (`localhost:9222`) is used only as a browser reuse probe.
- **Browser automation**: `scripts/plugins/antigravity.sh` — `_browser_launch`. `_browser_launch` calls `_antigravity_browser_ready` (defined in `scripts/lib/system.sh` via lib-foundation subtree) internally. Launches Chrome with `--remote-debugging-port=9222 --password-store=basic`.
- **Tunnel**: `scripts/plugins/tunnel.sh` — `tunnel_start`, `tunnel_stop`, `tunnel_status`. autossh + launchd; forward tunnel (k3s API :6443) + reverse tunnel (Vault :8200).
- **AWS helpers**: `scripts/plugins/aws.sh` — `aws_import_credentials`. `scripts/plugins/shopping_cart.sh` — `deploy_app_cluster`, `_ensure_k3sup`, `_k3sup_join_agent`.
- **Convenience scripts**: `bin/acg-up`, `bin/acg-down`, `bin/acg-refresh`, `bin/acg-status`, `bin/rotate-ghcr-pat` — orchestrate plugin calls for common one-shot operations.

---

## Review Focus

### Shell Injection (OWASP A03)
- All variable expansions in command arguments must be double-quoted: `"$var"`, not `$var`.
- Never pass user-supplied or external input to `eval`.
- Use `--` to separate options from arguments where arguments may contain hyphens.
- Variables expanded via `envsubst` in `*.yaml.tmpl` files must not contain shell metacharacters.

### Privilege Escalation
- Bare `sudo` calls in production code are a bug — all privilege escalation must go through `_run_command`.
- `_run_command --prefer-sudo` for operations that may succeed without sudo.
- `_run_command --require-sudo` for operations that always need root.
- Flag any multi-attempt permission cascades (trying the same operation 2+ times with escalating privilege).

### Platform Detection
- `_detect_platform` is the single source of truth for OS detection in `core.sh`.
- Flag inline dispatch chains (`if _is_mac; elif _is_debian_family; elif ...`) with more than 2 branches — these should route through `_detect_platform`.
- `linux` returned by `_detect_platform` means an unsupported generic Linux — do not route it into Debian or RedHat install paths.

### Secret Hygiene (OWASP A02)
- Vault tokens and passwords must never appear in `kubectl exec` command strings — they would be visible in `/proc/*/cmdline` and logs.
- New sensitive CLI flags (e.g. `--token`, `--password`, `--secret`) must be registered in `_args_have_sensitive_flag` in `system.sh`.
- No hardcoded credentials, tokens, or IP addresses in any file.
- Test credentials (`alice/password`, etc.) are dev-only — flag if they appear outside test files.

### Least Privilege (OWASP A01)
- New Vault policies must grant only the minimum required paths (`read` unless `write` is explicitly needed).
- New Kubernetes ServiceAccounts must not use `cluster-admin` — use namespace-scoped Role + RoleBinding.
- Every new deployed service must use its own namespace — never `default`.

### Cryptographic Failures (OWASP A02)
- `insecureSkipVerify: true` and `TRUST_ALL_CERTIFICATES` are dev-only — flag if introduced in production paths.
- Vault PKI leaf cert TTL must stay ≤720h — flag increases without justification.
- Never add `--insecure` or `-k` to scripts that may run against production endpoints.

### Supply Chain (OWASP A08)
- GitHub Actions steps must pin to a version tag (`@v4`) — never `@main` or `@latest`.
- Container image references in `*.yaml.tmpl` must use a pinned tag, not `latest`.

### ACG / Playwright / Browser Automation
- AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) must never appear in log output — even at INFO level. Use redacted placeholders or omit entirely.
- `PLURALSIGHT_EMAIL` and `PLURALSIGHT_PASSWORD` must never be logged or echoed.
- `acg_provision`, `acg_teardown` must check for existing resources before creating/deleting — "resource already exists" is not an error (`--soft` pattern or describe-stacks check).
- CloudFormation stack operations must always check stack existence before delete: `describe-stacks` → if None, skip.
- Playwright selectors (`input[aria-label="Copyable input"]`) are fragile — flag hardcoded positional index fallbacks that assume a fixed UI layout without a comment explaining why.
- For Playwright scripts that may attach via CDP: in the `finally` block, only call `browserContext.close()` when the context was launched by the script (`!_cdpBrowser`). Never call `browser.close()` on a CDP-attached session — it shuts down the entire Chrome process and disrupts other sessions.
- Chrome must always be launched with `--password-store=basic` and a dedicated `--user-data-dir` — flag any launch path that omits these flags.
- `GHCR_PAT` and GitHub PATs must be passed via stdin or env var — never as CLI arguments visible in `ps aux`.

### Idempotency
- Every public function must be safe to run more than once.
- "Resource already exists" → skip, not error.
- "Helm release already deployed" → upgrade, not re-install.

---

## Skip / Do Not Flag

- Pre-existing `shellcheck` warnings (SC2164 `pushd`/`popd`, etc.) in lines that were **not changed** by the PR.
- `_is_mac` / `_is_wsl` guards used as simple feature-skip (1–2 branch guards) — these are legitimate, not bloat.
- `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` and `insecureSkipVerify: true` in existing dev config files — already documented as dev-only.
- Test stubs and helper overrides in `scripts/tests/` — these intentionally override production functions.
- `set -euo pipefail` absence in sourced library files (`scripts/lib/`) — these are sourced, not executed directly.

---

## Code Style
- Public functions: no leading underscore.
- Private/helper functions: prefix with `_`.
- All new bash scripts must have `set -euo pipefail`.
- LF line endings only — no CRLF.
- No inline comments unless logic is non-obvious.
