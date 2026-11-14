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
- **Versioning and release scope; bugs before features; capture first, triage later** — `X.0.0` breaking; `X.Y.0` at most 5 plans (a 6th goes to the next minor, never a patch); `X.Y.N` bug-fix only, from `docs/bugs/`. P0 fixed at once, P1 blocks the open release PR; any other bug is captured as a short `docs/bugs/` doc (`**Waiting on:** operator decision`), classified by Argon (`gemini-4-argon-medium`) from the doc alone, and triaged at 20 captured, 7 days old, or each post-merge `/release-groom` (Claude says "triage due" at session start). [more](docs/process/rules.md#versioning-and-release-scope)
<!-- shared:end plan-cap -->

<!-- shared:begin bug-priority -->
Bug priority is urgency, separate from Severity: P0 outage/data loss/security now; P1 broken without a workaround; P2 degraded with a workaround; P3 cosmetic, hygiene or test-only. Every new `docs/bugs/` file carries, directly under Status, `**Priority:**`, `**Introduced by:** <commit or release | pre-existing | unknown>` and `**Should have been caught by:**` (`spec`, `offline test`, `review`, `deploy step`, `live check` or `none`; `unknown` rather than a guess). [more](docs/process/rules.md#bug-priority-and-escape-origin)
<!-- shared:end bug-priority -->

<!-- shared:begin security -->
## Security Rules (violations are bugs — catch before commit)
- **Injection (A03):** double-quote every expansion (`"$var"`); never `eval` external input; `--` before arguments that may start with a hyphen; validate `envsubst` values in `*.yaml.tmpl` for shell metacharacters.
- **Least privilege (A01):** Vault policies grant minimum paths (`read` unless `write` is needed); no `cluster-admin` ServiceAccounts (namespace Role + RoleBinding); justify any ClusterRole; workflows use `permissions: contents: read` unless more is needed.
- **Crypto (A02):** `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES`, `insecureSkipVerify: true` and `--insecure`/`-k` are dev-only, never on production paths; Vault PKI leaf TTL stays ≤720h (`VAULT_PKI_ROLE_TTL`).
- **Secrets (A02):** no Vault tokens in arguments, shell history, CI logs or `kubectl exec` strings (use env or stdin); register new sensitive flags in `_args_have_sensitive_flag` upstream in lib-foundation, then subtree-pull; test credentials (`alice/password`) are dev-only.
- **Misconfiguration (A05):** every new service gets its own namespace, never `default`; Helm chart versions pinned.
- **Supply chain (A08):** Actions pinned to a tag (`@v4`), images in `*.yaml.tmpl` pinned, never `@main`, `@latest` or `latest`. Pins get reviewed: critical/high CVE → patch release; upstream bug with a cheap workaround → workaround plus `**Fixed upstream in:**`; no workaround or several piling up → upgrade release; otherwise review quarterly, upgrade when about two minors behind. [more](docs/process/rules.md#security-rules)
- **Never weaken:** `_run_command` sudo handling; `_args_have_sensitive_flag` trace suppression (`--password`, `--token`, `--username`); ESO syncing credentials from Vault.
<!-- shared:end security -->
