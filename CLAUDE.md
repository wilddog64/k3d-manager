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
- **Prove external behaviour before dispatch** — a fix that depends on how an outside tool behaves carries proof from the deployed version (read-only capture, upstream source at the tag, or live probe; host, date, version) before dispatch. [more](docs/process/rules.md#prove-external-behaviour)
- **Ideas backlog and release grooming** — a new idea is one row in `docs/ideas.md`; `/release-groom` (Sunday afternoons and each release cut) orders bugs, dispatch queue, open and next release (5 plans each) and the `docs/roadmap.md` backlog; new work enters only by displacing a not-started plan. [more](docs/process/rules.md#ideas-backlog-and-release-grooming)
- **Dispatch WIP limit and P3 batching** — at most 3 open dispatches (running, or exited and not landed) and one per file; P0/P1 may exceed; a `--role review` child does not count; P3s are filed `**Waiting on:** dispatch` and batched by file. [more](docs/process/rules.md#dispatch-wip-limit)
- **Verify before trust** — never trust an agent's commit SHA, BATS result or "done" report without checking via `gh api`, `gh run view` or `git log`.
<!-- shared:begin plan-cap -->
- **Versioning and release scope; bugs before features; capture first, triage later** — `X.0.0` breaking; `X.Y.0` at most 5 plans (a 6th goes to the next minor, never a patch); `X.Y.N` bug-fix only, from `docs/bugs/`. P0 fixed at once, P1 blocks the open release PR; any other bug is captured as a short `docs/bugs/` doc (`**Waiting on:** operator decision`), classified by Argon (`gemini-4-argon-medium`) from the doc alone, and triaged at 20 captured, 7 days old, or each post-merge `/release-groom` (Claude says "triage due" at session start). [more](docs/process/rules.md#versioning-and-release-scope)
<!-- shared:end plan-cap -->
- **No network path out of a cloud session** — with only the GitHub connection you cannot reach the webhook, cluster or any host: never hunt for a token, tunnel, or ask for a credential (refused by policy). Read cluster state via the `cloud-requests` branch: **`docs/howto/cloud-session-requests.md`**. [more](docs/process/rules.md#no-network-path-out-of-a-cloud-session)
- **The hub reads `deploy/hub`; promote to reach it** — release-branch config is inert on the hub until `make hub-promote REF=<commit-ish>`, `make appsets-check`, `make platform-ops` (operator's tmux); confirm `make hub-promote-status` before asking for a live check, and ask for a promote if needed. Rollback: `make hub-rollback`. [more](docs/process/rules.md#hub-reads-deploy-hub)

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
New plugins go in `scripts/plugins/`: public `mytool_do_something`, private `_mytool_helper`. Route privileged or external commands through `_run_command` (`--prefer-sudo`, `--require-sudo`, `--probe '<kubectl args>'`, `--quiet`); never `sudo` or `command sudo` directly.

## Code Style
- Minimal patches — no unsolicited refactors
- Maintain existing indentation, quoting, and naming
- LF line endings only — no CRLF
- No inline comments in shell blocks unless explicitly requested
- Use `${PLACEHOLDER}` for secrets — never hardcode
- `set -euo pipefail` on all new bash scripts

## Docs Conventions

<!-- shared:begin bug-priority -->
Bug priority is urgency, separate from Severity: P0 outage/data loss/security now; P1 broken without a workaround; P2 degraded with a workaround; P3 cosmetic, hygiene or test-only. Every new `docs/bugs/` file carries, directly under Status, `**Priority:**`, `**Introduced by:** <commit or release | pre-existing | unknown>` and `**Should have been caught by:**` (`spec`, `offline test`, `review`, `deploy step`, `live check` or `none`; `unknown` rather than a guess). [more](docs/process/rules.md#bug-priority-and-escape-origin)
<!-- shared:end bug-priority -->

- **Waiting on line** — an open bug's header carries `**Waiting on:** <word>` (optionally `— since YYYY-MM-DD`), one of `dispatch`, `fix running`, `live check`, `scheduled run`, `investigation`, `operator decision`; update it as the bug moves, omit rather than guess. [more](docs/process/rules.md#waiting-on-line)
- **Status first word (operator, 2026-11-06)** — `OPEN`, `LANDED`, or `VERIFIED`; enforced by `.githooks/pre-commit` (`scripts/check-bug-status.py`).
- **Acceptance block** — a dispatched spec carries `## Acceptance` YAML (`must`, `must_not`, `evidence` with `proves` and offline/live, `interface`); every `must_not` red on pre-fix code; an independent verifier tests from Acceptance only; live evidence by operator or Claude, never Gemini. [more](docs/process/rules.md#acceptance-block)
<!-- shared:begin intent-approval -->
Every evidence item carries an operator-facing `intent`, and the spec carries `**Intent approved:**` before dispatch.
<!-- shared:end intent-approval -->
  Enforced at `codex-dispatch start` by `scripts/lib/spec_intent.py` (called from `bin/k3dm-codex-dispatch`).
- **Contract readers and writers** — a spec changing a shared contract (ref, Keychain item, webhook, port, env var, path) lists every reader and every `writer` under `## Contract readers`, by grep with file:line, saying what changes; one found after dispatch is a spec defect. [more](docs/process/rules.md#contract-readers)
- **Test controls** — pair every "X has no effect" test with a positive control; stub external tools from a real read-only capture (host, date in a comment); fixtures assert their target (fake root, stub endpoint, scratch HOME) first. [more](docs/process/rules.md#test-controls)
- **`docs/bugs/`** — unplanned bug fix specs; **`docs/issues/`** — Copilot PR findings and post-incident notes.
- **Dedup before filing — two passes** — Pass 1, exact slug (authoritative): `ls docs/bugs/*-<slug>.md` / `docs/issues/`; reuse any match. Pass 2, `make find-similar-docs Q="<symptom>"` (advisory, always exits 0): a high score means read that file first; a recurrence usually becomes a `Recurrence` section. [more](docs/process/rules.md#dedup-before-filing)
- **Record the result (operator, 2026-11-08)** — every new bug doc carries `**Prior art:** <path> (<score>) — <what was done>` (`read, different root cause`, `appended Recurrence`, `none above threshold`, or `not run`); review at the first grooming after 2026-12-08.

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
