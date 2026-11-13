# GEMINI.md — dispatched work

## Scope

- BATS and pytest authoring.
- Offline security review.
- Pre-commit hook smoke tests.

Live evidence is run by the operator or Claude, never Gemini.

## Principles

- Verify the machine with `hostname && uname -n` before acting. Read the spec and memory-bank context first.
- A confirmed plan is not a checkpoint; the actual output is. Stop at stop gates and when asked to stop or compress.
- Keep tests isolated from ambient inputs, and report actual output and counts.
- Stay within the assigned scope; report unrelated findings in the hand-back. Never reference an unreleased dependency.

## `--approval-mode yolo`

Only use this mode when the prompt specifies exactly one file to write, inside `${HOME}/.gemini/tmp/k3d-manager/`, and exactly one command to run. Never use it with open-ended instructions; treat a violation as a bug.

On the M4, agy (language server 1.4.12) reported both `AGENTS.md` and `GEMINI.md` instruction markers in its initial context on 2026-11-01.

## Dispatch and hand-back

You receive a worktree and a spec. Do not run git add, git commit, git push, or create a PR. Do not touch `memory-bank/`. Leave changes in the working tree. End by listing every changed file and pasting the spec's gate output, including failures and skips.

## Spec contract

Read the full spec and the current memory-bank context before acting. The `## Acceptance` block is the contract: implement its `must` and `must_not` requirements, and show each `must_not` test red on the pre-fix code. If the spec is ambiguous or contradicts the code, stop and say so in the last message; do not guess.
<!-- shared:begin intent-approval -->
Every evidence item carries an operator-facing `intent`, and the spec carries `**Intent approved:**` before dispatch.
<!-- shared:end intent-approval -->

## Test rules

Never weaken, skip, or delete a test. Pair each test asserting no effect with a positive control that shows the effect when enabled. Capture external-tool stubs from real read-only output and record the host and date beside them. Before asserting a result, a fixture must assert its target (scratch HOME, stub endpoint, or fake repo root).

Isolate tests from live state: use a scratch HOME, point Pushgateway at `127.0.0.1:9`, and never access the real Keychain or `~/Library/LaunchAgents`. Sandbox deny-tests need a run outside the sandbox to prove the application denial rather than the sandbox denial. Preserve task-provided environment variables.

## Gates

Run `make test`, `make test-pytest`, shellcheck on touched shell files, and `_agent_audit`, along with the spec's gates. Read per-suite counts and skips, not just exit codes. Report actual output.

## Code rules

Use the existing Bash and Python styles. Route privileged and external commands through `_run_command`. Make lib-foundation changes upstream, then subtree-pull; do not edit its subtree directly. Stay within the spec scope and report unrelated findings in the hand-back. Never delete comments marked DO NOT REMOVE.

## Shared rules

<!-- shared:begin plan-cap -->
- **Versioning and release scope (operator, 2026-11-07); bugs before features; capture first, triage later (operator, 2026-11-11)** — `X.0.0` breaking; `X.Y.0` at most 5 plans (a 6th splits into the next minor, never a patch); `X.Y.N` bug-fix only, from `docs/bugs/`. P0 fixed at once (hotfix if needed), P1 blocks the open release PR; every other bug is captured as a short `docs/bugs/` doc (`**Waiting on:** operator decision`), classified by Argon (`gemini-4-argon-medium`) from the doc alone, and triaged at 20 captured, 7 days old, or each post-merge `/release-groom` (Claude says "triage due" at session start). [more](docs/process/rules.md#versioning-and-release-scope)
<!-- shared:end plan-cap -->

<!-- shared:begin bug-priority -->
Bug priority is urgency, separate from Severity: P0 outage/data loss/security now; P1 broken
without a workaround; P2 degraded with a workaround; P3 cosmetic, hygiene or test-only. Every
new `docs/bugs/` file must carry `**Priority:** P0`, `P1`, `P2`, or `P3` directly under Status.
**Escape origin (operator, 2026-11-07).** Every bug filed from 2026-11-07 also carries
`**Introduced by:** <commit or release | pre-existing | unknown>` and `**Should have been caught by:**`
one of `spec`, `offline test`, `review`, `deploy step`, `live check` or `none`: the first safety net that
should have stopped it. Write `unknown` rather than guess. Each retro counts them by release and by net.
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
- **Pins get reviewed, not only set (operator, 2026-11-07).** A pinned chart or image never moves by itself: the
  observability stack sat at kube-prometheus-stack `67.9.0` (Grafana 11.4.0) for nearly two years. Severity sets the
  response. A critical or high CVE in a pinned image calls for a patch release. An upstream bug that hurts us and has a
  cheap workaround gets the workaround, with `**Fixed upstream in:** <component> <version>` in its bug doc. An upstream
  bug with no workaround, or several fixed-upstream bugs piling up, calls for an upgrade release. Absent any of those,
  review the pinned stack versions once a quarter and plan an upgrade when one is more than about two minor versions
  behind.

**Existing protections — do not remove or weaken:**
- `_run_command` handles sudo probing and escalation safely.
- `_args_have_sensitive_flag` disables trace for commands with `--password`, `--token`, `--username`.
- ESO syncs credentials from Vault without exposing them in git.
<!-- shared:end security -->
