# CLAUDE.md

Modular Bash utility for managing local Kubernetes dev clusters (Istio, Vault, OpenLDAP, ESO).
Uses a dispatcher pattern with lazy plugin loading.
(Jenkins is a deprecated demo feature — disabled by default, not deployed; code retained but unsupported.)

**Entry point:** `./scripts/k3d-manager <function> [args]`
**Current state:** `memory-bank/activeContext.md` and `memory-bank/progress.md`
**Task specs:** `docs/plans/`
**Full rule text, precedents and history:** [`docs/process/rules.md`](docs/process/rules.md). Blocks between `shared:` markers are
identical in `AGENTS.md` and `GEMINI.md`; `bin/k3dm-check-agent-docs` (run by `make test-pytest`) fails on drift, so edit all three.

## Claude Session Rules

- **Memory-bank update is mandatory and immediate** — after every completed action (spec written, PR created, agent assigned, merge done, task status changed), update `memory-bank/activeContext.md` and `memory-bank/progress.md` before anything else, unasked.
- **PR creation gate** — no PR until CI green, Copilot comments addressed, Gemini live smoke test and Claude scope check all pass; a draft PR only as an explicit placeholder.
- **Prove external behaviour before dispatch (operator, 2026-11-07)** — a fix that depends on how an outside tool behaves carries proof from the deployed version (read-only capture, upstream source at the tag, or live probe; host, date, version) before dispatch. [more](docs/process/rules.md#prove-external-behaviour)
- **Ideas backlog and release grooming (operator, 2026-11-07; 2026-11-08)** — a new idea is one row in `docs/ideas.md`; `/release-groom` (Sunday afternoons and each release cut) orders bugs, dispatch queue, open and next release (5 plans each) and the `docs/roadmap.md` backlog; new work enters only by displacing a not-started plan. [more](docs/process/rules.md#ideas-backlog-and-release-grooming)
- **Dispatch WIP limit and P3 batching (operator, 2026-11-07; 2026-11-08)** — at most 3 open dispatches (running, or exited and not landed) and one per file; P0/P1 may exceed; a `--role review` child does not count; P3s are filed `**Waiting on:** dispatch` and batched by file. [more](docs/process/rules.md#dispatch-wip-limit)
- **Verify before trust** — never trust an agent's commit SHA, BATS result or "done" report without checking via `gh api`, `gh run view` or `git log`.
<!-- shared:begin plan-cap -->
- **Versioning and release scope (operator, 2026-11-07); bugs before features; capture first, triage later (operator, 2026-11-11)** — `X.0.0` breaking; `X.Y.0` at most 5 plans (a 6th splits into the next minor, never a patch); `X.Y.N` bug-fix only, from `docs/bugs/`. P0 fixed at once (hotfix if needed), P1 blocks the open release PR; every other bug is captured as a short `docs/bugs/` doc (`**Waiting on:** operator decision`), classified by Argon (`gemini-4-argon-medium`) from the doc alone, and triaged at 20 captured, 7 days old, or each post-merge `/release-groom` (Claude says "triage due" at session start). [more](docs/process/rules.md#versioning-and-release-scope)
<!-- shared:end plan-cap -->
- **No network path out of a cloud session** — with only the GitHub connection you cannot reach the webhook, cluster or any host: never hunt for a token, tunnel, or ask for a credential (refused by policy). Read cluster state via the `cloud-requests` branch: **`docs/howto/cloud-session-requests.md`**. [more](docs/process/rules.md#no-network-path-out-of-a-cloud-session)
- **The hub reads `deploy/hub`; promote to reach it (operator, 2026-11-07; supersedes 2026-07-24)** — release-branch config is inert on the hub until
  `make hub-promote REF=<commit-ish>`, `make appsets-check`, `make platform-ops` (operator's tmux); confirm `make hub-promote-status` before asking for a live
  check, and ask for a promote if needed. Rollback: `make hub-rollback`. Green check runs and typed confirmation enforced by `bin/k3dm-hub-promote` (`check_runs`,
  `show_and_confirm`); `k3dm.k3d.io/rollout-stage` on every ApplicationSet by `scripts/tests/plugins/argocd_appset_rollout_stage.bats`. [more](docs/process/rules.md#hub-reads-deploy-hub)

## Environment Constraints
- **Thinking Budget:** Capped at 8,192 tokens (set via .envrc).
- **Context Management:** 200K window, auto-compaction at about 167K. Run a manual `/compact` at a natural break (between tasks, never mid-step) before that point. [more](docs/process/rules.md#environment-constraints)
- **Output Compression:** RTK (Rust Token Killer) is active for all CLI output.

## Layout
```
scripts/k3d-manager          # dispatcher
scripts/lib/                 # core libraries (system.sh, core.sh, cluster_provider.sh, ...)
scripts/plugins/             # lazy-loaded feature modules (vault.sh, jenkins.sh, eso.sh, ...)
scripts/etc/                 # config templates and vars (*.yaml.tmpl, vars.sh)
scripts/tests/               # BATS suites (pure logic only — no cluster mocks)
```

Provider selected by `CLUSTER_PROVIDER` env var (`orbstack` / `k3d` / `k3s` / `k3s-aws` / `k3s-gcp` / `k3s-az` / `k3s-hostinger`; `k3s-oci` descoped).
Directory service selected by `DIRECTORY_SERVICE_PROVIDER` (`openldap` / `activedirectory`).

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

## Code Style
- Minimal patches — no unsolicited refactors
- Maintain existing indentation, quoting, and naming
- LF line endings only — no CRLF
- No inline comments in shell blocks unless explicitly requested
- Use `${PLACEHOLDER}` for secrets — never hardcode
- `set -euo pipefail` on all new bash scripts

## Docs Conventions

<!-- shared:begin bug-priority -->
Bug priority is urgency, separate from Severity: P0 outage/data loss/security now; P1 broken
without a workaround; P2 degraded with a workaround; P3 cosmetic, hygiene or test-only. Every
new `docs/bugs/` file must carry `**Priority:** P0`, `P1`, `P2`, or `P3` directly under Status.
**Escape origin (operator, 2026-11-07).** Every bug filed from 2026-11-07 also carries
`**Introduced by:** <commit or release | pre-existing | unknown>` and `**Should have been caught by:**`
one of `spec`, `offline test`, `review`, `deploy step`, `live check` or `none`: the first safety net that
should have stopped it. Write `unknown` rather than guess. Each retro counts them by release and by net.
<!-- shared:end bug-priority -->

- **Waiting on line (operator, 2026-11-06)** — an open bug's header carries `**Waiting on:** <word>` (optionally `— since YYYY-MM-DD`), one of `dispatch`, `fix running`, `live check`, `scheduled run`, `investigation`, `operator decision`; update it as the bug moves, omit rather than guess. [more](docs/process/rules.md#waiting-on-line)
- **Status first word (operator, 2026-11-06)** — `OPEN`, `LANDED`, or `VERIFIED`; enforced by `.githooks/pre-commit` (`scripts/check-bug-status.py`).
- **Acceptance block (operator, 2026-10-17)** — a dispatched spec carries `## Acceptance` YAML (`must`, `must_not`, `evidence` with `proves` and offline/live, `interface`); every `must_not` red on pre-fix code; an independent verifier tests from Acceptance only; live evidence by operator or Claude, never Gemini. [more](docs/process/rules.md#acceptance-block)
<!-- shared:begin intent-approval -->
Every evidence item carries an operator-facing `intent`, and the spec carries `**Intent approved:**` before dispatch.
<!-- shared:end intent-approval -->
  Enforced at `codex-dispatch start` by `scripts/lib/spec_intent.py` (called from `bin/k3dm-codex-dispatch`).
- **Contract readers and writers (operator, 2026-11-08; writers 2026-11-10)** — a spec changing a shared contract (ref, Keychain item, webhook, port, env var, path) lists every reader and every `writer` under `## Contract readers`, by grep with file:line, saying what changes; one found after dispatch is a spec defect. [more](docs/process/rules.md#contract-readers)
- **Test controls (operator, 2026-10-30)** — pair every "X has no effect" test with a positive control; stub external tools from a real read-only capture (host, date in a comment); fixtures assert their target (fake root, stub endpoint, scratch HOME) first. [more](docs/process/rules.md#test-controls)
- **`docs/bugs/`** — unplanned bug fix specs; **`docs/issues/`** — Copilot PR findings and post-incident notes.
- **Dedup before filing — two passes** — Pass 1, exact slug (authoritative): `ls docs/bugs/*-<slug>.md` / `docs/issues/`; reuse any match. Pass 2, `make find-similar-docs Q="<symptom>"` (advisory, always exits 0): a high score means read that file first; a recurrence usually becomes a `Recurrence` section. [more](docs/process/rules.md#dedup-before-filing)
- **Record the result (operator, 2026-11-08)** — every new bug doc carries `**Prior art:** <path> (<score>) — <what was done>` (`read, different root cause`, `appended Recurrence`, `none above threshold`, or `not run`); review at the first grooming after 2026-12-08.

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
