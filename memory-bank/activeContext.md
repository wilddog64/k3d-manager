# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.6.3` (as of 2026-03-06)

**v0.6.2 SHIPPED** — tag `v0.6.2` pushed, PR #19 merged to `main`.
**v0.6.3 active** — branch cut from `main`; plan at `docs/plans/v0.6.3-refactor-and-audit.md`.

---

## Current Focus

**v0.6.3: Refactoring & External Audit Integration**

Plans:
- `docs/plans/v0.6.3-refactor-and-audit.md` — main refactor plan
- `docs/plans/v0.6.3-codex-run-command-fix.md` — active Codex task (see below)

Key objectives:
1. **Fix `_run_command` TTY flakiness** — remove `auto_interactive` block (Codex) ✅ done 2026-03-06
2. **Phase 1 Verification** — BATS 125/125 PASS, E2E Cluster rebuild success (Gemini) ✅ done 2026-03-06
3. De-bloat `system.sh` and `core.sh` — remove permission cascade anti-patterns (Codex) ✅ done 2026-03-06
4. Implement `_agent_lint` + `_agent_audit` in `agent_rigor.sh` (Codex) ✅ done 2026-03-06 — Claude reviewed: PASS
5. BATS suite: `scripts/tests/lib/agent_rigor.bats` (Gemini) ✅ done 2026-03-06
6. **Phase 2 Verification** — teardown/rebuild gate (Gemini) ⏳ active
7. **Codex install_k3s.bats fix** — execute manifest staging stub (plan: `docs/plans/v0.6.3-codex-install-k3s-bats-fix.md`) ✅ done 2026-03-06
8. Claude: final BATS run, commit, open PR

---

## Codex Next Task — Fix C only (install_k3s.bats)

Fix A and Fix B were completed correctly. Fix C was applied to the wrong test.

**What went wrong:** The `install`/`cp` execution branch was added to the
`_start_k3s_service` test's `_run_command` stub. It should be in the
`_install_k3s renders config and manifest` test, which has no local stub — it uses
the global `stub_run_command` from `setup()`, which is a no-op.

**Fix C (corrected):**

File: `scripts/tests/core/install_k3s.bats`
Test: `@test "_install_k3s renders config and manifest"` (currently line 149)

Add a local `_run_command` stub inside this test, before the `_install_k3s mycluster`
call, that executes real filesystem operations for `mkdir`, `install -m`, and `cp`:

```bash
_run_command() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-exit|--soft|--quiet|--prefer-sudo|--require-sudo) shift ;;
      --probe) shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  echo "$*" >> "$RUN_LOG"
  if [[ "$1" == "mkdir" && "$2" == "-p" ]]; then
    command mkdir -p "$3"
  elif [[ "$1" == "install" && "$2" == "-m" ]]; then
    command install -m "$3" "$4" "$5"
  elif [[ "$1" == "cp" ]]; then
    command cp "$2" "$3"
  fi
  return 0
}
export -f _run_command
```

Also restore `stub_run_command` at the end of the test (after the assertions) to avoid
leaking the local stub into subsequent tests.

Also remove the dead `install`/`cp` branch that was incorrectly added to the
`_start_k3s_service` test stub (lines 48–52 in current file) — it serves no purpose
there and is misleading.

**Rules:**
- Test file only — no production code changes.
- Run `shellcheck scripts/tests/core/install_k3s.bats` and report output.
- Run `./scripts/k3d-manager test install_k3s 2>&1` and report full TAP output.
- Commit your changes and update memory-bank to report completion.

---

## Engineering Protocol (Activated)

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Simplification**: Refactor for minimal logic before final verification.

## Agent Workflow — Revised Protocol

### Agent responsibilities (Codex / Gemini)
- **Commit your own work** — self-commit is your sign-off; provides clear attribution in git history.
- **Update memory-bank to report completion** — this is how you communicate back to Claude. Mark tasks done, note what changed, flag anything unexpected.
- **Report each fix individually.** State: fix letter, file, line numbers, what changed.
- **Verification is mandatory.** Run `shellcheck` on every touched `.sh` file and report output.
- **No credentials in task specs or reports.** Reference env var names only (`$VAULT_ADDR`, not the actual URL). Live values stay on the owner's machine.

### Claude responsibilities
- **Review every agent memory-bank write** — detect overclaiming, stale entries, missing items, inaccuracies before the next agent reads it.
- **Write corrective/instructional content to memory-bank** — this is what agents act on next.
- **Open PR when code is ready** — route PR review issues based on scope:
  - Small/isolated fix → Claude fixes directly in the branch
  - Logic or test fix → assign back to Codex via memory-bank
  - Cluster verification needed → assign to Gemini via memory-bank

### Memory-bank communication flow
```
Agent  → memory-bank   (report: task complete, what changed, what was unexpected)
Claude reads           (review: detect gaps, inaccuracies, overclaiming)
Claude → memory-bank   (instruct: corrections + next task spec)
Agent reads + acts
```

---

## Cluster State (as of 2026-03-02)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status | Notes |
|---|---|---|
| Vault | Running | `secrets` ns, initialized + unsealed |
| ESO | Running | `secrets` ns |
| OpenLDAP | Running | `identity` ns |
| Istio | Running | `istio-system` |
| Jenkins | Running | `cicd` ns |
| ArgoCD | Running | `cicd` ns |
| Keycloak | Running | `identity` ns |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status | Notes |
|---|---|---|
| k3s node | Ready | v1.34.4+k3s1 |
| Istio | Running | IngressGateway + istiod |
| ESO | Pending | Deploy after infra work stabilizes |
| shopping-cart-data | Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | Pending | basket, order, payment, catalog, frontend |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.6.1 | released | See CHANGE.md |
| v0.6.2 | **released** | AI Tooling + Agent Rigor + Security hardening |
| v0.6.3 | **active** | Refactoring (De-bloat) + `rigor-cli` Integration |
| v0.6.4 | planned | Linux k3s validation gate + lib-foundation extraction via git subtree |
| v0.7.0 | planned | Keycloak provider + App Cluster deployment |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.7.0; see `docs/plans/roadmap-v1.md` |

---

## Open Items

- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner action)
- [ ] `scripts/tests/plugins/jenkins.bats` — backlog
- [ ] `CLUSTER_NAME` env var not respected during `deploy_cluster` — see `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`
- [x] v0.6.3: De-bloat `system.sh` / `core.sh`
- [x] v0.6.3: `_agent_lint` implementation (Digital Auditor)
- [ ] v0.6.3: `_agent_audit` implementation
- [ ] v0.6.3: `rigor-cli` integration
- [ ] v0.7.0: Keycloak provider interface + App Cluster deployment
- [ ] v0.8.0: `k3dm-mcp` lean MCP server

---

## Operational Notes

- **Pipe all command output to `scratch/logs/<cmd>-<timestamp>.log`** — always print log path before starting
- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **New namespace defaults**: `secrets`, `identity`, `cicd` — old names still work via env var override
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64

### Keycloak Known Failure Patterns

1. **Istio sidecar blocks `keycloak-config-cli` job** — already mitigated via `sidecar.istio.io/inject: "false"` in `values.yaml.tmpl`.
2. **ARM64 image pull failures** — `docker.io/bitnami/*` is amd64-only; use `docker.io/bitnamilegacy/*`.
3. **Stale PVCs block retry** — delete `data-keycloak-postgresql-0` PVC in `identity` ns before retrying.

---

## Agent Workflow (canonical)

```
Claude
  -- reviews all agent memory-bank writes before writing next task
  -- opens PR on owner go-ahead; routes PR issues back to agents by scope
  -- writes corrective/instructional content to memory-bank

Gemini  (SDET + Red Team)
  -- authors BATS unit tests and test_* integration tests
  -- cluster verification: full teardown/rebuild, smoke tests
  -- red team: adversarially tests existing security controls (bounded scope)
  -- commits own work; updates memory-bank to report completion

Codex  (Production Code)
  -- pure logic fixes and feature implementation, no cluster dependency
  -- commits own work; updates memory-bank to report completion
  -- fixes security vulnerabilities found by Gemini red team

Owner
  -- approves and merges PRs
```

**Red Team scope (Gemini):**
- Test existing controls only: `_copilot_prompt_guard`, `_safe_path`, stdin injection, trace isolation
- Try to bypass, leak credentials, or inject via proc/cmdline
- Report findings to memory-bank as structured report — Claude routes fixes to Codex
- Do NOT propose new attack surfaces or modify production code

**Lessons learned:**
- Gemini may write stale memory-bank content — Claude reviews every update before writing next task
- PR sub-branches from Copilot agent (e.g. `copilot/sub-pr-*`) may conflict with branch work — evaluate and close if our implementation is superior
