# AGENTS.md — dispatched work

## Dispatch and hand-back

You receive a worktree and a spec. Do not run git add, git commit, git push, or create a PR. Do not touch `memory-bank/`. Leave changes in the working tree. End by listing every changed file and pasting the spec's gate output, including failures and skips.

## Spec contract

Read the full spec and the current memory-bank context before acting. The `## Acceptance` block is the contract: implement its `must` and `must_not` requirements, and show each `must_not` test red on the pre-fix code. If the spec is ambiguous or contradicts the code, stop and say so in the last message; do not guess.

## Test rules

Never weaken, skip, or delete a test. Pair each test asserting no effect with a positive control that shows the effect when enabled. Capture external-tool stubs from real read-only output and record the host and date beside them. Before asserting a result, a fixture must assert its target (scratch HOME, stub endpoint, or fake repo root).

Isolate tests from live state: use a scratch HOME, point Pushgateway at `127.0.0.1:9`, and never access the real Keychain or `~/Library/LaunchAgents`. Sandbox deny-tests need a run outside the sandbox to prove the application denial rather than the sandbox denial. Preserve task-provided environment variables.

## Gates

Run `make test`, `make test-pytest`, shellcheck on touched shell files, and `_agent_audit`, along with the spec's gates. Read per-suite counts and skips, not just exit codes. Report actual output.

## Code rules

Use the existing Bash and Python styles. Route privileged and external commands through `_run_command`. Make lib-foundation changes upstream, then subtree-pull; do not edit its subtree directly. Stay within the spec scope and report unrelated findings in the hand-back. Never delete comments marked DO NOT REMOVE.

## Shared rules

<!-- shared:begin plan-cap -->
- **Release scope limit — max 5 plan docs** — each release is a sprint story. If a milestone accumulates more than 5 spec files in `docs/plans/`, stop and split before writing another. A 6th spec is the signal the release is too large, not a reason to keep going. Split into two smaller releases with focused scopes. **Split early into a patch release:** when a release branch grows too big or too fast — even under five specs — move dependent or not-yet-started plans to `vX.Y.(N+1)` (`vX.Y.N-<slug>.md`, branch `k3d-manager-vX.Y.N` cut from `main` after the parent merges). Claude decides the split, records it in `docs/roadmap.md`, and tells the operator (operator, 2026-10-10; precedent: v1.43.0 → v1.43.1). A patch release may also be a **bug-fix-only release** when fixes are needed between minors; bug specs in `docs/bugs/` do not count toward the cap.
<!-- shared:end plan-cap -->

<!-- shared:begin bug-priority -->
Bug priority is urgency, separate from Severity: P0 outage/data loss/security now; P1 broken
without a workaround; P2 degraded with a workaround; P3 cosmetic, hygiene or test-only. Every
new `docs/bugs/` file must carry `**Priority:** P0`, `P1`, `P2`, or `P3` directly under Status.
<!-- shared:end bug-priority -->

<!-- shared:begin security -->
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
- New sensitive CLI flags must be registered in `_args_have_sensitive_flag` in lib-foundation's `scripts/lib/system.sh` (change it upstream, then subtree-pull; `scripts/lib/system.sh` here only loads it).
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
<!-- shared:end security -->
