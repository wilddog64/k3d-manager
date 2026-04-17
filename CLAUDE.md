# CLAUDE.md

Modular Bash utility for managing local Kubernetes dev clusters (Istio, Vault, Jenkins, OpenLDAP, ESO).
Uses a dispatcher pattern with lazy plugin loading.

**Entry point:** `./scripts/k3d-manager <function> [args]`
**Current state:** `memory-bank/activeContext.md` and `memory-bank/progress.md`
**Task specs:** `docs/plans/` (features/enhancements) · `docs/bugs/` (bug fixes)

## Claude Session Rules

- **Memory-bank update is mandatory and immediate** — after every completed action (spec written, PR created, agent assigned, merge done, task status changed), update `memory-bank/activeContext.md` and `memory-bank/progress.md` before doing anything else. Do not wait for the user to ask.
- **Memory-bank hygiene is required** — keep `memory-bank/activeContext.md` and `memory-bank/progress.md` focused on the current branch, open bugs/plans, and near-term context. When older milestone detail stops guiding active work, move it into `memory-bank/archive/*.md` instead of leaving long historical blocks in the active files. Archive; do not delete.

- **PR creation gate** — do NOT create a PR until ALL of these pass: CI green, Copilot review comments addressed, Gemini live smoke test, Claude scope check. Draft PR is acceptable only as an explicit placeholder.
- **Verify before trust** — never trust a commit SHA, BATS result, or "done" report from any agent without independently verifying via `gh api`, `gh run view`, or `git log`.
- **Release scope limit — max 5 plan docs** — each release is a sprint story. If a milestone accumulates more than 5 spec files in `docs/plans/`, stop and split before writing another. A 6th spec is the signal the release is too large, not a reason to keep going. Split into two smaller releases with focused scopes. Bug fix docs in `docs/bugs/` do not count toward this limit.

## Environment Constraints
- **Thinking Budget:** Capped at 8,192 tokens (set via .envrc).
- **Context Management:** Manual `/compact` required at 60% utilization.
- **Output Compression:** RTK (Rust Token Killer) is active for all CLI output.

---

## Layout

```
scripts/k3d-manager          # dispatcher
scripts/lib/                 # core libraries (system.sh, core.sh, cluster_provider.sh, ...)
scripts/plugins/             # lazy-loaded feature modules (vault.sh, jenkins.sh, eso.sh, ...)
scripts/etc/                 # config templates and vars (*.yaml.tmpl, vars.sh)
scripts/tests/               # BATS suites (pure logic only — no cluster mocks)
```

Provider selected by `CLUSTER_PROVIDER` env var (`orbstack` / `k3d` / `k3s`).
Directory service selected by `DIRECTORY_SERVICE_PROVIDER` (`openldap` / `activedirectory`).

---

## Plugin Development

New plugins go in `scripts/plugins/`. Public functions: no underscore. Private: `_` prefix.

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

**`_run_command` wrapper — always use this for privileged or external commands:**

```bash
_run_command --prefer-sudo -- apt-get install -y jq   # prefer sudo, fall back to user
_run_command --require-sudo -- mkdir /etc/myapp        # fail if sudo unavailable
_run_command --probe 'config current-context' -- kubectl get nodes  # probe to decide sudo
_run_command --quiet -- command_that_might_fail        # suppress stderr, still returns exit code
```

Do NOT call `sudo` directly. Do NOT use `command sudo`. Route through `_run_command`.

---

## Code Style

- Minimal patches — no unsolicited refactors
- Maintain existing indentation, quoting, and naming
- LF line endings only — no CRLF
- No inline comments in shell blocks unless explicitly requested
- Use `${PLACEHOLDER}` for secrets — never hardcode
- `set -euo pipefail` on all new bash scripts

---


## Security Rules (treat violations as bugs — catch before commit)

**Shell Injection (OWASP A03)**
- Always double-quote variable expansions: `"$var"`, never bare `$var` in command arguments.
- Never pass external or user-supplied input to `eval`.
- Use `--` to separate options from arguments in CLI calls where arguments may contain hyphens.
- Variables expanded via `envsubst` in `*.yaml.tmpl` must not contain shell metacharacters — validate before substitution.

**Least Privilege (OWASP A01)**
- New Vault policies must grant only the minimum required paths (`read` unless `write` is explicitly needed).
- New Kubernetes ServiceAccounts must not use `cluster-admin`. Use namespace-scoped Role + RoleBinding.
- New ClusterRoles must be justified — prefer namespace-scoped resources.
- GitHub Actions workflows must use `permissions: contents: read` unless elevated access is explicitly required.

**Cryptographic Failures (OWASP A02)**
- `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` and `insecureSkipVerify: true` are dev-only. Never introduce in production config paths.
- Vault PKI leaf cert TTL must stay short (≤720h). Do not increase `VAULT_PKI_ROLE_TTL` without justification.
- Never add `--insecure` or `-k` to scripts that may run against production endpoints.

**Secret Hygiene (OWASP A02)**
- Vault tokens must never appear in script arguments visible in shell history or CI logs. Use env vars or stdin.
- New sensitive CLI flags must be registered in `_args_have_sensitive_flag` in `scripts/lib/system.sh`.
- Test credentials (`alice/password`, etc.) are dev-only — never reference in production config paths.
- No secrets in `kubectl exec` command strings that appear in logs.

**Security Misconfiguration (OWASP A05)**
- Every new deployed service must use its own namespace — never `default`.
- New Helm chart installations must pin chart versions explicitly — no floating `latest`.

**Supply Chain Integrity (OWASP A08)**
- GitHub Actions steps must pin to a version tag (`@v4`) — never `@main` or `@latest`.
- New container image references in `*.yaml.tmpl` must use a pinned tag, not `latest`.

**Existing protections — do not remove or weaken:**
- `_run_command` handles sudo probing and escalation safely.
- `_args_have_sensitive_flag` disables trace for commands with `--password`, `--token`, `--username`.
- ESO syncs credentials from Vault without exposing them in git.
